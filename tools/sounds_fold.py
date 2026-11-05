"""The Fold's sounds (laser 15), all synthesised here from noise, impulses and physical models; nothing sampled. Every stem
is one take of many small irregular events, not a one-shot replayed: the only thing heard twice is nothing.

The heart of it is the ice: `flex` puts a hit through the real dispersion of a bending wave in a floating sheet (the
skipping stone on a frozen pond): the highs arrive first, the pitch falls as d / sqrt(f), it lands on the held tone where
the wave's phase speed meets the speed of sound in air (`fc`: ~725 Hz on 4 cm ice, ~195 Hz on 16 cm), and the dull knock
of the hit itself comes last through the air, d / 340 s late. Distance is the chirp's length. The land's sound in the
last act is the same physics at a thicker sheet, down to a springy low `pew` under each bounce.

As strike/fold.rs plays them (strike seconds; `EVENTS` below has volumes):

  descent   0 s, exactly 3.4 s: a tearing roar from very high, ending at full force on its last sample, no tail.
  wobble    3.49 s: the droplet's wobble heard close, tiny and wet: small bubbles and a heavy skin, 3.5 Hz, dying by 4.4.
  air       ~3.9 s (late by the distance, 0.5 s at 170 blocks): the air that kept going: a soft whump, a rush going past
            and off, then dust hissing over the ground, thinning to nothing by ~6.9 s.
  meld      6 s: a weighty soft contact, a closed hum, heavy liquid slumping in to about 7.5.
  ripple    7.5 s: the land moving like water: low heaves, each bigger, slow water and wet soil over them.
  score     12 s: the creases: ice. Lone cracks, stones skipping away, cracks racing, ever thicker, and from 16 s the tears.
  unravel   19 s: long falling glissandi off a thick sheet, tearing, ring after ring letting go.
  groan     19 s: the land bending, a hull's and a tree's stress, closing overhead from 26 s: the sky's air goes, the sound turns
            inward to a huge dark space.
  foldown   35 s: the seal, a far vault shutting, and the fold coming down: creases getting smaller and further apart, a vast mechanism's ticks running slower
            and slower, the air draining till there is nothing.
  ding      40 s: the touch: a small glass note in the silence.
  reverse   40.3 s, exactly 0.8 s: it all rushes backwards: a vast inhale, the fold's own sound played back, ticks racing,
            cut on the first bounce.
  bounce1-4 41.1, 42, 42.8, 43.7 s: a thud through the land, a springy low chirp under it, each smaller.
  fall      43.85 s: the last fall: the air under the land going, rising, and 90 ms of nothing before the slam.
  slam      45 s: the last bounce comes down: a door the size of the sky, the crater going in, a rumble rolling off.
  comedown  46 s: debris, the land settling, far ice pinging as it relaxes, cold air, quiet.

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
STOP, TOUCH, RIPPLE, SCORE, TEAR, FOLD, CLOSING, SEAL, DING, REL, FLAT, SLAM = 3.4, 6.0, 7.5, 12.0, 16.0, 19.0, 26.0, 35.0, 40.0, 40.3, 41.1, 45.0
# when the land lets go in great heaves; the fold's stages (FD_FOLDS); the bounces (time, how big), then the last fall
RINGS = [19.1, 21.0, 23.3, 25.1, 27.6, 29.9]
CREASES = [35.0, 35.6, 36.3, 37.1, 38.0, 39.0]
BOUNCES = [(41.1, 1.0), (42.0, 0.6), (42.8, 0.36), (43.7, 0.2)]
PULSES = [7.5, 8.6, 9.6, 10.6, 11.5]  # the water's pulses of the middle, from when the droplet is absorbed
SWELLS = [11.25, 12.25, 13.2, 14.2]   # the swell under a player at 170 blocks, a crest about 0.55 s after each; biggest ~12.8
FALL = 1.15                           # the last fall's air, ending just before the slam
AIR_LATE = 0.5                        # the air's sound after the stop, at 170 blocks (the plan uses the real distance)

# (time, file, volume, pitch), as fold_plan plays them
EVENTS = [(0.0, "descent", 1.0, 1.0), (STOP + 0.09, "wobble", 1.0, 1.0), (STOP + AIR_LATE, "air", 1.0, 1.0),
          (TOUCH, "meld", 1.0, 1.0), (RIPPLE, "ripple", 1.0, 1.0), (SCORE, "score", 1.0, 1.0),
          (FOLD, "unravel", 1.0, 1.0), (FOLD, "groan", 1.0, 1.0), (SEAL, "foldown", 1.0, 1.0),
          (DING, "ding", 1.0, 1.0), (REL, "reverse", 1.0, 1.0),
          *[(t, f"bounce{k + 1}", 1.0, 1.0) for k, (t, _) in enumerate(BOUNCES)],
          (SLAM - FALL, "fall", 1.0, 1.0), (SLAM, "slam", 1.0, 1.0), (SLAM + 1.0, "comedown", 1.0, 1.0)]
SECTIONS = [("descent", 0.0, 3.4), ("hush", 3.4, 3.9), ("air", 3.9, 6.0), ("meld", 6.0, 7.5), ("ripple", 7.5, 12.0), ("score", 12.0, 16.0),
            ("tear", 16.0, 19.0), ("unravel", 19.0, 26.0), ("close", 26.0, 35.0), ("foldown", 35.0, 39.3), ("hush2", 39.65, 40.0),
            ("ding", 40.0, 40.3), ("reverse", 40.3, 41.1), ("bounces", 41.1, 43.8), ("fall", 43.85, 45.0), ("slam", 45.0, 48.0), ("comedown", 48.0, 56.0)]


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


def out(name, L, R, db, tail=0.3, length=None, peak=PEAK):
    """Stereo out: the sum's loudest 400 ms at `db` dB, the peaks rounded off into `peak` (so a sound keeps its level, the
    loudest instants paying for it, not all of it) and held there decoded by the limiter. `tail` s of fade at the end,
    none (a hard end, on the very last sample) if 0; `length` cuts it first, to the sample."""
    n = length if length else min(len(L), len(R))
    x = np.stack([L[:n], R[:n]], axis=1)
    x = x * 10 ** (db / 20) / T.loudest(x.mean(axis=1))
    for _ in range(4):                                       # (rounding takes a little off: put back)
        y = rounded(x, peak * 0.97)
        x = x * 10 ** (db / 20) / T.loudest(y.mean(axis=1))
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
    db = -32.0 * (1 - u) ** 1.25                     # (held at the top past the cut: nothing eases before it)
    lv = 10 ** (db / 20)

    def roar(t, f):
        v = min(t / STOP, 1.0)
        fc = 320.0 * (3400.0 / 320.0) ** (v ** 1.3)
        fa = 2600.0 * (16000.0 / 2600.0) ** (v ** 1.6)
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
    fib = stick(n, 150.0 + 2600.0 * u ** 2, 0.6, 0.1, 0.002, 0.0007)
    fib = (T.unit(bp(fib, 500, 2500)) + 0.7 * T.unit(bp(fib, 2500, 9000))) * lv * (0.1 + 0.42 * near)
    L += fib
    R += fib * 0.8 + 0.2 * bn(n, 900, 7000) * lv * (0.1 + 0.42 * near)

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
            ch += T.unit(bp(fftconvolve(tk, ker)[:n], lo, hi)) * lv * amp * 0.28

    # (the pressure rising under it)
    f = (24.0 + 36.0 * u ** 1.4) * (1 + 0.04 * np.clip(PB.slow_random(n, 2.0, 12.0), -2, 2))
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


def scatter(f):
    """The sheet isn't even: a gain that wanders across the band, different each time, so a chirp comes in patches."""
    lf = np.log2(np.maximum(f, 20.0))
    nodes = rng().normal(0, 1, 40)
    return 10 ** (np.interp(lf, np.linspace(4, 14.5, 40), nodes) * 4.5 / 20)


