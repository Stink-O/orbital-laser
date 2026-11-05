"""The Fold's sounds (laser 15), all synthesised here from noise, impulses and physical models; nothing sampled. Every stem
is one take of many small irregular events, not a one-shot replayed: the only thing heard twice is nothing.

The heart of it is the ice: `flex` puts a hit through the real dispersion of a bending wave in a floating sheet (the
skipping stone on a frozen pond): the highs arrive first, the pitch falls as d / sqrt(f), it lands on the held tone where
the wave's phase speed meets the speed of sound in air (`fc`: ~725 Hz on 4 cm ice, ~195 Hz on 16 cm), and the dull knock
of the hit itself comes last through the air, d / 340 s late. Distance is the chirp's length.

As strike/fold.rs plays them (strike seconds; `EVENTS` below has volumes):

  descent   0 s, exactly 3.4 s: a body of fire coming down, flames and crackle, nothing climbing in pitch, swelling as it nears
            and ending at full force on its last sample, no tail.
  wobble    3.49 s: the droplet settling: one heavy dense surge and a small one back (the picture's 2.2 Hz), thick and dark,
            like a tonne of mercury, gone half a second after the stop.
  air       ~3.9 s (late by the distance, 0.5 s at 170 blocks): the air that kept going: a soft shove, the fire's roar carried
            past and away with a few embers, a gust thinning over the ground, gone by ~6.9 s.
  letgo     4.9 s, to 6.0: let go: one faint give in the metal, then the air over it as it falls, its speed the picture's.
  meld      5.6 s: the land rising to meet it, faintly; 6 s the landing, a heavy blow with its full speed behind it; the land
            closing over it at 6.3 with the first deep gulp, heaving to a peak at 6.4; the gulps sinking on to 7.5.
  ripple    7.5 s: the land moving like water: low heaves, each bigger, slow water and wet soil over them.
  score     12 s: the creases: ice. Clean pews one at a time with air between them, stones skipping away, a thicker sheet as it
            goes on, and from 16 s the tears: a heavy falling chirp and a dark breath of ground parting.
  unravel   19 s: long falling glissandi off a thick sheet, heave after heave, room between them.
  groan     19 s: the land bending, a hull's and a tree's stress, closing overhead from 26 s: the sky's air goes, the sound turns
            inward to a huge dark space.
  foldown   35 s: the seal, a far vault shutting, and the fold coming down: creases getting smaller and further apart, a vast
            mechanism's ticks running slower and slower, the air draining till there is nothing by 39.6.
  ding      40 s: the touch: one small pure tone in the silence, a fork's kind of note, the hollow answering far off.
  reverse   40.5 s, exactly 3.6 s: the whole fold going back, on the picture's own clock: the ground starting to move, the arm's
            stages undoing one by one, the seal parting at 41.9, the walls of land working open and the sky's air coming in,
            the far land going at the end. Forward sounds gathering: nothing played backwards, nothing climbing in pitch.
  bang1-4   44.1, 45.2, 46.3, 47.4 less 0.8 s: a ring of land falling for 0.8 s and stopping dead: its own fall, its own bang.
            bang1 the far land, a long hit rolling away round the horizon; bang2 a broken ring, two blows; bang3 the nearest and
            hardest, a shard landing after it; bang4 short, hollow and dead.
  fall      47.9 s: the last fall: the air under the land going, rising, and 90 ms of nothing before the slam.
  slam      48.7 s: the last ring comes down: a door the size of the sky, the crater going in, a rumble rolling off, and from
            1.5 s on the stones coming back down.
  comedown  49.7 s, to the strike's end at 59.7: the last of the stones to +5 s, the land settling, far ice pinging, cold air,
            quiet, with room for the fires.

The game mixes every file to mono as it decodes it, so all of these are built to sum well: their lows are mono, nothing on
the two sides is out of phase, and the levels here are measured on the sum.

    python3 tools/sounds_fold.py                  # writes orbital-sounds/assets/orbital/sounds/fold/*.ogg and the fold.* events
    python3 tools/sounds_fold.py --only ding      # one (or several)
    python3 tools/sounds_fold.py --listen DIR     # also an MP3 of each, the whole strike's mix (fold_mix.mp3, spectrograms)
                                                  # and the levels section by section, stereo and summed
"""
import argparse, json, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.fft import irfft, next_fast_len, rfft, rfftfreq
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
STOP, HANG, TOUCH, CLOSED, RIPPLE, SCORE, TEAR, FOLD, CLOSING, SEAL = 3.4, 4.9, 6.0, 6.3, 7.5, 12.0, 16.0, 19.0, 26.0, 35.0
REACHED, DING, REL, LEN = 39.0, 40.0, 40.5, 59.7      # (the arm's stages done, the tip 13 short and creeping: FW_HANG; FD_LEN)
SLAMS = [44.1, 45.2, 46.3, 47.4, 48.7]                # (FD_SLAM: each ring falling for FALL s and stopping dead)
FLAT, SLAM = SLAMS[0], SLAMS[4]
# when the land lets go in great heaves; the fold's stages (FD_FOLDS)
RINGS = [19.1, 21.0, 23.3, 25.1, 27.6, 29.9]
CREASES = [35.0, 35.5, 36.1, 36.8, 37.5, 38.2]
PULSES = [7.5, 8.6, 9.6, 10.6, 11.5]  # the water's pulses of the middle, from when the droplet is absorbed
SWELLS = [11.25, 12.25, 13.2, 14.2]   # the swell under a player at 170 blocks, a crest about 0.55 s after each; biggest ~12.8
MELD_LEAD = 0.4                       # meld starts this far before contact, as the land rises to meet the droplet (5.6 s)
FALL = 0.8                            # how long each ring falls (fold_warp's FW_FALL): 1 - u^3, slowly away, its weight in the last of it
AIR_LATE = 0.5                        # the air's sound after the stop, at 170 blocks (the plan uses the real distance)

