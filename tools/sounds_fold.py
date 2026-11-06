"""The Fold's sounds (laser 15), all synthesised here from noise, impulses and physical models; nothing sampled. Every stem
is one take of many small irregular events, not a one-shot replayed: the only thing heard twice is nothing.

The heart of it is the ice: `flex` puts a hit through the real dispersion of a bending wave in a floating sheet (the
skipping stone on a frozen pond): the highs arrive first, the pitch falls as d / sqrt(f), it lands on the held tone where
the wave's phase speed meets the speed of sound in air (`fc`: ~725 Hz on 4 cm ice, ~195 Hz on 16 cm), and the dull knock
of the hit itself comes last through the air, d / 340 s late. Distance is the chirp's length.

As strike/fold.rs plays them (strike seconds; `EVENTS` below has volumes):

  descent   0 s, exactly 3.4 s: a body of fire coming down, with the Payload's way of falling in it: a roar with low resonances wandering in it, a thin tearing whine bending up
            a little, torn air sweeping up under it, a few dull pops for the fire, no crackle; swelling as it nears and ending at full force on its last sample, no tail.
  wobble    3.49 s, to 4.6: something catches it: a push of pressure, a heavy hum thrown off its pitch and settling back on the picture's wobble, then only the hum, low and still.
  air       ~3.9 s (late by the distance, 0.5 s at 170 blocks): the air that kept going: a soft shove, the fire's roar carried
            past and away with a few embers, a gust thinning over the ground, gone by ~6.9 s.
  letgo     4.5 s, to contact at 6.0: the hum falling out from under it, and the fall: air split by a great body, its loudness the speed squared, cut on contact.
  meld      5.6 s: the land rising to meet it, faintly; 6 s the landing, a heavy wet blow; at 6.2 the land shuts over it: a deep, solid water drop's plop, two smaller after it
            and the last small drop falling back; then only the land's heave.
  ripple    7.5 s: the land moving like water: nine slow seas on the picture's pulses and swell, bands of chaos, no note and nothing ringing.
  score     12 s: the first of the creases: ice, one pew and a stone skipping off, and no more cracks; only a dark breath of ground parting under the tears, 15.2 to 19.
  unravel   19 s: the land bending as a machine turns: `CLACKS`, a great mechanism going over one detent at a time, tick and tock, each heave of the land a bigger one, closing up
            as it comes round, the last on the world's stopping at 31.5, each going off the land still standing. From 26 s it comes through the ground.
  groan     19 s: the land bending, a hull's stress, moans with no note, the bangs (`BANG_UP`, on or halfway to the clacks), the far land's slow lift to 23.5, closing overhead from 26 s:
            the sky's air goes; at 31.5 the world stops closing and it stops with it, leaving a stillness and the air in the tube to 34.5.
  foldown   34.5 s, exactly 5.5 s: the rim gathering at the hole, huge and far off; from 35 a stalactite of land lowering on the six stages, heavy and
            slow, nothing going round, earth and rock turning into the droplet's metal towards its tip; a low strain under it (`strain`) building and taking over, at its heaviest on its last sample, the touch.
  ding      37.8 s, the touch on 40.0: `DING_PICK`, one of `DINGS`, each a different idea of that moment and all of them holding up to it: it has its lead-in on the front of it.
  reverse   40.5 s, exactly 3.6 s: the whole fold going back, on the picture's own clock: the ground starting to move, the stalactite
            drawn back up on its stages, metal first and then earth, the rim up, the tube opening from 42.8 and the sky's air coming in,
            the far land going at the end. Forward sounds gathering: nothing played backwards, nothing climbing in pitch.
  bang1-4   44.1, 45.2, 46.3, 47.4 less 0.8 s: a ring of land falling for 0.8 s and stopping dead: its own fall, its own bang.
            bang1 the far land, a long hit rolling away round the horizon; bang2 a broken ring, two deep blows; bang3 the nearest and hardest, nothing after it; bang4 short, hollow and dead.
  fall      47.9 s: the last fall: the air under the land going, rising, and 90 ms of nothing before the slam.
  slam      48.7 s: the last ring comes down: a door the size of the sky: round 3's blow, the kick in it, the land's sheet answering, rock and roar, with what was over `FOIL` Hz of those taken off.
  sink      48.7 s, ~9 s: the crater going in, panel by panel on the picture's own clock (`panels`, read from fold_warp.wgsl):
            rock shearing as each lets go, ring after ring from the middle out; the pit's walls and air going while they
            fall; then the landings, ring 0 a tight roll, ring 3 the longest, its deep edge last; the debris after them.
  underfoot the panel under the player stopping, on its own: a shove through the soles and a second of the ground shuddering; when depends on how deep the crater is where they are (fold.rs).
  comedown  53.3 s, to the strike's end at 59.7: four slow seas of the ground going flat, `ripple`'s own making, the last thunder going round, cold air, nothing to count, nothing over 800 Hz or so: the fires.

The game mixes every file to mono as it decodes it, so all of these are built to sum well: their lows are mono, nothing on
the two sides is out of phase, and the levels here are measured on the sum.

    python3 tools/sounds_fold.py                  # writes orbital-sounds/assets/orbital/sounds/fold/*.ogg and the fold.* events
    python3 tools/sounds_fold.py --only ding      # one (or several)
    python3 tools/sounds_fold.py --listen DIR     # also an MP3 of each, the whole strike's mix (fold_mix.mp3, spectrograms)
                                                  # and the levels section by section, stereo and summed
"""
import argparse, json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.fft import irfft, next_fast_len, rfft, rfftfreq
from scipy.ndimage import gaussian_filter1d
from scipy.signal import butter, fftconvolve, lfilter, sosfilt
import soundlib
from soundlib import SR
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P
import sounds_nuke as N

TH = "fold"
ROOT = Path(__file__).resolve().parent.parent
PEAK = 10 ** (-1.2 / 20)              # every file's decoded peak at most

# The beats (strike/fold.rs's FD_*): the stems are built on them.
STOP, HANG, TOUCH, CLOSED, RIPPLE, SCORE, TEAR, FOLD, CLOSING, SEAL = 3.4, 4.5, 6.0, 6.2, 7.5, 12.0, 16.0, 19.0, 26.0, 35.0
HOLD, GATHER, TUBE = 31.5, 34.5, 42.8                  # the world stops closing; the rim gathers at the hole; on the way back the tube opens
LIFT = 23.5                                           # the far land's slow lift (20.1 s on) at its height
METAL_ON = (36.8, 38.0)                               # on the way down: the stalactite turning from earth into the droplet's metal
METAL_UP = (41.2, 41.6)                               # on the way back: all metal to the first, earth back by the second
REACHED, DING, REL, LEN = 39.0, 40.0, 40.5, 59.7      # (the arm's stages done, the tip 13 short and creeping: FW_HANG; FD_LEN)
SLAMS = [44.1, 45.2, 46.3, 47.4, 48.7]                # (FD_SLAM: each ring falling for FALL s and stopping dead)
FLAT, SLAM = SLAMS[0], SLAMS[4]
# when the land lets go in great heaves; the fold's stages (FD_FOLDS)
RINGS = [19.1, 21.0, 23.3, 25.1, 27.6, 29.9]
# the land's detents as it bends (`unravel`): the heaves are the downbeats, each cut into even clacks, so the beat tightens as it goes and the last falls on HOLD
BEATS = (2, 3, 3, 4, 4, 3)
CLACKS = [(a + (b - a) * k / q, k == 0) for a, b, q in zip(RINGS, RINGS[1:] + [HOLD], BEATS) for k in range(q)] + [(HOLD, True)]
CREASES = [35.0, 35.5, 36.1, 36.8, 37.5, 38.2]
PULSES = [7.5, 8.6, 9.6, 10.6, 11.5]  # the water's pulses of the middle, from when the droplet is absorbed
SWELLS = [11.25, 12.25, 13.2, 14.2]   # the swell under a player at 170 blocks, a crest about 0.55 s after each; biggest ~12.8
MELD_LEAD = 0.4                       # meld starts this far before contact, as the land rises to meet the droplet (5.6 s)
FALL = 0.8                            # how long each ring falls (fold_warp's FW_FALL): 1 - u^3, slowly away, its weight in the last of it
AIR_LATE = 0.5                        # the air's sound after the stop, at 170 blocks (the plan uses the real distance)
# The crater (fold_warp.wgsl's fw_sunk): a panel lets go `LATE0 + LATE1 ring + up to LATE2` after the slam, and falls with CAVE t^2 blocks
LATE0, LATE1, LATE2, CAVE, BOWL = 0.2, 0.62, 0.5, 18.0, 66.0
COMEDOWN = SLAM + 4.6                 # comedown starts here: the last panel is down at slam + 4.3 (`panels`)
DING_LEAD = 2.2                       # ding.ogg starts this long before the touch, for what leads into it (fold.rs's FD_DING_LEAD)
DING_PICK = "inbreath"                # which of `DINGS` is the one in the game
SITE = 170.0                          # where the mix has the player (fold.rs uses the real distance for `underfoot`)
RIM = 300.0                           # the crater's edge: `underfoot` is for a player inside it


def underfoot_at(dist=SITE):
    """How long after the slam the panel under a player `dist` blocks from the middle lands: it lets go first, on the slam."""
    u = min(dist / RIM, 1.0)
    return float(np.sqrt(BOWL * (1 - u ** 3) ** 0.75 / CAVE))

# (time, file, volume, pitch), as fold_plan plays them
EVENTS = [(0.0, "descent", 1.0, 1.0), (STOP + 0.09, "wobble", 1.0, 1.0), (STOP + AIR_LATE, "air", 1.0, 1.0), (HANG, "letgo", 1.0, 1.0),
          (TOUCH - MELD_LEAD, "meld", 1.0, 1.0), (RIPPLE, "ripple", 1.0, 1.0), (SCORE, "score", 1.0, 1.0),
          (FOLD, "unravel", 1.0, 1.0), (FOLD, "groan", 1.0, 1.0), (GATHER, "foldown", 1.0, 1.0),
          (DING - DING_LEAD, "ding", 1.0, 1.0), (REL, "reverse", 1.0, 1.0),
          *[(t - FALL, f"bang{k + 1}", 1.0, 1.0) for k, t in enumerate(SLAMS[:4])],
          (SLAM - FALL, "fall", 1.0, 1.0), (SLAM, "slam", 1.0, 1.0), (SLAM, "sink", 1.0, 1.0), (SLAM + underfoot_at(), "underfoot", 1.0, 1.0),
          (COMEDOWN, "comedown", 1.0, 1.0)]
SECTIONS = [("descent", 0.0, 3.4), ("hush", 3.4, 3.9), ("air", 3.9, 4.9), ("drop", 4.9, 6.0), ("hit", 6.0, 6.5), ("sink", 6.5, 7.5), ("ripple", 7.5, 12.0),
            ("score", 12.0, 16.0), ("tear", 16.0, 19.0), ("unravel", 19.0, 26.0), ("close", 26.0, 31.5), ("still", 32.2, 34.5), ("vortex", 34.5, 39.0), ("into it", 39.0, 40.0),
            ("ding", 40.0, 40.5), ("gather", 40.5, 42.8), ("open", 42.8, 43.3), ("farland", 43.3, 44.1), ("bang1", 44.1, 45.2), ("bang2", 45.2, 46.3),
            ("bang3", 46.3, 47.4), ("bang4", 47.4, 47.9), ("fall", 47.9, 48.7), ("slam", 48.7, 49.1), ("letgo", 49.1, 51.0), ("land", 51.0, 53.1), ("debris", 53.1, 56.0), ("comedown", 56.0, 59.7)]


def rng():
    return soundlib.rng


def grn(d, rate, taus=(0.012, 0.025, 0.05)):
    """`N.grains`, exactly `n_of(d)` long."""
    return N.grains(d + 0.01, rate, taus)[:n_of(d)]


def n_of(d):
    return int(round(d * SR))


def times(n):
    return np.arange(n) / SR


def ss(a, b, x):
    u = np.clip((x - a) / (b - a), 0, 1)
    return u * u * (3 - 2 * u)


def noise(n):
    return rng().standard_normal(n)


def bp(x, lo=None, hi=None, order=2):
    """A causal filter: nothing rings ahead of a hit, and nothing wraps round from a hard end to the file's start."""
    if lo and hi:
        s = butter(order, [lo, hi], "band", fs=SR, output="sos")
    elif lo:
        s = butter(order, lo, "high", fs=SR, output="sos")
    else:
        s = butter(order, hi, "low", fs=SR, output="sos")
    return sosfilt(s, x)


def bn(n, lo, hi, order=2):
    """Unit band noise."""
    return T.unit(bp(noise(n), lo, hi, order))


def reso(x, f, q):
    """A two-pole resonance on `f` Hz."""
    w = 2 * np.pi * f / SR
    r = np.exp(-w / (2 * q))
    return lfilter([1 - r], [1, -2 * r * np.cos(w), r * r], x)


def bank(x, modes):
    """`x` through a body: (Hz, Q, gain) each."""
    return sum(reso(x, f, q) * a for f, q, a in modes)


def stick(n, rate, jit=0.3, miss=0.15, grain=0.003, tau=0.0008):
    """Stick and slip: a rough little burst each time it gives, at `rate` a second (one value a sample), uneven."""
    imp = np.zeros(n)
    k = float(rng().uniform(0, 400))
    while k < n:
        i = int(k)
        if rng().random() > miss:
            imp[i] += rng().lognormal(0.0, 0.6) * rng().choice([-1.0, 1.0])
        k += max(SR / max(rate[i], 1.0) * max(1 + (jit[i] if np.ndim(jit) else jit) * rng().standard_normal(), 0.25), 6.0)
    m = n_of(grain)
    return fftconvolve(imp, noise(m) * np.exp(-np.arange(m) / SR / tau))[:n]


def morph(n, shape, size=2048, hop=512):
    """Noise whose spectrum moves: `shape(t, f)` the magnitudes at `t` seconds. Unit RMS."""
    win = np.hanning(size)
    f = np.fft.rfftfreq(size, 1 / SR)
    f[0] = 1.0
    out = np.zeros(n + 2 * size)
    for s in range(-size, n, hop):
        z = rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))
        a = s + size
        out[a:a + size] += np.fft.irfft(shape(max(s + size / 2, 0) / SR, f) * z, size) * win
    return T.unit(out[size:size + n])


def wide(a, b, corr):
    """Two channels, `corr` (a value or one a sample) alike."""
    return a, corr * a + np.sqrt(np.maximum(1 - corr ** 2, 0)) * b


def low_mono(L, R, f=170.0):
    """Everything under `f` Hz alike on both sides (the game sums them, and it is where the weight is)."""
    s = (L - R) / 2
    s = s - bp(s, None, f)
    m = (L + R) / 2
    return m + s, m - s


def pan(x, p):
    return PB.pan2(x, p)


def blow(n, t0, f_hi, f_lo, f_end, drop, rise, decs, drive=3.0, octv=0.32, h3=0.18, harm=0.45):
    """A tonal boom: f_hi falling to f_lo over `drop` s and on to f_end; its octave, twelfth and driven harmonics on it,
    so it is heard as weight on small speakers too."""
    t = times(n)
    u = np.maximum(t - t0, 0)
    m = t >= t0
    f = f_end + (f_lo - f_end) * np.exp(-u / 0.6) + (f_hi - f_lo) * np.exp(-u / drop)
    ph = 2 * np.pi * np.cumsum(f * m) / SR
    env = (1 - np.exp(-u / rise)) * sum(w * np.exp(-u / tc) for w, tc in decs) * m
    s = np.sin(ph)
    hh = bp(np.tanh(drive * s + 0.3) - np.tanh(0.3) - s * 0.9 * np.tanh(drive), None, 700)
    return (s + octv * np.sin(2 * ph + 1.1) + h3 * np.sin(3 * ph + 2.3) + harm * hh) * env


def struck(n, t0, span, modes, count=36, grit=0.3):
    """A great weight stopping on the ground, as the ground takes it: one contact at `t0`, `count` more over `span` s, all
    pressing the same way, through the ground's own low modes ((Hz, Q, gain) each). No sweep: nothing a kick drum does. Peak 1."""
    imp = np.zeros(n)
    imp[n_of(t0)] = count * 0.12
    for _ in range(count):
        imp[min(n_of(t0 + span * rng().random() ** 1.5), n - 1)] += min(rng().pareto(2.2) * 0.5 + 0.4, 3.0)
    m = n_of(0.012)
    s = times(m)
    ker = np.exp(-s / 0.003) * (1 + grit * noise(m))           # (a rough push, not a clean one)
    x = bank(fftconvolve(imp, ker)[:n], modes)
    return x / (np.abs(x).max() + 1e-9)


def rough(n, t0, span, count, lo, hi, tau):
    """The contacts' own hard front: short rough bursts of what's meeting there, over in the first tens of ms. Peak 1."""
    o = np.zeros(n)
    m = n_of(tau * 7)
    for k in range(count):
        s = times(m)
        y = bp(noise(m), lo, hi) * np.exp(-s / (tau * rng().uniform(0.6, 1.4))) * min(rng().pareto(2.2) * 0.5 + 0.3, 2.0)
        P.put(o, y, t0 + (span * rng().random() ** 2 if k else 0.0))
    return o / (np.abs(o).max() + 1e-9)


def rock_crack(d, size=1.0, bright=1.0):
    """A rock snapping (the Sinkhole's, duller): a short crack, its body, a thump under it, grit crumbling off."""
    n = n_of(d)
    t = times(n)
    t0 = 0.02
    x = soundlib.click(n, t0, 1.1 * bright, rng().uniform(700, 1200), rng().uniform(4500, 8000), rng().uniform(0.004, 0.009))
    for _ in range(rng().integers(2, 5)):
        x += soundlib.click(n, t0 + rng().uniform(0.004, 0.05), rng().uniform(0.2, 0.6) * bright, 500, 5000, rng().uniform(0.002, 0.006))
    x += bn(n, 220, 2000) * np.exp(-np.maximum(t - t0, 0) / (0.05 + 0.04 * size)) * (t >= t0) * 0.35
    x += soundlib.thump(n, t0 + 0.004, 110 * (1.2 - 0.4 * size), 36, 0.12 + 0.12 * size, 10.0) * 0.9 * size
    return x


def patter(d, t_lo, t_hi, rate, gain=1.0):
    """Debris coming down: clods, a stone clacking now and then, small stones; the further off the darker, and nothing bare and bright:
    a run of high ticks with nothing under them is tin foil. (L, R), dry."""
    n = n_of(d)
    L = np.zeros(n)
    R = np.zeros(n)
    for t1 in P.poisson_times(t_lo, t_hi, rate):
        near = rng().random() ** 1.6
        kind = rng().random()
        if kind < 0.45:
            size = min(rng().pareto(2.0) * 0.4 + 0.3, 2.0)
            m = n_of(0.2 + 0.3 * size)
            s = times(m)
            x = T.thud(m, size) * size * 0.12
            x += T.unit(bp(noise(m), 500, 4000)) * np.exp(-s / rng().uniform(0.012, 0.03)) * np.minimum(s / 0.002, 1) * 0.03
        elif kind < 0.62:
            size = rng().uniform(0.3, 1.0)
            m = n_of(0.3)
            x = P.modal_hit(m, rng().uniform(700, 2400) / (0.6 + size), [1.0, rng().uniform(1.45, 2.2), rng().uniform(2.4, 3.9), rng().uniform(4.1, 5.6)],
                            [rng().uniform(0.004, 0.02), rng().uniform(0.003, 0.01), 0.004, 0.002], [1.0, 0.7, 0.45, 0.25], 0.5)
            x = x / (np.abs(x).max() + 1e-9) * 0.07 * size
            if rng().random() < 0.3:
                P.put(x, x * rng().uniform(0.25, 0.5), rng().uniform(0.07, 0.2))
        else:
            m = n_of(0.09)                                     # (a small stone: a body under it, never a bare tick)
            x = T.thud(m, rng().uniform(0.08, 0.2)) * min(rng().pareto(2.4) * 0.35 + 0.15, 2.0) * 0.1
        x = bp(x, None, 1300 + 3200 * near)
        l, r = pan(x * (0.3 + 0.7 * near) * gain, rng().uniform(-0.85, 0.85))
        P.put(L, l, t1)
        P.put(R, r, t1)
    return L, R