def flex(exc, d, fc, q=90.0):
    """`exc` (a hit, at time 0) heard `d` m along the sheet: the dispersion's phase put on it in the frequency domain.
    Under `fc` nothing radiates; the highs die with distance (`q`). Time 0 of the result is the hit."""
    late = d / (2 * AIR * 0.72) + 0.1
    size = next_fast_len(len(exc) + n_of(late) + 2048)
    f = rfftfreq(size, 1 / SR)
    k, cg = plate(f, fc)
    keep = 1.0 / (1.0 + (0.86 * fc / np.maximum(f, 1.0)) ** 10) * np.exp(-np.pi * f * d / (q * cg)) * scatter(f)
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


def skip(L, R, t, d0, d1, count, fc, amp, side):
    """A stone skipping away: each skip further off, nearer in time, quieter, ending in a slide of small ones."""
    gap = rng().uniform(0.26, 0.36)
    d = d0
    grow = (d1 / d0) ** (1 / max(count - 1, 1))
    for k in range(count):
        ice(L, R, t, d, fc, amp * 0.86 ** k, side * (0.12 + 0.75 * k / count), 0 if k else 1)
        t += gap
        gap *= rng().uniform(0.68, 0.8)
        d *= grow
    for k in range(int(rng().integers(5, 14))):
        ice(L, R, t + k * rng().uniform(0.015, 0.03), d * (1 + 0.02 * k), fc, amp * 0.3 * 0.9 ** k, side * 0.85, 0)