# (time, file, volume, pitch), as fold_plan plays them
EVENTS = [(0.0, "descent", 1.0, 1.0), (STOP + 0.09, "wobble", 1.0, 1.0), (STOP + AIR_LATE, "air", 1.0, 1.0), (HANG, "letgo", 1.0, 1.0),
          (TOUCH - MELD_LEAD, "meld", 1.0, 1.0), (RIPPLE, "ripple", 1.0, 1.0), (SCORE, "score", 1.0, 1.0),
          (FOLD, "unravel", 1.0, 1.0), (FOLD, "groan", 1.0, 1.0), (SEAL, "foldown", 1.0, 1.0),
          (DING, "ding", 1.0, 1.0), (REL, "reverse", 1.0, 1.0),
          *[(t - FALL, f"bang{k + 1}", 1.0, 1.0) for k, t in enumerate(SLAMS[:4])],
          (SLAM - FALL, "fall", 1.0, 1.0), (SLAM, "slam", 1.0, 1.0), (SLAM + 1.0, "comedown", 1.0, 1.0)]
SECTIONS = [("descent", 0.0, 3.4), ("hush", 3.4, 3.9), ("air", 3.9, 4.9), ("drop", 4.9, 6.0), ("hit", 6.0, 6.5), ("sink", 6.5, 7.5), ("ripple", 7.5, 12.0),
            ("score", 12.0, 16.0), ("tear", 16.0, 19.0), ("unravel", 19.0, 26.0), ("close", 26.0, 35.0), ("foldown", 35.0, 39.0), ("hush2", 39.6, 40.0),
            ("ding", 40.0, 40.5), ("gather", 40.5, 41.9), ("open", 41.9, 43.3), ("farland", 43.3, 44.1), ("bang1", 44.1, 45.2), ("bang2", 45.2, 46.3),
            ("bang3", 46.3, 47.4), ("bang4", 47.4, 47.9), ("fall", 47.9, 48.7), ("slam", 48.7, 50.2), ("stones", 50.2, 53.7), ("comedown", 53.7, 59.7)]


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
    """Debris coming down: clods, stones clacking, grit ticks; the further off the darker. (L, R), dry."""
    n = n_of(d)
    L = np.zeros(n)
    R = np.zeros(n)
    for t1 in P.poisson_times(t_lo, t_hi, rate):
        near = rng().random() ** 1.6
        kind = rng().random()
        if kind < 0.3:
            size = min(rng().pareto(2.0) * 0.4 + 0.3, 2.0)
            m = n_of(0.2 + 0.3 * size)
            s = times(m)
            x = T.thud(m, size) * size * 0.12
            x += T.unit(bp(noise(m), 500, 4000)) * np.exp(-s / rng().uniform(0.012, 0.03)) * np.minimum(s / 0.002, 1) * 0.03
        elif kind < 0.65:
            size = rng().uniform(0.3, 1.0)
            m = n_of(0.3)
            x = P.modal_hit(m, rng().uniform(700, 2400) / (0.6 + size), [1.0, rng().uniform(1.45, 2.2), rng().uniform(2.4, 3.9), rng().uniform(4.1, 5.6)],
                            [rng().uniform(0.004, 0.02), rng().uniform(0.003, 0.01), 0.004, 0.002], [1.0, 0.7, 0.45, 0.25], 0.5)
            x = x / (np.abs(x).max() + 1e-9) * 0.07 * size
            if rng().random() < 0.3:
                P.put(x, x * rng().uniform(0.25, 0.5), rng().uniform(0.07, 0.2))
        else:
            m = n_of(0.006)
            x = bp(PB.tick(m, 0, min(rng().pareto(2.4) * 0.35 + 0.15, 2.0) * 0.06, rng().uniform(0.0002, 0.0008), rng().choice([-1.0, 1.0])), 900, 8000)
        x = bp(x, None, 1500 + 7000 * near)
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

    # (the air tearing: rough grabs too quick to count, thickening; no tone in it)
    fib = stick(n, 900.0 * np.clip(1 + 0.3 * PB.slow_random(n, 1.0, 6.0), 0.4, None), 0.6, 0.1, 0.002, 0.0007)
    fib = (T.unit(bp(fib, 500, 2500)) + 0.7 * T.unit(bp(fib, 2500, 9000))) * lv * (0.1 + 0.42 * near)
    L += fib
    R += fib * 0.8 + 0.2 * bn(n, 900, 7000) * lv * (0.1 + 0.42 * near)

    # (flame: a body of fire flapping and tearing at itself, its flicker uneven, fuller as it nears)
    fl = np.clip(0.5 + 0.8 * PB.slow_random(n, 5.0, 26.0), 0.02, None) ** 1.5
    fa_, fb_ = wide(bn(n, 90, 950), bn(n, 90, 950), 0.75 - 0.3 * near)
    L += fa_ * fl * lv * 0.85
    R += fb_ * fl * lv * 0.85

    # (plasma crackle: ticks thickening to a sizzle, then pops)
    for rate, amp, gr, tau, lo, hi in ((lambda t: 30 + 1500 * (t / STOP) ** 3, 1.0, 0.002, 0.00035, 1400, 11000),
                                       (lambda t: 3 + 55 * (t / STOP) ** 2.2, 2.2, 0.008, 0.0022, 500, 5000)):
        tick = [np.zeros(n), np.zeros(n)]
        for t1 in P.poisson_times(0.0, STOP + pad, lambda t: rate(min(t, STOP))):
            k = int(t1 * SR)
            a_ = min(rng().pareto(2.0) * 0.5 + 0.25, 5.0) * rng().choice([-1.0, 1.0])
            p = rng().uniform(-1, 1) * (0.2 + 0.8 * near[k])
            tick[0][k] += a_ * (1 - p) / 2
            tick[1][k] += a_ * (1 + p) / 2
        m = n_of(gr)
        ker = noise(m) * np.exp(-times(m) / tau)
        for ch, tk in zip((L, R), tick):
            ch += T.unit(bp(fftconvolve(tk, ker)[:n], lo, hi)) * lv * amp * 0.4

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
def wobble():
    """Something very heavy settling: one dense low surge and a small one back, the picture's 2.2 Hz (fold.wgsl: 0.055 e^(-5.5 a)
    sin 14 a), thick and dark. No bubbles, no pitch rising: a tonne of mercury in a steel tank, heard through the wall, gone
    half a second after the stop. Plays 0.09 s after it, about the bottom of the first squash."""
    d = 0.8
    n = n_of(d)
    t = times(n)
    f = 2.2
    swing = np.abs(np.sin(2 * np.pi * f * t + 1.16))           # (crests about 0.03 and 0.26 s in: the settle, the small one back)
    env = np.exp(-5.5 * t) * ss(0.0, 0.04, t) * (0.12 + 0.88 * swing ** 2.2) * (1 - ss(0.36, 0.56, t))
    # (the weight of it: a dark band sinking as it dies, a pressure under that)
    body = P.glide_band(d, 82.0 - 26.0 * ss(0.0, 0.5, t), 0.42)
    thick = P.glide_band(d, 190.0 - 70.0 * ss(0.0, 0.5, t), 0.6)
    ph = 2 * np.pi * np.cumsum(41.0 - 7.0 * ss(0.0, 0.5, t)) / SR
    M = (body * 1.0 + thick * 0.34 + (np.sin(ph) + 0.25 * np.sin(2 * ph + 0.7)) * 0.75) * env
    # (its skin dragging against itself, very faint, only as it turns)
    a, b = wide(bn(n, 420, 1300), bn(n, 420, 1300), 0.6)
    drag = np.exp(-5.5 * t) * ss(0.0, 0.06, t) * (1 - swing) ** 2 * 0.05 * (1 - ss(0.36, 0.56, t))
    L, R = low_mono(M + a * drag, M + b * drag, 200.0)
    out("wobble", L, R, -28.0, tail=0.2)


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
    """Held dead still, and let go. Nothing lets go of it, so there is no latch: only the metal taking its own weight, a single
    faint give, a tick off its skin and the mass under it easing down. Then the air over it, on the picture's free fall (speed
    rising in a straight line to 35.6 blocks a second on contact): quiet, low and uneven, a big body going through still air,
    not a whoosh: no band sweeping, its top barely moving. Right at the end the air under it spills out over the ground."""
    d = TOUCH - HANG + 0.03
    n = n_of(d)
    t = times(n)
    u = np.clip(t / (TOUCH - HANG), 0, 1)
    L, R = np.zeros(n), np.zeros(n)
    # (the give: what the wobble was made of, once, low and small)
    m = n_of(0.5)
    s = times(m)
    e = (1 - np.exp(-s / 0.03)) * np.exp(-s / 0.11)
    y = (P.glide_band(0.5, 66.0 - 14.0 * ss(0.0, 0.3, s), 0.4) + np.sin(2 * np.pi * np.cumsum(38.0 - 5.0 * ss(0.0, 0.3, s)) / SR) * 0.6) * e * 0.37
    P.put(L, y, 0.0)
    P.put(R, y, 0.0)
    # (the tick: a heavy metal skin relaxing, a small dull note, not a chime; a smaller one a moment after)
    for at, a_, f1 in ((0.012, 0.9, 640.0), (0.083, 0.31, 910.0)):
        m = n_of(0.08)
        y = P.modal_hit(m, f1, [1.0, 1.52, 2.31, 3.4], [0.012, 0.008, 0.005, 0.003], [1.0, 0.55, 0.3, 0.14], 0.15, 3000)
        y = y / (np.abs(y).max() + 1e-9) * a_
        l, r = pan(y, 0.1)
        P.put(L, l, at)
        P.put(R, r, at)

    # (the air: its loudness going as the speed squared, unsteady)
    def over(s_, f):
        v = min(s_ / (TOUCH - HANG), 1.0)
        fc = 170.0 + 90.0 * v
        return np.minimum((f / fc) ** 1.1, (fc / f) ** 1.0) * np.exp(-(f / (1300.0 + 1500.0 * v)) ** 1.5)

    lv = u ** 2.0
    a, b = wide(morph(n, over), morph(n, over), 0.7)
    gust = np.clip(1 + 0.42 * PB.slow_random(n, 2.0, 11.0), 0.2, None)
    L += a * gust * lv * 0.6
    R += b * gust * lv * 0.6
    # (the weight of air pushed ahead of it, the pressure under it)
    low = bn(n, 26, 95) * np.clip(1 + 0.3 * PB.slow_random(n, 1.5, 7.0), 0.3, None) * u ** 2.6 * 0.42
    L += low
    R += low
    # (the last of it: the air spilling out from under it, a breath of dust over the ground)
    a, b = wide(bn(n, 900, 5200), bn(n, 900, 5200), 0.25)
    sp = ss(0.72, 1.0, u) * np.clip(1 + 0.35 * PB.slow_random(n, 3.0, 14.0), 0.3, None) * 0.05
    L += a * sp
    R += b * sp
    L, R = low_mono(L, R, 170.0)
    out("letgo", L, R, -24.5, tail=0.03)