def verb(L, R, wet, length=3.5, darken=(2200, 300), decay=1.4):
    """A big dark outdoor space on (L, R): the same length out, a different tail on each side."""
    out = []
    for k, x in enumerate((L, R)):
        ir = T.outdoor_ir(length, 10 + k, density=50.0, darken=darken, decay=decay)
        out.append(x + fftconvolve(x, ir)[:len(x)] * wet)
    return out


def hollow(n, fcs=(97.0, 151.0, 233.0, 373.0, 587.0), amps=(1.0, 0.8, 0.6, 0.35, 0.2), width=0.05):
    """Cold air in something huge and empty: a noise-blown cavity's few resonances, each wandering a little. Unit RMS."""
    x = np.zeros(n)
    d = n / SR
    for f, a in zip(fcs, amps):
        fc = f * (1 + 0.03 * np.clip(PB.slow_random(n, 0.1, 0.6), -2, 2))
        x += P.glide_band(d, fc, width) * a * np.clip(1 + 0.5 * PB.slow_random(n, 0.15, 1.2), 0.1, None)
    return T.unit(x)


# ================================================================================================  bands of chaos, the land's blows
# What the Tsunami and the Supervolcano learnt, the hard way: nothing big has a note. A sine under a blow is a kick drum, ringing
# bubbles are a stream into a can, one envelope on one band of noise is a synth patch, and bare ticks over 1.5 kHz are tin foil.
def band_noise(n, fc, oct_=1 / 3):
    """Unit-RMS noise in a band `oct_` octaves either side of `fc`."""
    m = next_fast_len(n + n_of(0.25), real=True)
    f = rfftfreq(m, 1 / SR)
    u = (np.log2(np.maximum(f, 1.0)) - np.log2(fc)) / oct_
    H = np.where(np.abs(u) < 1, np.cos(np.pi / 2 * u), 0.0)
    y = irfft((rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))) * H, m)[:n]
    return y / (y.std() + 1e-15)


def boiled(n, lo, hi, db_, cap=1.6):
    """A gain wandering by `db_` dB between `lo` and `hi` Hz, its rare freak swell rounded off: a roar has no moment that stands out."""
    return np.exp(db_ * cap * np.tanh(PB.slow_random(n, lo, hi) / cap) / 8.686)


def eddies(d, f0, f1, per_oct=2.5, slope=-4.0, turns=14.0, depth=4.0, drive=None, lift=0.0, pivot=None):
    """Turbulence, unit RMS: bands of noise each boiling on its own at a rate that goes with its pitch, a slow heave at the bottom,
    a fine tearing at the top. `drive`, a curve round 1, brightens as it swells: `lift` dB an octave round `pivot` for each 1 over."""
    n = n_of(d)
    k = max(int(np.log2(f1 / f0) * per_oct) + 1, 2)
    y = np.zeros(n)
    for i in range(k):
        u = i / (k - 1)
        fc = f0 * (f1 / f0) ** u
        r = min(fc / turns, 420.0)
        b = band_noise(n, fc, 0.62 / per_oct) * boiled(n, r * 0.22, r, depth * (1 - 0.66 * u)) * 10 ** (slope * np.log2(fc / f0) / 20)
        if drive is not None and lift:
            b = b * 10 ** (lift * np.log2(fc / (pivot or np.sqrt(f0 * f1))) * (drive - 1) / 20)
        y += b
    return T.unit(y)


def rocks(d, rate, lo, hi, sizes=(0.25, 0.6, 1.3), share=(0.62, 0.3, 0.08), tail=1.9):
    """Rocks landing, unit RMS and dry: `rate` a second (one value a sample), each a dull blow of earth and rock with its body under
    it, strengths heavy-tailed. However thick they come it's a rattle of blows, nothing fine or bright on top."""
    n = n_of(d)
    rate = np.broadcast_to(rate, (n,))
    at = np.nonzero(rng().random(n) < rate / SR)[0]
    y = np.zeros(n)
    which = rng().choice(len(sizes), len(at), p=share)
    amp = np.minimum(rng().pareto(tail, len(at)) * 0.5 + 0.3, 5.0) * rng().choice([-1.0, 1.0], len(at))
    for c, size in enumerate(sizes):
        pick = at[which == c]
        take = rng().integers(0, 5, len(pick))
        a = amp[which == c]
        for k in range(5):
            train = np.zeros(n)
            np.add.at(train, pick[take == k], a[take == k])
            y += fftconvolve(train, T.thud(n_of(0.12 + 0.3 * size), size))[:n] * (0.55 + 0.45 * size)
    return T.unit(bp(y, lo, hi))


def bare_blow(size, lo=26.0, hi=120.0, rise=0.012, fall=0.11):
    """A blow with no pitch in it: low noise up in `rise`, dying over `fall` times `size`. Unit RMS before its shape."""
    m = n_of(fall * size * 7 + 0.05)
    s = times(m)
    return T.unit(bp(noise(m), lo, hi)) * (1 - np.exp(-s / rise)) * np.exp(-s / (fall * size))


def whole(size=1.0, bright=0.4, rise=0.003, fall=0.6, late=0.02):
    """A blow of everything: every third of an octave up at once, each dying at its own rate, the lows last, the top a moment
    after. Its first quarter second has an RMS of `size`. `bright`, 0 to 1: how much of the top there is."""
    fcs = 20.0 * 2 ** (np.arange(30) / 3.0)
    m = n_of(float(np.clip(fall * 6, 0.7, 5.0)))
    s = times(m)
    tilt = np.interp(np.log2(fcs), np.log2([20, 50, 125, 315, 800, 2000, 5000, 12700]),
                     np.array([-6.0, 1, 0, -6, -18, -31, -48, -70]) * (1 - bright) + np.array([-6.0, 1, 0, -1, -2, -3, -6, -12]) * bright)
    fb = np.clip(fall * (fcs / 120.0) ** -0.42, 0.05, fall * 2.2)
    x = np.zeros(m)
    for k, fc in enumerate(fcs):
        if tilt[k] < -60:
            continue
        u = np.maximum(s - late * np.clip((np.log2(fc) - 9.0) / 4.0, 0, 1), 0)
        x += band_noise(m, fc) * (1 - np.exp(-u / rise)) ** 2 * np.exp(-u / fb[k]) * 10 ** (tilt[k] / 20)
    return x / (np.sqrt(np.mean(x[:n_of(0.25)] ** 2)) + 1e-12) * size


def lows_heard(x, fc=70.0, hi=420.0, db_=-5.0):
    """`x` with its lows' own harmonics (a driven copy, kept to `fc`-`hi`), so a laptop implies the weight."""
    lo = bp(x, None, fc * 1.2, 3)
    c = np.percentile(np.abs(lo), 99.0) * 0.35 + 1e-9
    h = bp(np.tanh(lo / c) * c, fc, hi)
    return x + h / (T.loudest(h) + 1e-9) * T.loudest(lo) * 10 ** (db_ / 20)


def land(x, length=4.0, wet=0.5, darken=(1800, 180), decay=1.6, density=35.0, seed=0):
    """`x` off the land round it: clumps of echoes, each later one duller. Mono."""
    ir = T.outdoor_ir(length, seed, density=density, darken=darken, decay=decay)
    return x + fftconvolve(x, ir)[:len(x)] * wet


# Water that big has no note and it isn't a lot of small water: 30 thirds of an octave of independent noise, each under a gain that is
# chaos in dB (the Tsunami's `water`, its numbers from measured surf): eddies on a 1/f curve, slow low down and quick up high, part shared;
# surges of a second or more, up fast, away slowly, bunched, never an LFO; blobs, slaps in the time-frequency plane an octave wide.
CR = 400                                                       # frames a second of the gains
FCS = 20.0 * 2 ** (np.arange(30) / 3.0)
LFC = np.log2(FCS)


def one_over_f(nt, beta, fcut, fmin=0.05):
    """A unit-variance curve with a power spectrum f^-beta between `fmin` and `fcut` Hz, at CR."""
    m = next_fast_len(nt + CR // 2, real=True)
    f = rfftfreq(m, 1 / CR)
    a = np.where(f > 0, np.maximum(f, fmin) ** (-beta / 2), 0.0) / (1 + (f / fcut) ** 6)
    y = irfft(a * (rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))), m)[:nt]
    return y / (y.std() + 1e-12)


def surges(d, rate, up=(0.2, 0.9), down=(0.7, 2.8), bunch=0.55, top=4.5):
    """Swells over seconds, dB, mean 0: arrivals with a wandering rate, heavy-tailed sizes, up quickly, away slowly; no period."""
    nt = int(d * CR) + 2
    r = np.maximum(rate * np.exp(bunch * one_over_f(nt, 1.5, 1.0)), 1e-3)
    p = np.cumsum(r) / CR
    s = np.zeros(nt)
    for a in np.searchsorted(p, rng().uniform(0, p[-1], rng().poisson(p[-1]))):
        u = np.arange(nt - a) / CR
        s[a:] += min(rng().pareto(1.9) + 0.3, top) * (1 - np.exp(-u * 2.5 / rng().uniform(*up))) * np.exp(-u / rng().uniform(*down))
    L = 10 * np.log10(1 + s)
    return L - L.mean()


def blob_field(d, rate, level, flo, fhi, width=(0.5, 1.4), rise=(0.012, 0.05), fall=(0.08, 0.55)):
    """The slaps, as a power gain over 1, bands by frames."""
    nt = int(d * CR) + 2
    H = np.zeros((len(FCS), nt))
    for _ in range(rng().poisson(rate * d)):
        i = int(rng().uniform(0, nt - 2))
        fc, w = rng().uniform(np.log2(flo), np.log2(fhi)), rng().uniform(*width)
        a = level * min(rng().pareto(1.9) + 0.25, 3.5) ** 2
        ru, fa = rng().uniform(*rise), rng().uniform(*fall) * np.clip(1.5 / 2 ** (fc - 9), 0.35, 1.6)
        u = np.arange(min(int(fa * 7 * CR), nt - i)) / CR
        H[:, i:i + len(u)] += a * np.exp(-0.5 * ((LFC - fc) / w) ** 2)[:, None] * ((1 - np.exp(-u / ru)) ** 2 * np.exp(-u / fa))[None, :]
    return H


def water(d, shape, level, surge=(0.42, 1.0), eddy=1.0, blobs=(10.0, 0.6, 90.0, 2400.0)):
    """`d` s of it. `shape`: dB at (20, 31.5, 50, 79, 125, 198, 315, 500, 794, 1260, 2000, 3175, 5040, 8000, 12700, 16000 Hz). `level(t)`: dB over
    it all, `t` in seconds at CR. Unit RMS bands: 0 dB is a band of unit RMS."""
    n, nt = n_of(d), int(d * CR) + 2
    t = np.arange(nt) / CR
    sf = np.log2((20, 31.5, 50, 79, 125, 198, 315, 500, 794, 1260, 2000, 3175, 5040, 8000, 12700, 16000.0))
    over = lambda xs, ys: np.interp(LFC, np.log2(xs), ys)
    s = np.interp(LFC, sf, shape)[:, None] + level(t)[None, :]
    fcut = over([20, 200, 1000, 8000], [3, 8, 14, 22])
    sd = over([20, 200, 1000, 8000], [3.5, 2.6, 2.4, 3.2]) * eddy
    Z = gaussian_filter1d(np.stack([one_over_f(nt, 1.2, c) for c in fcut]), 2.0, axis=0, mode="nearest")
    Z /= Z.std(axis=1, keepdims=True) + 1e-12
    F_ = (np.sqrt(0.75) * Z + np.sqrt(0.25) * one_over_f(nt, 1.2, 8.0)) * sd[:, None]
    sea = surges(d, surge[0])
    regs = [surges(d, surge[0] * r, down=(0.7 * q, 2.8 * q)) for r, q in ((0.7, 1.3), (1.0, 1.0), (1.5, 0.7))]
    wl, wh = over([200, 700], [1, 0]), over([1000, 3000], [0, 1])
    wm = np.clip(1 - wl - wh, 0, 1)
    L = 0.6 * sea[None, :] + 0.7 * (wl[:, None] * regs[0][None, :] + wm[:, None] * regs[1][None, :] + wh[:, None] * regs[2][None, :])
    L = np.where(L > 0, 9.0 * np.tanh(L / 9.0), L)
    s = s + F_ + L * (surge[1] * over([20, 200, 1000, 8000], [0.9, 1.0, 1.2, 1.9]))[:, None]
    G = np.sqrt(10 ** (s / 10) * (1 + blob_field(d, *blobs)))
    ts = np.arange(n) * CR / SR
    y = np.zeros(n)
    for b, fc in enumerate(FCS):
        if G[b].max() > 2e-4:
            y += band_noise(n, fc) * np.interp(ts, np.arange(nt), G[b])
    return y


def rolls(n, t0, count, length):
    """`PB.thunder_rolls`, `n` samples long: a blow going off round the land, each swell from somewhere of its own."""
    l, r = PB.thunder_rolls(n / SR + 0.01, t0, count=count, length=length)
    return l[:n], r[:n]


def panels():
    """The crater's kites as fw_sunk drops them: (ring, let go, first of it down, last of it down), seconds after the slam, in the
    order they let go. Every part of a kite falls alike, so it lands from its shallow edge in; ring 3's reaches the rim."""
    src = (ROOT / "mod" / "shaders" / "fold_warp.wgsl").read_text()
    inv = np.array([float(v) for v in re.search(r"CP_INV: array<f32, 40> = array<f32, 40>\(([^)]*)\)", src).group(1).split(",")]).reshape(8, 5)

    def hash_(k, i):                                           # (fw_hash, in f32 as the shader has it)
        p = np.array([k * 13.0 + 3.0, i * 7.0 + 1.0], dtype=np.float32)
        q = p * np.array([0.1031, 0.1137], dtype=np.float32)
        q = q - np.floor(q)
        d = np.dot(q, q[::-1] + np.float32(33.33))
        v = (q[0] + d) * (q[1] + d)
        return float(v - np.floor(v))

    out_ = []
    for k in range(8):
        for i in range(4):
            late = LATE0 + LATE1 * i + LATE2 * hash_(k, i)
            us = [r * inv[c, 3] for c in (k, (k + 1) % 8) for r in ((1 / inv[c, i - 1] if i else 0.0), 1 / inv[c, i])]
            fall_ = [np.sqrt(BOWL * max(1 - min(u, 1.0) ** 3, 0.0) ** 0.75 / CAVE) for u in (max(us), min(us))]
            out_.append((i, late, late + fall_[0], late + fall_[1]))
    return sorted(out_, key=lambda p_: p_[1])


# ==================================================================================================================  out
def path_of(name):
    return f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"


def decoded(name):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path_of(name) + ".ogg", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(float)


def rounded(x, top, knee=0.6):
    """Peaks rounded off into `top` from `knee` of it up: a little harmonic weight on the big ones, nothing on the rest."""
    k = top * knee
    a = np.abs(x)
    return np.where(a > k, np.sign(x) * (k + (top - k) * np.tanh((a - k) / (top - k))), x)


def out(name, L, R, db, tail=0.3, length=None, peak=PEAK, ref=None):
    """Stereo out: the sum's loudest 400 ms at `db` dB, the peaks rounded off into `peak` (so a sound keeps its level, the
    loudest instants paying for it, not all of it) and held there decoded by the limiter. `tail` s of fade at the end,
    none (a hard end, on the very last sample) if 0; `length` cuts it first, to the sample."""
    n = length if length else min(len(L), len(R))
    x = np.stack([L[:n], R[:n]], axis=1)
    base = np.stack([ref[0][:n], ref[1][:n]], axis=1) if ref else x    # (`ref`: take the gain from this instead)
    g = 10 ** (db / 20) / T.loudest(base.mean(axis=1))
    for _ in range(4):                                       # (rounding takes a little off: put back)
        y = rounded(base * g, peak * 0.97)
        g = g * 10 ** (db / 20) / T.loudest(y.mean(axis=1))
    x = x * g
    x = rounded(x, peak * 0.97)
    if tail:
        nf = n_of(tail)
        x[-nf:] *= np.cos(np.linspace(0, np.pi / 2, nf))[:, None] ** 2
    c = peak * 0.985
    for _ in range(6):
        y = PB.limit(x, c) if np.abs(x).max() > c else x
        PB.write_ogg(path_of(name), y, 2)
        z = decoded(name)
        pk = np.abs(z).max()
        if pk <= peak * 1.004:
            break
        c *= peak / pk
    print(f"wrote {TH}/{name:9s} {len(z) / SR:7.4f}s  loudest {20 * np.log10(T.loudest(z.mean(axis=1))):6.1f} dB  peak {20 * np.log10(pk):6.2f} dBFS")



# =================================================================================================================  the fall
def descent():
    pad = 0.5
    n = n_of(STOP + pad)
    ts = times(n)
    u = np.clip(ts / STOP, 0, 1)
    db = -15.0 * (1 - u) ** 1.2                      # (a fire getting nearer, not a riser; nothing eases before the cut)
    lv = 10 ** (db / 20)

    def roar(t, f):
        fc = 620.0 * (1 + 0.1 * np.sin(t * 2.3))              # (no pitch moving: a roar that stays where it is)
        fa = 9000.0
        lf = np.log2(f / fc)
        body = np.minimum((f / fc) ** 1.0, (fc / f) ** 0.95)
        ridges = sum(a * np.exp(-0.5 * ((lf - o) / 0.17) ** 2) for o, a in ((-1.1, 1.2), (0.0, 2.2), (0.75, 1.5), (1.45, 0.9)))
        return (body + body * ridges) * np.exp(-(f / fa) ** 1.5)

    gust = np.clip(1 + (0.2 + 0.45 * u) * PB.slow_random(n, 3.0, 16.0), 0.15, None)
    near = u ** 2
    a, b = wide(morph(n, roar), morph(n, roar), 0.94 - 0.42 * near)
    L = a * gust * lv
    R = b * gust * lv

    # (wind-shear: bands of the air torn, chopped at an uneven flutter that deepens as it comes)
    for lo, hi, rate, lvl in ((1300, 7500, (18, 55), 0.55), (260, 1100, (7, 26), 0.8)):
        common = PB.slow_random(n, *rate)
        for ch in (L, R):
            chop = np.clip(0.75 * common + 0.25 * PB.slow_random(n, *rate) + 0.3, 0, None) ** 1.7
            chop = 1 + (chop / np.sqrt(np.mean(chop ** 2)) - 1) * (0.35 + 0.65 * near)
            top = np.exp(-(1 - u) * 3.2)
            ch += bn(n, lo, hi) * chop * lv * lvl * (0.25 + 0.75 * top)

    # (flame: a body of fire flapping and tearing at itself, its flicker uneven, fuller as it nears)
    fl = np.clip(0.5 + 0.8 * PB.slow_random(n, 5.0, 26.0), 0.02, None) ** 1.5
    fa_, fb_ = wide(bn(n, 90, 950), bn(n, 90, 950), 0.75 - 0.3 * near)
    L += fa_ * fl * lv * 0.85
    R += fb_ * fl * lv * 0.85

    # (the Payload's way of falling, loosely: a few low resonances wandering in the roar, a thin tearing whine that bends up a little as it closes, never a
    # held note, a rush of torn air sweeping up under it, and in place of a crackle a few dull pops through the air, each a small cluster)
    for f0, q, g in ((112.0, 0.16, 1.0), (139.0, 0.14, 0.8), (262.0, 0.2, 0.75)):
        fc = f0 * (1 + 0.08 * np.clip(PB.slow_random(n, 0.3, 0.9), -1.5, 1.5))
        y = P.glide_band((n + 0.5) / SR, fc, q) * lv * g * 0.7 * np.clip(1 + 0.5 * PB.slow_random(n, 0.4, 1.5), 0.2, None)
        L += y
        R += y
    pitch = 1 + 0.2 * u ** 2.2
    for r, w, g in ((1.0, 0.07, 1.0), (1.437, 0.08, 0.5), (2.23, 0.1, 0.25)):
        fc = 720.0 * r * pitch * (1 + 0.006 * PB.slow_random(n, 2.0, 7.0) + 0.01 * PB.slow_random(n, 0.2, 1.2))
        am = np.exp((2.4 * PB.slow_random(n, 0.3, 2.5) + 1.2 * PB.slow_random(n, 4.0, 14.0)) / 8.686) * (0.08 + 0.26 * u ** 1.5) * lv * g * 3.2
        y, y2 = P.glide_band((n + 0.5) / SR, fc, w), P.glide_band((n + 0.5) / SR, fc * 1.003, w)
        L += (y + y2 * 0.15) * am
        R += (y - y2 * 0.15) * am
    fc = 330.0 * (1450.0 / 330.0) ** (u ** 1.8)
    rl, rr = wide(P.glide_band((n + 0.5) / SR, fc, 1.0), P.glide_band((n + 0.5) / SR, fc * 1.02, 1.0), 0.92 - 0.3 * near)
    e = 10 ** (np.interp(u, (0, 0.6, 0.85, 1), (-16.0, -11.0, -6.0, -2.0)) / 20) * np.exp(1.8 * PB.slow_random(n, 0.5, 3.0) / 8.686) * 2.2
    L += rl * e
    R += rr * e
    pl, pr = P.pop_crackle(STOP + pad, 0.0, lambda v: np.interp(v, (0, 2.2, STOP), (5.0, 6.5, 9.0)), lambda v: np.interp(v, (0, STOP), (-4.0, 6.0)), big=1.4, smear=0.8,
                           air_fc=lambda v: np.interp(v, (0, 2.4, STOP), (3200.0, 4200.0, 5600.0)))
    L += pl[:n]
    R += pr[:n]

    # (the pressure rising under it)
    f = 31.0 * (1 + 0.04 * np.clip(PB.slow_random(n, 2.0, 12.0), -2, 2))
    ph = 2 * np.pi * np.cumsum(f) / SR
    sub = (np.sin(ph) + 0.5 * np.sin(2 * ph + 1) + 0.3 * np.tanh(3 * np.sin(ph))) * lv * (0.5 + 0.5 * near) * 2.2
    rumble = bn(n, 28, 170) * gust * lv * 2.0
    L += sub + rumble
    R += sub + rumble

    L, R = low_mono(L, R, 200.0)
    # (full force: the last of it driven hard)
    g = 1.0 / np.abs(np.stack([L, R])[:, n_of(STOP - 0.4):n_of(STOP)]).max()
    L, R = (np.tanh(c * g * 1.4) / np.tanh(1.4) for c in (L, R))
    out("descent", L, R, -9.0, tail=0, length=n_of(STOP))