def race(L, R, t, d0, d1, dur, count, fc, amp, side):
    """A crack running away: a tip giving in many little jumps as it goes, uneven."""
    for s in np.sort(rng().uniform(0, 1, count)) ** 0.8:
        a = amp * (1 - 0.65 * s) * min(rng().pareto(2.4) * 0.4 + 0.35, 2.0)
        ice(L, R, t + s * dur, d0 + (d1 - d0) * s, fc, a, side * (0.08 + 0.85 * s), 0 if rng().random() < 0.7 else 1)


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


def rip(n, at, dur, power=1.0):
    """The land tearing: fibres snapping in uneven surges, cloth and earth. (L, R), dry, starting at `at` s."""
    m = n_of(dur)
    t = times(m)
    v = ss(0.0, 0.22, t) * (1 - ss(dur * 0.72, dur, t)) * np.clip(0.72 + 0.36 * PB.slow_random(m, 0.8, 5.0), 0.1, 1.5)
    fib = stick(m, 40 + 420 * v, 0.5, 0.1, 0.004, 0.0012)
    canvas = (T.unit(bp(fib, 150, 520)) + 0.7 * T.unit(bp(fib, 520, 1900)) + 0.3 * T.unit(bp(fib, 1900, 6500))) * v
    canvas = canvas * np.clip(grn(dur, 26.0, (0.02, 0.05)), 0, 4) ** 0.8
    chop = np.clip(grn(dur, 80.0, (0.004, 0.012, 0.03)), 0, 6) ** 1.1
    cloth = (bn(m, 170, 1300) + 0.3 * bn(m, 1300, 4200)) * chop * v
    earth = bn(m, 26, 150) * v ** 1.1 * np.clip(1 + 0.6 * PB.slow_random(m, 2.5, 11.0), 0.05, None) * 1.3
    grind = T.unit(bp(stick(m, 22 + 40 * v, 0.5, 0.2, 0.01, 0.003), 50, 420)) * v * 0.7
    a, b = wide(canvas * 0.75 + cloth * 0.5, T.unit(bp(noise(m), 170, 1800)) * v * 0.8 * chop, 0.55)
    L, R = np.zeros(n), np.zeros(n)
    P.put(L, (earth + grind + a) * power, at)
    P.put(R, (earth + grind + b) * power, at)
    return L, R


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
    d = 1.5
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    f = 3.5
    # (its heavy skin: a small dark cavity opening and closing as it wobbles)
    env = np.exp(-5.0 * t) * np.minimum(t / 0.012, 1)
    form = 250.0 + 210.0 * (0.5 + 0.5 * np.cos(2 * np.pi * f * t)) * np.exp(-1.6 * t)
    skin = P.glide_band(d, form, 0.5) * env * (0.55 + 0.45 * np.abs(np.cos(2 * np.pi * f * t)))
    L += skin * 0.2
    R += skin * 0.2
    # (each half swing lands: a few small wet bubbles, a fat low one under them)
    for k in range(9):
        at = 0.02 + k / (2 * f) + rng().uniform(-0.008, 0.012)
        a = np.exp(-5.0 * at)
        y = bubble(rng().uniform(120, 175), a * 1.1, rng().uniform(0.2, 0.45), 0.05)
        l, r = pan(y, rng().uniform(-0.1, 0.1))
        P.put(L, l, at)
        P.put(R, r, at)
        for j in range(int(rng().integers(2, 6))):
            y = bubble(float(np.exp(rng().uniform(np.log(420), np.log(1500)))), a * rng().uniform(0.15, 0.45), rng().uniform(0.15, 0.5), 0.04)
            l, r = pan(y, rng().uniform(-0.3, 0.3))
            P.put(L, l, at + rng().uniform(0, 0.05))
            P.put(R, r, at + rng().uniform(0, 0.05))
    L, R = low_mono(L, R, 200.0)
    out("wobble", L, R, -29.0, tail=0.3)