def meld():
    """A landing with the whole fall behind it: the drop doesn't brake, it goes straight in like a stone into water. A heavy blow
    on 6.0, the air it pushes out, the land closing over it at 6.3 with the first deep gulp, as water shuts over a stone; the
    land heaving to its peak about 6.4 and settling to 7.5, with the deep gulps sinking in it."""
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
    # (the blow: tens of tonnes of metal meeting the ground tip first: earth taking it, nothing stony, nothing that rings)
    body = struck(n, t0, 0.06, ((30, 3, 1.3), (43, 4, 1.1), (61, 4, 0.9), (88, 3, 0.75), (133, 3, 0.55)), 30)
    thick = struck(n, t0, 0.05, ((118, 2.5, 1.0), (187, 2.5, 0.8), (296, 2, 0.5), (470, 2, 0.25)), 24)
    front_ = rough(n, t0, 0.03, 12, 170, 1500, 0.007)
    chest = blow(n, t0 + 0.008, 62, 46, 33, 0.05, 0.007, [(0.8, 0.17), (0.2, 0.55)], drive=2.6, octv=0.26, h3=0.12, harm=0.5)
    mass = bn(n, 70, 340) * (1 - np.exp(-u / 0.003)) * np.exp(-u / 0.06) * on
    puff = bn(n, 100, 900) * (1 - np.exp(-u / 0.014)) * np.exp(-u / 0.11) * on
    hit_ = body * 0.8 + thick * 0.8 + mass * 0.55 + front_ * 0.26 + chest * 0.42 + puff * 0.1
    # (the land heaving after it, up to about 6.4, then settling; slow earth, no grit)
    hv = ss(0.0, 0.42, u) * (1 - ss(0.5, 1.35, u)) * on
    ph3 = 2 * np.pi * np.cumsum((24.0 + 7.0 * (1 - ss(0.0, 1.4, u))) * on) / SR
    heave = (np.sin(ph3) + 0.35 * np.sin(2 * ph3 + 0.6) + 0.18 * np.sin(3 * ph3 + 1.4)) * hv * 0.3
    heave += bn(n, 46, 175) * np.clip(1 + 0.45 * PB.slow_random(n, 1.5, 7.0), 0.15, None) * hv * 0.12
    L = swell + hit_ + heave
    R = L.copy()
    # (the land shuts over it at 6.3, a stone's pinch-off made huge; then the deep gulps, the pitch of each falling, the last the biggest)
    for at, f0, a in ((0.3, 92, 0.42), (0.52, 74, 0.5), (0.74, 118, 0.3), (0.95, 66, 0.95), (1.17, 58, 1.25), (1.45, 49, 0.8)):
        y = bubble(f0, a * 0.4, rng().uniform(-0.2, -0.05), 0.03)                 # (sinking: the pitch falls, not rises)
        l, r = pan(y, rng().uniform(-0.25, 0.25))
        P.put(L, l, lead + at)
        P.put(R, r, lead + at)
    bubbles(L, R, lead + 0.3, lead + 1.3, lambda s: 8.0 * np.exp(-s / 0.9), 200, 620, 0.03, 0.45)
    L, R = low_mono(*verb(L, R, 0.18, length=1.6, darken=(900, 200), decay=0.7), 170.0)
    out("meld", L, R, -14.5, tail=0.3, peak=10 ** (-2.5 / 20))