# ===================================================================================================================  ice
AIR = 340.0
THICK = {"thin": 1100.0, "skate": 725.0, "mid": 420.0, "thick": 195.0, "slab": 110.0}    # the held tone, Hz, by the sheet
_kernels = {}


def plate(f, fc, cmax=1900.0):
    """A floating sheet's bending wave: (wavenumber, group speed) at `f`, its phase speed the speed of sound at `fc` and
    going as sqrt(f) above it, up to what stiff ice can carry."""
    cp = 1.0 / np.sqrt(1.0 / (AIR ** 2 * np.maximum(f, 1.0) / fc) + 1.0 / cmax ** 2)
    return 2 * np.pi * f / cp, 2 * cp


def scatter(f, rough=4.5):
    """The sheet isn't even: a gain that wanders across the band, different each time, so a chirp comes in patches."""
    lf = np.log2(np.maximum(f, 20.0))
    nodes = rng().normal(0, 1, 40)
    return 10 ** (np.interp(lf, np.linspace(4, 14.5, 40), nodes) * rough / 20)


def flex(exc, d, fc, q=90.0, rough=4.5, top=None):
    """`exc` (a hit, at time 0) heard `d` m along the sheet: the dispersion's phase put on it in the frequency domain.
    Under `fc` nothing radiates; the highs die with distance (`q`). Time 0 of the result is the hit."""
    late = d / (2 * AIR * 0.72) + 0.1
    size = next_fast_len(len(exc) + n_of(late) + 2048)
    f = rfftfreq(size, 1 / SR)
    k, cg = plate(f, fc)
    keep = 1.0 / (1.0 + (0.86 * fc / np.maximum(f, 1.0)) ** 10) * np.exp(-np.pi * f * d / (q * cg)) * scatter(f, rough)
    if top:
        keep = keep / (1.0 + (f / top) ** 4)
    return irfft(rfft(exc, size) * keep * np.exp(-1j * k * d), size)


def hit(v, m=2400):
    """What strikes the sheet: a short rough burst, 0 bright (a pebble) to 2 dull (a boot's weight)."""
    s = times(m)
    tau = (0.00018, 0.0006, 0.002)[v]
    x = noise(m) * np.exp(-s / tau)
    return T.unit(x[: max(n_of(tau * 7), 16)])


def kernel(d, fc, v):
    """One hit's whole sound at `d`: the chirp, the tone it lands on, the shore's longer, duller copy, the knock through
    the air last. Peak 1. Kept by distance band, three takes each."""
    band_ = int(round(np.log(max(d, 8.0)) / np.log(1.07)))
    take = int(rng().integers(0, 3))
    key = (band_, fc, v, take)
    if key not in _kernels:
        d0 = 1.07 ** band_
        e = hit(v)
        y = flex(e, d0, fc)
        out_ = np.zeros(n_of(d0 / AIR * 2.6 + 1.6))
        P.put(out_, y[:len(out_)], 0)
        ref = np.max(np.abs(y)) + 1e-12
        # (a second way round through the broken sheet, a little longer: fringes in the chirp, never a clean line)
        y1 = flex(e, d0 * rng().uniform(1.03, 1.12), fc)
        P.put(out_, y1[:len(out_)] * 0.55, 0)
        # the held tone: from where the chirp lands until the air wave, wandering a hair
        t0, t1 = d0 / (2 * AIR), d0 / AIR
        m = n_of(t1 - t0 + 0.12)
        s = times(m)
        g = fc * (1 - 0.018 * s / max(t1 - t0, 0.02)) * (1 + 0.002 * PB.slow_random(m, 8, 40))
        tone = np.sin(2 * np.pi * np.cumsum(g) / SR + rng().uniform(0, 6)) * (1 - np.exp(-s / 0.012)) * np.exp(-s / max(0.5 * (t1 - t0), 0.03))
        P.put(out_, tone * ref * 0.2, t0)
        # the shore: a path twice over, longer, duller
        shore = d0 + rng().uniform(120, 340)
        y2 = flex(e, 2 * shore - d0, fc, 160.0)
        P.put(out_, y2[:len(out_)] / (np.abs(y2).max() + 1e-12) * ref * 0.3, 0)
        # the hit through the air
        m = n_of(0.05)
        knock = bp(noise(m), 120, 900) * np.exp(-times(m) / 0.008)
        P.put(out_, knock / (np.abs(knock).max() + 1e-9) * ref * 3.0 / (1 + d0 / 25), t1)
        _kernels[key] = out_ / (np.abs(out_).max() + 1e-12)
    return _kernels[key]


def ice(L, R, t, d, fc, amp, p, v=None):
    """One crack, `d` m off, starting (at the source) at `t` s."""
    v = int(rng().integers(0, 3)) if v is None else v
    y = kernel(d * rng().uniform(0.97, 1.03), fc, v) * amp
    l, r = pan(y, p)
    P.put(L, l, t)
    P.put(R, r, t)


def pew(L, R, t, d, fc, amp, p, v=1):
    """One clean chirp with air round it: a soft hit, no knock, the top rounded, the sheet's unevenness only a touch, one
    quiet longer copy behind it. Made fresh each time, so no two are alike."""
    e = hit(v)
    y = flex(e, d, fc, 110.0, 2.5, 5200.0)
    o = np.zeros(n_of(d / AIR * 2.2 + 1.4))
    P.put(o, y[:len(o)], 0)
    ref = np.abs(y).max() + 1e-12
    y1 = flex(e, d * rng().uniform(1.04, 1.1), fc, 110.0, 2.5, 5200.0)
    P.put(o, y1[:len(o)] * 0.3, 0)
    t0, t1 = d / (2 * AIR), d / AIR
    m = n_of(t1 - t0 + 0.1)
    s = times(m)
    g = fc * (1 - 0.018 * s / max(t1 - t0, 0.02))
    tone = np.sin(2 * np.pi * np.cumsum(g) / SR + rng().uniform(0, 6)) * (1 - np.exp(-s / 0.02)) * np.exp(-s / max(0.42 * (t1 - t0), 0.03))
    P.put(o, tone * ref * 0.13, t0)
    y2 = flex(e, d + 2 * rng().uniform(120, 340), fc, 170.0, 2.5, 3800.0)
    P.put(o, y2[:len(o)] / (np.abs(y2).max() + 1e-12) * ref * 0.2, 0)
    l, r = pan(o / (np.abs(o).max() + 1e-12) * amp, p)
    P.put(L, l, t)
    P.put(R, r, t)


def stones(L, R, t, d0, d1, count, fc, amp, side):
    """A stone skipping away: each skip further, nearer in time, quieter; it just stops, as a stone does."""
    gap = rng().uniform(0.3, 0.4)
    d = d0
    grow = (d1 / d0) ** (1 / max(count - 1, 1))
    for k in range(count):
        pew(L, R, t, d, fc, amp * 0.8 ** k, side * (0.12 + 0.75 * k / count))
        t += gap
        gap *= rng().uniform(0.72, 0.82)
        d *= grow


def runs(L, R, t, d0, d1, count, fc, amp, side):
    """A crack running off: a few separate jumps, each heard on its own."""
    for k in range(count):
        s = k / max(count - 1, 1)
        pew(L, R, t, d0 + (d1 - d0) * s, fc, amp * (1 - 0.55 * s), side * (0.1 + 0.75 * s), 2 if rng().random() < 0.3 else 1)
        t += rng().uniform(0.09, 0.17)


def sheer(n, at, dur, power=1.0):
    """The land parting: no fibres, no grit: a long dark breath of ground giving way, its weight sliding down. (L, R)."""
    m = n_of(dur)
    t = times(m)
    v = ss(0.0, dur * 0.3, t) * (1 - ss(dur * 0.55, dur, t))
    fc = 380.0 * (0.3 ** (t / dur))
    exact = (m + 0.5) / SR                                     # (`glide_band` counts its samples its own way)
    a = P.glide_band(exact, fc, 0.9) * np.clip(1 + 0.3 * PB.slow_random(m, 1.0, 6.0), 0.3, None)
    b = P.glide_band(exact, fc * 1.3, 0.9) * np.clip(1 + 0.3 * PB.slow_random(m, 1.0, 6.0), 0.3, None)
    low = bn(m, 26, 110) * v * 0.9
    L, R = np.zeros(n), np.zeros(n)
    P.put(L, (a * 0.55 + low * 0.9) * v * power, at)
    P.put(R, (a * 0.4 + b * 0.25 + low * 0.9) * v * power, at)
    return L, R


# =================================================================================================================  liquid
def bubble(f0, amp, rise=0.14, damp=0.03):
    """One bubble: a decaying tone on its Minnaert pitch, rising a little as it nears the surface."""
    tau = 1 / (np.pi * f0 * damp)
    m = n_of(tau * 6)
    s = times(m)
    y = np.sin(2 * np.pi * np.cumsum(f0 * (1 + rise * s / tau)) / SR) * np.exp(-s / tau) * np.minimum(s * f0 * 3, 1)
    return y * amp


def bubbles(L, R, t_lo, t_hi, rate, f_lo, f_hi, gain, spread=0.7):
    for t1 in P.poisson_times(t_lo, t_hi, rate):
        f = float(np.exp(rng().uniform(np.log(f_lo), np.log(f_hi))))
        a = min(rng().pareto(2.2) * 0.45 + 0.3, 2.2) * (f_lo / f) ** 0.4
        y = bubble(f, a * gain, rng().uniform(0.05, 0.3), rng().uniform(0.022, 0.05))
        l, r = pan(y, rng().uniform(-spread, spread))
        P.put(L, l, t1)
        P.put(R, r, t1)


# ==================================================================================================================  spaces
def hollow_ir(k, length=7.0, lo=1.7, mid=1.0, hi=0.3, build=0.12):
    """Inside the sphere: long, dark, smooth (no slapback), filling slowly, the far wall coming back ~2.8 s on as a swell
    in the tail rather than an echo. A different tail per side."""
    n = n_of(length)
    t = times(n)
    r = np.random.default_rng(4100 + k)
    x = r.standard_normal(n)
    ir = bp(x, None, 280) * np.exp(-t / lo) + 0.7 * bp(x, 280, 1500) * np.exp(-t / mid) + 0.2 * bp(x, 1500, 6000) * np.exp(-t / hi)
    ir *= (1 - np.exp(-t / build)) * (1 + 0.55 * np.exp(-0.5 * ((t - 2.8) / 0.3) ** 2) + 0.25 * np.exp(-0.5 * ((t - 5.6) / 0.45) ** 2))
    return ir / np.sqrt(np.sum(ir ** 2))


def inside(L, R, send, wet, lo=None):
    """(L, R) sent into the sphere by `send` (one value a sample, or 1), only what's over `lo` Hz: the tail only; add it."""
    o = []
    for k, x in enumerate((L, R)):
        x = bp(x, lo, None) if lo else x
        o.append(fftconvolve(x * send, hollow_ir(k))[:len(x)] * wet)
    return o


def muffle(x, w, hi=420.0):
    """`x` losing its top as `w` goes 0 to 1: the open sky shut out."""
    return x * (1 - w) + bp(x, None, hi) * w


def creak_take(dur, f0):
    """One creak of something huge twisting (bark, a hull's plate): slow grabs quickening and easing through a body with
    its own modes, never the same body twice. Mono."""
    n = n_of(dur)
    t = times(n)
    u = t / dur
    e = np.sin(np.pi * u ** rng().uniform(0.6, 1.3)) ** 1.4
    rate = (6.0 + rng().uniform(18, 46) * e ** 1.5) * np.clip(1 + 0.25 * PB.slow_random(n, 0.8, 5.0), 0.4, None)
    x = stick(n, rate, 0.3, 0.12, 0.004, 0.0012)
    ratios = np.cumprod(rng().uniform(1.35, 1.75, 7))
    body = bank(x, [(f0 * r, rng().uniform(6, 10), 0.8 ** k) for k, r in enumerate(ratios)])
    return (T.unit(body) + 0.3 * T.unit(bp(x, 1400, 3800))) * e * np.clip(1 + 0.45 * PB.slow_random(n, 0.8, 4.0), 0.2, None)