def air():
    d = 3.2
    n = n_of(d)
    t = times(n)
    # (it hits the land: a soft heavy push, no crack)
    whump = (bn(n, 26, 130) * 1.4 + bn(n, 130, 420) * 0.3) * (1 - np.exp(-t / 0.07)) * np.exp(-t / 0.32)

    def rush(s, f):
        fc = 280.0 + 1500.0 * np.exp(-s / 0.5)                 # (going by, and off: its top falling away)
        body = np.minimum((f / fc) ** 1.1, (fc / f) ** 0.9)
        return body * np.exp(-(f / (2000.0 + 7000.0 * np.exp(-s / 0.7))) ** 1.5)

    e = ss(0.04, 0.38, t) * np.exp(-t / 0.8) * np.clip(1 + 0.4 * PB.slow_random(n, 2.0, 14.0), 0.2, None)
    a, b = wide(morph(n, rush), morph(n, rush), 0.45)
    p = -0.75 + 1.5 * ss(0.05, 1.3, t)                         # (past you, across)
    L = a * e * 0.8 * np.cos((p + 1) * np.pi / 4) * 1.41 + whump
    R = b * e * 0.8 * np.sin((p + 1) * np.pi / 4) * 1.41 + whump
    # (dust: sand over a surface, a fine uneven hiss spreading, then thinning)
    gr = np.clip(grn(d, 900.0, (0.0015, 0.004, 0.012)), 0, 6) ** 1.25
    dust = ss(0.08, 0.5, t) * np.exp(-np.maximum(t - 0.5, 0) / 0.8) * np.clip(1 + 0.5 * PB.slow_random(n, 0.8, 5.0), 0.1, None)
    a, b = wide(bn(n, 2400, 10500), bn(n, 2400, 10500), 0.15)
    c, e2 = wide(bn(n, 600, 2400), bn(n, 600, 2400), 0.15)
    L += (a * 0.2 + c * 0.1) * gr * dust
    R += (b * 0.2 + e2 * 0.1) * gr * dust
    L, R = verb(L, R, 0.25, length=2.0, darken=(1800, 260), decay=0.8)
    L, R = low_mono(L, R, 170.0)
    out("air", L, R, -27.0, tail=0.5)


