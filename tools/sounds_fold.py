"""The Fold's sounds (laser 15), all synthesised here from noise, pulses, resonators and swept tones; nothing sampled.
As strike/fold.rs plays them (strike seconds; `volume` and `pitch` are in `EVENTS` below):

  descent   0 s, exactly 3.4 s: a tearing roar coming down from very high, rising in pitch and pressure like a re-entry:
            a moving band of roar with its ridges climbing, wind-shear chopped into it, plasma crackle thickening, the top
            opening up as it nears, a sub push rising under it. It ends at full force: the file stops on its loudest
            samples with no fade, no tail and no reverb. The droplet stops dead.
  stop      3.4 s, ~1.8 s: 0.3 s of digital silence, then a tiny high clean ring (a wet fingertip on a thin glass-steel
            bell): a shell's few modes, each a slowly beating pair, a soft touch, quiet and sparse; 1.5 s of ring.
  meld      6.0 s, ~2.2 s: a soft low touch: a very quiet deep sub "tmm" (a dull little contact, then a closed hum on ~40 Hz)
            and a faint viscous slide of liquid metal (slow falling tones, a few small sliding beads). No splash.
  ripple    6.6 s, ~6.4 s: four barely-there sub pulses (50, 43, 36.5, 31 Hz), each lower and longer than the last and
            wider (a breath of low noise over each, the two sides less alike each time). The land starting to breathe.
  score     12 s, ~4.2 s: thin dry hairline cracking racing away from you: runs of dispersive ticks (ice under stress: the
            highs arrive first) going from the middle out to either side and further off, darker as they go, a fingernail's
            fine drag along a taut skin under them, the runs coming faster and faster. Dry.
  tear      16 s, ~4.4 s: a huge slow rip: fibres snapping in uneven surges, canvas and earth tearing, rock cracking,
            spreading out to the sides, wide and deep, ending in cold hollow air (a noise-blown cavity's resonances).
  groan     19 s, exactly 16 s: the land bending under load, like a ship's hull or an iceberg: slow irregular tonal moans,
            stick-slip pulsing through a huge hull's modes, deep knocks, a sub bed heaving, all building. The last 0.8 s is
            pulled in (the whole sound's pitch rushing up), then the file is cut (the crush takes over at 35).
  creak     19, 21.1, 23.2, 25.3, 27.4 s at pitch 1, .86, .94, .78, .7, ~4.4 s: one huge timber-and-rock creak (slow grabs
            through a hull's timbers, quickening to a chatter and easing, rock grinding under it), then a low settling boom
            at 3 s. Its body is built so that it works from pitch .7 (5.9 s long) to 1.
  crush     35 s, exactly 2.5 s: everything sucked in: rush rising and narrowing, the bloom's chord climbing out of the sub,
            stick-slip quickening to a buzz, the pressure rising, the sides closing to one point. It stops dead on its
            loudest samples: silence at 37.5.
  (37.5 to 38.7: true silence, no file plays)
  bloom     38.7 s, ~9 s: one colossal open bloom: an instant low detonation (no crack) that unfolds into wide ringing air:
            bell-like inharmonic modes on E2 struck by it, the same modes sung by the air as they open upward, a long
            reverb, a choir-like swell under it. It sinks quickly enough for the thuds to land on it.
  thud      39.8, 40.6, 41.4, 42.2, 43.1 s at pitch 1.1 down to .75, ~4 s: a continent landing: a ground transient, a very low
            chest thump, a rumble tail and debris pattering down. Its peak is kept low: five land 0.8 s apart.
  comedown  44.1 s, ~11.5 s: settling: a distant low rumble dying, grit falling, a faint cold air tone, then quiet.

The game mixes every file to mono as it decodes it (audio.rs's `decode`), so all of these are built to sum well: their lows
are mono, nothing on the two sides is out of phase, and the levels here are measured on the sum.

    python3 tools/sounds_fold.py                  # writes orbital-sounds/assets/orbital/sounds/fold/*.ogg and the fold.* events
    python3 tools/sounds_fold.py --only thud      # one (or several)
    python3 tools/sounds_fold.py --listen DIR     # also a WAV of each, the whole strike's mix (fold_full.wav/.mp3, its
                                                  # spectrogram) and the levels, section by section; the hard cuts checked
"""
import argparse, json, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, sosfilt
import soundlib
from soundlib import SR, make_ir
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P
import sounds_nuke as N

TH = "fold"
ROOT = Path(__file__).resolve().parent.parent
PEAK = 10 ** (-1.2 / 20)              # every file's decoded peak at most
DESCENT = 3.4
CRUSH = 2.5
GROAN = 16.0
E2 = 82.4
BLOOM_MODES = (1, 2.0, 2.76, 3.0, 4.07, 5.4, 6.7, 8.1, 10.4)

# (time, file, volume, pitch), as fold_plan plays them
EVENTS = [(0.0, "descent", 1.0, 1.0), (3.4, "stop", 0.6, 1.0), (6.0, "meld", 0.8, 1.0), (6.6, "ripple", 0.7, 1.0),
          (12.0, "score", 0.8, 1.0), (16.0, "tear", 1.0, 1.0), (19.0, "groan", 1.0, 1.0),
          *[(19.0 + 2.1 * k, "creak", 1.0, p) for k, p in enumerate((1.0, 0.86, 0.94, 0.78, 0.7))],
          (35.0, "crush", 1.0, 1.0), (38.7, "bloom", 1.0, 1.0),
          *[(t, "thud", 1.0, 1.1 - 0.35 * k / 4) for k, t in enumerate((39.8, 40.6, 41.4, 42.2, 43.1))],
          (44.1, "comedown", 0.8, 1.0)]