# ==============================================================================================================  the stop
def plop(f0, f1, amp, tau, top=2.2):
    """One deep water drop's sound: the bubble a stone's closure leaves, its pitch climbing from `f0` to `f1` as it rises, gone in `tau` or so. The note of it is what a
    drop is, so it keeps its note; a band of wet noise on the same pitch, and a driven copy for its edges, make it water and not a synth. Mono, peak `amp`."""
    d = max(tau * 6, 0.2)
    n = n_of(d)
    t = times(n)
    f = f0 + (f1 - f0) * (1 - np.exp(-t / (tau * 0.9)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = (1 - np.exp(-t / 0.007)) * np.exp(-t / tau)
    core = np.sin(ph) + 0.22 * np.sin(2 * ph + 0.6)
    wet = P.glide_band((n + 0.5) / SR, f * 1.02, 0.34)
    edge = bp(np.tanh(top * core), 150, 1400)
    y = (core + T.unit(wet) * 0.2 + edge * 0.24) * e
    return y / (np.abs(y).max() + 1e-9) * amp


def surge_gain(n, depth):
    """A gain going by surges, up quickly and away slowly, no period: air moving in lumps. Mean about 1."""
    d = n / SR
    s = surges(d, 1.6, (0.1, 0.4), (0.3, 1.1))
    return np.interp(np.arange(n) * CR / SR, np.arange(len(s)), 10 ** (s * depth / 20))


def field(d, f, top, seed_side=0.3):
    """What's holding it up: a thick electric weight of a hum, every harmonic of `f` (Hz, one value a sample) to about 900 Hz, two voices a hair apart so it never sits still,
    through a body with its own wide bumps, so it's heavy machinery and not an oscillator, closing over `top` (Hz, one value a sample). Unit RMS. (L, R)."""
    n = n_of(d)
    t = times(n)
    out_ = []
    for sgn in (-1.0, 1.0):
        y = np.zeros(n)
        for det in (0.0, 0.31 * sgn):
            ph = 2 * np.pi * np.cumsum(f + det) / SR + rng().uniform(0, 6)
            for k in range(1, 22):
                a = k ** -0.72 * np.clip((1100.0 - k * np.mean(f)) / 500.0, 0, 1) * (1 + 0.3 * rng().standard_normal())
                y += a * np.sin(k * ph + rng().uniform(0, 6))
        y = bank(y, ((88, 2, 1.0), (176, 3, 1.1), (342, 3, 1.0), (610, 3, 0.8)))
        lo, hi = bp(y, None, 260, 2), bp(y, 260, None, 2)
        w = np.clip(np.log2(np.maximum(top, 200.0) / 260.0) / 3.2, 0, 1)
        out_.append(T.unit(lo) + T.unit(hi) * w)
    return out_[0], out_[1]


def wobble():
    """The fire is cut dead and the thing doesn't stop by itself: something catches it. A deep soft push of pressure as all that speed is taken up, no contact and nothing struck, and
    a heavy hum coming up under it, thrown off its pitch by the catch and settling back in the picture's wobble (fold.wgsl: 0.055 e^(-5.5 a) sin 14 a), the top of it closing as
    it locks on; a dark sheen of air going through the same comb for a moment; then only the hum, low and steady, holding it dead still to the let-go at 4.5. Plays 0.09 s after the stop."""
    d = HANG - STOP - 0.09 + 0.12
    n = n_of(d)
    t = times(n)
    e_wob = np.exp(-5.5 * t) * np.sin(14.0 * t + 0.25)
    f = 46.25 * (1 + 1.1 * np.exp(-t / 0.045) + 0.32 * e_wob)
    top = 300.0 + 3000.0 * np.exp(-t / 0.17)
    a, b = field(d, f, top)
    lv = 10 ** (np.interp(t, (0.0, 0.03, 0.14, 0.4, 0.75, d - 0.14, d), (-14.0, -3.0, 0.0, -10.0, -18.0, -22.0, -22.0)) / 20)
    L, R = a * lv, b * lv
    # (the catch: all that speed taken up by nothing, a push of air and pressure)
    M = bare_blow(3.6, 20, 95, 0.03, 0.11) * 1.6
    x = np.zeros(n)
    P.put(x, M[:n], 0.0)
    x = x + bn(n, 34, 170) * (1 - np.exp(-t / 0.02)) * np.exp(-t / 0.2) * 0.8
    x = x + bn(n, 20, 62) * ss(0.0, 0.1, t) * 10 ** (np.interp(t, (0.0, 0.4, d), (-6.0, -16.0, -27.0)) / 20) * 0.6     # (its weight, the hold's pressure)
    # (the air it was carrying going through the same field for a moment: noise on the hum's own comb, dark, gone in half a second)
    sheen = np.zeros(n)
    for k in range(3, 40, 2):
        sheen += P.glide_band((n + 0.5) / SR, np.maximum(f * k, 60.0), 0.012)
    sheen = bp(sheen, 240, 3400) / (T.loudest(bp(sheen, 240, 3400)) + 1e-9)
    e = ss(0.0, 0.03, t) * np.exp(-t / 0.16)
    a, b = wide(sheen, np.roll(sheen, 613), 0.5)
    L, R = L + x + a * e * 0.9, R + x + b * e * 0.9
    L, R = verb(L, R, 0.2, length=1.6, darken=(1100, 200), decay=0.7)
    L, R = lows_heard(L, 70, 360, -7.0), lows_heard(R, 70, 360, -7.0)
    L, R = low_mono(L, R, 170.0)
    out("wobble", L, R, -15.0, tail=0.1)


def air():
    """What kept going when the droplet stopped: a soft shove, the fire's own roar carried past and away, embers, and the
    gust thinning out over the ground. Nothing granular: a wind, not a texture."""
    d = 3.2
    n = n_of(d)
    t = times(n)
    whump = (bn(n, 26, 110) * 1.3 + bn(n, 110, 300) * 0.25) * (1 - np.exp(-t / 0.09)) * np.exp(-t / 0.42)

    def rush(s, f):
        fc = 240.0 + 650.0 * np.exp(-s / 0.6)                 # (going by, and off: its top falling away)
        return np.minimum((f / fc) ** 1.0, (fc / f) ** 0.8) * np.exp(-(f / (1500.0 + 4500.0 * np.exp(-s / 0.8))) ** 1.5)

    gust = np.clip(1 + 0.45 * PB.slow_random(n, 0.5, 4.0), 0.25, None)
    e = ss(0.03, 0.45, t) * np.exp(-t / 0.95) * gust
    a, b = wide(morph(n, rush), morph(n, rush), 0.5)
    p = -0.75 + 1.5 * ss(0.05, 1.6, t)                         # (past you, across)
    L = a * e * 0.8 * np.cos((p + 1) * np.pi / 4) * 1.41 + whump
    R = b * e * 0.8 * np.sin((p + 1) * np.pi / 4) * 1.41 + whump
    # (the fire carried by: the descent's flames, thinning)
    fl = np.clip(0.5 + 0.8 * PB.slow_random(n, 5.0, 22.0), 0.02, None) ** 1.5
    c, c2 = wide(bn(n, 120, 1000), bn(n, 120, 1000), 0.5)
    fire = ss(0.0, 0.2, t) * np.exp(-t / 0.5) * fl * 0.42
    L += c * fire
    R += c2 * fire
    # (a few embers, each its own small snap)
    for t1 in P.poisson_times(0.06, 1.3, lambda s: 12.0 * np.exp(-s / 0.4)):
        m = n_of(0.012)
        y = bp(noise(m), 900, 5200) * np.exp(-times(m) / rng().uniform(0.001, 0.003)) * min(rng().pareto(2.2) * 0.2 + 0.12, 0.6) * np.exp(-t1 / 0.7)
        l, r = pan(y, rng().uniform(-0.7, 0.7))
        P.put(L, l, t1)
        P.put(R, r, t1)
    # (the dust: a gust's fine top going off over the ground, smooth)
    dust = ss(0.2, 0.9, t) * np.exp(-np.maximum(t - 0.9, 0) / 0.7) * np.clip(1 + 0.4 * PB.slow_random(n, 0.4, 2.5), 0.2, None)
    a, b = wide(bn(n, 1800, 8000), bn(n, 1800, 8000), 0.2)
    L += a * dust * 0.075
    R += b * dust * 0.075
    L, R = verb(L, R, 0.18, length=2.0, darken=(1800, 260), decay=0.8)
    L, R = low_mono(L, R, 170.0)
    out("air", L, R, -25.0, tail=0.5)


def letgo():
    """Whatever had it lets go: `wobble`'s hum falling out from under it, down through the floor in about half a second, and the mass goes. Then the fall itself: one body of air
    being split, its loudness the speed squared on the picture's free fall (4.5 to 6.0, 82 blocks a second at the end), low and torn, opening as it comes, the air under it
    packing down over the land; on the last of it the land's own answer is already there (`meld`). It stops on contact."""
    d = TOUCH - HANG
    n = n_of(d)
    t = times(n)
    u = t / d
    f = 12.0 + 34.25 * np.exp(-t / 0.2)
    a, b = field(d, f, 200.0 + 1900.0 * np.exp(-t / 0.13))
    e = ss(0.0, 0.03, t) * np.exp(-t / 0.2) * 0.62
    L, R = a * e, b * e
    # (it goes: one soft low drop of pressure as the weight leaves the hold)
    x = np.zeros(n)
    P.put(x, bare_blow(3.2, 18, 90, 0.05, 0.13)[:n] * 1.0, 0.0)
    L, R = L + x, R + x
    sp = np.clip(t / d, 0, 1)

    def over(s_, f_):
        v = min(s_ / d, 1.0)
        fc = 150.0 + 230.0 * v
        return np.minimum((f_ / fc) ** 1.2, (fc / f_) ** 0.9) * np.exp(-(f_ / (900.0 + 4200.0 * v ** 1.5)) ** 1.5)

    lv = sp ** 2.0
    a, b = wide(morph(n, over), morph(n, over), 0.72 - 0.3 * sp)
    gust = np.clip(1 + 0.42 * PB.slow_random(n, 3.0, 14.0), 0.2, None)
    tear = eddies(d, 200, 2400, 2.5, -3.0, 12.0, 6.0)
    L += (a * gust * 0.8 + tear * 0.28) * lv
    R += (b * gust * 0.8 + tear * 0.28) * lv
    low = bn(n, 20, 80) * np.clip(1 + 0.3 * PB.slow_random(n, 1.5, 7.0), 0.3, None) * sp ** 2.8 * 0.7    # (the air packing down under it)
    L, R = L + low, R + low
    L, R = lows_heard(L, 70, 360, -8.0), lows_heard(R, 70, 360, -8.0)
    L, R = low_mono(L, R, 170.0)
    gate = 1 - ss(d - 0.012, d - 0.002, t)
    out("letgo", L * gate, R * gate, -15.5, tail=0, length=n)


def meld():
    """A deep, solid water drop, the size of a house, going into the land. The land rises faintly to meet it; on 6.0 the drop lands, a heavy wet blow with the whole fall behind it, the land opening
    under it in a dark low gulp of air; at 6.2 the land shuts over it, and that is the sound: the great round plop of a drop going in, its pitch climbing as the bubble it leaves comes up, a smaller
    one after it, a smaller one again, and the last small drop falling back. Then only the land's heave, under `ripple`."""
    lead = MELD_LEAD
    d = 2.1 + lead
    n = n_of(d)
    t = times(n)
    t0 = lead
    u = np.maximum(t - t0, 0)
    on = t >= t0
    # (the land rising to meet it from 5.6 s: a slow breath of weight, earth shifting in it, till the blow takes over)
    rise = ss(0.0, lead, t) * (1 - ss(lead + 0.02, lead + 0.5, t))
    ph2 = 2 * np.pi * np.cumsum(27.0 + 7.0 * ss(0.0, lead, t)) / SR
    swell = (np.sin(ph2) + 0.3 * np.sin(2 * ph2 + 0.5)) * rise * 0.1
    swell += bn(n, 45, 170) * np.clip(grn(d, 22.0, (0.03, 0.08)), 0, 4) * rise * 0.025
    # (the blow: dense liquid on the ground, thick and wet, nothing stony and nothing that rings)
    body = struck(n, t0, 0.05, ((30, 3, 1.3), (43, 4, 1.1), (61, 4, 0.9), (88, 3, 0.75), (133, 3, 0.55)), 30)
    thick = struck(n, t0, 0.04, ((118, 2.5, 1.0), (187, 2.5, 0.8), (296, 2, 0.5)), 24)
    chest = blow(n, t0 + 0.008, 62, 46, 33, 0.05, 0.007, [(0.8, 0.14), (0.2, 0.4)], drive=2.6, octv=0.26, h3=0.12, harm=0.5)
    slap = bn(n, 240, 1500) * (1 - np.exp(-u / 0.003)) * np.exp(-u / 0.05) * on
    hit_ = body * 0.8 + thick * 0.7 + chest * 0.42 + slap * 0.3
    # (the cavity opening under it, the air going down)
    c = ss(0.0, 0.05, u) * (1 - ss(CLOSED - TOUCH - 0.06, CLOSED - TOUCH + 0.02, u)) * on
    gulp = P.glide_band((n + 0.5) / SR, 86.0 - 40.0 * ss(0.0, 0.2, u), 0.4) * c * 0.5
    # (the land heaving after it, settling; slow earth, no grit)
    hv = ss(0.1, 0.5, u) * (1 - ss(0.6, 1.5, u)) * on
    ph3 = 2 * np.pi * np.cumsum((24.0 + 7.0 * (1 - ss(0.0, 1.4, u))) * on) / SR
    heave = (np.sin(ph3) + 0.35 * np.sin(2 * ph3 + 0.6) + 0.18 * np.sin(3 * ph3 + 1.4)) * hv * 0.24
    heave += bn(n, 46, 175) * np.clip(1 + 0.45 * PB.slow_random(n, 1.5, 7.0), 0.15, None) * hv * 0.1
    L = swell + hit_ + gulp + heave
    R = L.copy()
    # (the drop going in: the land shuts at CLOSED)
    at = lead + CLOSED - TOUCH
    for dt, f0, f1, a_, tau, p in ((0.0, 62, 150, 1.5, 0.15, 0.0), (0.2, 96, 214, 0.7, 0.1, -0.18), (0.36, 142, 300, 0.42, 0.07, 0.22), (0.72, 196, 410, 0.26, 0.055, -0.1)):
        l, r = pan(plop(f0, f1, a_, tau), p)
        P.put(L, l, at + dt)
        P.put(R, r, at + dt)
    # (the wet of it closing over the top: a soft slap, no splash of bright drops)
    m = n_of(0.3)
    y = T.unit(bp(noise(m), 300, 2200)) * (1 - np.exp(-times(m) / 0.008)) * np.exp(-times(m) / 0.05) * 0.12
    P.put(L, y, at)
    P.put(R, y, at)
    L, R = low_mono(*verb(L, R, 0.3, length=2.0, darken=(1100, 200), decay=0.85), 170.0)
    out("meld", L, R, -12.5, tail=0.3, peak=10 ** (-2.5 / 20))


def ripple():
    """The land moving like water, and not one note in it: the five pulses, then the swell going under the player, each a slow sea of the
    ground's own weight, built as big water is. Its top is the wet soil going by, opening a little on each crest; the first hairline at the end."""
    d = 7.9
    n = n_of(d)
    t = times(n)
    SEAS = tuple(zip((*PULSES, *SWELLS), (0.9, 1.0, 1.0, 1.0, 1.1, 1.6, 1.7, 1.5, 1.3), (0.14, 0.3, 0.46, 0.6, 0.42, 0.34, 1.0, 0.62, 0.28)))

    def crest(tc, power=1.0):
        """How the heaves stand at `tc` seconds: a sum of the seas, each up quickly and away slowly."""
        e = np.zeros(len(tc))
        for t_, dur, amp in SEAS:
            v = np.clip((tc - (t_ - RIPPLE)) / dur, 0, 1)
            e = e + amp * (v ** 0.8 * (1 - v) ** 1.7 / 0.31) ** power
        return e

    # (the weight of it, under 200 Hz; the wash over it, what a phone hears, opening later and only on the crests)
    weight = water(d, (-8.0, 0, 2, 0, -4, -9, -16, -24, -34, -46, -60, -70, -80, -90, -90, -90), lambda s: 20 * np.log10(0.05 + crest(s)), (0.3, 0.5), 1.0, (6.0, 0.5, 40.0, 240.0))
    wash = water(d, (-40.0, -30, -20, -12, -6, -2, -1, -3, -6, -10, -15, -21, -28, -36, -48, -60), lambda s: 20 * np.log10(0.035 + 0.8 * crest(s - 0.12, 1.5)), (0.5, 0.9), 1.0, (9.0, 0.8, 120.0, 1800.0))
    L, R = weight + wash * 0.6, weight + wash * 0.6
    b = water(d, (-40.0, -30, -20, -12, -6, -2, -1, -3, -6, -10, -15, -21, -28, -36, -48, -60), lambda s: 20 * np.log10(0.035 + 0.8 * crest(s - 0.12, 1.5)), (0.5, 0.9), 1.0, (9.0, 0.8, 120.0, 1800.0))
    R = R + (b - wash) * 0.2
    L, R = lows_heard(L, 70, 300, -9.0), lows_heard(R, 70, 300, -9.0)
    L, R = low_mono(L, R, 170.0)
    L, R = verb(L, R, 0.14, length=2.6, darken=(900, 200), decay=1.0)
    # (the first hairline, right at the end, a hint)
    a, b = np.zeros(n), np.zeros(n)
    pew(a, b, 3.7, 300, THICK["skate"], 0.03, -0.5)
    pew(a, b, 4.25, 220, THICK["skate"], 0.05, 0.4)
    out("ripple", L + a, R + b, -17.5, tail=0.2)


# ============================================================================================================  the creases
def score():
    dur = FOLD - SCORE
    d = dur + 1.5
    n = n_of(d)
    L, R = np.zeros(n), np.zeros(n)
    # (one pew alone; a beat; a stone skipping off; then more, thicker, always one at a time with air between them)
    pew(L, R, 0.0, 110, THICK["skate"], 1.0, -0.15)
    stones(L, R, 0.9, 70, 320, 5, THICK["skate"], 0.8, 1.0)
    L, R = verb(L, R, 0.07, length=2.4, darken=(2600, 300), decay=0.9)
    L, R = PB.causal_lowcut(L, 45.0), PB.causal_lowcut(R, 45.0)
    L, R = low_mono(L, R, 170.0)
    # (and that's all of the cracks; the ground parting under the tears is only a dark breath now, no crack on it, there so `ripple`'s end and the bend have something between them)
    gl, gr = np.zeros(n), np.zeros(n)
    for at, ln, po in ((3.2, 3.4, 0.12), (TEAR - SCORE + 1.6, 1.9, 0.16)):
        a, b = sheer(n, at, ln, po)
        gl += a
        gr += b
    gl, gr = low_mono(gl, gr, 170.0)
    out("score", L + gl, R + gr, -18.45, tail=0.4, peak=10 ** (-2.5 / 20), ref=(L, R))


# the machine's two voices, tick and tock: the same great mechanism, so a listener hears one thing going round (Hz, Q, gain)
TICK = ((34, 3, 1.1), (49, 4, 1.2), (71, 5, 1.1), (104, 5, 1.0))
TOCK = ((29, 3, 1.1), (43, 4, 1.2), (62, 5, 1.1), (91, 5, 1.0))
CLANK = ((143, 7, 1.0), (211, 9, 0.9), (317, 9, 0.8), (457, 8, 0.5), (689, 7, 0.28))
CLUNK = ((127, 7, 1.0), (187, 9, 0.95), (283, 9, 0.75), (409, 8, 0.45), (613, 7, 0.24))


def clack(size, tock, big):
    """One detent of the land going over: a pawl lifting, 80 ms of nothing much, the whole weight dropping into the next notch, and a small bounce on it. Heavy metal and rock, a body with a few
    short modes that stop, nothing that rings, no bright edge. The modes wander a hair each time. Mono, 1.2 s, the drop 0.1 s in."""
    m = n_of(1.2)
    s = times(m)
    t0 = 0.1
    q = np.maximum(s - t0, 0)
    on = s >= t0
    jit = lambda modes: tuple((f * rng().uniform(0.97, 1.03), Q, a) for f, Q, a in modes)
    low, mid = (TOCK, CLUNK) if tock else (TICK, CLANK)
    x = struck(m, t0, 0.012 + 0.012 * big, jit(low), 16, 0.4) * 1.0
    x = x + struck(m, t0, 0.008, jit(mid), 10, 0.5) * (0.8 + 0.2 * big) * np.exp(-q / (0.09 + 0.05 * big))
    x = x + rough(m, t0, 0.006, 8, 220, 1500, 0.004) * 0.22
    x = x + bn(m, 40, 210) * (1 - np.exp(-q / 0.002)) * np.exp(-q / (0.06 + 0.05 * big)) * on * 0.5
    x = x + bn(m, 90, 420) * (1 - np.exp(-q / 0.01)) * np.exp(-q / 0.05) * on * 0.1        # (the air out of the notch)
    P.put(x, struck(n_of(0.3), 0.0, 0.004, jit(mid[:3]), 6, 0.5) * 0.3, t0 - 0.082)       # (the pawl lifting)
    P.put(x, struck(n_of(0.3), 0.0, 0.004, jit(mid[:3]), 6, 0.5) * 0.26, t0 + 0.068)      # (and bouncing)
    return x * size


def unravel():
    """The land bending as a machine turns: `CLACKS`, a great mechanism going over one detent at a time, tick and tock, deep and heavy and dead regular, each heave of the land (`RINGS`) a bigger
    one with the weight of a ring going over it, closer together as the land comes round, the last on the world's stopping. Each goes off the land still standing, a long way out and back. All made
    here: no film's sound in it, only the idea of scale. From 26 s the sky shuts, and what's left of it comes through the ground."""
    dur = SEAL - FOLD
    d = dur + 1.0
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    eL, eR = np.zeros(n), np.zeros(n)                          # (what goes out to the land still standing)
    for k, (at, big) in enumerate(CLACKS):
        v = k / (len(CLACKS) - 1)
        size = (1.0 if big else 0.56 + 0.14 * (k % 2)) * (0.72 + 0.28 * v) * rng().uniform(0.95, 1.05)
        x = clack(size, k % 2 == 1, big)
        p = (-1) ** k * 0.14
        l, r = pan(x, p)
        P.put(L, l, at - FOLD - 0.1)
        P.put(R, r, at - FOLD - 0.1)
        P.put(eL, x * (0.5 - p), at - FOLD - 0.1)
        P.put(eR, x * (0.5 + p), at - FOLD - 0.1)
    # (the ring's own weight going over on each heave: the ground's dark breath, heavier as they come)
    for k, r in enumerate(RINGS):
        a, b = sheer(n, r - FOLD + 0.03, rng().uniform(1.0, 1.4), 0.1 + 0.015 * k)
        L += a
        R += b
    # (the land still standing: a long way out, dark, one side then the other)
    for at, dull, g, pn in ((0.31, 520, 0.2, -0.5), (0.52, 380, 0.13, 0.55), (0.93, 260, 0.08, -0.2)):
        x = bp(eL + eR, None, dull) * g
        l, r = pan(x, pn)
        P.put(L, l, at)
        P.put(R, r, at)
    L, R = verb(L, R, 0.1, length=3.0, darken=(1300, 240), decay=1.0)
    # (the sky going: from 26 s it closes overhead, and all that's left of it is heard through the ground)
    w = ss(CLOSING - FOLD, HOLD - FOLD, t)
    L, R = muffle(L, w ** 0.7 * 0.8, 700.0) * (1 - 0.3 * w), muffle(R, w ** 0.7 * 0.8, 700.0) * (1 - 0.3 * w)
    L, R = lows_heard(L, 70, 420, -6.0), lows_heard(R, 70, 420, -6.0)
    L, R = low_mono(L, R, 170.0)
    out("unravel", L, R, -12.5, tail=1.0, peak=10 ** (-3.0 / 20))


# =======================================================================================================  the land closing
def moan(n, at, dur, f0, f1, wob=0.05):
    """One of the land's moans, with no note in it: rock dragged under load, stick and slip, each period about a third out from the
    last and the rate gliding from `f0` to `f1`, through wide bands that come and go. A body and a strain. Mono."""
    m = min(n_of(dur), n - n_of(at))
    s = times(m)
    v = s / dur
    f = f0 * (f1 / f0) ** (v + 0.2 * np.sin(np.pi * v) * rng().uniform(-1, 1)) * (1 + wob * np.clip(PB.slow_random(m, 0.4, 3.0), -2.5, 2.5))
    imp = np.zeros(m)
    k = 0.0
    while k < m:
        imp[int(k)] = rng().lognormal(0, 0.8)
        k += max(SR / f[int(k)] * (1 + rng().normal(0, 0.3)), 60.0)
    h = np.arange(n_of(0.024) + 1)
    y = np.maximum(fftconvolve(imp, np.exp(-h / (0.004 * SR)))[:m], 0.0) * noise(m)
    e = np.sin(np.pi * v ** rng().uniform(0.55, 1.2)) ** 1.5
    body = sum(T.unit(bp(y, lo, hi)) * boiled(m, 0.5, 4.0, 8.0) * a_ for (lo, hi), a_ in (((70, 210), 1.0), ((210, 520), 0.62), ((520, 1200), 0.26)))
    o = np.zeros(n)
    P.put(o, body * e, at)
    return o


BANG_UP = 10 ** (14.0 / 20)                                    # (how far the bangs are over what they were on the page's round 4)


def groan():
    seal, close = HOLD - FOLD, CLOSING - FOLD                 # (it stops with the world's closing; what's left is the tube's air)
    end = GATHER + 1.0 - FOLD
    d = end
    n = n_of(d)
    t = times(n)
    build = (0.06 + 0.94 * ss(1.0, seal - 0.5, t) ** 1.7) * (1 - ss(seal - 0.1, seal + 0.7, t))
    heave = np.clip(1 + 0.42 * PB.slow_random(n, 0.1, 0.8), 0.25, None)
    strain = np.clip(0.42 + 0.85 * PB.slow_random(n, 0.1, 0.5), 0.12, None) ** 1.5     # (it comes and goes: never a wall)
    bed_ = bn(n, 19, 58) * heave * build * 0.8
    # (two low tones a hair apart, beating, felt more than heard)
    drift = 1 + 0.03 * PB.slow_random(n, 0.1, 0.7)
    ph = 2 * np.pi * np.cumsum(31.0 * drift) / SR
    ph2 = 2 * np.pi * np.cumsum(32.1 * drift) / SR
    sub = (np.sin(ph) + np.sin(ph2) + 0.3 * np.sin(2 * ph + 0.7)) * np.clip(0.75 + 0.4 * PB.slow_random(n, 0.15, 1.0), 0.05, None) * build * 0.45
    rate = (7.0 + 14.0 * ss(0, 15, t)) * np.clip(1 + 0.4 * PB.slow_random(n, 0.2, 1.4), 0.4, None)
    hull = bank(stick(n, rate, 0.4, 0.22, 0.012, 0.004), ((37, 7, 1.2), (58, 8, 1.0), (91, 8, 0.8), (139, 8, 0.55), (211, 7, 0.32), (333, 6, 0.16)))
    hull = T.unit(hull) * strain * build * 0.8
    tones = np.zeros(n)
    t1 = 0.2
    while t1 < seal:
        v = t1 / seal
        dur = rng().uniform(2.2, 4.8)
        f0 = rng().uniform(38, 92)
        tones += moan(n, t1, dur, f0, f0 * rng().choice([0.72, 0.84, 1.18, 1.32])) * rng().uniform(0.5, 1.0) * (0.35 + 0.65 * v)
        t1 += rng().uniform(0.8, 2.3) * (1.15 - 0.6 * v)
    M = bed_ + sub + hull + T.unit(tones) * (0.2 + 0.8 * strain) * build * 1.1
    # (the far land lifting: a slow heave of the whole horizon, up from 20.1 s, no note in it)
    M = M + eddies(d, 24, 320, 2.5, -5.0, 13.0, 6.0) * np.exp(-0.5 * ((t - (LIFT - FOLD)) / 1.5) ** 2) * ss(1.0, 2.5, t) * 0.5
    L, R = M.copy(), M.copy()
    # (the bangs: great lumps of it going, on the mechanism's beat or halfway to it, so they push it along and don't fight it)
    beat = np.sort(np.r_[[c[0] for c in CLACKS], [(x[0] + y[0]) / 2 for x, y in zip(CLACKS, CLACKS[1:])]]) - FOLD
    B, B2 = np.zeros(n), np.zeros(n)
    for t1 in P.poisson_times(0.5, seal, lambda s: 0.5 + s / d):
        x = T.thud(n_of(1.0), rng().uniform(1.6, 3.0)) * rng().uniform(0.8, 1.8) * (0.3 + 0.7 * t1 / d)
        l, r = pan(x, rng().uniform(-0.7, 0.7))
        t1 = float(beat[np.argmin(np.abs(beat - t1))])
        P.put(B, l, t1)
        P.put(B2, r, t1)

    def space(L, R):
        L, R = verb(L, R, 0.3, length=3.4, darken=(1500, 240), decay=1.5)
        # (it closes: the open air's top goes, and everything rings on in the hollow it has become)
        w = ss(close, seal, t)
        L, R = muffle(L, w * 0.85), muffle(R, w * 0.85)
        wl, wr = inside(L, R, 0.05 + 0.95 * ss(close, seal - 1.0, t), 0.6)
        k = 1 - 0.6 * w
        hush = 1 - 0.84 * ss(seal + 0.1, seal + 1.0, t)         # (and the stillness: its long tail shut off, only the air left)
        return (L * k + wl) * hush, (R * k + wr) * hush

    L, R = space(L, R)
    bl, br = space(B * BANG_UP, B2 * BANG_UP)
    # (the air in it)
    room = ss(close + 2.0, seal, t) * (1 - ss(end - 0.7, end - 0.1, t))
    a, b = wide(hollow(n), hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0)), 0.5)
    L += a * room * 0.36
    R += b * room * 0.36
    L, R = low_mono(L, R, 190.0)
    bl, br = low_mono(bl, br, 190.0)
    out("groan", L + bl, R + br, -15.5, tail=0.6, peak=10 ** (-4.0 / 20), ref=(L, R))    # (its level taken without the bangs: what's round them stays where it was)