def meld():
    d = 2.4
    n = n_of(d)
    t = times(n)
    t0 = 0.03
    u = np.maximum(t - t0, 0)
    f = 40.0 + 22.0 * np.exp(-u / 0.05)
    ph = 2 * np.pi * np.cumsum(f * (t >= t0)) / SR
    hum = (np.sin(ph) + 0.4 * np.sin(2 * ph + 0.8) + 0.16 * np.sin(3 * ph + 1.9)) * (1 - np.exp(-u / 0.02)) * np.exp(-u / 0.6) * (t >= t0)
    press = bn(n, 70, 340) * np.exp(-u / 0.09) * (1 - np.exp(-u / 0.006)) * (t >= t0) * 1.5     # (weight, braking over 0.25 s: nothing sharp)
    L = hum + press
    R = L.copy()
    # (it slumps in like two lava-lamp blobs joining, to about 7.5: fat slow bubbles, a few small)
    for at, f0, a in ((0.28, 92, 0.42), (0.62, 74, 0.5), (0.95, 118, 0.3), (1.25, 66, 0.42), (1.5, 58, 0.36)):
        y = bubble(f0, a, rng().uniform(-0.2, -0.05), 0.03)                        # (sinking: the pitch falls, not rises)
        l, r = pan(y, rng().uniform(-0.25, 0.25))
        P.put(L, l, at)
        P.put(R, r, at)
    bubbles(L, R, 0.3, 1.7, lambda s: 8.0 * np.exp(-s / 0.9), 200, 620, 0.05, 0.45)
    L, R = low_mono(*verb(L, R, 0.18, length=1.6, darken=(900, 200), decay=0.7), 170.0)
    out("meld", L, R, -22.0, tail=0.3)


def ripple():
    d = 7.9
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    # (the five pulses, each stronger, then the swell itself passing under the player, dying under the scoring)
    for t_, f, dur, amp in zip((*PULSES, *SWELLS), (46.0, 42.0, 38.0, 34.0, 30.0, 31.0, 29.0, 31.0, 33.0), (0.9, 1.0, 1.0, 1.0, 1.1, 1.6, 1.7, 1.5, 1.3),
                               (0.14, 0.3, 0.46, 0.66, 0.6, 0.6, 1.0, 0.66, 0.3)):
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
        g = np.clip(grn(dur, 34.0, (0.02, 0.06)), 0, 5)
        P.put(L, a * g * e ** 1.5 * amp * 0.07, at + 0.1)
        P.put(R, b * g * e ** 1.5 * amp * 0.07, at + 0.1)
        bubbles(L, R, at + 0.25 * dur, at + dur, lambda _: 7.0 + 26.0 * amp, 55, 300, 0.11 * amp, 0.8)
    L, R = low_mono(L, R, 170.0)
    L, R = verb(L, R, 0.2, length=2.6, darken=(900, 200), decay=1.0)
    # (the first hairline, right at the end, a hint)
    a, b = np.zeros(n), np.zeros(n)
    ice(a, b, 3.7, 300, THICK["thin"], 0.03, -0.5, 0)
    ice(a, b, 4.25, 220, THICK["thin"], 0.05, 0.4, 0)
    out("ripple", L + a, R + b, -20.0, tail=0.2)


# ============================================================================================================  the creases
def score():
    dur = FOLD - SCORE
    d = dur + 1.5
    n = n_of(d)
    L, R = np.zeros(n), np.zeros(n)
    # (the first crease: one clean pew; a beat; a stone skipping off; then more and more, thicker)
    ice(L, R, 0.0, 90, THICK["skate"], 1.0, -0.15, 1)
    skip(L, R, 0.85, 45, 320, 6, THICK["skate"], 0.8, 1.0)
    t = 2.1
    while t < dur - 0.15:
        v = t / dur
        fc = THICK[rng().choice(["thin", "skate", "skate", "mid"] if v < 0.5 else ["skate", "mid", "mid", "thick"])]
        side = rng().choice([-1.0, 1.0])
        kind = rng().random()
        big = (0.5 + 0.6 * v) * rng().uniform(0.7, 1.15)
        if kind < 0.3:
            skip(L, R, t, rng().uniform(35, 90), rng().uniform(220, 520), int(rng().integers(4, 8)), fc, big * 0.75, side)
        elif kind < 0.72:
            d0 = rng().uniform(30, 120)
            race(L, R, t, d0, d0 + rng().uniform(120, 340), rng().uniform(0.2, 0.55), int(rng().integers(12, 34)), fc, big * 0.5, side)
        else:
            ice(L, R, t, rng().uniform(70, 460), fc, big, side * rng().uniform(0.1, 0.8))
        t += rng().uniform(0.35, 1.1) * (1.25 - 0.85 * v)
    # (crazing: the thin top skin fizzing with tiny cracks close by, as the score sets in)
    for t1 in P.poisson_times(1.0, dur, lambda s: 3.0 + 40.0 * (s / dur) ** 2):
        ice(L, R, t1, rng().uniform(14, 44), THICK["thin"], rng().uniform(0.02, 0.08), rng().uniform(-0.9, 0.9), 0)
    # (the tears open: from 16 s, ripping through the sheet, each dropping a heavy crack)
    for at, ln, po in ((TEAR - SCORE, 2.2, 0.15), (TEAR - SCORE + 1.5, 1.7, 0.2)):
        a, b = rip(n, at, ln, po)
        L += a
        R += b
        ice(L, R, at, 110, THICK["thick"], 1.3, rng().uniform(-0.3, 0.3), 2)
    L, R = verb(L, R, 0.05, length=2.4, darken=(2600, 300), decay=0.9)
    L, R = PB.causal_lowcut(L, 45.0), PB.causal_lowcut(R, 45.0)
    L, R = low_mono(L, R, 170.0)
    out("score", L, R, -11.0, tail=0.4, peak=10 ** (-2.5 / 20))