def ripple():
    d = 7.9
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    # (the five pulses, each stronger, then the swell itself passing under the player, dying under the scoring)
    for t_, f, dur, amp in zip((*PULSES, *SWELLS), (46.0, 42.0, 38.0, 34.0, 30.0, 31.0, 29.0, 31.0, 33.0), (0.9, 1.0, 1.0, 1.0, 1.1, 1.6, 1.7, 1.5, 1.3),
                               (0.14, 0.3, 0.46, 0.6, 0.42, 0.34, 1.0, 0.62, 0.28)):
        at = t_ - RIPPLE
        m = n_of(dur)
        s = times(m)
        v = s / dur
        e = v ** 0.8 * (1 - v) ** 1.7
        e /= e.max()
        ph = 2 * np.pi * np.cumsum(f * (1 - 0.1 * v)) / SR
        y = (np.sin(ph) + 0.28 * np.sin(2 * ph + 0.6) + 0.12 * np.sin(3 * ph + 1.7)) * e * amp
        P.put(L, y, at)
        P.put(R, y, at)
        # (the land's weight of water going by: a slow wash, wet soil seeping and sucking in its wake)
        a, b = wide(bn(m, 150, 900), bn(m, 150, 900), 0.3)
        g = np.clip(1 + 0.4 * PB.slow_random(m, 0.6, 3.5), 0.2, None)
        P.put(L, a * g * e ** 1.5 * amp * 0.07, at + 0.1)
        P.put(R, b * g * e ** 1.5 * amp * 0.07, at + 0.1)
        for t1 in P.poisson_times(at + 0.3 * dur, at + dur, lambda _: 1.0 + 2.5 * amp):    # (a few slow deep gulps, each its own)
            y = bubble(rng().uniform(48, 120), rng().uniform(0.5, 1.0) * 0.16 * amp, rng().uniform(-0.2, -0.05), 0.04)
            l, r = pan(y, rng().uniform(-0.6, 0.6))
            P.put(L, l, t1)
            P.put(R, r, t1)
    L, R = low_mono(L, R, 170.0)
    L, R = verb(L, R, 0.2, length=2.6, darken=(900, 200), decay=1.0)
    # (the first hairline, right at the end, a hint)
    a, b = np.zeros(n), np.zeros(n)
    pew(a, b, 3.7, 300, THICK["skate"], 0.03, -0.5)
    pew(a, b, 4.25, 220, THICK["skate"], 0.05, 0.4)
    out("ripple", L + a, R + b, -20.0, tail=0.2)