# ===========================================================================================================  the fold down
def strain(d, touch):
    """A very great weight held off the ground on something thin, and all of it bending: what's under the stalactite as it comes down and what
    the last of it is, building to its heaviest at `touch` s, `d` s long, nothing climbing in pitch. The hull's stress getting closer together, the
    land's moans under load, a pressure in the tube, the flex of the whole thing swelling on and off slower than the breath, the tube's air
    thickening, the drop's small weight on the end of it. Its loudest about 1. (L, R), the top of it wide, the lows alike."""
    n = n_of(d)
    t = times(n)
    # (dB against where it ends: a long way down at 36, under the stages; on top of everything by 39.2)
    lv = 10 ** (np.interp(t, (0.0, touch - 4.3, touch - 3.0, touch - 1.8, touch - 0.8, touch), (-70.0, -44.0, -24.0, -13.0, -6.0, 0.0)) / 20)
    fl = 1.0 + 0.9 * t / touch                                # (the flex: slow, quickening, on its crest at the touch)
    fp = 2 * np.pi * (np.cumsum(fl) - np.sum(fl[:n_of(touch)])) / SR + np.pi / 2
    flex_ = 10 ** ((2.6 + 1.0 * PB.slow_random(n, 0.8, 2.2)) * np.sin(fp) / 20)
    rate = (8.0 + 30.0 * (t / touch) ** 3) * np.clip(1 + 0.35 * PB.slow_random(n, 0.4, 2.0), 0.4, None)
    hull = T.unit(bank(stick(n, rate, 0.4, 0.2, 0.012, 0.004), ((31, 6, 1.2), (47, 7, 1.0), (73, 8, 0.85), (112, 8, 0.6), (171, 7, 0.35), (262, 6, 0.18))))
    press = bn(n, 18, 58) * boiled(n, 0.4, 2.0, 3.0)
    tones = np.zeros(n)
    for at, ln, f0, r in ((touch - 3.6, 6.4, 54, 0.8), (touch - 2.5, 4.6, 71, 0.86), (touch - 1.5, 2.9, 43, 0.84), (touch - 0.9, 1.8, 92, 0.8)):
        tones += moan(n, at, ln, f0, f0 * r, 0.03)
    tones = T.unit(tones)
    drop = P.glide_band((n + 0.5) / SR, 112.0 + 0 * t, 0.3) + 0.4 * P.glide_band((n + 0.5) / SR, 226.0 + 0 * t, 0.26)
    M = hull * 0.6 + press * 0.8 + tones * 0.62 + T.unit(drop) * boiled(n, 0.5, 2.0, 3.0) * 0.26 * ss(touch - 1.8, touch - 0.3, t)
    a, b = wide(hollow(n), hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0)), 0.5)
    L, R = (M + a * 0.3) * lv * flex_, (M + b * 0.3) * lv * flex_
    L, R = lows_heard(L, 70, 420, -6.0), lows_heard(R, 70, 420, -6.0)
    L, R = low_mono(L, R, 170.0)
    g = 1.0 / (T.loudest((L + R)[:n_of(touch)] / 2) + 1e-9)
    return L * g, R * g


def settle(size=1.0):
    """The droplet's own weight, one surge of it: what `wobble` is made of, a dense dark band sinking as it dies and one small swing back,
    a tonne of mercury heard through the wall, with no sine in it. Mono, 0.8 s, peak about `size`."""
    d = 0.8
    n = n_of(d)
    t = times(n)
    swing = np.abs(np.sin(2 * np.pi * 2.2 * t + 1.16))
    env = np.exp(-5.5 * t) * ss(0.0, 0.05, t) * (0.12 + 0.88 * swing ** 2.2) * (1 - ss(0.36, 0.56, t))
    x = (P.glide_band(d, 82.0 - 26.0 * ss(0.0, 0.5, t), 0.42) + P.glide_band(d, 190.0 - 70.0 * ss(0.0, 0.5, t), 0.6) * 0.34
         + P.glide_band(d, 41.0 - 7.0 * ss(0.0, 0.5, t), 0.3) * 0.75) * env
    return x / (np.abs(x).max() + 1e-9) * size


def foldown():
    """The rim gathers at the hole from 34.5, huge and far off, and from 35 a narrow stalactite of the land lowers from it on the six stages:
    nothing goes round, it comes down, heavy and slow, each stage a weight taken up and let down. It starts as earth and rock, and towards the
    tip it is the droplet's metal: the grind and the rattle go, the ground's blows turn into `settle`, the dark band under it is `wobble`'s,
    and the last of it closes on `meld`'s deep sinking gulps. Under all of it a low strain (`strain`) builds from 36 and takes over as the stages
    end, and it doesn't let go: it is at its heaviest on the last sample, the touch. What comes after is the ding's."""
    last = REACHED - GATHER                                   # (the stages are over; the tip creeps on to the touch)
    d = DING - GATHER - 0.3
    n = n_of(d)
    t = times(n)
    stages = [c - GATHER for c in CREASES]
    metal = ss(METAL_ON[0] - GATHER, METAL_ON[1] - GATHER, t)  # (earth into metal, what the picture is seen to turn)
    mass = np.zeros(n)                                        # (how much is moving: each stage a slow lowering, up in a third of a second, eased off over a second)
    for k, at in enumerate(stages):
        u = np.maximum(t - at, 0)
        mass += 0.86 ** k * (1 - np.exp(-u / 0.3)) * np.exp(-u / 0.75) * (t >= at)
    mass = mass / mass.max()
    gather = ss(0.0, 0.75, t)
    move = 0.14 * gather + 0.86 * mass
    # (earth and rock: the land's weight sliding, a dull rattle, rock dragged under load)
    earth = eddies(d, 40, 2600, 3.0, -5.0, 11.0, 6.0, np.clip(move * 2.0, 0.2, 2.0), 1.2, 260.0) * move * 0.3
    earth = earth + rocks(d, (16.0 + 150.0 * mass ** 1.2) * gather + 1e-3, 120, 1300, (0.3, 0.7, 1.4), (0.5, 0.36, 0.14)) * move ** 0.6 * 0.26
    for at, ln, f0, g in ((0.2, 2.4, 58, 0.36), (1.5, 2.2, 50, 0.3)):
        earth = earth + moan(n, at, ln, f0, f0 * 0.78) * g
    # (the metal: wobble's dark band, sinking as it comes, its skin dragging against itself very faintly)
    ex = (n + 0.5) / SR
    ooze = (P.glide_band(ex, 84.0 - 30.0 * ss(2.3, 4.5, t), 0.42) + P.glide_band(ex, 190.0 - 70.0 * ss(2.3, 4.5, t), 0.6) * 0.34
            + P.glide_band(ex, 41.0 - 7.0 * ss(2.3, 4.5, t), 0.3) * 0.75) * boiled(n, 0.3, 1.6, 3.5) * (0.3 + 0.7 * mass) * 0.3
    a, b = wide(bn(n, 420, 1300), bn(n, 420, 1300), 0.6)
    drag = (0.3 + 0.7 * mass) * boiled(n, 0.5, 3.0, 5.0) * metal * 0.014
    low = bn(n, 22, 100) * boiled(n, 0.3, 2.0, 4.0) * move * 0.6 * (1 - 0.6 * metal)
    M = earth * (1 - metal) + ooze * metal + low
    P.put(M, bare_blow(4.0, 20, 90, 0.26, 0.14) * 0.55, 0.0)  # (the gathering: the first of it shifting, a long way off, through the ground)
    L, R = M + a * drag, M + b * drag
    for k, at in enumerate(stages):
        size = 0.84 ** k
        m_ = float(metal[n_of(at)])
        # (each stage's weight let down: the ground taking it, turning into the metal's own surge)
        m = n_of(1.6)
        y = (struck(m, 0.0, 0.12, GROUND[1:], 26, 0.4) * 0.9 + struck(m, 0.0, 0.08, RUBBLE, 16, 0.5) * 0.45) * (1 - m_)
        P.put(y, bare_blow(2.2, 22, 110, 0.05, 0.16) * 0.5 * (1 - m_), 0.0)
        P.put(y, settle(1.15 * m_), 0.0)
        y = y * size
        P.put(L, y, at)
        P.put(R, y, at)
        # (the sheet's own voice, only while it's still land)
        if m_ < 0.6:
            pew(L, R, at + 0.02, 200 - 60 * k, THICK[("slab", "thick", "thick", "mid")[min(k, 3)]], 0.34 * size * (1 - m_), rng().uniform(-0.25, 0.25), 2)
    # (the tip's last weight: the stages over, it comes to rest as the droplet did; then meld's gulps, sinking, the last the deepest)
    y = settle(0.8)
    P.put(L, y, last)
    P.put(R, y, last)
    for at, f0, a_ in ((stages[4] + 0.42, 78, 0.34), (stages[5] + 0.38, 62, 0.46), (last + 0.25, 52, 0.55)):
        y = bubble(f0, a_ * 0.4, rng().uniform(-0.2, -0.05), 0.03)
        P.put(L, y, at)
        P.put(R, y, at)
    # (the drop gathering under the tip from 38.2, the one that touches: a thin slow swell of the same liquid, its weight small and rounding)
    y = P.glide_band(ex, 128.0 - 22.0 * ss(3.7, 5.1, t), 0.3) * boiled(n, 0.4, 1.8, 3.0) * ss(3.7, 4.8, t) * 0.11
    L, R = L + y, R + y
    # (it hangs in the land round it, less so as it's metal)
    wl, wr = inside(L, R, 1 - 0.6 * metal, 0.3, 90.0)
    L, R = L + wl, R + wr
    gone = 1 - ss(last + 0.05, last + 0.6, t)                 # (the stages' own sound is over by 39.6: `strain` has it by then)
    L, R = lows_heard(L * gone, 70, 360, -6.0), lows_heard(R * gone, 70, 360, -6.0)
    ref = low_mono(L, R, 170.0)
    # (the strain, on a level of its own: its loudest by this far from the stages' loudest)
    d2 = DING - GATHER
    sl, sr = strain(d2, d2)
    A = T.loudest((ref[0] + ref[1]) / 2)
    L2, R2 = np.zeros(len(sl)), np.zeros(len(sr))
    P.put(L2, ref[0], 0)
    P.put(R2, ref[1], 0)
    out("foldown", L2 + sl * A, R2 + sr * A, -14.0, tail=0.012, peak=10 ** (-3.0 / 20), ref=(np.r_[ref[0], np.zeros(len(sl) - n)], np.r_[ref[1], np.zeros(len(sl) - n)]))


def after_touch(n, t0, tau, low=1.0):
    """What the strain leaves running past the touch: the low weight and the tube's air, dying over `tau` s, for what doesn't carry it of itself. (L, R)."""
    u = np.maximum(times(n) - t0, 0)
    e = ss(0.0, 0.006, u) * np.exp(-u / tau) * (times(n) >= t0)
    w = bn(n, 18, 62) * boiled(n, 0.4, 2.0, 3.0) * e * low
    a, b = wide(hollow(n), hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0)), 0.5)
    return w + a * e * 0.5, w + b * e * 0.5


def ding_finish(L, R, db_, send=0.0, lo=None, heard=-7.0, gone=(1.0, 2.7)):
    """Into the hollow by `send`, the lows' harmonics, the lows alike, out as `ding`, its lead on the front of it, handed over to `reverse` over `gone` s after
    the touch: 3 s after it the first ring's fall is coming."""
    if send:
        wl, wr = inside(L, R, 1.0, send, lo)
        L, R = L + wl, R + wr
    e = 1 - ss(DING_LEAD + gone[0], DING_LEAD + gone[1], times(len(L)))
    L, R = L * e, R * e
    if heard:
        L, R = lows_heard(L, 70, 420, heard), lows_heard(R, 70, 420, heard)
    L, R = low_mono(L, R, 170.0)
    out("ding", L, R, db_, tail=0.1, peak=10 ** (-2.0 / 20))


def ding_weight():
    """The land's whole weight arriving through the touch: more felt than heard. All of it under 300 Hz: the ground taking it over a sixth of a
    second, the air of the tube thrown out and sucked back, the blow going off down the tube and coming back as a swell."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t0 = DING_LEAD
    u = np.maximum(times(n) - t0, 0)
    on = times(n) >= t0
    b = np.zeros(n)
    P.put(b, whole(1.0, 0.1, 0.006, 0.8, 0.01), t0)
    press = bp(T.friedlander(n, t0, 0.5, 1.5), 11, 80)
    M = struck(n, t0, 0.16, GROUND, 60, 0.4) * 1.0 + b * 0.9 + press / np.abs(press).max() * 0.9
    M = M + bn(n, 30, 160) * (1 - np.exp(-u / 0.008)) * np.exp(-u / 0.2) * on * 0.5
    M = M + bn(n, 110, 620) * (1 - np.exp(-u / 0.004)) * np.exp(-u / 0.07) * on * 0.3 + rough(n, t0, 0.02, 12, 140, 900, 0.01) * 0.3
    M = M + bn(n, 18, 70) * boiled(n, 0.5, 3.0, 4.0) * ss(0.0, 0.08, u) * np.exp(-u / 1.5) * on * 0.42
    al, ar = after_touch(n, t0, 1.6, 0.0)
    ding_finish(M + al * 0.1, M + ar * 0.1, -8.5, 0.32, None, -4.0)


def ding_mercury():
    """Liquid metal meeting: the neck of the drop stretching and thickening in the last half second; the touch, a dense wet knock with no edge; the
    drop going into the ground as mercury goes into mercury, one great slow plop from under the surface and two after it, the skin of it running
    off in small falling ripples, and the mass under it slopping back on `wobble`'s surge, twice."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    ex = (n + 0.5) / SR
    neck = (P.glide_band(ex, 96.0 + 0 * t, 0.24) + 0.5 * P.glide_band(ex, 190.0 + 0 * t, 0.22)) * ss(t0 - 0.9, t0, t) ** 2 * (1 - on) * 0.2
    knock = struck(n, t0, 0.02, ((46, 3, 1.0), (68, 4, 1.0), (101, 4, 0.9), (151, 3, 0.7), (226, 3, 0.5)), 16, 0.3)
    wet = bn(n, 260, 1300) * (1 - np.exp(-u / 0.004)) * np.exp(-u / 0.035) * on
    L = neck + knock * 0.8 + wet * 0.2
    R = L.copy()
    for at, f0, f1, a_, tau, p in ((0.05, 50, 118, 1.0, 0.2, 0.0), (0.31, 74, 168, 0.5, 0.13, 0.25), (0.5, 112, 236, 0.28, 0.09, -0.3)):
        l, r = pan(plop(f0, f1, a_, tau), p)
        P.put(L, l, t0 + at)
        P.put(R, r, t0 + at)
    a_, b_ = np.zeros(n), np.zeros(n)
    for k in range(7):                                        # (the skin running off: short falling ripples, dark, no bright edge)
        pew(a_, b_, t0 + 0.08 + 0.11 * k + 0.05 * rng().random(), 26 + 15 * k, THICK["thick"], 0.2 * 0.84 ** k, (-0.5, 0.6, -0.2, 0.7, -0.7, 0.3, -0.4)[k], 2)
    L, R = L + bp(a_, None, 2200), R + bp(b_, None, 2200)
    for at, g in ((0.62, 0.62), (1.28, 0.38)):                # (the mass under it, slopping back)
        y = settle(g)
        P.put(L, y, t0 + at)
        P.put(R, y, t0 + at)
    al, ar = after_touch(n, t0, 1.5)
    ding_finish(L + al * 0.2, R + ar * 0.2, -11.5, 0.3, 60.0)