def unravel():
    dur = SEAL - FOLD
    d = dur + 1.0
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    # (each heave: the great falling glissandi, the thick sheet giving, a sound a kilometre long; then it eases)
    for k, r in enumerate(RINGS):
        at = r - FOLD
        side = -1.0 if k % 2 else 1.0
        ice(L, R, at, 300 + 70 * k, THICK["thick"], 1.2, side * 0.35, 2)
        ice(L, R, at + 0.2, 640, THICK["slab"], 1.0, -side * 0.5, 2)
        race(L, R, at + 0.1, 90, 520, 1.0, 26, THICK["mid"], 0.5, side)
        a, b = rip(n, at + 0.05, rng().uniform(0.8, 1.5), 0.1 + 0.02 * k)
        L += a
        R += b
    # (between them the sheet ticking and singing, a long way off)
    for t1 in P.poisson_times(0.3, dur - 2.0, lambda s: 0.9 + 1.2 * s / dur):
        fc = THICK[rng().choice(["skate", "mid", "thick", "thick", "slab"])]
        ice(L, R, t1, rng().uniform(160, 860), fc, rng().uniform(0.15, 0.55), rng().uniform(-0.9, 0.9))
    for t1 in P.poisson_times(0.3, dur - 2.0, lambda s: 0.5):
        race(L, R, t1, rng().uniform(60, 200), rng().uniform(260, 640), rng().uniform(0.3, 0.9), int(rng().integers(8, 22)), THICK["skate"], 0.22, rng().choice([-1.0, 1.0]))
    L, R = verb(L, R, 0.08, length=3.0, darken=(2200, 280), decay=1.2)
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
    last = CREASES[-1] - SEAL
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
    # (a mechanism the size of a county, running down: slower and slower, to one last tick after the last fold)
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
    """Glass touched once: one clear mode and its doublet, three fainter, a tiny tick, the hollow barely answering."""
    d = 3.2
    n = n_of(d)
    t = times(n)
    L, R = np.zeros(n), np.zeros(n)
    f1 = 1437.0
    #          ratio  tau   amp    split (Hz)
    modes = ((1.0, 0.95, 1.0, 0.7), (2.32, 0.42, 0.17, 1.3), (4.25, 0.16, 0.06, 1.1), (6.63, 0.06, 0.02, 2.4))
    for r, tau, amp, split in modes:
        for sign, share in ((-0.5, 0.6), (0.5, 0.4)):
            f = (f1 * r + sign * split) * (1 + 0.0009 * np.exp(-t / 0.03))     # (a hair sharp as it's struck)
            w = np.sin(2 * np.pi * np.cumsum(f) / SR + rng().uniform(0, 6)) * np.exp(-t / tau) * amp * share
            lean = rng().uniform(-0.12, 0.12)
            L += w * (1 - lean)
            R += w * (1 + lean)
    touch = np.minimum(t / 0.0009, 1) ** 2
    L *= touch
    R *= touch
    m = n_of(0.004)
    tip = T.unit(bp(noise(m), 2200, 9000)) * np.sin(np.pi * np.arange(m) / m) ** 2 * 0.1
    P.put(L, tip, 0)
    P.put(R, tip, 0)
    # (its small body, a dull little knock of glass)
    m = n_of(0.05)
    y = np.sin(2 * np.pi * 410 * times(m)) * np.exp(-times(m) / 0.008) * 0.05
    P.put(L, y, 0)
    P.put(R, y, 0)
    wl, wr = inside(L, R, 1.0, 0.09)
    out("ding", L + wl, R + wr, -19.0, tail=0.5)