SECTIONS = [("descent", 0.0, 3.4), ("hang", 3.4, 6.0), ("meld", 6.0, 6.6), ("ripple", 6.6, 12.0), ("score", 12.0, 16.0),
            ("tear", 16.0, 19.0), ("fold", 19.0, 30.0), ("fold end", 30.0, 35.0), ("crush", 35.0, 37.5),
            ("silence", 37.5, 38.7), ("bloom", 38.7, 39.8), ("slams", 39.8, 44.1), ("comedown", 44.1, 56.0)]


def rng():
    return soundlib.rng


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
    n = n_of(DESCENT + pad)
    ts = times(n)
    u = np.clip(ts / DESCENT, 0, 1)
    db = -32.0 * (1 - u) ** 1.25                     # (held at the top past the cut: nothing eases before it)
    lv = 10 ** (db / 20)

    def roar(t, f):
        v = min(t / DESCENT, 1.0)
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

    # (the shriek: a thin band sliding up over it)
    fc = 950.0 * (4300.0 / 950.0) ** (u ** 1.5)
    wh = P.glide_band(DESCENT + pad, fc, 0.1) * lv * (0.12 + 0.3 * near)
    L += wh
    R += wh

    # (plasma crackle: ticks thickening to a sizzle, then pops)
    for rate, amp, gr, tau, lo, hi in ((lambda t: 30 + 1500 * (t / DESCENT) ** 3, 1.0, 0.002, 0.00035, 1400, 11000),
                                       (lambda t: 3 + 55 * (t / DESCENT) ** 2.2, 2.2, 0.008, 0.0022, 500, 5000)):
        tick = [np.zeros(n), np.zeros(n)]
        for t1 in P.poisson_times(0.0, DESCENT + pad, lambda t: rate(min(t, DESCENT))):
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
    g = 1.0 / np.abs(np.stack([L, R])[:, n_of(DESCENT - 0.4):n_of(DESCENT)]).max()
    L, R = (np.tanh(c * g * 1.4) / np.tanh(1.4) for c in (L, R))
    out("descent", L, R, -9.0, tail=0, length=n_of(DESCENT))


def stop():
    lead = 0.3
    d = 1.5
    n = n_of(lead + d)
    k0 = n_of(lead)
    s = times(n - k0)
    x = [np.zeros(n), np.zeros(n)]
    f1 = 2349.0
    #          ratio   tau   amp
    modes = ((1.0, 0.62, 1.0), (1.41, 0.3, 0.1), (2.32, 0.34, 0.42), (4.25, 0.17, 0.2), (6.63, 0.08, 0.05))
    for r, tau, amp in modes:
        for sign, share in ((-1, 0.55), (1, 0.45)):
            f = f1 * r + sign * rng().uniform(0.35, 1.1)
            ph = rng().uniform(0, 6.28)
            w = np.sin(2 * np.pi * f * s + ph) * np.exp(-s / tau) * amp * share
            lean = rng().uniform(-0.25, 0.25)
            x[0][k0:] += w * (1 - lean)
            x[1][k0:] += w * (1 + lean)
    touch = np.minimum(s / 0.0016, 1) ** 2             # (a soft touch: no strike)
    x[0][k0:] *= touch
    x[1][k0:] *= touch
    # (the wet fingertip itself, a breath of a contact)
    m = n_of(0.006)
    tip = T.unit(bp(noise(m), 1500, 7000)) * np.sin(np.pi * times(m) / times(m)[-1]) ** 2 * 0.05
    x[0][k0:k0 + m] += tip
    x[1][k0:k0 + m] += tip
    # (a very small clean space, only on the ring)
    for k in range(2):
        ir = make_ir(length=0.9, tau_lo=0.2, tau_mid=0.25, tau_hi=0.22)
        wet = fftconvolve(x[k][k0:], ir)[:n - k0]
        x[k][k0:] += wet * 0.13
    out("stop", x[0], x[1], -26.0, tail=0.12)


def meld():
    d = 2.2
    n = n_of(d)
    t = times(n)
    t0 = 0.04
    u = np.maximum(t - t0, 0)
    f = 40.0 + 24.0 * np.exp(-u / 0.05)
    ph = 2 * np.pi * np.cumsum(f * (t >= t0)) / SR
    hum = (np.sin(ph) + 0.4 * np.sin(2 * ph + 0.8) + 0.16 * np.sin(3 * ph + 1.9)) * (1 - np.exp(-u / 0.02)) * np.exp(-u / 0.62) * (t >= t0)
    contact = bn(n, 120, 460) * np.exp(-u / 0.014) * (1 - np.exp(-u / 0.002)) * (t >= t0) * 1.3
    x = hum + contact
    L = x.copy()
    R = x.copy()
    # (the slide: slow viscous tones falling, thick, drifting across)
    for f0, f1, at, dur, amp, drift in ((165, 96, 0.14, 1.7, 0.2, 0.5), (252, 131, 0.3, 1.5, 0.12, -0.6), (405, 214, 0.5, 1.2, 0.05, 0.35)):
        m = n_of(dur)
        s = times(m)
        v = s / dur
        fg = f0 * (f1 / f0) ** (v ** 0.7) * (1 + 0.012 * np.sin(2 * np.pi * 3.1 * s + at))
        y = np.sin(2 * np.pi * np.cumsum(fg) / SR) * np.sin(np.pi * v ** 0.6) ** 2
        y *= np.clip(1 + 0.45 * PB.slow_random(m, 2.0, 7.0), 0.2, None) * amp
        p = drift * (v - 0.5) * 2
        P.put(L, y * np.cos((p + 1) * np.pi / 4) * 1.41, at)
        P.put(R, y * np.sin((p + 1) * np.pi / 4) * 1.41, at)
    # (small beads running off it)
    for at, f0, amp in ((0.42, 720, 0.022), (0.86, 560, 0.018), (1.28, 640, 0.012)):
        m = n_of(0.2)
        v = times(m) / 0.2
        y = np.sin(2 * np.pi * np.cumsum(f0 * (1 - 0.42 * v ** 0.8)) / SR) * np.sin(np.pi * v) ** 2 * amp
        l, r = pan(y, rng().uniform(-0.6, 0.6))
        P.put(L, l, at)
        P.put(R, r, at)
    sheen = P.glide_band(d, 880 * (0.46 ** ss(0.1, 1.9, t)), 0.13) * np.sin(np.pi * np.clip(t / 2.0, 0, 1)) ** 2 * 0.012
    L += sheen
    R += sheen
    out("meld", L, R, -25.0, tail=0.3)