def ding_inbreath():
    """The touch's own echo, backwards: the blow's long tail in the hollow drawn in from 37.8, dark and far at first, opening and closing in on the ear,
    and stopping dead on the blow itself, and the blow forward, short, heavy and stony, with hardly any tail, because the world starts going back from here."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t0 = DING_LEAD
    m = n_of(1.6)
    H = struck(m, 0.0, 0.05, GROUND, 40, 0.4) * 0.9 + struck(m, 0.0, 0.03, RUBBLE, 24, 0.5) * 0.7
    P.put(H, whole(1.0, 0.5, 0.0025, 0.32, 0.008), 0.0)
    P.put(H, bare_blow(2.2, 24, 130, 0.008, 0.1) * 0.6, 0.0)
    H = H + rough(m, 0.0, 0.012, 12, 240, 2600, 0.006) * 0.35
    L, R = np.zeros(n), np.zeros(n)
    y = np.zeros(n_of(4.0))
    P.put(y, H, 0.0)
    wl, wr = inside(y, y, 1.0, 1.0)                           # (its tail in the hollow, longer than the lead)
    rl, rr = wl[::-1], wr[::-1]                               # (the blow is the last of it)
    k = n_of(DING_LEAD)
    e = times(k) / DING_LEAD
    sw = e ** 0.8 * ss(0.0, 0.5, e)                           # (it comes up from nothing; the last of it is the loudest)
    gap = 1 - ss(DING_LEAD - 0.022, DING_LEAD - 0.012, times(k))    # (a hair of nothing, so the blow is a blow)
    g = np.abs(H).max() / (np.abs(rl[-k:]).max() + 1e-9)
    L[:k] += rl[-k:] * sw * gap * g * 0.46
    R[:k] += rr[-k:] * sw * gap * g * 0.46
    P.put(L, H, t0)
    P.put(R, H, t0)
    # (what's left of it forward: the hollow shut off quickly, a low weight handing over to the walls starting to move)
    wl, wr = bp(wl[:n_of(2.6)], None, 900), bp(wr[:n_of(2.6)], None, 900)
    e = np.exp(-times(n_of(2.6)) / 0.55)
    P.put(L, wl * e * 0.8, t0)
    P.put(R, wr * e * 0.8, t0)
    al, ar = after_touch(n, t0, 1.6, 0.9)
    ding_finish(L + al * 0.4, R + ar * 0.4, -7.5, gone=(1.5, 2.8))


def ding_subdrop():
    """The floor of the sound going out from under it: one enormous low fall from the touch, 110 Hz to under 20 in about three seconds, two voices a hair apart
    so it beats slower and slower as it goes, its own harmonics carrying it on small speakers. A dull touch on the front and no blow: nothing strikes, it drops."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    f = 18.0 + 92.0 * np.exp(-u / 0.72)
    p1 = 2 * np.pi * np.cumsum(f * on) / SR
    p2 = 2 * np.pi * np.cumsum(f * 1.03 * on) / SR
    e = (1 - np.exp(-u / 0.018)) * (1 - ss(1.8, 4.2, u)) * on
    core = (np.sin(p1) + np.sin(p2)) * 0.5
    harm = bp(np.tanh(3.2 * core), 60, 520)
    grain = bn(n, 22, 120) * boiled(n, 1.0, 6.0, 4.0) * 0.4
    M = (core * 1.0 + harm * 0.34 * np.exp(-u / 1.6) + grain) * e
    M = M + struck(n, t0, 0.02, GROUND[2:], 14, 0.3) * 0.5
    al, ar = after_touch(n, t0, 1.8, 0.0)
    ding_finish(M + al * 0.14, M + ar * 0.14, -8.0, 0.14, 70.0, 0.0, (1.3, 2.9))


def ding_release():
    """All the pressure built up in the tube let go at once: a seal breaking, one rough dark crack and the air jumping, then a vast breath out, rushing past the ears
    and out of the hole, its top closing as it runs down. Air, not a blow: the strain cut dead by it."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    M = rough(n, t0, 0.014, 18, 170, 1500, 0.012) * 0.8 + struck(n, t0, 0.03, RUBBLE, 18, 0.5) * 0.7
    press = bp(T.friedlander(n, t0, 0.3, 1.2), 14, 100)
    M = M + press / np.abs(press).max() * 0.75
    lead_ = n_of(t0)

    def vent(s, f):
        v = max(s - t0, 0.0)
        top = 700.0 + 5600.0 * np.exp(-v / 0.8)
        return np.minimum((f / 170.0) ** 0.9, (170.0 / f) ** 0.55) * np.exp(-(f / top) ** 1.5)

    a, b = wide(morph(n, vent), morph(n, vent), 0.3)
    gust = surge_gain(n, 1.2)
    e = (1 - np.exp(-u / 0.02)) * (0.72 * np.exp(-u / 0.75) + 0.28 * np.exp(-u / 1.7)) * on
    sw = np.clip(u / 1.6, 0, 1)
    L = M + a * e * gust * 0.8 * (1 - 0.5 * sw)
    R = M + b * e * gust * 0.8 * (1 + 0.1 * sw)
    low = bn(n, 22, 110) * (1 - np.exp(-u / 0.03)) * np.exp(-u / 1.0) * boiled(n, 0.5, 3.0, 4.0) * on * 0.5
    al, ar = after_touch(n, t0, 1.8, 0.0)
    ding_finish(L + low + al * 0.14, R + low + ar * 0.14, -9.5, 0.2, 90.0, -9.0, (1.4, 2.8))


def ding_chord():
    """The land's own chord: everything in the tube's walls singing at once, not a pad: the ground's rumble through very narrow resonances tuned to an open chord, so
    each note is a band of earth wandering on its own and there's no clean tone in it. It comes up from under the strain from 38.6, blooms at the touch from the
    root up, with a slow bright shimmer on the top of it, and dies back into the walls. No blow."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    u = t - t0
    NOTES = ((55.0, 1.0, 0.0), (82.41, 0.9, 0.0), (110.0, 0.85, 0.02), (164.81, 0.72, 0.05), (220.0, 0.62, 0.08), (246.94, 0.42, 0.1), (329.63, 0.42, 0.14),
             (440.0, 0.3, 0.2), (493.88, 0.22, 0.25), (659.25, 0.18, 0.3), (987.77, 0.1, 0.42), (1318.5, 0.075, 0.5))
    drive = eddies(d, 40, 2600, 3.0, -2.0, 11.0, 5.0)
    L, R = np.zeros(n), np.zeros(n)
    for k, (f, a_, late) in enumerate(NOTES):
        e = (ss(-1.5, 0.0, u) ** 1.8 * 0.5 + ss(0.0 + late, 0.26 + late * 1.8, u) * 0.5) * (1 - ss(1.9, 3.2, u))
        for c, cents in ((L, -2.0 - k * 0.3), (R, 2.0 + k * 0.3)):
            y = reso(noise(n) * 0.5 + drive, f * 2 ** (cents / 1200), f / 1.5)
            c += T.unit(y) * e * a_
    # (the shimmer: the top notes' bands opening and shutting on their own, slow and uneven)
    sh = boiled(n, 1.5, 7.0, 7.0)
    a, b = wide(bn(n, 900, 3200), bn(n, 900, 3200), 0.2)
    s = sum(T.unit(reso(a if j % 2 else b, f, f / 7.0)) for j, f in enumerate((987.77, 1318.5, 1975.5, 2637.0)))
    e = ss(-0.3, 0.3, u) * (1 - ss(1.3, 3.4, u))
    L += s * sh * e * 0.05
    R += np.roll(s, 311) * sh * e * 0.05
    M = bn(n, 20, 80) * ss(-1.0, 0.06, u) * (1 - ss(0.5, 3.2, u)) * boiled(n, 0.4, 2.0, 3.0) * 0.6
    y = struck(n, t0, 0.05, GROUND, 30, 0.3) * 1.1
    P.put(y, whole(1.0, 0.4, 0.004, 0.3, 0.01), t0)
    al, ar = after_touch(n, t0, 0.6, 1.2)
    ding_finish(L + M + y + al * 1.0, R + M + y + ar * 1.0, -11.0, 0.5, 80.0, 0.0, (1.0, 2.8))


def ding_horn():
    """One enormous note out of the ground, bowed, not struck: the land dragged over itself so regularly it speaks, like a ship's horn a county wide. The pulse of it stays dead
    on one pitch, only rough; it comes in dark on the touch and opens from the bottom up for a second and a half, and goes dark again."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    u = t - t0
    L, R = np.zeros(n), np.zeros(n)
    BODY = ((80, 4, 1.0), (126, 5, 1.0), (203, 6, 1.0), (331, 6, 0.9), (505, 6, 0.7), (790, 5, 0.45), (1230, 4, 0.22), (1900, 3, 0.09))
    for f0, side in ((41.2, -0.25), (41.45, 0.25), (20.6, 0.0)):
        imp = np.zeros(n)
        k = float(n_of(t0 - 0.8)) - float(rng().uniform(0, 100))
        while k < n:
            imp[int(k)] = rng().lognormal(0, 0.22)
            k += SR / f0 * (1 + 0.006 * rng().standard_normal())
        h = bank(fftconvolve(imp, noise(n_of(0.004)) * np.exp(-times(n_of(0.004)) / 0.0012) + np.exp(-times(n_of(0.004)) / 0.0015))[:n], BODY)
        v = 0.0
        y = np.zeros(n)
        for (lo, hi), late, a_ in (((None, 150), -0.7, 0.8), ((150, 420), -0.3, 0.8), ((420, 1000), 0.1, 0.8), ((1000, 3200), 0.5, 0.55)):
            e = ss(late, late + 0.75, u) * (1 - ss(1.5 + late * 0.3, 3.0, u))
            y += bp(h, lo, hi) * e * a_
        l, r = pan(T.unit(y) * (0.5 if f0 < 30 else 1.0), side)
        L, R = L + l, R + r
    y = struck(n, t0, 0.05, GROUND, 30, 0.3) * 1.2
    P.put(y, whole(1.0, 0.4, 0.004, 0.3, 0.01), t0)
    al, ar = after_touch(n, t0, 0.5, 1.6)
    ding_finish(L + y + al * 1.0, R + y + ar * 1.0, -9.5, 0.3, 70.0, 0.0, (1.2, 2.7))


def ding_countdown():
    """The land's weight coming down on a beat: a heavy pulse in the ground from 37.9, closer and closer together, bigger each time, a stall running out of road, and
    the last of them the touch: one stopped blow, a shock after it, the walls taking it up."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    gaps = [0.62]
    while gaps[-1] > 0.07:
        gaps.append(gaps[-1] * 0.8)
    at = t0 - np.cumsum(gaps)[::-1]
    L, R = np.zeros(n), np.zeros(n)
    for k, a_ in enumerate(at):
        if a_ < 0.02:
            continue
        v = k / len(at)
        m = n_of(0.8)
        s = times(m)
        y = struck(m, 0.0, 0.02, GROUND[1:], 16, 0.4) * 0.9 + bn(m, 110, 520) * (1 - np.exp(-s / 0.0015)) * np.exp(-s / 0.04) * 0.6
        y = y + rough(m, 0.0, 0.006, 6, 200, 1400, 0.004) * 0.1
        P.put(y, bare_blow(1.6, 24, 110, 0.008, 0.11) * 0.6, 0.0)
        y = y * (0.42 + 0.46 * v ** 1.3) * rng().uniform(0.92, 1.05)
        l, r = pan(y, (-1) ** k * 0.08)
        P.put(L, l, a_)
        P.put(R, r, a_)
    for at_, g in ((0.0, 1.0), (0.62, 0.34)):
        m = n_of(2.2)
        y = struck(m, 0.0, 0.08, GROUND, 40, 0.4) * 0.9 + struck(m, 0.0, 0.05, RUBBLE, 22, 0.5) * 0.6
        P.put(y, whole(1.0, 0.42, 0.0025, 0.3, 0.008), 0.0)
        P.put(y, bare_blow(2.4, 22, 110, 0.01, 0.12) * 0.7, 0.0)
        P.put(L, y * g, t0 + at_)
        P.put(R, y * g, t0 + at_)
    al, ar = after_touch(n, t0, 1.5)
    ding_finish(L + al * 0.2, R + ar * 0.2, -8.5, 0.22, 80.0)


def ding_sheet():
    """The Fold's own voice, once, at its biggest: the touch strikes the land as a stone strikes a frozen lake, and the whole sheet of it says so: one enormous falling
    pew through a sheet as thick as a hill, going off round the inside of the tube and coming back from the other side longer and darker. A dull blow under the front of it."""
    d = DING_LEAD + 3.0
    n = n_of(d)
    t = times(n)
    t0 = DING_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    L, R = np.zeros(n), np.zeros(n)
    for at, dist, fc, a_, p in ((0.0, 300, THICK["thick"], 3.2, -0.2), (0.3, 620, THICK["slab"], 2.4, 0.5), (0.85, 980, THICK["slab"], 1.6, -0.55)):
        pew(L, R, t0 + at, dist, fc, a_, p, 2)
    a, b = sheer(n, t0 + 0.04, 2.2, 0.5)
    y = struck(n, t0, 0.05, GROUND, 30, 0.4) * 1.3
    P.put(y, whole(1.0, 0.4, 0.004, 0.32, 0.01), t0)
    y = y + bn(n, 26, 130) * (1 - np.exp(-u / 0.01)) * np.exp(-u / 0.26) * on * 0.5
    al, ar = after_touch(n, t0, 0.8, 1.2)
    ding_finish(L + a + y + al * 0.7, R + b + y + ar * 0.7, -10.5, 0.3, 70.0)


# (every way of the touch tried, each its own idea: `DING_PICK` is the one in the game; what plain words the review page gives them, in tools' CUES)
DINGS = {"weight": ding_weight, "mercury": ding_mercury, "inbreath": ding_inbreath, "subdrop": ding_subdrop, "release": ding_release, "chord": ding_chord,
         "horn": ding_horn, "countdown": ding_countdown, "sheet": ding_sheet}


def ding():
    DINGS[DING_PICK]()


# ==============================================================================================================  backwards
def back_at(tau):
    """When the run back passes the fold's clock `tau`: seconds after FW_REL (fold_warp's fw_tau; it never turns round)."""
    u = np.linspace(0, 1, 4001)
    return float(np.interp((DING - tau) / (DING - 20.0), u * u * (3.11 + u * (-5.05 + u * 2.94)), u)) * (FLAT - REL)


def reverse():
    """The whole fold going back, 3.6 s of it, as slow as the picture: a very great weight starting to move, not a tape rewound.
    Every sound here goes forward, with forward attacks, and comes in the fold's order backwards: the ground stirring under the
    ding, the stalactite drawn up on its stages, each bigger, the droplet's metal in the first of them and earth after, the rim up, the tube opening from 42.8 with the sky's air
    coming in through it, and the far land going at the end. Its loudness is the picture's speed; nothing climbs in pitch."""
    dur = FLAT - REL
    n = n_of(dur)
    t = times(n)
    u = t / dur
    sp = (6.22 * u - 15.15 * u ** 2 + 11.76 * u ** 3) / 2.83    # (how fast the fold's clock runs back: fw_tau; 1 at the very end)
    # (how much is moving: the ground's weight taking up slowly, the speed's own run at the end)
    lv = 10 ** (np.interp(u, (0.0, 0.08, 0.25, 0.4, 0.6, 0.78, 0.9, 1.0), (-60.0, -44.0, -33.0, -27.0, -22.0, -15.5, -7.0, 0.0)) / 20)
    seal, sky = TUBE - REL, back_at(27.0)                       # (the tube opens: fw_tau reaches FW_HOLD on 42.8; the sky is back by about 43.4)
    wide_ = ss(seal, sky, t)
    # (the ground: the groan's two low tones a hair apart, the land's weight taking up, a rumble rolling under them)
    heave = np.clip(1 + 0.42 * PB.slow_random(n, 0.2, 1.2), 0.25, None)
    drift = 1 + 0.03 * PB.slow_random(n, 0.1, 0.7)
    ph = 2 * np.pi * np.cumsum(31.0 * drift) / SR
    ph2 = 2 * np.pi * np.cumsum(32.1 * drift) / SR
    sub = (np.sin(ph) + np.sin(ph2) + 0.3 * np.sin(2 * ph + 0.7) + 0.35 * np.tanh(3.0 * np.sin(ph))) * lv ** 0.72 * 0.5
    bed_ = bn(n, 19, 58) * heave * lv ** 0.8 * 0.9
    roll = bn(n, 40, 190) * np.clip(1 + 0.5 * PB.slow_random(n, 0.6, 3.5), 0.1, None) * lv * 1.1
    # (the walls under load: the groan's hull and its moans, working against each other)
    strain = np.clip(0.5 + 0.8 * PB.slow_random(n, 0.3, 1.4), 0.12, None) ** 1.4
    rate = (6.0 + 22.0 * sp ** 0.7) * np.clip(1 + 0.4 * PB.slow_random(n, 0.3, 1.6), 0.4, None)
    hull = bank(stick(n, rate, 0.4, 0.22, 0.012, 0.004), ((37, 7, 1.2), (58, 8, 1.0), (91, 8, 0.8), (139, 8, 0.55), (211, 7, 0.32), (333, 6, 0.16)))
    hull = T.unit(hull) * strain * lv ** 0.62 * 0.7
    tones = np.zeros(n)
    for at, ln in ((0.5, 2.2), (1.15, 2.1), (1.7, 1.9), (2.25, 1.6), (2.7, 1.2)):
        f0 = rng().uniform(40, 86)
        tones += moan(n, at, ln, f0, f0 * rng().choice([0.72, 0.84, 1.18])) * rng().uniform(0.6, 1.0)
    M = sub + bed_ + roll + hull + T.unit(tones) * lv ** 0.5 * (0.3 + 0.7 * strain) * 0.55
    L, R = M.copy(), M.copy()
    # (the stalactite drawn up, smallest first: each stage a reversed breath of the land round it into a forward weight, the metal's near the tip, the ground's after)
    for k, tau in enumerate((39.0, 38.2, 37.5, 36.8, 36.1, 35.5)):
        at = back_at(tau)
        v = 1 - k / 5
        m = n_of(0.2)
        s = times(m)
        strength = lv[n_of(at)] ** 0.6 * 0.38
        y = bn(m, 70, 420) * np.exp((s - 0.2) / 0.06) * 0.22 * strength
        P.put(L, y, at - 0.2)
        P.put(R, y, at - 0.2)
        m = n_of(0.8)
        s = times(m)
        m_ = 1 - ss(METAL_UP[0] - REL, METAL_UP[1] - REL, at)   # (the tip's stages all metal, earth back by 41.6)
        y = (struck(m, 0.0, 0.05, GROUND[1:], 14, 0.4) * 0.8 + struck(m, 0.0, 0.04, RUBBLE, 10, 0.5) * 0.4) * strength * (1 - m_)
        P.put(y, settle(1.2 * m_ * strength), 0.0)
        y += bn(m, 36, 220 - 90 * v) * (1 - np.exp(-s / 0.02)) * np.exp(-s / 0.1) * 0.5 * strength
        l, r = pan(y, rng().uniform(-0.3, 0.3))
        P.put(L, l, at)
        P.put(R, r, at)
    # (the drop going back up into the tip, gone by 41.3: the thin swell it came with, under the ding's ring)
    y = P.glide_band((n + 0.5) / SR, 106.0 + 0 * t, 0.3) * ss(0.0, 0.2, t) * (1 - ss(0.45, 0.8, t)) * 0.05
    L += y
    R += y
    # (the tube opening: the land's weight going off it, no blow to it; then the walls tearing free one at a time)
    boom = blow(n, seal, 52, 36, 27, 0.12, 0.05, [(0.7, 0.5), (0.3, 1.3)], drive=2.4) * 0.34
    L += boom
    R += boom
    at = seal + 0.22
    while at < dur - 0.55:
        y = bp(rock_crack(1.2, rng().uniform(1.0, 1.5), 0.5), None, 1000) * rng().uniform(0.5, 0.8) * (0.25 + 0.75 * lv[n_of(at)] ** 0.5)
        l, r = pan(y, rng().uniform(-0.8, 0.8))
        P.put(L, l, at)
        P.put(R, r, at)
        at += rng().uniform(0.24, 0.5)
    # (earth pouring off the walls as they tilt, a long way off: a slow roar, no grit)
    pour = np.clip(1 + 0.5 * PB.slow_random(n, 1.2, 7.0), 0.1, None) * wide_ * lv ** 0.7
    a, b = wide(bn(n, 80, 620), bn(n, 80, 620), 0.5)
    L += a * pour * 0.55
    R += b * pour * 0.55
    # (it rings on in the hollow till the walls are open; add the air after, which is what's left of the hollow)
    wl, wr = inside(L, R, 1 - wide_, 0.5, 70.0)
    L, R = L + wl, R + wr
    tone = T.unit(hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0))) * (1 - wide_) * (0.25 + 0.75 * ss(0.3, seal, t)) * 0.02
    L += tone
    R += tone

    # (the sky's air coming in as they part: its top opening, nothing moving in pitch, gusts not a sweep)
    def rush(s_, f):
        o = ss(seal, sky, s_)
        return np.minimum((f / 150.0) ** 1.1, (150.0 / f) ** 0.7) * np.exp(-(f / (380.0 * (6500.0 / 380.0) ** o)) ** 1.6)

    a, b = wide(morph(n, rush), morph(n, rush), 0.35 + 0.45 * u)
    gust = np.clip(1 + 0.45 * PB.slow_random(n, 0.5, 5.0), 0.2, None)
    w = ss(seal - 0.05, seal + 0.6, t) * lv ** 0.8
    L += a * gust * w * 0.95
    R += b * gust * w * 0.95
    # (the far land going: the air out from under the whole horizon)
    press = bn(n, 24, 150) * ss(dur - 0.9, dur, t) ** 2 * 0.8
    L += press
    R += press
    L, R = low_mono(L, R, 200.0)
    g = 1.0 / np.abs(np.stack([L, R])).max()
    L, R = (np.tanh(c * g * 1.3) / np.tanh(1.3) for c in (L, R))
    gate = 1 - ss(dur - 0.062, dur - 0.05, t)                   # (cut before the first bang, as the ring's own fall is)
    out("reverse", L * gate, R * gate, -15.5, tail=0, length=n, peak=10 ** (-3.0 / 20))