# ============================================================================================================  the creases
def score():
    dur = FOLD - SCORE
    d = dur + 1.5
    n = n_of(d)
    L, R = np.zeros(n), np.zeros(n)
    # (one pew alone; a beat; a stone skipping off; then more, thicker, always one at a time with air between them)
    pew(L, R, 0.0, 110, THICK["skate"], 1.0, -0.15)
    stones(L, R, 0.9, 70, 320, 5, THICK["skate"], 0.8, 1.0)
    t = 2.55
    while t < dur - 0.5:
        v = t / dur
        fc = THICK[rng().choice(["skate", "skate", "mid"] if v < 0.55 else ["skate", "mid", "thick"])]
        side = rng().choice([-1.0, 1.0])
        kind = rng().random()
        big = (0.55 + 0.45 * v) * rng().uniform(0.75, 1.1)
        if kind < 0.24:
            stones(L, R, t, rng().uniform(70, 110), rng().uniform(240, 460), int(rng().integers(3, 6)), fc, big * 0.75, side)
            t += 0.7
        elif kind < 0.42:
            d0 = rng().uniform(80, 160)
            runs(L, R, t, d0, d0 + rng().uniform(120, 260), int(rng().integers(3, 6)), fc, big * 0.7, side)
            t += 0.35
        else:
            pew(L, R, t, rng().uniform(90, 460), fc, big, side * rng().uniform(0.1, 0.8))
        t += rng().uniform(0.5, 1.1) * (1.2 - 0.55 * v)
    # (the tears: the sheet parting under a heavy drop in pitch, then the dark weight of it going)
    for at, ln, po in ((TEAR - SCORE, 2.3, 0.3), (TEAR - SCORE + 1.6, 1.8, 0.34)):
        a, b = sheer(n, at, ln, po)
        L += a
        R += b
        pew(L, R, at, 130, THICK["thick"], 1.25, rng().uniform(-0.3, 0.3), 2)
    L, R = verb(L, R, 0.07, length=2.4, darken=(2600, 300), decay=0.9)
    L, R = PB.causal_lowcut(L, 45.0), PB.causal_lowcut(R, 45.0)
    L, R = low_mono(L, R, 170.0)
    out("score", L, R, -11.0, tail=0.4, peak=10 ** (-2.5 / 20))


def unravel():
    dur = SEAL - FOLD
    d = dur + 1.0
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    # (each heave: the great falling glissandi, a few jumps running off, the dark weight going; then room again)
    for k, r in enumerate(RINGS):
        at = r - FOLD
        side = -1.0 if k % 2 else 1.0
        pew(L, R, at, 300 + 70 * k, THICK["thick"], 1.2, side * 0.35, 2)
        pew(L, R, at + 0.22, 620, THICK["slab"], 1.0, -side * 0.5, 2)
        runs(L, R, at + 0.5, 140, 420, int(rng().integers(3, 5)), THICK["mid"], 0.45, side)
        a, b = sheer(n, at + 0.05, rng().uniform(1.3, 1.9), 0.26 + 0.03 * k)
        L += a
        R += b
    # (between them one far crack at a time)
    for t1 in P.poisson_times(0.6, dur - 2.5, lambda s: 0.45 + 0.4 * s / dur):
        fc = THICK[rng().choice(["skate", "mid", "thick", "thick", "slab"])]
        pew(L, R, t1, rng().uniform(200, 800), fc, rng().uniform(0.2, 0.5), rng().uniform(-0.9, 0.9))
    L, R = verb(L, R, 0.1, length=3.0, darken=(2200, 280), decay=1.2)
    # (the sky going: from 26 s it closes overhead, and all that's left of this is heard through the ground)
    w = ss(CLOSING - FOLD, dur - 0.8, t)
    L, R = muffle(L, w ** 0.7, 500.0) * (1 - 0.65 * w), muffle(R, w ** 0.7, 500.0) * (1 - 0.65 * w)
    L, R = PB.causal_lowcut(L, 45.0), PB.causal_lowcut(R, 45.0)
    L, R = low_mono(L, R, 170.0)
    out("unravel", L, R, -11.0, tail=1.0, peak=10 ** (-2.5 / 20))


# =======================================================================================================  the land closing
def moan(n, at, dur, f0, f1, wob=0.05):
    """One of the land's moans: a slow irregular glide pulled rough by stick-slip, swelling and easing. Mono."""
    m = min(n_of(dur), n - n_of(at))
    s = times(m)
    v = s / dur
    f = f0 * (f1 / f0) ** (v + 0.2 * np.sin(np.pi * v) * rng().uniform(-1, 1))
    f = f * (1 + wob * np.clip(PB.slow_random(m, 0.4, 3.0), -2.5, 2.5))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.sin(np.pi * v ** rng().uniform(0.55, 1.2)) ** 1.5
    rough = np.clip(1 + (0.25 + 0.45 * v) * PB.slow_random(m, 9.0, 34.0), 0.05, None)
    y = bp(np.tanh((1.2 + 2.5 * e) * np.sin(ph + 0.5 * np.sin(ph * 0.5))) * e * rough, None, 520)
    o = np.zeros(n)
    P.put(o, y, at)
    return o


def groan():
    seal, close = SEAL - FOLD, CLOSING - FOLD
    end = 38.0 - FOLD                                         # (gone before the last folds)
    d = end
    n = n_of(d)
    t = times(n)
    build = (0.06 + 0.94 * ss(1.0, seal - 0.5, t) ** 1.7) * (1 - ss(seal - 0.1, seal + 1.4, t))
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
    L, R = M.copy(), M.copy()
    for t1 in P.poisson_times(0.5, seal, lambda s: 0.5 + s / d):
        x = T.thud(n_of(1.0), rng().uniform(1.6, 3.0)) * rng().uniform(0.8, 1.8) * (0.3 + 0.7 * t1 / d)
        l, r = pan(x, rng().uniform(-0.7, 0.7))
        P.put(L, l, t1)
        P.put(R, r, t1)
    # (things twisting: never the same body twice, wider and closer as it wraps round)
    t1 = 2.0
    while t1 < seal - 0.3:
        v = t1 / seal
        x = creak_take(rng().uniform(2.0, 4.0), rng().uniform(60, 150)) * rng().uniform(0.12, 0.26) * (0.4 + 0.9 * v)
        l, r = pan(x, rng().uniform(-0.5 - 0.4 * v, 0.5 + 0.4 * v))
        P.put(L, l, t1)
        P.put(R, r, t1)
        t1 += rng().uniform(1.2, 3.0) * (1.2 - 0.6 * v)
    L, R = verb(L, R, 0.3, length=3.4, darken=(1500, 240), decay=1.5)
    # (it closes: the open air's top goes, and everything rings on in the hollow it has become)
    w = ss(close, seal, t)
    L, R = muffle(L, w * 0.85), muffle(R, w * 0.85)
    wl, wr = inside(L, R, 0.05 + 0.95 * ss(close, seal - 1.0, t), 0.6)
    k = 1 - 0.6 * w
    L, R = L * k + wl, R * k + wr
    # (the air in it)
    room = ss(close + 2.0, seal, t) * (1 - ss(seal + 0.5, end - 0.2, t))
    a, b = wide(hollow(n), hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0)), 0.5)
    L += a * room * 0.09
    R += b * room * 0.09
    L, R = low_mono(L, R, 190.0)
    out("groan", L, R, -11.5, tail=0.8, peak=10 ** (-3.0 / 20))