def ripple():
    d = 6.4
    n = n_of(d)
    L = np.zeros(n)
    R = np.zeros(n)
    #        at    Hz    long  amp   sides alike
    for at, f, dur, amp, corr in ((0.05, 50.0, 0.95, 0.5, 0.92), (1.3, 43.0, 1.3, 0.68, 0.65), (2.8, 36.5, 1.7, 0.85, 0.35), (4.3, 31.0, 2.05, 1.0, 0.05)):
        m = n_of(dur)
        s = times(m)
        v = s / dur
        e = v ** 0.8 * (1 - v) ** 1.9
        e /= e.max()
        ph = 2 * np.pi * np.cumsum(f * (1 - 0.09 * v)) / SR
        y = (np.sin(ph) + 0.24 * np.sin(2 * ph + 0.6) + 0.1 * np.sin(3 * ph + 1.7)) * e * amp
        P.put(L, y, at)
        P.put(R, y, at)
        a, b = wide(bn(m, 90, 340), bn(m, 90, 340), corr)
        P.put(L, a * e ** 1.4 * amp * 0.028, at)
        P.put(R, b * e ** 1.4 * amp * 0.028, at)
    out("ripple", L, R, -23.0, tail=0.2)


def chirp(fh, fl, dur):
    """A dispersive tick: the highs first, as a crack heard along ice or a taut skin."""
    m = n_of(dur)
    v = times(m) / dur
    y = np.sin(2 * np.pi * np.cumsum(fh * (fl / fh) ** v) / SR) * np.exp(-v * 3.2) * np.minimum(v / 0.02, 1)
    return y / np.sqrt(np.sum(y ** 2))