# ==================================================================================================================  the rings
# Each ring has its own way of landing, by where it is and what it is: outermost first, nearer and harder each time. A ring's
# arrival is spread by its size, as the land round the horizon comes down, so the hits tighten as they come in.
# body and modes the ground's response; flam the same blow again; roll the ring's far side coming in after it; edge how hard its
# front is; stones what comes down after; echoes the land still standing (time, how dark, gain); room how much hollow is left.
BANGS = (
    dict(name="bang1", db=-13.5, fall_db=-15.0, d=3.1, span=0.11, body=(46, 40, 30), decs=[(0.9, 0.12), (0.1, 0.5)],
         modes=((28, 3, 0.8), (39, 4, 0.9), (57, 5, 1.0), (84, 4, 1.1), (121, 3, 1.0)), thick=((92, 2.5, 1.0), (140, 2.5, 0.9), (205, 2, 0.4)), thick_g=0.9,
         mass=(60, 230, 0.085, 0.66), edge=(0.08, 120, 600, 0.014), flam=(), roll=(0.62, 11, 0.5), puff=(0.26, 0.22, 520), stones=(6.0, 0.5, 2.4, 0.45, 1800), echoes=((0.36, 420, 0.12), (0.77, 300, 0.08), (1.31, 220, 0.05)),
         wet=0.12, room=1.0, gap=0.055, side=-0.2),
    dict(name="bang2", db=-13.5, fall_db=-15.0, d=2.5, span=0.05, body=(46, 38, 28), decs=[(0.88, 0.1), (0.12, 0.36)],
         modes=((26, 4, 0.8), (37, 5, 1.0), (54, 5, 1.1), (78, 5, 1.1), (115, 4, 0.9)), thick=((98, 3, 1.0), (160, 3, 1.0), (246, 3, 0.7), (405, 2, 0.35)), thick_g=1.1,
         mass=(80, 500, 0.05, 0.66), edge=(0.42, 230, 2200, 0.008), flam=((0.118, 0.86),), roll=(0.34, 5, 0.3), puff=(0.12, 0.09, 950), stones=(4.5, 0.3, 1.7, 0.5, 3000), echoes=((0.29, 380, 0.07), (0.63, 260, 0.04)),
         wet=0.08, room=0.5, gap=0.04, side=0.3),
    dict(name="bang3", db=-12.5, fall_db=-14.5, d=2.2, span=0.022, body=(50, 42, 31), decs=[(0.88, 0.14), (0.12, 0.6)],
         modes=((31, 3, 1.0), (45, 6, 0.8), (68, 4, 1.0), (97, 6, 1.1), (146, 5, 1.1), (214, 4, 0.9)), thick=((158, 2.5, 1.0), (262, 2.5, 1.1), (420, 2, 0.8), (690, 2, 0.45)), thick_g=1.5,
         mass=(100, 760, 0.042, 0.75), edge=(0.5, 420, 4200, 0.005), flam=(), roll=(0.0, 0, 0.0), puff=(0.2, 0.08, 1600), stones=(2.5, 0.3, 1.5, 0.4, 4200), echoes=(),
         wet=0.08, room=0.34, gap=0.07, side=0.0),
    dict(name="bang4", db=-13.0, fall_db=-15.5, d=1.5, span=0.014, body=(70, 60, 44), decs=[(1.0, 0.06)],
         modes=((43, 4, 0.7), (61, 8, 1.1), (87, 8, 1.2), (123, 7, 1.2), (178, 6, 1.0), (257, 5, 0.6)), thick=((196, 6, 1.0), (283, 6, 0.9), (407, 5, 0.6)), thick_g=1.3,
         mass=(130, 420, 0.03, 0.4), edge=(0.34, 500, 3400, 0.004), flam=(), roll=(0.0, 0, 0.0), puff=(0.1, 0.045, 1200), stones=(0.0, 0.0, 0.0, 0.0, 0), echoes=(),
         wet=0.06, room=0.1, gap=0.05, side=-0.1),
)


def ring_fall(n, b):
    """A ring's 0.8 s down, on the picture's curve (1 - u^3): slow to leave, all its weight in the last of it, each its own
    sort of falling. Dry, nothing on its last `gap` s: it stops dead. (L, R)."""
    t = times(n)
    u = np.clip(t / FALL, 0, 1)
    k = int(b["name"][-1])
    lv = u ** 4.2
    fc0, top = {1: (130.0, 900.0), 2: (210.0, 2400.0), 3: (170.0, 1500.0), 4: (300.0, 3600.0)}[k]

    def under(s_, f):
        v = min(s_ / FALL, 1.0) ** 2
        fc = fc0 * (1 + 0.3 * v)
        return np.minimum((f / fc) ** 1.2, (fc / f) ** 1.1) * np.exp(-(f / top) ** 1.5)

    a, b_ = wide(morph(n, under), morph(n, under), 0.5)
    gust = np.clip(1 + 0.32 * PB.slow_random(n, 3.0, 16.0), 0.2, None)
    sub = bn(n, 22, 84) * lv * 0.6
    gain = {1: 0.55, 2: 0.9, 3: 1.0, 4: 1.2}[k]
    L, R = a * gust * lv * gain + sub, b_ * gust * lv * gain + sub
    # (each its own: all scaled by the air at the end of it, so the air can be set under the hit)
    if k == 2:                                                 # (the soil going off it, a long sheet of it, into the air)
        a, b_ = wide(bn(n, 800, 3400), bn(n, 800, 3400), 0.4)
        e = ss(0.12, 0.75, u) * np.clip(1 + 0.3 * PB.slow_random(n, 2.0, 9.0), 0.2, None) * 0.12
        L += a * e
        R += b_ * e
    elif k == 3:                                               # (the shard straining as it goes: one long creak, under the air)
        y = bp(creak_take(0.6, 74.0), None, 900.0) * 0.1
        l, r = pan(y, 0.3)
        P.put(L, l, 0.1)
        P.put(R, r, 0.1)
    gate = 1 - ss(FALL - b["gap"] - 0.012, FALL - b["gap"], t)
    return low_mono(L * gate, R * gate, 170.0)


def bang(b):
    """One ring landing: on the stem's FALL s. Land stopping dead on land: a contact and the ground taking it, the air thrown out
    from under it, the ring's further parts arriving after it, stones, the last of the walls answering. No sweep, no spring."""
    d = FALL + b["d"]
    n = n_of(d)
    t = times(n)
    t0 = FALL
    u = np.maximum(t - t0, 0)
    on = t >= t0

    def blowk(at, g):
        f = b["body"]
        chest = blow(n, at + 0.006, f[0], f[1], f[2], 0.05, 0.006, b["decs"], drive=3.0, octv=0.26, h3=0.13, harm=0.5)
        x = struck(n, at, b["span"], b["modes"], 34) * 0.7 + struck(n, at, b["span"] * 0.8, b["thick"], 22) * b["thick_g"] * 0.7 + chest * 0.4
        lo, hi, tau, gm = b["mass"]
        w = np.maximum(t - at, 0)
        x = x + bn(n, lo, hi) * (1 - np.exp(-w / 0.0025)) * np.exp(-w / tau) * (t >= at) * gm    # (the blow's own weight: rough, not a note)
        e = b["edge"]
        return (x + rough(n, at, max(b["span"], 0.01) * 0.6, 14, e[1], e[2], e[3]) * e[0]) * g

    M = blowk(t0, 1.0)
    for dt, g in b["flam"]:
        M += blowk(t0 + dt, g)
    p = b["puff"]
    M += bn(n, 90, p[2]) * (1 - np.exp(-u / 0.012)) * np.exp(-u / p[1]) * on * p[0]
    tail = bn(n, 24, 110) * N.env_ar(n, t0 + 0.02, 0.05, 0.14, 0.2, 0.3 + b["d"] * 0.12) * np.clip(1 + 0.5 * PB.slow_random(n, 2.0, 9.0), 0.1, None) * (0.17 + 0.05 * b["room"])
    M += tail
    L, R = M.copy(), M.copy()
    # (the ring's further parts landing after the near side: fewer and duller with distance, each on its own bearing)
    span, count, g = b["roll"]
    for k in range(count):
        v = (k + rng().uniform(0.2, 0.8)) / count
        m = n_of(0.5)
        s = times(m)
        y = bank(np.exp(-s / 0.008) * (1 + 0.4 * noise(m)), b["modes"][:4])
        y = y / (np.abs(y).max() + 1e-9) * g * (1 - 0.72 * v) * rng().uniform(0.7, 1.1) * np.exp(-s / 0.14)
        l, r = pan(y, rng().uniform(-0.9, 0.9) * (0.4 + 0.6 * v))
        P.put(L, l, t0 + 0.06 + span * v ** 1.25)
        P.put(R, r, t0 + 0.06 + span * v ** 1.25)
    rate, a_, z, g_, top = b["stones"]
    if rate:
        pl, pr = patter(d, t0 + a_, t0 + z, lambda v: rate * np.exp(-max(v - t0 - a_, 0) / 0.6), g_)
        L += bp(pl, None, top)
        R += bp(pr, None, top)
    wl, wr = verb(L, R, b["wet"], length=2.0, darken=(1500, 230), decay=0.5)
    hl, hr = inside(L, R, 1.0, 0.3 * b["room"], 150.0)
    L, R = wl + hl, wr + hr
    for at, dull, g_ in b["echoes"]:                           # (what's still standing answering, out and away)
        for c, x in zip((L, R), (L.copy(), R.copy())):
            P.put(c, bp(x[n_of(t0):n_of(t0 + 0.6)], None, dull) * g_, t0 + at)
    L, R = low_mono(L, R, 170.0)
    # (its fall under the hit by this much: the step up from the one to the other is the bang)
    fl, fr = ring_fall(n, b)
    i, w = n_of(t0), n_of(0.1)
    last = np.sqrt(np.mean(((fl + fr)[i - n_of(0.3):i - n_of(b["gap"] + 0.02)] / 2) ** 2))
    g = 10 ** (b["fall_db"] / 20) * np.sqrt(np.mean(((L + R)[i:i + w] / 2) ** 2)) / (last + 1e-12)
    fl, fr = fl * g, fr * g
    out(b["name"], L + fl, R + fr, b["db"], tail=0.4, peak=10 ** (-2.0 / 20), ref=(L, R))


def bang1():
    bang(BANGS[0])


def bang2():
    bang(BANGS[1])


def bang3():
    bang(BANGS[2])


def bang4():
    bang(BANGS[3])


def fall():
    """The land coming down the last time: all the air under it going, rising, and a moment's nothing before the hit."""
    n = n_of(FALL)
    t = times(n)
    u = t / FALL
    lv = 10 ** (-30.0 * (1 - u) ** 1.2 / 20)

    def under(s, f):
        v = min(s / FALL, 1.0)
        fc = 110.0 + 520.0 * v ** 1.6
        return np.minimum((f / fc) ** 1.2, (fc / f) ** 1.1)

    a, b = wide(morph(n, under), morph(n, under), 0.55)
    gust = np.clip(1 + 0.3 * PB.slow_random(n, 4.0, 20.0), 0.2, None)
    sub = bn(n, 22, 80) * lv * 1.3
    L, R = a * gust * lv + sub, b * gust * lv + sub
    L, R = low_mono(L, R, 170.0)
    gate = 1 - ss(FALL - 0.14, FALL - 0.09, t)                 # (the last 90 ms: nothing)
    out("fall", L * gate, R * gate, -18.0, tail=0, peak=10 ** (-5.0 / 20))


GROUND = ((24, 2.5, 1.0), (33, 3, 1.1), (47, 4, 1.0), (68, 4, 0.9), (97, 3, 0.75), (141, 3, 0.5))
RUBBLE = ((118, 2.5, 1.0), (187, 2.5, 0.9), (296, 2, 0.7), (470, 2, 0.4), (760, 2, 0.2))


FOIL = 1100.0                                                  # (slam: what was over this was the tin foil)


def slam():
    """The last ring down, and all the land with it: round 3's blow, a door the size of the sky, with its bright top taken off and nothing else moved: the kick, the air slammed out, the frame's crack,
    the land's whole sheet answering from all round, rock going, the roar, the stones coming back. What was crinkling on top of that was the roar's grains and the rock's snaps
    over about a kilohertz: those are dull now. The panels are `sink`, on the same instant."""
    d = 7.0
    n = n_of(d)
    t = times(n)
    t0 = 0.002
    u = np.maximum(t - t0, 0)
    # (a door the size of the sky: the frame's crack, the air slammed out, a chest blow that doesn't let go)
    chest = blow(n, t0, 150, 43, 29, 0.05, 0.0012, [(0.7, 0.3), (0.3, 1.5)], drive=3.6, octv=0.3, h3=0.16, harm=0.6) * 3.0
    press = bn(n, 22, 160, 3) * N.env_ar(n, t0, 0.006, 0.25, 0.25, 1.6) * 1.2
    crack = bp(bn(n, 300, 6000), None, FOIL * 2, 2) * np.exp(-u / 0.018) * (t >= t0) * 1.3 + bn(n, 120, 900) * np.exp(-u / 0.09) * (1 - np.exp(-u / 0.001)) * (t >= t0) * 1.0
    M = chest + press + crack
    L, R = M.copy(), M.copy()
    a, b = np.zeros(n), np.zeros(n)
    for k in range(5):                                         # (the land's whole sheet answering, from all round)
        ice(a, b, 0.0, 180 + 170 * k, THICK[("thick", "slab", "thick", "slab", "mid")[k]], 1.0 - 0.13 * k, (-0.7, 0.6, -0.3, 0.8, 0.1)[k], 2)
    L += a
    R += b
    # (the crater: rock going, a long roar of it falling in; none of it over FOIL Hz now)
    rl, rr = np.zeros(n), np.zeros(n)
    for t1 in P.poisson_times(0.02, 1.8, lambda s: 8.0):
        x = rock_crack(1.3, rng().uniform(0.7, 1.3), 0.8) * rng().uniform(0.3, 0.7)
        l, r = pan(x, rng().uniform(-0.9, 0.9))
        P.put(rl, l, t1)
        P.put(rr, r, t1)
    e = N.env_ar(n, 0.08, 0.12, 0.9, 0.4, 2.2)
    a, b = wide(bn(n, 60, 1500), bn(n, 60, 1500), 0.4)
    g = np.clip(grn(d, 60.0, (0.01, 0.03, 0.07)), 0, 5) ** 0.8
    rl = rl + a * e * g * 0.5
    rr = rr + b * e * g * 0.5
    L += bp(rl, None, FOIL, 3)
    R += bp(rr, None, FOIL, 3)
    # (the thrown blocks coming back down, from about 1.5 s to 5 s)
    pl, pr = patter(d, 1.5, 5.4, lambda v: 30.0 * np.clip((v - 1.5) / 0.7, 0, 1) * np.exp(-max(v - 2.3, 0) / 1.1), 1.4)
    L += pl
    R += pr
    L, R = verb(L, R, 0.4, length=4.5, darken=(1400, 220), decay=1.8)
    # (it rolls off round the land, out and away)
    for at, dull, g_ in ((0.8, 500, 0.3), (1.7, 360, 0.2), (3.0, 260, 0.13)):
        for c, x in zip((L, R), (L.copy(), R.copy())):
            P.put(c, bp(x[:n_of(1.5)], None, dull) * g_, at)
    e = 1 - 0.6 * ss(2.0, 2.8, t)                              # (from where `sink`'s landings come in it stands back)
    L, R = low_mono(L * e, R * e, 170.0)
    out("slam", L, R, -6.0, tail=0.8, peak=10 ** (-3.2 / 20))