# ===========================================================================================================  the fold down
def foldown():
    last = REACHED - SEAL                                     # (the stages are over; the tip creeps on to 39.7, and this is gone by 39.6)
    d = DING - SEAL - 0.3
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    # (the seal itself: a vault door a long way off, heard through the ground; the first fold starts on it)
    boom = blow(n, 0.0, 66, 36, 27, 0.1, 0.01, [(0.7, 0.5), (0.3, 1.6)], drive=2.4) * 1.5
    L += boom
    R += boom
    for k, c in enumerate(CREASES):
        at = c - SEAL
        v = k / (len(CREASES) - 1)
        size = 0.52 ** k
        # (the sheet creased: a bending wave off a plate, thinner and higher as the folds halve)
        fc = 110.0 * (640.0 / 110.0) ** v
        ice(L, R, at + 0.02, 170 - 110 * v, fc, 0.42 * size ** 0.8, rng().uniform(-0.25, 0.25), 2)
        # (the crease itself: a run of paper-fine breaks)
        m = n_of(0.34)
        s = times(m)
        cr = stick(m, 240 * np.exp(-s / 0.12) + 20, 0.6, 0.15, 0.0015, 0.0005)
        cr = bp(cr, 220 + 900 * v, 1100 + 2600 * v) * np.exp(-s / (0.13 - 0.05 * v))
        y = T.unit(cr) * 0.09 * size ** 0.6
        P.put(L, y, at)
        P.put(R, y, at)
        # (the air it shoves)
        m = n_of(0.9)
        s = times(m)
        y = bn(m, 40, 260 - 100 * v) * (1 - np.exp(-s / 0.05)) * np.exp(-s / 0.2) * 0.34 * size
        P.put(L, y, at)
        P.put(R, y, at)
    # (a mechanism the size of a county, running down: slower and slower, to one last tick as the arm comes to its stop)
    tk, rate = 0.15, 13.0
    while tk < last + 0.3:
        v = tk / last
        m = n_of(0.25)
        f1 = rng().uniform(170, 215) * (1 + 0.5 * v)
        y = P.modal_hit(m, f1, [1.0, rng().uniform(1.5, 1.7), rng().uniform(2.6, 3.1), rng().uniform(4.6, 5.4)],
                        [rng().uniform(0.012, 0.03), 0.012, 0.008, 0.004], [1.0, 0.6, 0.3, 0.15], 0.25, 2500)
        y = y / (np.abs(y).max() + 1e-9) * 0.075 * (1 - 0.72 * v) * rng().uniform(0.7, 1.1)
        l, r = pan(y, rng().uniform(-0.25, 0.25))
        P.put(L, l, tk)
        P.put(R, r, tk)
        rate = max(13.0 * np.exp(-3.0 * v), 1.1)
        tk += (1 / rate) * rng().uniform(0.88, 1.12)
    # (it hangs, all of it, in the hollow)
    wl, wr = inside(L, R, 1.0, 0.5, 90.0)
    # (the pressure sinking and the air going, till there is nothing)
    f = 27.0 - 9.0 * ss(0, last, t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    drain = np.exp(-t / 0.9) * (1 - ss(last * 0.5, last + 0.1, t))
    sub = (np.sin(ph) + 0.3 * np.sin(2 * ph + 0.4)) * drain * 0.16
    a, b = wide(hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0)), hollow(n, (61.0, 103.0, 149.0, 211.0, 293.0)), 0.5)
    L, R = L + wl + a * drain * 0.06 + sub, R + wr + b * drain * 0.06 + sub
    gone = 1 - ss(last + 0.05, last + 0.6, t)               # (nothing left by 39.6)
    L, R = L * gone, R * gone
    L, R = low_mono(L, R, 170.0)
    out("foldown", L, R, -13.0, tail=0.05, peak=10 ** (-4.0 / 20))


def ding():
    """A tuning fork's kind of purity: one clean tone that barely changes, a slow beat in it, a high glint gone in a blink,
    touched rather than struck, and the hollow answering late and very far away."""
    d = 4.2
    n = n_of(d)
    t = times(n)
    f1 = 1318.5
    L, R = np.zeros(n), np.zeros(n)
    for split, share in ((-0.19, 0.62), (0.19, 0.38)):         # (its two near-equal modes: a beat every 2.6 s)
        w = np.sin(2 * np.pi * (f1 + split) * t + rng().uniform(0, 6)) * np.exp(-t / 1.5) * share
        L += w
        R += w
    # (the fork's high partial, the glint of the touch)
    for r, tau, a in ((6.27, 0.05, 0.075), (17.5, 0.012, 0.012)):
        w = np.sin(2 * np.pi * f1 * r * t + rng().uniform(0, 6)) * np.exp(-t / tau) * a
        L += w * 0.9
        R += w * 1.1
    touch = ss(0.0, 0.0035, t)                                 # (soft: a touch, no strike)
    L *= touch
    R *= touch
    m = n_of(0.003)
    tip = T.unit(bp(noise(m), 1800, 6000)) * np.sin(np.pi * np.arange(m) / m) ** 2 * 0.018
    P.put(L, tip, 0)
    P.put(R, tip, 0)
    # (the hollow, a long way off: late, dark, barely there)
    pre = n_of(0.16)
    wl, wr = inside(np.r_[np.zeros(pre), L[:-pre]], np.r_[np.zeros(pre), R[:-pre]], 1.0, 0.16)
    wl, wr = bp(wl, None, 3200), bp(wr, None, 3200)
    out("ding", L + wl, R + wr, -20.0, tail=0.6)