# ==============================================================================================================  backwards
def reverse():
    dur = FLAT - REL
    pad = 0.4
    n = n_of(dur + pad)
    t = times(n)
    u = np.clip(t / dur, 0, 1)
    lv = 10 ** (-42.0 * (1 - u) ** 1.5 / 20)                 # (out of nothing, the ding still ringing into it)
    near = u ** 2

    def inhale(s, f):
        v = min(s / dur, 1.0)
        fc = 220.0 * (1800.0 / 220.0) ** (v ** 1.2)
        return np.exp(-0.5 * (np.log2(f / fc) / 0.95) ** 2) + 0.45 * np.exp(-0.5 * (np.log2(f / (fc * 2.7)) / 0.6) ** 2)

    a, b = wide(morph(n, inhale), morph(n, inhale), 0.3 + 0.55 * u)
    gust = np.clip(1 + 0.35 * PB.slow_random(n, 6.0, 30.0), 0.2, None)
    L = a * gust * lv
    R = b * gust * lv
    # (the fold's own sound played back, fast, its tails coming first)
    try:
        src = np.concatenate([decoded("groan")[n_of(SEAL - FOLD - 3.0):n_of(SEAL - FOLD)], decoded("foldown")])[::-1]
        src = src[n_of(0.9):]                                 # (the fold's silence skipped)
        for k in range(2):
            y = np.interp(np.arange(n) * 7.0, np.arange(len(src)), src[:, k], right=0.0)
            (L if k == 0 else R)[:] += y * lv * 4.0
    except Exception as e:
        print("  (reverse: build foldown and groan first:", e, ")")
    # (the ticks back, forward attacks at a rising rate: a plain reversal has no edges)
    tk = 0.16
    while tk < dur:
        v = tk / dur
        m = n_of(0.05)
        y = P.modal_hit(m, rng().uniform(320, 760), [1.0, 1.6, 2.8, 4.9], [0.01, 0.008, 0.005, 0.003], [1.0, 0.6, 0.3, 0.15], 0.7, 6000)
        y = y / (np.abs(y).max() + 1e-9) * (0.04 + 0.5 * v ** 2)
        l, r = pan(y, rng().uniform(-0.5, 0.5))
        P.put(L, l, tk)
        P.put(R, r, tk)
        tk += 0.12 * (1 - v) ** 1.5 + 0.008
    f = 22.0 + 46.0 * u ** 2
    ph = 2 * np.pi * np.cumsum(f) / SR
    sub = (np.sin(ph) + 0.4 * np.sin(2 * ph + 1)) * lv * 1.2
    L += sub
    R += sub
    L, R = low_mono(L, R, 200.0)
    g = 1.0 / np.abs(np.stack([L, R])[:, n_of(dur - 0.15):n_of(dur)]).max()
    L, R = (np.tanh(c * g * 1.3) / np.tanh(1.3) for c in (L, R))
    out("reverse", L, R, -9.0, tail=0, length=n_of(dur), peak=10 ** (-2.0 / 20))