def score():
    d = 4.2
    n = n_of(d)
    kinds = [chirp(11500, 2500, 0.0028), chirp(8500, 1500, 0.0065), chirp(5600, 800, 0.016), chirp(4200, 420, 0.05)]
    trains = [[np.zeros(n), np.zeros(n)] for _ in kinds]
    rate = lambda t: 2.4 + 15.0 * (t / d) ** 2.3
    for t1 in [0.02, *P.poisson_times(0.25, d - 0.25, rate)]:
        v0 = t1 / d
        side = rng().choice([-1.0, 1.0])
        dur = rng().uniform(0.2, 0.62) * (1 - 0.3 * v0)
        big = min(rng().pareto(2.0) * 0.3 + 0.55, 1.3)
        for s in np.sort(rng().uniform(0, 1, rng().integers(30, 130))) ** 0.75:
            at = t1 + s * dur
            if at >= d:
                continue
            p = side * (0.08 + 0.92 * s ** 0.7)                     # (out from the middle to the side)
            amp = big * (1 - 0.78 * s) * min(rng().pareto(2.5) * 0.4 + 0.3, 2.0) * rng().choice([-1.0, 1.0])
            c = min(int(s * 3.0 + rng().uniform(0, 1.0)), 2)       # (further off, duller)
            if rng().random() < 0.018:
                c = 3
                amp *= 1.5
            k = int(at * SR)
            a = (p + 1) * np.pi / 4
            trains[c][0][k] += amp * np.cos(a) * 1.41
            trains[c][1][k] += amp * np.sin(a) * 1.41
    L = np.zeros(n)
    R = np.zeros(n)
    for ker, (a, b), g in zip(kinds, trains, (0.55, 0.9, 1.25, 1.0)):
        L += fftconvolve(a, ker)[:n] * g
        R += fftconvolve(b, ker)[:n] * g
    t = times(n)
    build = 0.3 + 0.7 * (t / d) ** 1.5
    # (the drag: a fingernail's fine grains along a taut skin, two of them, running outward again and again)
    gr = 0.75 * np.std(L[n // 2:])
    for side in (-1, 1):
        g = np.clip(N.grains(d, 900.0, (0.0008, 0.002, 0.006)), 0, 6) ** 1.3
        y = bn(n, 2300, 8500) * g * build * gr
        w = (t * (0.55 + 0.25 * t / d) + (side + 1) * 0.13) % 1.0
        a = (side * (0.1 + 0.9 * w) + 1) * np.pi / 4
        L += y * np.cos(a) * 1.41 * np.sin(np.pi * w) ** 0.6
        R += y * np.sin(a) * 1.41 * np.sin(np.pi * w) ** 0.6
    L *= build
    R *= build
    # (a very little body under the bigger ones, the skin taut)
    body = bn(n, 110, 420) * np.clip(N.grains(d, 14.0, (0.006, 0.014)), 0, 8) * build ** 1.5 * 0.1 * np.std(L[n // 2:])
    L, R = PB.causal_lowcut(L + body, 60.0), PB.causal_lowcut(R + body, 60.0)
    out("score", L, R, -22.0, tail=0.12, peak=10 ** (-7.0 / 20))


# ===========================================================================================================  the land opens
def tear():
    d = 4.4
    n = n_of(d)
    t = times(n)
    # (how fast it is going: a start, uneven surges, stalling; slow)
    v = ss(0.0, 0.3, t) * (1 - ss(2.5, 3.25, t)) * np.clip(0.72 + 0.34 * PB.slow_random(n, 0.8, 5.0), 0.12, 1.5)
    # fibres: rough grabs at 120-500 a second, in low bands (the rip of a whole landscape played slowly)
    rate = 40 + 420 * v
    fib = stick(n, rate, 0.5, 0.1, 0.004, 0.0012)
    canvas = T.unit(bp(fib, 150, 520)) + 0.7 * T.unit(bp(fib, 520, 1900)) + 0.28 * T.unit(bp(fib, 1900, 6500))
    canvas = canvas * v * np.clip(N.grains(d, 26.0, (0.02, 0.05)), 0, 4) ** 0.8
    chop = np.clip(N.grains(d, 80.0, (0.004, 0.012, 0.03)), 0, 6) ** 1.1
    cloth = (bn(n, 170, 1300) + 0.3 * bn(n, 1300, 4200)) * chop * v
    # earth: a low heave and grind under it
    lump = np.clip(1 + 0.6 * PB.slow_random(n, 2.5, 11.0), 0.05, None)
    earth = bn(n, 26, 150) * v ** 1.1 * lump * 1.5
    grind = T.unit(bp(stick(n, 22 + 40 * v, 0.5, 0.2, 0.01, 0.003), 50, 420)) * v * 0.8
    boom = blow(n, 0.02, 74, 42, 32, 0.08, 0.004, [(0.6, 0.3), (0.4, 1.4)]) * 1.3
    boom += blow(n, 1.72, 60, 36, 30, 0.1, 0.006, [(0.7, 0.4), (0.3, 1.1)]) * 0.9
    M = earth + grind + boom
    a, b = wide(canvas * 0.75 + cloth * 0.55, T.unit(bp(noise(n), 170, 1800)) * v * 0.9 * chop, 0.75 - 0.5 * ss(0.3, 1.8, t))
    L = M + a
    R = M + b
    # rock and fibres going, outward from the middle
    for t1 in P.poisson_times(0.05, 3.1, lambda t: 3.0):
        x = rock_crack(1.3, rng().uniform(0.5, 1.1), 0.7) * rng().uniform(0.3, 0.8)
        l, r = pan(x, rng().choice([-1, 1]) * min(0.1 + t1 / 3.1, 1.0) * rng().uniform(0.5, 1))
        P.put(L, l, t1)
        P.put(R, r, t1)
    for t1 in P.poisson_times(0.1, 3.0, lambda t: 11.0):
        m = n_of(0.4)
        f1 = rng().uniform(110, 480)
        x = P.modal_hit(m, f1, [1.0, rng().uniform(1.9, 2.1), rng().uniform(2.9, 3.3), rng().uniform(4.5, 5.5)], [rng().uniform(0.03, 0.09), 0.03, 0.02, 0.01],
                        [1.0, 0.6, 0.35, 0.2], 0.45, 6000)
        x = x / (np.abs(x).max() + 1e-9) * rng().uniform(0.12, 0.5)
        l, r = pan(x, rng().uniform(-1, 1) * min(0.15 + t1 / 2.0, 1.0))
        P.put(L, l, t1)
        P.put(R, r, t1)
    L, R = verb(L, R, 0.42, length=3.0, darken=(2000, 260), decay=1.1)
    # the open air after it: cold and hollow
    air = ss(2.15, 3.2, t)
    for ch in (L, R):
        ch += hollow(n) * air * 0.34 + bn(n, 2600, 7500) * air * np.clip(1 + 0.5 * PB.slow_random(n, 0.4, 2.5), 0.1, None) * 0.02
    L, R = low_mono(L, R, 180.0)
    out("tear", L, R, -10.5, tail=0.55)


def moan(n, at, dur, f0, f1, wob=0.05):
    """One of the land's tonal moans (an iceberg's, a hull's): a slow irregular glide, pulled rough by stick-slip, its
    harmonics thrown up by a soft drive, swelling and easing. Mono, `n` long."""
    m = min(n_of(dur), n - n_of(at))
    s = times(m)
    v = s / dur
    f = f0 * (f1 / f0) ** (v + 0.2 * np.sin(np.pi * v) * rng().uniform(-1, 1))
    f = f * (1 + wob * np.clip(PB.slow_random(m, 0.4, 3.0), -2.5, 2.5))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.sin(np.pi * v ** rng().uniform(0.55, 1.2)) ** 1.5
    rough = np.clip(1 + (0.25 + 0.45 * v) * PB.slow_random(m, 9.0, 34.0), 0.05, None)
    y = np.tanh((1.2 + 2.5 * e) * np.sin(ph + 0.5 * np.sin(ph * 0.5))) * e * rough
    y = bp(y, None, 520)
    o = np.zeros(n)
    P.put(o, y, at)
    return o


def groan():
    pad = 1.6
    d = GROAN + pad
    n = n_of(d)
    t = times(n)
    build = 0.16 + 0.84 * ss(0, 15.5, t) ** 1.4
    heave = np.clip(1 + 0.42 * PB.slow_random(n, 0.1, 0.8), 0.25, None)
    strain = np.clip(0.5 + 0.75 * PB.slow_random(n, 0.1, 0.6), 0.3, None) ** 1.3     # (it comes and goes: never a wall)
    # a sub bed heaving
    bed = bn(n, 19, 58) * heave * build * 0.8
    ph = 2 * np.pi * np.cumsum(29.0 * (1 + 0.1 * PB.slow_random(n, 0.1, 0.7)) + 7.0 * build) / SR
    sub = (np.sin(ph) + 0.35 * np.sin(2 * ph + 0.7)) * np.clip(0.75 + 0.4 * PB.slow_random(n, 0.15, 1.0), 0.05, None) * build * 0.8
    # stick-slip through the hull: a very slow rough pulsing, quickening, the hull's low modes rung by it
    rate = (7.0 + 14.0 * ss(0, 15, t)) * np.clip(1 + 0.4 * PB.slow_random(n, 0.2, 1.4), 0.4, None)
    hull_x = stick(n, rate, 0.4, 0.22, 0.012, 0.004)
    hull = bank(hull_x, ((37, 7, 1.2), (58, 8, 1.0), (91, 8, 0.8), (139, 8, 0.55), (211, 7, 0.32), (333, 6, 0.16)))
    hull = T.unit(hull) * strain * build * 0.8
    # slow moans, irregular, thickening
    tones = np.zeros(n)
    t1 = 0.2
    while t1 < d - 2.5:
        v = t1 / GROAN
        dur = rng().uniform(2.2, 4.8)
        f0 = rng().uniform(38, 92)
        y = moan(n, t1, dur, f0, f0 * rng().choice([0.72, 0.84, 1.18, 1.32]))
        tones += y * rng().uniform(0.5, 1.0) * (0.35 + 0.65 * v)
        t1 += rng().uniform(0.8, 2.3) * (1.15 - 0.6 * v)
    M = bed + sub + hull + T.unit(tones) * (0.25 + 0.75 * strain) * build * 1.1
    L = M.copy()
    R = M.copy()
    # knocks deep down, and rock giving now and then
    for t1 in P.poisson_times(0.5, d - 1.0, lambda t: 0.5 + 1.0 * t / GROAN):
        m = n_of(1.0)
        x = T.thud(m, rng().uniform(1.6, 3.0)) * rng().uniform(0.8, 1.8) * (0.4 + 0.6 * t1 / GROAN)
        l, r = pan(x, rng().uniform(-0.7, 0.7))
        P.put(L, l, t1)
        P.put(R, r, t1)
    for t1 in P.poisson_times(1.5, d - 1.0, lambda t: 0.35 + 0.8 * t / GROAN):
        x = bp(rock_crack(1.0, rng().uniform(0.5, 1.0), 0.45), None, 2600) * rng().uniform(0.2, 0.5)
        l, r = pan(x, rng().uniform(-0.9, 0.9))
        P.put(L, l, t1)
        P.put(R, r, t1)
    # far off, all round
    grind = T.unit(bp(stick(n, 16 + 22 * build, 0.5, 0.2, 0.012, 0.004), 90, 620)) * np.clip(0.3 + 0.7 * PB.slow_random(n, 0.3, 1.5), 0, None) * build * 0.3
    a, b = wide(grind, T.unit(bp(stick(n, 16 + 22 * build, 0.5, 0.2, 0.012, 0.004), 90, 620)) * build * 0.3, 0.4)
    L += a
    R += b
    L, R = verb(L, R, 0.5, length=4.0, darken=(1500, 240), decay=1.7)
    L, R = low_mono(L, R, 190.0)
    # the fast pull-in: the whole sound rushing up over the last 0.8 s, then cut
    tp = times(n_of(GROAN))
    speed = 1 + 3.6 * ss(GROAN - 0.8, GROAN, tp) ** 1.6
    at = np.cumsum(speed) - 1
    lift = 1 + 0.5 * ss(GROAN - 0.8, GROAN, tp)
    L2 = np.interp(at, np.arange(n), L) * lift
    R2 = np.interp(at, np.arange(n), R) * lift
    out("groan", L2, R2, -16.0, tail=0, length=n_of(GROAN), peak=10 ** (-8.0 / 20))


def creak():
    d = 4.4
    n = n_of(d)
    t = times(n)
    hit = 3.0
    swell = ss(0, 0.8, t) * (1 - ss(2.65, 3.05, t))
    # the timbers: slow grabs quickening to a chatter, easing into the boom
    rate = (9.0 + 44.0 * np.sin(np.pi * np.clip(t / 2.95, 0, 1)) ** 1.6) * np.clip(1 + 0.22 * PB.slow_random(n, 0.8, 5.0), 0.5, None)
    x = stick(n, rate, 0.3, 0.12, 0.004, 0.0011)
    wood = bank(x, ((104, 7, 1.0), (163, 8, 1.0), (248, 9, 0.9), (387, 9, 0.7), (612, 9, 0.42), (965, 8, 0.22), (1530, 7, 0.1)))
    wood = T.unit(wood) + 0.35 * T.unit(bp(x, 1600, 4200))
    wood = wood * swell * np.clip(1 + 0.45 * PB.slow_random(n, 0.8, 4.0), 0.2, None) * 0.22
    # the rock under it
    rock = bn(n, 44, 280) * np.clip(N.grains(d, 24.0, (0.015, 0.04, 0.09)), 0, 6) ** 1.2 * swell * 0.13
    sub = bn(n, 24, 70) * swell ** 1.3 * 0.13
    # the settling boom, and what it shakes loose
    boom = blow(n, hit, 82, 47, 36, 0.09, 0.006, [(0.65, 0.3), (0.35, 0.95)], drive=2.5) * 1.7
    boom += bn(n, 30, 130) * N.env_ar(n, hit, 0.015, 0.26, 0.3, 0.8) * 0.7
    M = sub + boom
    L = M + rock
    R = M + rock
    L += wood
    R += wood
    x2 = rock_crack(1.2, 0.95, 0.6) * 0.5
    P.put(L, x2, hit - 0.03)
    P.put(R, x2, hit - 0.03)
    pl, pr = patter(d, hit + 0.1, d - 0.2, lambda t: 14.0 * np.exp(-(t - hit) / 0.5), 1.2)
    L += pl
    R += pr
    L, R = verb(L, R, 0.55, length=3.2, darken=(1700, 250), decay=1.2)
    L, R = low_mono(L, R, 170.0)
    out("creak", L, R, -15.0, tail=0.4, peak=10 ** (-6.5 / 20))


def crush():
    pad = 0.5
    n = n_of(CRUSH + pad)
    ts = times(n)
    u = np.clip(ts / CRUSH, 0, 1)
    lv = 10 ** (-27.0 * (1 - u) ** 1.35 / 20)
    near = u ** 2

    def rush(t, f):
        v = min(t / CRUSH, 1.0)
        fc = 90.0 * (2600.0 / 90.0) ** (v ** 1.15)
        w = 2.6 - 1.5 * v
        return np.exp(-0.5 * (np.log2(f / fc) / (w / 2.355)) ** 2)

    a, b = wide(morph(n, rush), morph(n, rush), 0.25 + 0.75 * ss(0.3, 0.97, u))   # (the sides close to one point)
    gust = np.clip(1 + (0.3 - 0.15 * u) * PB.slow_random(n, 5.0, 22.0), 0.2, None)
    L = a * gust * lv
    R = b * gust * lv
    # stick-slip quickening to a buzz
    bz = T.unit(bp(stick(n, 11.0 * (34.0) ** (u ** 1.1), 0.25 * (1 - 0.7 * u), 0.1, 0.002, 0.0006), 120, 3400)) * lv * 0.45
    L += bz
    R += bz
    # the chord the bloom will open on, climbing out of the sub
    fm = 0.25 * (2.0 ** (2.0 * u ** 1.7))
    ch = np.zeros(n)
    for k, r in enumerate(BLOOM_MODES[:7]):
        ch += np.sin(2 * np.pi * np.cumsum(E2 * r * fm) / SR + k) / (1 + 0.5 * k)
    ch = bp(ch, 20, None) * lv * 0.75
    L += ch
    R += ch
    # the pressure
    f = 17.0 + 62.0 * u ** 2.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    sub = (np.sin(ph) + 0.45 * np.sin(2 * ph + 1) + 0.35 * np.tanh(3 * np.sin(ph))) * lv * 1.9
    sub = sub + bn(n, 24, 120) * lv * 0.9
    L += sub
    R += sub
    L, R = low_mono(L, R, 200.0)
    g = 1.0 / np.abs(np.stack([L, R])[:, n_of(CRUSH - 0.3):n_of(CRUSH)]).max()
    L, R = (np.tanh(c * g * 1.6) / np.tanh(1.6) for c in (L, R))
    out("crush", L, R, -7.5, tail=0, length=n_of(CRUSH))


# ================================================================================================================  the bloom
def bed(d, f0, level, seed, parts=(1, 1.5, 2, 3, 4.02, 5.01, 6.03), amps=(1, .55, .7, .35, .22, .15, .1), side=0):
    """A choir-like pad: detuned partials of a sliding fundamental, each breathing on its own slow curve."""
    r = np.random.default_rng(seed)
    n = n_of(d)
    t = times(n)
    out_ = np.zeros(n)
    for p, a in zip(parts, amps):
        for v in range(3):
            det = 1 + (r.uniform(-1, 1) * 0.0035) + (side * 0.0007)
            ph = np.cumsum(f0(t) * p * det) / SR * 2 * np.pi + r.uniform(0, 6.28)
            br = 0.55 + 0.45 * soundlib.smooth_noise(d, 0.35 + 0.2 * r.random(), n)
            out_ += a * br * np.sin(ph + 0.6 * np.sin(2 * np.pi * (0.1 + 0.07 * v) * t + r.uniform(0, 6)))
    return out_ * level(t) / 9.0


def bloom():
    d = 9.5
    n = n_of(d)
    t = times(n)
    # the detonation: instant, low, no crack
    boom = blow(n, 0.0006, 96, 41.2, 34, 0.055, 0.0012, [(0.8, 0.2), (0.2, 0.9)], drive=3.2, octv=0.32, h3=0.16, harm=0.6) * 2.6
    press = bn(n, 26, 170, 3) * N.env_ar(n, 0.001, 0.004, 0.14, 0.14, 0.8) * 1.3
    body = bn(n, 150, 1400) * N.env_ar(n, 0.001, 0.003, 0.085, 0.1, 0.5) * 0.7
    M = boom + press + body
    rings = []
    for side in (-1, 1):
        r = np.random.default_rng(90 + side)
        x = np.zeros(n)
        # the struck modes, unfolding: each a little later, each one sliding up a hair as it opens
        for k, ratio in enumerate(BLOOM_MODES):
            f = E2 * ratio * (1 + 0.0016 * side * r.uniform(0.3, 1)) * (1 + 0.012 * ss(0, 1.6, t))
            dec = 2.6 / (1 + 0.22 * k)
            env = np.minimum(t / (0.03 + 0.05 * k), 1) * np.exp(-t / dec)
            x += (1.0 / (1 + 0.32 * k)) * env * np.sin(2 * np.pi * np.cumsum(f) / SR + r.uniform(0, 6))
        pad = bed(d, lambda t: E2 * np.ones_like(t) * (1 + 0.02 * np.sin(t * 0.5)), lambda t: ss(0, 1.2, t) * np.exp(-t / 1.9), 55 + side, side=side)
        # the air singing the same notes, opening upward
        air = np.zeros(n)
        for k, ratio in enumerate((4.07, 5.4, 6.7, 8.1, 10.4, 13.1, 16.2, 21.4, 27.0, 34.0)):
            fc = E2 * ratio * (1 + 0.02 * ss(0, 2.0, t))
            e = ss(0.04 + 0.11 * k, 0.5 + 0.2 * k, t) * np.exp(-t / (2.3 - 0.09 * k))
            air += P.glide_band(d, fc, 0.035) * e / (1 + 0.18 * k)
        hiss = bn(n, 2600, 12000) * ss(0.1, 1.0, t) * np.exp(-t / 1.7) * 0.05
        rings.append(x * 0.5 + pad * 1.5 + air * 0.26 + hiss)
    l, _ = soundlib.reverb_st(rings[0], wet=0.5, tau_lo=3.0, tau_mid=1.9, tau_hi=0.8, length=4.5)
    _, rr = soundlib.reverb_st(rings[1], wet=0.5, tau_lo=3.0, tau_mid=1.9, tau_hi=0.8, length=4.5)
    v, w = verb(M, M, 0.35, length=2.6, darken=(1400, 220), decay=0.9)
    a, b = l[:n] * 0.22, rr[:n] * 0.22
    L = 0.75 * a + 0.25 * b + v
    R = 0.75 * b + 0.25 * a + w
    L, R = low_mono(L, R, 150.0)
    out("bloom", L, R, -6.0, tail=0.8)


def thud():
    d = 4.0
    n = n_of(d)
    t = times(n)
    t0 = 0.004
    u = np.maximum(t - t0, 0)
    chest = blow(n, t0, 118, 50, 34, 0.032, 0.0014, [(0.85, 0.13), (0.15, 0.45)], drive=3.5, octv=0.26, h3=0.13, harm=0.55) * 2.0
    ground = bn(n, 240, 3200) * np.exp(-u / 0.011) * (t >= t0) * 0.9 + bn(n, 90, 420) * np.exp(-u / 0.05) * (1 - np.exp(-u / 0.002)) * (t >= t0) * 0.7
    tail = bn(n, 24, 115) * N.env_ar(n, t0 + 0.02, 0.05, 0.3, 0.3, 0.9) * np.clip(1 + 0.5 * PB.slow_random(n, 2.0, 9.0), 0.1, None) * 0.28
    M = chest + ground + tail
    L = M.copy()
    R = M.copy()
    pl, pr = patter(d, 0.28, d - 0.25, lambda v: 26.0 * np.clip(v / 0.5, 0, 1) * np.exp(-max(v - 0.6, 0) / 0.8), 1.5)
    L += pl
    R += pr
    wetL, wetR = verb(L, R, 0.28, length=2.4, darken=(1500, 230), decay=0.8)
    L, R = low_mono(wetL, wetR, 170.0)
    out("thud", L, R, -14.0, tail=0.5, peak=10 ** (-7.5 / 20))


def comedown():
    d = 11.5
    n = n_of(d)
    t = times(n)
    roll = np.clip(1 + 0.5 * PB.slow_random(n, 0.25, 1.6), 0.1, None)
    M = (bn(n, 22, 90) * 1.2 + bn(n, 60, 190) * 0.4 * np.exp(-t / 1.6)) * np.exp(-t / 2.5) * roll
    L = M.copy()
    R = M.copy()
    for t1 in (0.5, 1.4, 2.7, 4.2):                     # (the land still shifting, further and further off)
        y = T.thud(n_of(1.2), rng().uniform(2.2, 3.0)) * np.exp(-t1 / 2.5) * 2.4
        l, r = pan(y, rng().uniform(-0.6, 0.6))
        P.put(L, l, t1)
        P.put(R, r, t1)
    pl, pr = patter(d, 0.05, d - 2.0, lambda v: 22.0 * np.exp(-v / 2.3) + 0.8, 1.0)
    L += pl
    R += pr
    # grit trickling, a fine hiss of it
    tr = np.clip(N.grains(d, 210.0, (0.002, 0.006)), 0, 6) ** 1.2
    a, b = wide(bn(n, 1200, 6500), bn(n, 1200, 6500), 0.2)
    L += a * tr * np.exp(-t / 2.8) * 0.018
    R += b * tr * np.exp(-t / 2.8) * 0.018
    L, R = verb(L, R, 0.45, length=3.4, darken=(1500, 240), decay=1.3)
    # the cold air, a faint hollow tone
    air = ss(0.8, 4.0, t) * (1 - ss(6.5, 11.3, t))
    for ch in (L, R):
        ch += hollow(n, (116.5, 174.6, 233.1, 349.2, 466.2), (0.8, 1.0, 0.7, 0.4, 0.22), 0.04) * air * 0.05
        ch += bn(n, 2200, 6500) * air * np.clip(1 + 0.5 * PB.slow_random(n, 0.2, 1.4), 0.1, None) * 0.0032
    L, R = low_mono(L, R, 170.0)
    out("comedown", L, R, -18.0, tail=2.0)


BUILD = {"descent": descent, "stop": stop, "meld": meld, "ripple": ripple, "score": score, "tear": tear, "groan": groan,
         "creak": creak, "crush": crush, "bloom": bloom, "thud": thud, "comedown": comedown}
SEEDS = {name: 151000 + 7 * k for k, name in enumerate(BUILD)}


# ==============================================================================================================  listening
def db(x):
    return 20 * np.log10(max(float(x), 1e-12))


def full_mix():
    """The whole strike's timeline, as stereo files: (mix). The game sums each file to mono; `game` below does that."""
    clips = {nm: decoded(nm) for nm in BUILD}
    end = max(at + len(clips[f]) / SR / p for at, f, _, p in EVENTS) + 0.5
    mix = np.zeros((n_of(end), 2))
    for at, f, vol, p in EVENTS:
        c = N.pitched(clips[f], p) * vol
        k = n_of(at)
        mix[k:k + len(c)] += c
    return mix


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


def listen(out_dir):
    d = Path(out_dir)
    d.mkdir(parents=True, exist_ok=True)
    print(f"\n{'file':10s} {'len':>7s} {'peak':>7s} {'loudest':>8s} {'LUFS':>7s} {'KB':>6s}")
    total = 0
    for nm in BUILD:
        x = decoded(nm)
        p = d / f"fold_{nm}.wav"
        N.write_wav(p, x)
        lufs, _, _ = N.measure(p)
        kb = Path(path_of(nm) + ".ogg").stat().st_size / 1024
        total += kb
        print(f"{nm:10s} {len(x) / SR:7.3f} {db(np.abs(x).max()):7.2f} {db(T.loudest(x.mean(axis=1))):8.1f} {lufs:7.1f} {kb:6.0f}")
    print(f"total {total / 1024:.2f} MB")

    mix = full_mix()
    p = d / "fold_full.wav"
    N.write_wav(p, mix)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(p), "-c:a", "libmp3lame", "-b:a", "192k", str(p.with_suffix(".mp3"))], check=True)
    mono = mix.mean(axis=1)
    picture(mono, d / "fold_full.png")
    print(f"\nthe mix: peak {db(np.abs(mix).max()):.2f} dBFS stereo, {db(np.abs(mono).max()):.2f} dBFS summed (the game: 0.596 of that on each side)")
    print(f"{'section':10s} {'from':>6s} {'to':>6s} {'stereo':>7s} {'peak':>7s} {'rms':>7s} {'loudest':>8s}")
    for nm, a, b in SECTIONS:
        s = mono[n_of(a):n_of(b)]
        s = s if len(s) else np.zeros(1)
        print(f"{nm:10s} {a:6.1f} {b:6.1f} {db(np.abs(mix[n_of(a):n_of(b)]).max()):7.1f} {db(np.abs(s).max()):7.1f} {db(np.sqrt(np.mean(s ** 2))):7.1f} {db(T.loudest(s)) if len(s) > n_of(0.5) else float('nan'):8.1f}")

    print("\nthe hard ends:")
    for nm, want in (("descent", DESCENT), ("crush", CRUSH), ("groan", GROAN)):
        x = decoded(nm)
        last = np.sqrt(np.mean(x[-n_of(0.01):] ** 2))
        was = np.sqrt(np.mean(x[-n_of(0.06):-n_of(0.01)] ** 2))
        raw = untrimmed(nm)
        over = raw[len(x):] if len(raw) > len(x) else np.zeros((1, 2))
        print(f"  {nm:8s} {len(x)} samples ({len(x) / SR:.4f} s, wanted {want}); last 10 ms {db(last):.1f} dB (the 50 ms before {db(was):.1f}), last sample {db(np.abs(x[-1]).max()):.1f} dB; "
              f"untrimmed, as the game decodes it: {len(over)} samples more, peak {db(np.abs(over).max()):.1f} dB, its last {db(np.abs(over[-1]).max()):.1f} dB")
    a, b = n_of(37.5), n_of(38.7)
    print(f"  37.5 to 38.7 s: peak {np.abs(mix[a:b]).max():.2e}; 37.5 + 1 ms on {np.abs(mix[a + 44:b]).max():.2e}")
    a, b = n_of(3.4), n_of(3.68)
    print(f"  3.4 to 3.68 s (stop's lead): peak {np.abs(mix[a:b]).max():.2e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=list(BUILD))
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write WAVs, the whole strike's mix and the level checks here")
    a = ap.parse_args()
    soundlib.init(a.out)
    for name in a.only if a.only is not None else BUILD:
        with PB.seeded(SEEDS[name]):
            BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    sounds.pop(f"{TH}.drone", None)
    for name in BUILD:
        sounds[f"{TH}.{name}"] = {"sounds": [{"name": f"orbital:{TH}/{name}", "stream": True}], "subtitle": f"subtitles.orbital.{TH}.{name}"}
    path.write_text(json.dumps(sounds, indent=2))
    (Path(a.out) / "assets" / "orbital" / "sounds" / TH / "drone.ogg").unlink(missing_ok=True)
    if a.listen:
        listen(a.listen)


if __name__ == "__main__":
    main()