# ==============================================================================================================  backwards
def back_at(tau):
    """When the run back passes the fold's clock `tau`: seconds after FW_REL (fold_warp's fw_tau; it never turns round)."""
    u = np.linspace(0, 1, 4001)
    return float(np.interp((DING - tau) / (DING - 20.0), u * u * (3.11 + u * (-5.05 + u * 2.94)), u)) * (FLAT - REL)


def reverse():
    """The whole fold going back, 3.6 s of it, as slow as the picture: a very great weight starting to move, not a tape rewound.
    Every sound here goes forward, with forward attacks, and comes in the fold's order backwards: the ground stirring under the
    ding, the arm's stages undoing one by one, each bigger, the seal parting at 41.9, the walls working open with the sky's air
    coming in through them, and the far land going at the end. Its loudness is the picture's speed; nothing climbs in pitch."""
    dur = FLAT - REL
    n = n_of(dur)
    t = times(n)
    u = t / dur
    sp = (6.22 * u - 15.15 * u ** 2 + 11.76 * u ** 3) / 2.83    # (how fast the fold's clock runs back: fw_tau; 1 at the very end)
    # (how much is moving: the ground's weight taking up slowly, the speed's own run at the end)
    lv = 10 ** (np.interp(u, (0.0, 0.08, 0.25, 0.4, 0.6, 0.78, 0.9, 1.0), (-60.0, -44.0, -33.0, -27.0, -22.0, -15.5, -7.0, 0.0)) / 20)
    seal, sky = back_at(SEAL), back_at(29.0)                    # (41.94 the seal parts, 43.2 the sky is back)
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
    # (the arm's stages undoing, smallest first: each a reversed breath of the hollow into a forward knock, the same mechanism's)
    for k, tau in enumerate((39.0, 38.2, 37.5, 36.8, 36.1, 35.5)):
        at = back_at(tau)
        v = 1 - k / 5
        m = n_of(0.2)
        s = times(m)
        strength = lv[n_of(at)] ** 0.6 * 0.38
        y = bn(m, 70, 420) * np.exp((s - 0.2) / 0.06) * 0.22 * strength
        P.put(L, y, at - 0.2)
        P.put(R, y, at - 0.2)
        m = n_of(0.3)
        s = times(m)
        y = P.modal_hit(m, rng().uniform(130, 170) * (1 + 0.6 * v), [1.0, rng().uniform(1.5, 1.7), rng().uniform(2.6, 3.1), rng().uniform(4.6, 5.4)],
                        [0.03, 0.016, 0.009, 0.004], [1.0, 0.6, 0.3, 0.15], 0.2, 1800)
        y = y / (np.abs(y).max() + 1e-9) * 0.7 * strength
        y += bn(m, 36, 220 - 90 * v) * (1 - np.exp(-s / 0.02)) * np.exp(-s / 0.1) * 0.5 * strength
        l, r = pan(y, rng().uniform(-0.3, 0.3))
        P.put(L, l, at)
        P.put(R, r, at)
    # (the seal parting: the far vault again, opening, no blow to it; then the walls tearing free one at a time)
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
    dict(name="bang2", db=-13.5, fall_db=-15.0, d=2.5, span=0.05, body=(62, 53, 39), decs=[(0.94, 0.08), (0.06, 0.3)],
         modes=((36, 4, 0.8), (51, 5, 1.0), (74, 5, 1.1), (107, 5, 1.1), (158, 4, 0.9)), thick=((136, 3, 1.0), (221, 3, 1.0), (340, 3, 0.7), (560, 2, 0.35)), thick_g=1.2,
         mass=(120, 760, 0.04, 0.66), edge=(0.5, 340, 3200, 0.007), flam=((0.118, 0.86),), roll=(0.34, 5, 0.3), puff=(0.12, 0.09, 1300), stones=(4.5, 0.3, 1.7, 0.5, 4200), echoes=((0.29, 500, 0.07), (0.63, 340, 0.04)),
         wet=0.08, room=0.5, gap=0.04, side=0.3),
    dict(name="bang3", db=-12.5, fall_db=-14.5, d=2.2, span=0.022, body=(50, 42, 31), decs=[(0.88, 0.14), (0.12, 0.6)],
         modes=((31, 3, 1.0), (45, 6, 0.8), (68, 4, 1.0), (97, 6, 1.1), (146, 5, 1.1), (214, 4, 0.9)), thick=((158, 2.5, 1.0), (262, 2.5, 1.1), (420, 2, 0.8), (690, 2, 0.45)), thick_g=1.5,
         mass=(100, 760, 0.042, 0.75), edge=(0.5, 420, 4200, 0.005), flam=(), roll=(0.0, 0, 0.0), puff=(0.2, 0.08, 1600), stones=(2.5, 0.3, 1.5, 0.4, 4200), echoes=((0.44, 460, 0.06),),
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
    if b["name"] == "bang3":                                   # (a shard of it landing on its own, after it)
        y = struck(n_of(0.6), 0.0, 0.01, ((58, 4, 1.0), (84, 5, 0.9), (130, 5, 0.6)), 10) * 0.42
        y = y + rough(n_of(0.6), 0.0, 0.012, 6, 500, 3000, 0.004) * 0.09
        l, r = pan(y, 0.45)
        P.put(L, l, t0 + 0.47)
        P.put(R, r, t0 + 0.47)
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


def slam():
    d = 7.0
    n = n_of(d)
    t = times(n)
    t0 = 0.002
    u = np.maximum(t - t0, 0)
    # (a door the size of the sky: the frame's crack, the air slammed out, a chest blow that doesn't let go)
    chest = blow(n, t0, 150, 43, 29, 0.05, 0.0012, [(0.7, 0.3), (0.3, 1.5)], drive=3.6, octv=0.3, h3=0.16, harm=0.6) * 3.0
    press = bn(n, 22, 160, 3) * N.env_ar(n, t0, 0.006, 0.25, 0.25, 1.6) * 1.2
    crack = bn(n, 300, 6000) * np.exp(-u / 0.018) * (t >= t0) * 1.3 + bn(n, 120, 900) * np.exp(-u / 0.09) * (1 - np.exp(-u / 0.001)) * (t >= t0) * 1.0
    M = chest + press + crack
    L, R = M.copy(), M.copy()
    a, b = np.zeros(n), np.zeros(n)
    for k in range(5):                                         # (the land's whole sheet answering, from all round)
        ice(a, b, 0.0, 180 + 170 * k, THICK[("thick", "slab", "thick", "slab", "mid")[k]], 1.0 - 0.13 * k, (-0.7, 0.6, -0.3, 0.8, 0.1)[k], 2)
    L += a
    R += b
    # (the crater: rock going, a long roar of it falling in)
    for t1 in P.poisson_times(0.02, 1.8, lambda s: 8.0):
        x = rock_crack(1.3, rng().uniform(0.7, 1.3), 0.8) * rng().uniform(0.3, 0.7)
        l, r = pan(x, rng().uniform(-0.9, 0.9))
        P.put(L, l, t1)
        P.put(R, r, t1)
    e = N.env_ar(n, 0.08, 0.12, 0.9, 0.4, 2.2)
    a, b = wide(bn(n, 60, 1500), bn(n, 60, 1500), 0.4)
    g = np.clip(grn(d, 60.0, (0.01, 0.03, 0.07)), 0, 5) ** 0.8
    L += a * e * g * 0.5
    R += b * e * g * 0.5
    # (the thrown blocks coming back down, from about 1.5 s to 5 s)
    pl, pr = patter(d, 1.5, 5.4, lambda v: 30.0 * np.clip((v - 1.5) / 0.7, 0, 1) * np.exp(-max(v - 2.3, 0) / 1.1), 1.4)
    L += pl
    R += pr
    L, R = verb(L, R, 0.4, length=4.5, darken=(1400, 220), decay=1.8)
    # (it rolls off round the land, out and away)
    for at, dull, g_ in ((0.8, 500, 0.3), (1.7, 360, 0.2), (3.0, 260, 0.13)):
        for c, x in zip((L, R), (L.copy(), R.copy())):
            P.put(c, bp(x[:n_of(1.5)], None, dull) * g_, at)
    L, R = low_mono(L, R, 170.0)
    out("slam", L, R, -5.5, tail=0.8, peak=10 ** (-1.2 / 20))


def comedown():
    d = LEN - SLAM - 1.0
    n = n_of(d)
    t = times(n)
    roll = np.clip(1 + 0.5 * PB.slow_random(n, 0.25, 1.6), 0.1, None)
    M = (bn(n, 22, 90) * 1.2 + bn(n, 60, 190) * 0.4 * np.exp(-t / 1.6)) * np.exp(-t / 2.4) * roll
    L, R = M.copy(), M.copy()
    for t1 in (0.5, 1.4, 2.7, 4.2):                            # (the land still shifting, further and further off)
        y = T.thud(n_of(1.2), rng().uniform(2.2, 3.0)) * np.exp(-t1 / 2.5) * 2.4
        l, r = pan(y, rng().uniform(-0.6, 0.6))
        P.put(L, l, t1)
        P.put(R, r, t1)
    # (the last of the stones, to 5 s after the slam, then only one now and then: the fires have the rest of it)
    pl, pr = patter(d, 0.5, d - 2.0, lambda v: 12.0 * np.clip((v - 0.5) / 0.8, 0, 1) * np.exp(-max(v - 1.4, 0) / 1.0) + 0.15, 1.0)
    L += pl
    R += pr
    tr = np.clip(grn(d, 210.0, (0.002, 0.006)), 0, 6) ** 1.2
    a, b = wide(bn(n, 1200, 6500), bn(n, 1200, 6500), 0.2)
    L += a * tr * np.exp(-t / 2.8) * 0.018
    R += b * tr * np.exp(-t / 2.8) * 0.018
    L, R = verb(L, R, 0.45, length=3.4, darken=(1500, 240), decay=1.3)
    # (far off the sheet relaxing: a ping, a long wait, a ping, as a lake does at night)
    a, b = np.zeros(n), np.zeros(n)
    tk = 1.9
    while tk < d - 1.6:
        ice(a, b, tk, rng().uniform(380, 820), THICK[rng().choice(["skate", "mid", "thick"])], rng().uniform(0.05, 0.11) * np.exp(-tk / 7.0), rng().uniform(-0.7, 0.7), 1)
        tk += rng().uniform(0.9, 2.3)
    L += a
    R += b
    air_ = ss(0.8, 4.0, t) * (1 - ss(6.2, d - 0.2, t))
    for ch in (L, R):
        ch += hollow(n, (116.5, 174.6, 233.1, 349.2, 466.2), (0.8, 1.0, 0.7, 0.4, 0.22), 0.04) * air_ * 0.04
        ch += bn(n, 2200, 6500) * air_ * np.clip(1 + 0.5 * PB.slow_random(n, 0.2, 1.4), 0.1, None) * 0.0032
    L, R = low_mono(L, R, 170.0)
    out("comedown", L, R, -18.0, tail=2.0)


BUILD = {"descent": descent, "wobble": wobble, "air": air, "meld": meld, "ripple": ripple, "score": score, "unravel": unravel,
         "groan": groan, "foldown": foldown, "ding": ding, "reverse": reverse, "bang1": bang1, "bang2": bang2,
         "bang3": bang3, "bang4": bang4, "fall": fall, "slam": slam, "comedown": comedown, "letgo": letgo}
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=list(BUILD))
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write MP3s, the whole strike's mix and the level checks here")
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


if __name__ == "__main__":
    main()