def bounce_take(name, size, room):
    d = 1.9 + 1.5 * size
    n = n_of(d)
    t = times(n)
    t0 = 0.003
    u = np.maximum(t - t0, 0)
    chest = blow(n, t0, 100 + 30 * size, 46, 33, 0.04, 0.0016, [(0.9, 0.085 + 0.06 * size), (0.1, 0.25)], drive=3.2, octv=0.26, h3=0.13, harm=0.5) * 1.8
    ground = bn(n, 180, 2600) * np.exp(-u / (0.012 + 0.008 * size)) * (t >= t0) * 0.6 + bn(n, 80, 380) * np.exp(-u / 0.05) * (1 - np.exp(-u / 0.002)) * (t >= t0) * 0.8
    tail = bn(n, 24, 110) * N.env_ar(n, t0 + 0.02, 0.05, 0.14, 0.2, 0.4) * np.clip(1 + 0.5 * PB.slow_random(n, 2.0, 9.0), 0.1, None) * 0.3
    M = chest + ground + tail
    L, R = M.copy(), M.copy()
    # (the spring in it: the blow running out through the land as a low bending wave, the slowest thing there is)
    a, b = np.zeros(n), np.zeros(n)
    ice(a, b, 0.0, 300 - 60 * size, THICK["slab"], 0.4 * size ** 0.5, -0.3, 2)
    ice(a, b, 0.02, 420 + 80 * size, THICK["thick"], 0.26 * size ** 0.5, 0.35, 2)
    L += a
    R += b
    pl, pr = patter(d, 0.2, d - 0.3, lambda v: 12.0 * size * np.clip(v / 0.4, 0, 1) * np.exp(-max(v - 0.5, 0) / 0.5), 0.8)
    L += pl
    R += pr
    wl, wr = verb(L, R, 0.12, length=2.0, darken=(1500, 230), decay=0.5)
    hl, hr = inside(L, R, 1.0, 0.3 * room, 150.0)
    L, R = low_mono(wl + hl, wr + hr, 170.0)
    out(name, L, R, -9.5 - 20.0 * (1 - size) ** 1.5, tail=0.4, peak=10 ** (-3.0 / 20))


def bounce1():
    bounce_take("bounce1", BOUNCES[0][1], 1.0)


def bounce2():
    bounce_take("bounce2", BOUNCES[1][1], 0.66)


def bounce3():
    bounce_take("bounce3", BOUNCES[2][1], 0.34)


def bounce4():
    bounce_take("bounce4", BOUNCES[3][1], 0.1)


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
    pl, pr = patter(d, 0.3, d - 0.4, lambda v: 38.0 * np.clip(v / 0.5, 0, 1) * np.exp(-max(v - 0.6, 0) / 1.4), 1.4)
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
    d = 10.5
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
    pl, pr = patter(d, 0.05, d - 2.0, lambda v: 22.0 * np.exp(-v / 2.3) + 0.8, 1.0)
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
    air_ = ss(0.8, 4.0, t) * (1 - ss(6.2, 10.3, t))
    for ch in (L, R):
        ch += hollow(n, (116.5, 174.6, 233.1, 349.2, 466.2), (0.8, 1.0, 0.7, 0.4, 0.22), 0.04) * air_ * 0.04
        ch += bn(n, 2200, 6500) * air_ * np.clip(1 + 0.5 * PB.slow_random(n, 0.2, 1.4), 0.1, None) * 0.0032
    L, R = low_mono(L, R, 170.0)
    out("comedown", L, R, -18.0, tail=2.0)


# (order matters only for `reverse`, which plays the fold's own sound backwards)
BUILD = {"descent": descent, "wobble": wobble, "air": air, "meld": meld, "ripple": ripple, "score": score, "unravel": unravel,
         "groan": groan, "foldown": foldown, "ding": ding, "reverse": reverse, "bounce1": bounce1, "bounce2": bounce2,
         "bounce3": bounce3, "bounce4": bounce4, "fall": fall, "slam": slam, "comedown": comedown}
GONE = ("stop", "tear", "creak", "crush", "bloom", "thud", "drone")
SEEDS = {name: 171000 + 7 * k for k, name in enumerate(BUILD)}


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
    end = max(max(at + len(clips[f]) / SR / p for at, f, _, p in EVENTS) + 0.5, 56.0)
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
    for a, b, what in ((STOP, STOP + 0.05, "after the stop"), (39.7, DING, "before the ding")):
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