def sink():
    """The crater going in, on the picture's clock, panel by panel (`panels`): 0.2 s of nothing moving, then each kite shears off its
    neighbours, ring after ring from the middle out to 2.4 s; while they fall the walls of the pit grind and the air goes down
    after them; from 2.15 s they land, each ring its own way, the last of the deep edge of ring 3 at 4.3; what they threw comes down
    after them; it all rolls off round the land. A staged collapse, not a roar with a fade: every event here is a panel."""
    d = 9.0
    n = n_of(d)
    t = times(n)
    table = panels()
    falling = np.zeros(n)                                      # (how much land is in the air, by the panels' areas)
    landing = np.zeros(n)                                      # (how hard the land is coming down: what the debris follows)
    SIZE = (0.72, 0.86, 1.0, 1.22)                             # (ring 0's a slab, ring 3's a county: but the small ones land nearer the ear of it)
    for ring, late, first, last in table:
        falling += SIZE[ring] ** 2 * ss(late, late + 0.3, t) * (1 - ss(first, last + 0.15, t))
    falling /= falling.max()
    # (the walls of the pit going: rock sliding on rock, boiling at every scale, its top opening as more of it moves)
    wave = falling
    fade = 10 ** (np.interp(t, (0.0, 0.2, 0.6, 2.0, 4.4, 6.0, 8.0, 9.0), (-70.0, -44.0, -14.0, -2.0, 0.0, -11.0, -24.0, -60.0)) / 20)
    slide = eddies(d, 55, 2200, 3.0, -5.0, 11.0, 6.0, np.clip(wave * 2.0, 0.2, 2.4), 1.6, 280.0) * (0.14 + 1.0 * wave) * fade
    # (the air: dragged down after the land, then shoved back up out of the pit; a slow suck, no whistle)
    ai = bp(noise(n), 18, 70) * 10 ** (np.interp(t, (0.0, 0.4, 1.8, 2.3, 4.3, 5.5, 8.0), (-70.0, -26.0, -9.0, -6.0, -3.0, -14.0, -60.0)) / 20)
    rush = eddies(d, 90, 900, 2.5, -4.0, 9.0, 5.0) * 10 ** (np.interp(t, (0.0, 0.5, 2.1, 4.3, 5.6, 7.5), (-70.0, -44.0, -26.0, -21.0, -32.0, -70.0)) / 20)
    x = slide * 0.13 + ai * 0.16 + rush * 0.7
    for ring, late, first, last in table:
        s = SIZE[ring]
        # (it lets go: a shear through the rock along the crease, a dull break with its weight under it, no bright edge)
        y = bp(rock_crack(1.4, 0.8 + 0.7 * s, 0.6), None, 1300) * 0.3 * s * rng().uniform(0.75, 1.1)
        P.put(y, bare_blow(1.2 + s, 28, 120, 0.02, 0.09) * 0.32 * s, 0.0)
        P.put(x, y, max(late - 0.02, 0.0))
        # (it lands: a contact, the ground taking it, the rock of it breaking, over however long its span takes to come down)
        span = last - first
        k = n_of(1.6 + span)
        c = 0.0 if ring < 2 else max(span - 0.12, 0.0)         # (rings 2 and 3: the deep inner edge is the weight, the rim only a roll before it)
        g = rng().uniform(0.85, 1.1) * s
        y = struck(k, c, max(span - c, 0.012) + 0.02 + 0.03 * s, GROUND[1:], 30, 0.4) * 0.8
        y = y + struck(k, c, max(span - c, 0.012) + 0.02, RUBBLE, 18, 0.5) * 0.55
        q = np.maximum(times(k) - c, 0)
        y = y + rocks(k / SR, (260.0 + 240.0 * s) * (1 - np.exp(-q / 0.03)) * np.exp(-q / (0.08 + 0.08 * s)) + 1e-3, 110, 2600, (0.4, 0.9, 1.7), (0.5, 0.36, 0.14)) * np.exp(-q / (0.2 + 0.14 * s)) * 0.5
        P.put(y, bare_blow(1.2 + s, 24, 130, 0.012, 0.09) * 0.5, c)
        P.put(y, whole(0.8, 0.78, 0.003, 0.12 + 0.05 * s, 0.01), c)
        if ring >= 2:                                          # (the rim first, the contact running in along it)
            q0 = times(k)
            y = y + rocks(k / SR, 160.0 * ss(0.0, 0.2, q0) * (1 - ss(c - 0.1, c + 0.05, q0)) + 1e-3, 90, 900, (0.5, 1.0, 1.8), (0.5, 0.36, 0.14)) * 0.12 + \
                bn(k, 26, 140) * ss(0.0, c, q0) * (1 - ss(c, c + 0.25, q0)) * 0.14
        P.put(x, y * g * 0.8, first)
        # (the debris it threw: starting a moment after it lands, a thing of the same size as the panel)
        landing += s * (1 - np.exp(-np.maximum(t - last - 0.3, 0) / 0.12)) * np.exp(-np.maximum(t - last - 0.3, 0) / (0.8 + 0.4 * s)) * (t > last + 0.3)
    landing /= landing.max()
    clatter = rocks(d, 90.0 * landing ** 0.8 + 1e-3, 150, 1500, (0.2, 0.45, 1.0), (0.6, 0.3, 0.1))
    L, R = x.copy(), x.copy()
    # (the ice's voice, thick and far, as each ring goes: the crease running off)
    a_, b_ = np.zeros(n), np.zeros(n)
    for at, fc, dd, amp, side in ((0.42, "thick", 240, 0.26, -0.4), (1.05, "slab", 320, 0.32, 0.5), (1.72, "slab", 420, 0.36, -0.2), (2.3, "slab", 300, 0.4, 0.3)):
        pew(a_, b_, at, dd, THICK[fc], amp, side, 2)
    pl, pr = patter(d, 2.6, 7.6, lambda v: 13.0 * np.clip((v - 2.6) / 0.9, 0, 1) * np.exp(-max(v - 4.0, 0) / 1.2), 0.9)
    L, R = L + a_ + clatter * 0.13 + pl, R + b_ + clatter * 0.13 + pr
    Lr, Rr = verb(L, R, 0.16, length=3.0, darken=(1300, 200), decay=0.9)
    rl, rr = rolls(n, 2.8, 22, 5.2)
    g = T.loudest(x) * 0.16 / (T.loudest((rl + rr) / 2) + 1e-9)
    L, R = Lr + rl * g, Rr + rr * g
    L, R = lows_heard(L, 70, 420, -4.0), lows_heard(R, 70, 420, -4.0)
    L, R = low_mono(L, R, 170.0)
    out("sink", L, R, -10.5, tail=1.0, peak=10 ** (-2.0 / 20))


def underfoot():
    """Not another blow: the sink has those. This is the ground under the player's own feet, close and dry: the panel they're standing on stops, one short thick shove up through the soles, and the
    whole of it shudders for a second, a dozen uneven tremors a second dying away, loose stuff chattering on it. Nothing here is further off than the ground, so no echo."""
    d = 1.9
    n = n_of(d)
    t = times(n)
    x = np.zeros(n)
    press = bp(T.friedlander(n, 0.0, 0.16, 1.4), 16, 90)
    x += press / np.abs(press).max() * 1.0
    # (the shudder: tremors uneven in time and size, each a little lump of the ground's lows)
    at = 0.03
    rate = np.zeros(n)
    while at < 1.5:
        g = np.exp(-at / 0.42) * rng().uniform(0.6, 1.1)
        m = n_of(0.16)
        s = times(m)
        y = T.unit(bp(noise(m), 26, 150)) * (1 - np.exp(-s / 0.006)) * np.exp(-s / 0.03) * g * 0.8
        P.put(x, y, at)
        rate[min(n_of(at), n - 1)] = g
        at += rng().uniform(0.062, 0.11) * (1 + at * 0.5)
    # (and what's lying on it jumps with each)
    e = fftconvolve(rate, np.exp(-times(n_of(0.05)) / 0.012))[:n]
    jump = rocks(d, np.clip(e * 900.0, 0.5, 1800.0), 130, 760, (0.2, 0.4, 0.8), (0.6, 0.32, 0.08))
    x = x + jump * 0.12
    x = x + bn(n, 20, 62) * (1 - np.exp(-t / 0.03)) * np.exp(-t / 0.5) * 0.5
    x = lows_heard(x, 70, 420, -5.0)
    out("underfoot", x, x.copy(), -18.0, tail=0.4, peak=10 ** (-7.0 / 20))


def comedown():
    """Nothing happens here: that's what it is. The land has stopped, and what's left goes out of it as `ripple`'s seas came in: four slow seas of the ground's own weight, made the same way, each
    lower and further off and the wash on them going, the last of the thunder rolling round the horizon, and cold wide air coming in over the crater at the end. No stones, no ticks, no pings: nothing
    to count. Nothing over 800 Hz or so: the fires are there. It ends with the strike at 59.7."""
    d = LEN - COMEDOWN
    n = n_of(d)
    t = times(n)
    SEAS = ((-0.2, 2.2, 1.0), (1.5, 2.2, 0.62), (2.9, 2.0, 0.36), (4.1, 1.9, 0.2))

    def crest(tc, power=1.0):
        e = np.zeros(len(tc))
        for t_, dur, amp in SEAS:
            v = np.clip((tc - t_) / dur, 0, 1)
            e = e + amp * (v ** 0.8 * (1 - v) ** 1.7 / 0.31) ** power
        return e

    weight = water(d, (-8.0, 0, 2, 0, -4, -9, -16, -24, -34, -46, -60, -70, -80, -90, -90, -90), lambda s_: 20 * np.log10(0.02 + crest(s_)), (0.3, 0.5), 1.0, (5.0, 0.5, 40.0, 240.0))
    wash = lambda: water(d, (-40.0, -30, -20, -12, -6, -3, -2, -5, -10, -20, -34, -50, -70, -90, -90, -90), lambda s_: 20 * np.log10(0.01 + 0.7 * crest(s_ - 0.12, 1.5)), (0.5, 0.9), 1.0, (6.0, 0.7, 90.0, 700.0))
    L, R = weight + wash() * 0.45, weight + wash() * 0.45
    rl, rr = rolls(n, 0.4, 7, 3.8)
    g = T.loudest(weight) * 0.32 / (T.loudest((rl + rr) / 2) + 1e-9)
    L, R = L + bp(rl, None, 260) * g, R + bp(rr, None, 260) * g
    L, R = lows_heard(L, 70, 300, -9.0), lows_heard(R, 70, 300, -9.0)
    L, R = low_mono(L, R, 170.0)
    L, R = verb(L, R, 0.3, length=3.2, darken=(700, 170), decay=1.3)
    # (the cold air coming in, wide, under the fires' band)
    e = ss(2.4, 4.4, t) * (1 - ss(d - 1.5, d - 0.1, t))
    wl, wr = wide(eddies(d, 150, 760, 2.0, -4.0, 16.0, 7.0), eddies(d, 150, 760, 2.0, -4.0, 16.0, 7.0), 0.25)
    A = T.loudest((L + R) / 2)
    L, R = L + wl * e * A * 0.14, R + wr * e * A * 0.14
    L, R = bp(L, None, 900, 3), bp(R, None, 900, 3)
    out("comedown", L, R, -19.0, tail=1.2)


BUILD = {"descent": descent, "wobble": wobble, "air": air, "meld": meld, "ripple": ripple, "score": score, "unravel": unravel,
         "groan": groan, "foldown": foldown, "ding": ding, "reverse": reverse, "bang1": bang1, "bang2": bang2,
         "bang3": bang3, "bang4": bang4, "fall": fall, "slam": slam, "comedown": comedown, "letgo": letgo, "sink": sink, "underfoot": underfoot}
GONE = ("stop", "tear", "creak", "crush", "bloom", "thud", "drone", "bounce1", "bounce2", "bounce3", "bounce4")
SEEDS = {name: 171000 + 7 * k for k, name in enumerate(BUILD)}          # (a new stem goes on the end, so no other's take changes)


# ==============================================================================================================  listening
def db(x):
    return 20 * np.log10(max(float(x), 1e-12))


def picture(x, path, w=1800, rows=420, env=160):
    """A spectrogram of `x` (log frequency, 20 Hz at the bottom to 20 kHz; a second a 32 pixels or so, black at -90 dB,
    white at 0) over its level (-60 to 0 dB), as a PNG: its bands are read off the FFT, so what is drawn is what is there."""
    size = 8192
    hop = max(len(x) // w, 1)
    win = np.hanning(size)
    f = np.fft.rfftfreq(size, 1 / SR)
    edges = np.geomspace(20, 20000, rows + 1)
    lo = np.searchsorted(f, edges[:-1])
    hi = np.maximum(np.searchsorted(f, edges[1:]), lo + 1)
    img = np.zeros((rows, w))
    for c in range(w):
        fr = x[c * hop:c * hop + size]
        if len(fr) < size:
            fr = np.pad(fr, (0, size - len(fr)))
        p = np.abs(np.fft.rfft(fr * win)) ** 2
        cum = np.concatenate([[0], np.cumsum(p)])
        img[:, c] = ((cum[hi] - cum[lo]) / (hi - lo))[::-1]
    gray = np.clip((10 * np.log10(img / (size / 4) ** 2 + 1e-14) + 90) / 90, 0, 1)
    lev = np.zeros((env, w))
    for c in range(w):
        fr = x[c * hop:c * hop + hop]
        v = 20 * np.log10(np.sqrt(np.mean(fr ** 2)) + 1e-9) if len(fr) else -120
        pk = 20 * np.log10(np.abs(fr).max() + 1e-9) if len(fr) else -120
        lev[int(np.clip(-pk / 60, 0, 1) * (env - 1)):, c] = 0.45
        lev[int(np.clip(-v / 60, 0, 1) * (env - 1)):, c] = 1.0
    for db_ in (-20, -40):
        lev[int(-db_ / 60 * (env - 1))] = np.maximum(lev[int(-db_ / 60 * (env - 1))], 0.25)
    for sec in range(0, int(len(x) / SR), 5):                   # (a tick every 5 s)
        c = int(sec * SR / hop)
        if c < w:
            lev[:, c] = np.maximum(lev[:, c], 0.3)
            gray[:, c] = np.maximum(gray[:, c], 0.3)
    raw = (np.vstack([gray, np.zeros((6, w)), lev]) ** 1.2 * 255).astype("u1").tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "gray", "-s", f"{w}x{rows + 6 + env}", "-i", "-", "-frames:v", "1", str(path)],
                   input=raw, check=True)


def untrimmed(name):
    """The file as the game's decoder sees it (no gapless trimming): (samples past the file's end, their loudest)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-flags2", "+skip_manual", "-i", path_of(name) + ".ogg", "-f", "f32le", "-ac", "2", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(float)


def full_mix():
    """The whole strike's timeline, as stereo files. The game sums each file to mono."""
    clips = {nm: decoded(nm) for nm in BUILD}
    end = max(max(at + len(clips[f]) / SR / p for at, f, _, p in EVENTS) + 0.5, LEN)
    mix = np.zeros((n_of(end), 2))
    for at, f, vol, p in EVENTS:
        c = N.pitched(clips[f], p) * vol
        k = n_of(at)
        mix[k:k + len(c)] += c
    return mix


def mp3(x, path):
    wav = Path(path).with_suffix(".wav")
    N.write_wav(wav, x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libmp3lame", "-b:a", "224k", str(path)], check=True)
    return wav


def listen(out_dir):
    d = Path(out_dir)
    d.mkdir(parents=True, exist_ok=True)
    print(f"\n{'file':10s} {'len':>7s} {'peak':>7s} {'loudest':>8s} {'LUFS':>7s} {'TP':>6s} {'mono-st':>8s} {'KB':>6s}")
    total = 0
    for nm in BUILD:
        x = decoded(nm)
        wav = mp3(x, d / f"{nm}.mp3")
        mono = np.repeat(x.mean(axis=1, keepdims=True), 2, axis=1)
        p = d / "_mono.wav"
        N.write_wav(p, mono)
        lufs, tp, _ = N.measure(p)
        wav.unlink()
        p.unlink()
        kb = Path(path_of(nm) + ".ogg").stat().st_size / 1024
        total += kb
        st = db(np.sqrt(np.mean(x ** 2)))
        print(f"{nm:10s} {len(x) / SR:7.3f} {db(np.abs(x).max()):7.2f} {db(T.loudest(x.mean(axis=1))):8.1f} {lufs:7.1f} {tp:6.1f} {db(np.sqrt(np.mean(x.mean(axis=1) ** 2))) - st:8.1f} {kb:6.0f}")
    print(f"total {total / 1024:.2f} MB")

    mix = full_mix()
    wav = mp3(mix, d / "fold_mix.mp3")
    mono = mix.mean(axis=1)
    picture(mono, d / "fold_mix.png")
    p = d / "_mono.wav"
    N.write_wav(p, np.repeat(mono[:, None], 2, axis=1))
    lufs, tp, _ = N.measure(p)
    p.unlink()
    wav.unlink()
    print(f"\nthe mix: peak {db(np.abs(mix).max()):.2f} dBFS stereo, summed {db(np.abs(mono).max()):.2f} dBFS, {lufs:.1f} LUFS, {tp:.1f} dBTP")
    print(f"{'section':10s} {'from':>6s} {'to':>6s} {'stereo':>7s} {'peak':>7s} {'rms':>7s} {'loudest':>8s}")
    for nm, a, b in SECTIONS:
        s = mono[n_of(a):n_of(b)]
        s = s if len(s) else np.zeros(1)
        print(f"{nm:10s} {a:6.1f} {b:6.1f} {db(np.abs(mix[n_of(a):n_of(b)]).max()):7.1f} {db(np.abs(s).max()):7.1f} {db(np.sqrt(np.mean(s ** 2))):7.1f} {db(T.loudest(s)) if len(s) > n_of(0.5) else float('nan'):8.1f}")

    print("\nthe hard edges:")
    for nm, want in (("descent", STOP), ("reverse", FLAT - REL)):
        x = decoded(nm)
        print(f"  {nm:8s} {len(x)} samples ({len(x) / SR:.4f} s, wanted {want}); last 10 ms {db(np.sqrt(np.mean(x[-n_of(0.01):] ** 2))):.1f} dB, the 50 ms before {db(np.sqrt(np.mean(x[-n_of(0.06):-n_of(0.01)] ** 2))):.1f} dB")
    for a, b, what in ((STOP, STOP + 0.05, "after the stop"), (39.6, DING, "before the ding")):
        print(f"  {what}: {a:.2f} to {b:.2f} s peak {db(np.abs(mix[n_of(a):n_of(b)]).max()):.1f} dB")


def dings(out_dir):
    """Every way of the touch, in what leads into it and out of it: `foldown`, the option, `reverse`, 37.6 to 43.3 s. MP3s, pictures and the levels."""
    d = Path(out_dir)
    d.mkdir(parents=True, exist_ok=True)
    real = soundlib.OUT
    fold, back = decoded("foldown"), decoded("reverse")
    a, b = 37.6, 43.3
    for k, f in DINGS.items():
        soundlib.init(d / "stems" / k)
        with PB.seeded(SEEDS["ding"]):
            _kernels.clear()
            f()
        clip = decoded("ding")
        soundlib.OUT = real
        mix = np.zeros((n_of(46.0), 2))
        for at, c in ((GATHER, fold), (DING - DING_LEAD, clip), (REL, back)):
            i = n_of(at)
            mix[i:i + len(c)] += c[:len(mix) - i]
        w = mix[n_of(a):n_of(b)]
        w[-n_of(0.15):] *= np.linspace(1, 0, n_of(0.15))[:, None]
        wav = mp3(w, d / f"ding_{k}.mp3")
        wav.unlink()
        picture(w.mean(axis=1), d / f"ding_{k}.png", 900, 300, 120)
        m = mix.mean(axis=1)
        lev = " ".join(f"{db(np.sqrt(np.mean(m[n_of(t):n_of(t + 0.25)] ** 2))):5.0f}" for t in np.arange(38.5, 42.5, 0.25))
        print(f"{k:10s} peak {db(np.abs(mix).max()):5.1f}  {lev}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=list(BUILD))
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write MP3s, the whole strike's mix and the level checks here")
    ap.add_argument("--dings", help="also write every way of the touch here, in its context (after the stems)")
    a = ap.parse_args()
    soundlib.init(a.out)
    for name in a.only if a.only is not None else BUILD:
        with PB.seeded(SEEDS[name]):
            _kernels.clear()
            BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    for name in GONE:
        sounds.pop(f"{TH}.{name}", None)
        (Path(a.out) / "assets" / "orbital" / "sounds" / TH / f"{name}.ogg").unlink(missing_ok=True)
    for name in BUILD:
        sounds[f"{TH}.{name}"] = {"sounds": [{"name": f"orbital:{TH}/{name}", "stream": True}], "subtitle": f"subtitles.orbital.{TH}.{name}"}
    path.write_text(json.dumps(sounds, indent=2))
    if a.listen:
        listen(a.listen)
    if a.dings:
        dings(a.dings)


if __name__ == "__main__":
    main()
