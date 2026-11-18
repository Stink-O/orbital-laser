"""Six Stars' sounds: a six-star wanted level climbing, the sixth star tearing loose, falling, burning, and its blast.

What breaks, burns, rolls or rushes is real: CC0 recordings from Freesound (credited in NOTICE; not in the repository),
read from SRC (`--src DIR[:DIR...]`, or the SS_SOUND_SRC environment variable), each found by its Freesound number in
the file name (`SOURCES`). They are cut, slowed, filtered and re-enveloped here. What carries the weight is synthesised
under them: the low booms falling in pitch, the stars' blooms, the far sirens, the bed's drones, the blast's roar shaped to
octave levels over time (`BLAST_T`, `BLAST_DB`), which were measured on two recordings of real explosions (`REFS`:
measured only, nothing of them is in any file).

The strike's clock (seconds; keep in step with the strike's plan), each event's file with its hit where it says:

  sixstars.climb     0.0    the bed under the climb: a deep drone and the ground's own rumble swelling from the HUD's
                            fade-in (0.3) to the peel, far thunder in the sky from about 2 s; handed over to `peel`
                            from 8.2 and gone by 10.0
  sixstars.sirens    1.2    police sirens far off under the climb, never loud: one more car with each star (their count
                            is the wanted level, six by star 6), wails and yelps of synthesised horn-like tones, each its
                            own pitch and pace, wandering a little (doppler), through 1,600 blocks of air and a little
                            nearer each star (to 1,000), with the land's echoes; carried on past the peel a little
                            lower and fading out over 9.5-11.0 (9.8 s; to 8.25 the file the sirens had when they went
                            into the peel by 9.5: `sirens_to_peel`)
  sixstars.star1-6   1.20 2.35 3.50 4.65 5.80 6.95   a deep soft bloom each as a star lights, starting 0.0 s into its
                            file: a rounded swell of 40-150 Hz (no transient, no tone), up out of the bed in a quarter
                            of a second and back in by about 1.2 s, a little fuller each star
  sixstars.peel      8.16   the sixth star popping out of the HUD like a pane of glass (its hit 0.04 s in, on 8.2:
                            `PEEL_LEAD`): a window's glass breaking, only its front (one pop, never a shatter; its
                            rings and tinkle eased off within 50 ms), then a dark pull of real air away from it (a
                            bamboo stick's whoosh, slowed and darkened), and under the pull the glass's own body
                            ringing on (the same recording through a bank of its partials, 300 Hz-1 kHz, measured on
                            it: `RING_MODES`), 18 dB under the pop a tenth of a second on, its top closing as the air
                            pulls away, dying over about 0.7 s; nothing under 140 Hz (1.0 s)
  sixstars.flight    8.25   the star flying off into the sky (8.3-10.35): a smooth rush of air following it up and
                            away (a real fire's roar over 180 Hz, its pitch rising, then falling as it recedes, its top
                            closing), a slowed stick's whoosh swelling out of the pop; then as it turns into the burning
                            star and hangs (10.35-11.2), a low warm swell (D1, A1, D2 and their harmonics, the fire's
                            low body) and a first breath of fire growing into `fall` and held under its quiet opening,
                            fading as the fall rises to meet it (7.25 s, to 15.5; the rush ends by 11.6); levelled so
                            9-11 s sits where the climb's bed sat at 6-8 s from 150 blocks, and 11-15 s within about 3
                            dB of that
  sixstars.fall      11.2   the star hanging high up burning (11.2-11.8), then falling, accelerating, louder and
                            brighter and rising in pitch as it comes down; the file ends exactly on 17.0 (5.8 s)
  sixstars.ground    17.0 + d / 1715   the shock through the ground, ahead of the air (its hit 0.03 s in)
  sixstars.blast_near / _mid / _far    17.0 + d / 343, the air's front (its hit 0.02 s in): a low knock and a boom
                            falling from ~60 Hz to ~24, the fireball's roar, the land's dust wall, rolls off the land;
                            mid and far are the near one through 600 and 1,300 blocks of air (ISO 9613 absorption, a
                            minimum-phase filter, so nothing rings ahead of the front) with the land's echoes added
  sixstars.plough    17.0 + d / 343    the five points tearing out across the land: five real earth slides slowed
                            and slowing further as they decelerate, a low churn under them, each settling in turn by
                            about 2.6 s
  sixstars.after     18.0   the crater burning and the land rumbling, settling over ~20 s (the file 30 s, to 48)

Levels are set as the game plays them (see `game_mix`): every file mono, each voice at 0.596 a side, a voice at most
volume 1 (more is more voices of the same file), a limiter only over full scale. `VOLUME` is each event's volume.

    python3 tools/sounds_sixstars.py --src DIR              # write orbital-sounds/.../sixstars/*.ogg and the events
    python3 tools/sounds_sixstars.py --src DIR --out TMP    # build elsewhere first (TMP/assets/orbital/sounds/...)
    python3 tools/sounds_sixstars.py --src DIR --review DIR # also mp3s of each and game mixdowns from 150 and 400 blocks
"""
import argparse, json, os, subprocess, sys
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
TH = "sixstars"

# ------------------------------------------------------------------------------------------------- the strike's clock
HUD_IN = 0.3
STARS = [1.20, 2.35, 3.50, 4.65, 5.80, 6.95]
PEEL = 8.2
FLIGHT = 8.25                           # (the star flying off into the sky, turning into the burning star and hanging)
FLIGHT_LEN = 7.25                       # (to 15.5: under the fall's quiet opening, till it has risen to meet it)
RUSH_END = 11.6                         # (the rush of air gone into the fall's first 0.4 s)
LIFT_UP = 10.35                         # (the star high up, turning into the burning star)
HANG = 11.2
DROP = 11.8
HIT = 17.0
PLOUGH_STOP = 19.4
AFTER = 18.0
END = 58.0
SIRENS_AT = 1.2
AIR_V = 343.0
GROUND_V = 1715.0
GROUND_LEAD = 0.03                      # (its hit this far into its file)
BLAST_LEAD = 0.02

FILES = ["climb", "sirens", "star1", "star2", "star3", "star4", "star5", "star6", "peel", "flight", "fall", "ground",
         "blast_near", "blast_mid", "blast_far", "plough", "after"]
SUBTITLE = {"climb": "climb", "sirens": "sirens", "star": "star", "peel": "peel", "flight": "flight", "fall": "fall", "ground": "ground",
            "blast": "blast", "plough": "plough", "after": "after"}
SUBTITLE_TEXT = {"climb": "Wanted level rises", "sirens": "Sirens wail far off", "star": "A star lights", "peel": "A star tears loose",
                 "flight": "A star rises into the sky",                 "fall": "A burning star falls", "ground": "Ground shakes", "blast": "The star explodes",
                 "plough": "The ground is torn open", "after": "Fire burns in the crater"}
# each event's volume in the game (over 1: as many voices of the file as it takes)
VOLUME = {"climb": 1.0, "sirens": 1.0, "star1": 1.0, "star2": 1.0, "star3": 1.0, "star4": 1.0, "star5": 1.0, "star6": 1.0,
          "peel": 1.0, "flight": 1.0, "fall": 1.2, "ground": 1.0, "blast_near": 1.5, "blast_mid": 1.5, "blast_far": 1.5, "plough": 0.7,
          "after": 1.0}
# each file's loudest 400 ms (dBFS, as decoded), its peaks never over PEAK; the peel's measured on its pop alone (`pop`),
# the ring after it added at that gain
LEVEL = {"climb": -15.0, "sirens": -25.0, "star1": -21.0, "star2": -20.2, "star3": -19.4, "star4": -18.6, "star5": -17.8,
         "star6": -17.0, "peel": -19.0, "flight": -15.3, "fall": -10.0, "ground": -14.5, "blast_near": -6.5, "blast_mid": -7.0,
         "blast_far": -8.0, "plough": -13.0, "after": -15.0}
PEAK = 0.912                            # (-0.8 dBFS)
PEEL_LEAD = 0.04                        # (the peel's hit this far into its file)

# ------------------------------------------------------------------------------------------------- the recordings
# key: (Freesound number, title, author). All CC0 1.0, credited in NOTICE.
SOURCES = {
    "dynamite": (251401, "Dynamite explosion in the mountain", "felix.blume"),
    "quake": (369485, "Earthquake **audible only with appropriate speakers**", "MBARI_MARS"),
    "geofon": (613617, "Rocket Launch Rumble (Geofon recording)", "felix.blume"),
    "avalanche": (438683, "G43-04-AvalancheRockslide.wav", "craigsmith"),
    "soil": (426174, "Soil Slide", "NeoSpica"),
    "merrimack": (125937, "merrimack-st-demolition.aif", "alienistcog"),
    "dthunder": (393634, "Extremely distant thunder", "supercell10"),
    "landslide": (675736, "S24-18 Landslide.wav", "craigsmith"),
    "fire": (387924, "Fire -massive no cracking.wav", "Aegersum"),
    "flame": (494085, "Flamethrower.wav", "sidequesting"),
    "rocket": (494827, "Seamless Rocket Booster Roar & Crackle", "NickTimesAudio"),
    "thunder1": (574412, "Thunder big crack explosive close ms 77mel 190903.flac", "TRP"),
    "thunder2": (840628, "Closeup Thunder Strike 01", "loganzsound"),
    "stick": (352719, "Woosh (stick swung in the air)", "Dalesome"),
    "bamboo": (855844, "Whoosh - Long Bamboo stick - OS ST 13", "Sadiquecat"),
    "gwindows": (487138, "R28-12-Glass Windows Break.wav", "craigsmith"),
}
# measured only (the blast's table), none of their sound used
REFS = {
    "eleven": (483286, "R28-38-Eleven Large Explosions.wav", "craigsmith"),
    "huge": (417691, "huge explosion in distance.wav", "SuperPhat"),
}
# hum and machine lines in some of them (Hz), notched out wherever they are used
HUM = {"avalanche": [59.2, 118.4, 177.6, 180.3], "merrimack": [60.6, 121.2], "landslide": [60.0, 120.0]}
SRC = [Path(p) for p in os.environ.get("SS_SOUND_SRC", "sixstars-sound-src").split(":")]
CUTS = []                               # (key, from, to) of every cut, for looking at their spectrograms


# ================================================================================================= helpers
def rng(seed):
    return np.random.default_rng(seed)


_cache = {}


def src(key):
    """A recording, mono at SR, as float."""
    if key in _cache:
        return _cache[key]
    num = SOURCES[key][0] if key in SOURCES else REFS[key][0]
    hits = [p for d in SRC for p in sorted(d.glob(f"*{num}*")) if p.suffix.lower() in (".mp3", ".wav", ".flac", ".ogg", ".aif", ".aiff")]
    if not hits:
        raise SystemExit(f"no recording with Freesound number {num} ({key}) in {':'.join(map(str, SRC))} (set --src or SS_SOUND_SRC)")
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(hits[0]), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    if key in HUM:
        for f in HUM[key]:
            b, a = signal.iirnotch(f, 18.0, SR)
            x = signal.filtfilt(b, a, x)
    _cache[key] = x
    return x


def cut(key, a, b, fade=0.01):
    """Seconds a to b of a recording, faded at both ends (logged for the spectrogram check)."""
    x = src(key)
    seg = x[int(a * SR):int(b * SR)].copy()
    k = int(fade * SR)
    if k and len(seg) > 2 * k:
        w = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
        seg[:k] *= w
        seg[-k:] *= w[::-1]
    CUTS.append((key, a, b))
    return seg


def onset(key, t, frac=0.15):
    """Where a blow in a recording starts: the first moment within 0.15 s before and 0.25 s after `t` (seconds, found by
    eye on its spectrogram) that its 2 ms level reaches `frac` of its loudest there, less 2 ms; `frac` 0: `t` itself
    (for a blow that grows out of a rumble, where no threshold finds it)."""
    if frac == 0:
        return t
    a = max(t - 0.15, 0.0)
    x = src(key)[int(a * SR):int((t + 0.25) * SR)]
    e = np.sqrt(np.convolve(x * x, np.ones(88) / 88, "same"))
    return max(a + int(np.argmax(e > frac * e.max())) / SR - 0.002, 0.0)


def round_off(x, over_db, until=None):
    """Peaks rounded off softly `over_db` over the loudest 400 ms (until `until` seconds, if given, and free after)."""
    c = 10 ** ((loudest(x) + over_db) / 20)
    if until is not None:
        u = np.arange(len(x)) / SR
        c = c * (1 + 1e3 * np.clip((u - until) / 0.15, 0, 1) ** 2)
    return c * np.tanh(x / c)


def sos(kind, f, order):
    return signal.butter(order, f, kind, fs=SR, output="sos")


def lp(x, f, order=4, zero=False):
    s = sos("low", f, order)
    return signal.sosfiltfilt(s, x) if zero else signal.sosfilt(s, x)


def hp(x, f, order=2, zero=False):
    s = sos("high", f, order)
    return signal.sosfiltfilt(s, x) if zero else signal.sosfilt(s, x)


def bp(x, lo, hi, order=2, zero=False):
    s = sos("band", [lo, hi], order)
    return signal.sosfiltfilt(s, x) if zero else signal.sosfilt(s, x)


def unit(x):
    return x / (np.sqrt(np.mean(x * x)) + 1e-12)


def slow(x, rate):
    """Played at `rate` of its speed (under 1: slower and lower), resampled cleanly."""
    from fractions import Fraction
    fr = Fraction(1 / rate).limit_denominator(50)
    return signal.resample_poly(x, fr.numerator, fr.denominator)


def vary(x, rate, n):
    """`n` samples of `x` played at a speed that changes (`rate`: an array of n), looping it if it runs out."""
    rate = np.broadcast_to(np.asarray(rate, dtype=float), (n,))
    if rate.max() > 1.0:
        x = lp(x, 0.45 * SR / rate.max(), 6, zero=True)
    pos = np.concatenate([[0.0], np.cumsum(rate)[:-1]])
    if pos[-1] >= len(x) - 2:
        x = loop(x, int(pos[-1]) + 4)
    return np.interp(pos, np.arange(len(x)), x)


def loop(x, n, xf=1.5):
    """`x` made `n` long by looping it with equal-power crossfades of `xf` seconds."""
    k = int(xf * SR)
    out = x.copy()
    while len(out) < n:
        w = np.sin(np.linspace(0, np.pi / 2, k))
        joined = out[-k:] * w[::-1] + x[:k] * w
        out = np.concatenate([out[:-k], joined, x[k:]])
    return out[:n]


def place(n, x, t0, gain=1.0):
    """`x` laid into a buffer of `n` samples at `t0` seconds."""
    out = np.zeros(n)
    k = int(round(t0 * SR))
    a = max(k, 0)
    m = min(len(x) - (a - k), n - a)
    if m > 0:
        out[a:a + m] = x[a - k:a - k + m] * gain
    return out


def env(n, pts, db=False):
    """A curve through (seconds, value) points, linear between them (in dB if `db`)."""
    t = np.arange(n) / SR
    ts, vs = zip(*pts)
    v = np.interp(t, ts, vs)
    return 10 ** (v / 20) if db else v


def ease_top(x, k0, rise, fc=1200.0):
    """Everything over `fc` eased in over `rise` seconds from sample `k0` (a hit's front with no bright burst)."""
    lo = lp(x, fc, 4)
    hi = x - lo
    u = np.clip((np.arange(len(x)) - k0) / max(rise * SR, 1), 0, 1)
    return lo + hi * (u * u * (3 - 2 * u))


def wander(n, rate, seed, pace=None):
    """A slow random curve, about unit spread, `rate` turns a second; `pace` (samples): the curve as it is over that
    many, carried on past them (its first `pace` samples the same as `wander(pace, ...)`'s)."""
    g = rng(seed)
    if pace is None:
        pts = g.standard_normal(int(n / SR * rate) + 4)
        xs = np.linspace(0, len(pts) - 2, n)
    else:
        k = int(pace / SR * rate) + 4
        xs = np.arange(n) * ((k - 2) / (pace - 1))
        pts = g.standard_normal(max(k, int(xs[-1]) + 3))
    i = np.floor(xs).astype(int)
    f = xs - i
    f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[i + 1] * f


def surges(n, db, rate, seed, pace=None):
    """A gain heaving `db` dB about 1 at `rate` turns a second (`pace`: as `wander`'s)."""
    return 10 ** (db * wander(n, rate, seed, pace) / 20)


def saturate(x, drive, even=0.25):
    """A lopsided soft saturation (its own odd and even harmonics), level kept."""
    a = np.sqrt(np.mean(x * x)) * 3 + 1e-12
    v = x / a * drive
    y = np.tanh(v) + even * (v * v / (1 + v * v))
    y = hp(y, 18.0, 2)
    return y * a / drive


def boom(n, t0, f0, f1, glide, rise, decay, seed, body=0.0, hold=0.0):
    """A low boom from `t0`: a tone falling from `f0` to `f1` (Hz, `glide` s), rising over `rise` s, held `hold` s and
    dying over `decay` s; `body` of band noise (35-160 Hz) under the same envelope for breadth."""
    t = np.arange(n) / SR
    u = t - t0
    f = f1 + (f0 - f1) * np.exp(-np.maximum(u, 0) / glide)
    ph = 2 * np.pi * np.cumsum(f * (u >= 0)) / SR + rng(seed).uniform(0, 6.28)
    e = np.where(u < 0, 0.0, np.where(u < rise, np.sin(0.5 * np.pi * np.clip(u / rise, 0, 1)) ** 2,
                                      np.exp(-np.maximum(u - rise - hold, 0) / decay)))
    x = np.sin(ph) * e
    if body:
        x = x + unit(bp(rng(seed + 1).standard_normal(n), 35, 160, 2)) * e * body * 0.7071
    return x


# --------------------------------------------------------------------------------------- octave-shaped noise
OCT = np.array([31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])


def shaped(d, times, table, seed, size=4096, hop=1024):
    """Noise whose octave levels follow `table` (dB, a row per time in `times`), built frame by frame in the spectrum
    with random phase (nothing rings), equal dB in each octave is pink."""
    n = int(d * SR)
    g = rng(seed)
    f = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    xs = np.concatenate([[np.log2(8.0)], np.log2(OCT), [np.log2(22050.0)]])
    win = np.hanning(size)
    out = np.zeros(n + 2 * size)
    for start in range(-size, n, hop):
        tc = (start + size / 2) / SR
        row = np.array([np.interp(tc, times, table[:, k]) for k in range(len(OCT))])
        ys = np.concatenate([[row[0] - 30], row, [row[-1] - 30]])
        mag = 10 ** (np.interp(lf, xs, ys) / 20) / np.sqrt(np.maximum(f, 20.0) / 1000.0)
        mag[0] = 0
        z = g.standard_normal(len(f)) + 1j * g.standard_normal(len(f))
        out[start + size:start + 2 * size] += np.fft.irfft(mag * z, size) * win
    return out[size:size + n]


def oct_levels(x, a, b):
    """Octave levels (dB) of x between a and b seconds."""
    seg = x[int(a * SR):int(b * SR)]
    out = []
    for f in OCT:
        hi = min(f * np.sqrt(2), SR / 2 * 0.95)
        y = signal.sosfiltfilt(sos("band", [f / np.sqrt(2), hi], 4), seg)
        out.append(10 * np.log10(np.mean(y * y) + 1e-20))
    return np.array(out)


def loudest(x, w=0.4):
    """The loudest `w` seconds' level (dB)."""
    k = int(w * SR)
    c = np.cumsum(np.concatenate([[0.0], x * x]))
    return 10 * np.log10(((c[k:] - c[:-k]) / k).max() + 1e-20)


# --------------------------------------------------------------------------------------- distance
# air's absorption, dB a kilometre (ISO 9613-1, 20 C, 70% humidity), by frequency
AIR_F = np.array([31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
AIR_DB_KM = np.array([0.02, 0.1, 0.4, 1.0, 1.9, 3.7, 9.7, 32.8, 117.0, 400.0])


def air(x, dist, extra_db_oct=0.0):
    """`x` heard through `dist` blocks (metres) of air: a minimum-phase filter (nothing ahead of the front) with the
    absorption's own curve, rising with frequency as it does, never a flat low-pass; `extra_db_oct` more (dB an octave
    over 500 Hz) for the land and the trees in the way."""
    N = 16384
    f = np.fft.rfftfreq(N, 1 / SR)
    lf = np.log10(np.maximum(f, 20.0))
    att = 10 ** np.interp(lf, np.log10(AIR_F), np.log10(AIR_DB_KM)) * dist / 1000.0
    att = att + extra_db_oct * np.maximum(np.log2(np.maximum(f, 1.0) / 500.0), 0)
    att = np.minimum(att, 100.0)
    logmag = -att / 20 * np.log(10)
    c = np.fft.irfft(logmag, N)
    w = np.zeros(N)
    w[0] = 1
    w[1:N // 2] = 2
    w[N // 2] = 1
    h = np.fft.irfft(np.exp(np.fft.rfft(c * w)), N)[:N // 2]
    h[-512:] *= np.linspace(1, 0, 512)
    return signal.fftconvolve(x, h)[:len(x)]


def land_echoes(x, seed, t_a, t_b, count, decay, fc, wet, upto=None):
    """The sound coming back off the land: `count` echoes between `t_a` and `t_b` seconds, each smeared wider the
    later it comes and darker (`fc` Hz the first, halving by the last), dying over `decay` seconds; `wet` of `x`'s level
    over its first `upto` samples (all of it if None)."""
    g = rng(seed)
    n_ir = int((t_b + 0.3) * SR)
    ir = np.zeros(n_ir)
    for _ in range(count):
        t = t_a + (t_b - t_a) * g.random() ** 1.6
        w = int((0.01 + 0.08 * (t - t_a) / (t_b - t_a + 1e-9)) * SR)
        k = int(t * SR)
        hw = np.hanning(max(w, 8))
        m = min(len(hw), n_ir - k)
        ir[k:k + m] += hw[:m] / hw.sum() * np.exp(-(t - t_a) / decay) * g.uniform(0.5, 1.0) * g.choice([-1, 1])
    y = signal.fftconvolve(x, ir)[:len(x)]
    y = lp(y, fc, 2)
    y = lp(y, fc * 0.6, 1)
    xa, ya = x[:upto], y[:upto]
    return x + y / (np.sqrt(np.mean(ya * ya)) + 1e-12) * np.sqrt(np.mean(xa * xa)) * wet


# ================================================================================================= the sounds
def climb():
    """The bed under the climb, 0 to 10 s."""
    d = 10.0
    n = int(d * SR)
    t = np.arange(n) / SR
    # (the whole swelling as the stars climb: from the HUD's fade-in to the peel, about 12 dB)
    swell = env(n, [(0.0, -40.0), (0.25, -16.0), (HUD_IN, -14.0), (STARS[0], -11.0), (STARS[2], -8.0),
                    (STARS[4], -4.5), (STARS[5], -2.0), (PEEL, 0.0), (PEEL + 0.5, -2.0), (9.3, -14.0), (10.0, -60.0)], db=True)
    # ---- the ground's own rumble (real, a geophone under a launch: nothing over 300 Hz), slowed a little deeper
    rum = slow(cut("geofon", 40.0, 40.0 + d * 0.8 + 0.5), 0.8)[:n]
    rum = unit(lp(hp(rum, 22.0, 2, zero=True), 260.0, 4, zero=True)) * surges(n, 2.5, 0.7, 11)
    # ---- the drone: D1, A1 and D2 as detuned dark saws, the filter opening from 110 to 420 Hz as the stars climb
    fc = env(n, [(0.0, 110.0), (STARS[0], 140.0), (STARS[5], 330.0), (PEEL, 420.0), (d, 300.0)])
    drone = np.zeros(n)
    g = rng(12)
    for root, amp in ((36.71, 1.0), (55.0, 0.6), (73.42, 0.45)):
        for v in range(4):
            fr = root * (1 + g.uniform(-0.004, 0.004))
            ph = 2 * np.pi * fr * t + g.uniform(0, 6.28)
            k = 1
            while k * fr < 900:
                drone += np.sin(k * ph) / k / np.sqrt(1 + (k * fr / fc) ** 4) * amp / 4
                k += 1
    drone = unit(drone) * surges(n, 1.5, 0.4, 13)
    # ---- far thunder in the sky (real), from about 2 s, dark
    sky = slow(cut("dthunder", 2.0, 2.0 + d * 0.85 + 0.5), 0.85)[:n]
    sky = unit(lp(sky, 400.0, 2, zero=True)) * env(n, [(0.0, -60.0), (1.8, -30.0), (3.0, -14.0), (PEEL, -6.0), (d, -10.0)], db=True)
    x = rum * 0.9 + drone * 0.55 + sky * 0.35
    return x * swell


def star(i):
    """Star i+1's bloom, starting at 0.0: a deep soft swell felt more than heard, 40-150 Hz band noise (no tone, no
    transient, nothing over it) rising out of the bed over a quarter of a second and settling back by about 1.2 s, a
    little fuller each star (wider and lower, longer)."""
    d = 1.6
    n = int(d * SR)
    t = np.arange(n) / SR
    lo = 52.0 - 2.4 * i
    hi = 120.0 + 6.0 * i
    x = unit(bp(rng(1500 + i).standard_normal(n), lo, hi, 2, zero=True))
    x = x * surges(n, 1.5, 3.0, 1510 + i)
    rise = 0.22 + 0.02 * i
    e = np.where(t < rise, np.sin(0.5 * np.pi * t / rise) ** 2, np.exp(-((t - rise) / (0.38 + 0.04 * i)) ** 1.6))
    x = x * e
    x[-int(0.1 * SR):] *= np.linspace(1, 0, int(0.1 * SR))
    return x


SIRENS_D = 8.3                          # (the sirens as approved: to 9.5, gone into the peel; `sirens_to_peel`)
SIRENS_ON = 9.8                         # (carried on: to 11.0, `sirens`)
SIRENS_JOIN = 8.25                      # (the approved file to here, the carried-on one after it)


def sirens_render(d, fade, pace=None):
    """Police sirens far off (from 1.2 s), `d` s: one more car with each star, so their count is the wanted level
    (one faint car at star 1, six by star 6), each a horn-like tone (odd harmonics) sweeping in a wail or a yelp at its
    own pitch and pace, its pitch wandering a little as it moves (doppler), through 1,600 blocks of air for the first
    and a little nearer each star after (to 1,000), with the land's echoes; `fade` (seconds into the file, dB) its fade.
    `pace` (samples): the cars' wandering, levels and echoes as a render that long has them, carried on after it."""
    at = SIRENS_AT
    n = int(d * SR)
    m = pace or n
    t = np.arange(n) / SR
    # (each: wail or yelp, low and high Hz, sweeps a second, distance, its own seed); car k comes in with star k+1
    cars = [("wail", 640.0, 1280.0, 0.24, 1600.0, 1201), ("wail", 590.0, 1180.0, 0.29, 1450.0, 1202),
            ("yelp", 700.0, 1350.0, 3.1, 1350.0, 1203), ("wail", 680.0, 1330.0, 0.21, 1250.0, 1204),
            ("yelp", 610.0, 1250.0, 2.6, 1100.0, 1205), ("wail", 560.0, 1150.0, 0.33, 1000.0, 1206)]
    x = np.zeros(n)
    for k, (kind, lo, hi, rate, dist, seed) in enumerate(cars):
        g = rng(seed)
        ph0 = g.uniform(0, 1)
        r = rate * (1 + 0.04 * wander(n, 0.3, seed, pace))
        cyc = (np.cumsum(r) / SR + ph0) % 1.0
        if kind == "wail":                          # (rising slowly, falling slower: a smooth hump each cycle)
            shape = np.sin(np.pi * cyc) ** 1.5
        else:                                       # (yelp: a quick rise, a fall)
            shape = np.where(cyc < 0.35, cyc / 0.35, 1 - (cyc - 0.35) / 0.65) ** 1.2
        dop = 1 + 0.012 * wander(n, 0.15, seed + 50, pace)              # (the car moving: its pitch wandering)
        f = (lo + (hi - lo) * shape) * dop
        ph = 2 * np.pi * np.cumsum(f) / SR
        tone = np.sin(ph) + 0.33 * np.sin(3 * ph) + 0.18 * np.sin(5 * ph) + 0.1 * np.sin(7 * ph)
        tone = air(tone, dist, 0.6 * dist / 1000)
        # (as loud as its distance makes it: 1/r and the air, each car 1,600 blocks off at -6 dB)
        ta = tone[:m]
        tone = tone / (np.sqrt(np.mean(ta * ta)) + 1e-12) * 10 ** ((-6.0 - 20 * np.log10(dist / 1600.0)) / 20) \
            * surges(n, 2.5, 0.5, seed + 70, pace)
        start = STARS[k] - at
        tone *= np.clip((t - start) / 0.9, 0, 1) ** 2
        x += tone
    x = land_echoes(x, 1210, 0.15, 2.5, 40, 1.2, 1400.0, 0.9, pace)
    x = hp(x, 300.0, 2) * env(n, fade, db=True)
    x[:int(0.05 * SR)] *= np.linspace(0, 1, int(0.05 * SR))
    x[-int(0.1 * SR):] *= np.linspace(1, 0, int(0.1 * SR))
    return x


def sirens_to_peel():
    """The sirens as approved, 8.3 s: gone into the peel (from 8.2, by 9.5)."""
    at, d = SIRENS_AT, SIRENS_D
    return sirens_render(d, [(0.0, 0.0), (PEEL - at, 0.0), (PEEL - at + 0.6, -12.0), (d - 0.3, -40.0), (d, -80.0)])


def sirens():
    """The sirens carried on past the pop, 9.8 s: as approved to 8.25 (`sirens_to_peel`, the file the same), then the
    same cars rendered on (`pace`) and joined over 20 ms, a little lower through the star's flight (3-5 dB under), fading
    out over 9.5-11.0."""
    at, d = SIRENS_AT, SIRENS_ON
    on = sirens_render(d, [(t - at, db) for t, db in ((at, 0.0), (PEEL, 0.0), (SIRENS_JOIN, -1.0), (PEEL + 0.6, -3.0),
                                                       (9.5, -5.0), (10.2, -14.0), (10.7, -32.0), (at + d, -80.0))],
                       pace=int(SIRENS_D * SR))
    x = sirens_to_peel()
    k = int(round((SIRENS_JOIN - SIRENS_AT) * SR))
    w = int(0.02 * SR)
    u = np.sin(np.linspace(0, np.pi / 2, w)) ** 2
    on[:k] = x[:k]
    on[k:k + w] = x[k:k + w] * (1 - u) + on[k:k + w] * u
    return on


def smooth(u):
    u = np.clip(u, 0, 1)
    return u * u * (3 - 2 * u)


def moving_lp(x, fcs, blk=512, order=2):
    """`x` through a low-pass that moves (`fcs`, Hz, an array as long as x), in short overlapping blocks."""
    n = len(x)
    out = np.zeros(n)
    win = np.hanning(2 * blk)
    for s0 in range(-blk, n, blk):
        a0, b0 = max(s0, 0), min(s0 + 2 * blk, n)
        out[a0:b0] += lp(x[a0:b0] * win[a0 - s0:b0 - s0], fcs[min(max(s0 + blk, 0), n - 1)], order, zero=True)
    return out


def dip(x, f, q, db):
    """`x` with a narrow band round `f` (Hz, `q` its sharpness) lowered by `db` dB (a recording's own ring tamed, not
    taken out), zero-phase."""
    b, a = signal.iirpeak(f, q, SR)
    return x - (1 - 10 ** (-db / 20)) * signal.filtfilt(b, a, x)


def fades(x, a, b):
    """`x` faded in over `a` s and out over `b` s (sine-squared)."""
    ka, kb = int(a * SR), int(b * SR)
    if ka:
        x[:ka] *= np.sin(np.linspace(0, np.pi / 2, ka)) ** 2
    if kb:
        x[-kb:] *= np.cos(np.linspace(0, np.pi / 2, kb)) ** 2
    return x


def glass_front(key, t_on, keep, close=0.06, to=1600.0, rate=1.0):
    """The front of a real glass break: from 3 ms before its onset (`t_on`, s, found by eye on its spectrogram) for
    `keep` s, read at `rate`, its top (to 10 kHz) let through for its first instant and closed down to `to` Hz by `close` s
    (the ring and the tinkle eased off: one pop, never a shatter)."""
    on = onset(key, t_on)
    y = cut(key, on - 0.003, on + keep / rate + 0.01, fade=0.002)
    if rate != 1.0:
        y = slow(y, rate)
    m = len(y)
    y = np.concatenate([y, np.zeros(256 - m % 256 + 256)])       # (whole blocks for the moving filter)
    u = np.arange(len(y)) / SR - 0.003
    fc = to + (10000.0 - to) * (1 - smooth(u / close)) ** 2
    return moving_lp(y, fc, 256, 2)[:m]


def room(x, decay, fc, wet, seed):
    """`x` with a short dark room after it: a synthesised reflection tail (noise dying over `decay` s, under `fc` Hz),
    `wet` of it."""
    n = int(decay * 5 * SR)
    ir = rng(seed).standard_normal(n) * np.exp(-np.arange(n) / SR / decay)
    ir[:int(0.006 * SR)] = 0.0                    # (its first reflections a few metres off)
    ir = lp(ir, fc, 2, zero=True)
    ir = ir / np.sqrt(np.sum(ir * ir))
    tail = signal.fftconvolve(x, ir)[:len(x)]
    return x + tail * wet * np.sqrt(np.mean(x * x)) / (np.sqrt(np.mean(tail * tail)) + 1e-12)


def pop():
    """The peel's pop and the air pulled away (its hit `PEEL_LEAD` in, 0.62 s): a window's break, its front alone
    (its body 200-600 Hz, its rings at 1.5, 2.2 and 3 kHz lowered, its top eased down to 1.4 kHz by 50 ms, gone in a
    tenth of a second), then a smooth pull of real air away from it: a bamboo stick's whoosh past its loudest, slowed to 0.7
    of its speed (its tone lowered), darkened (its low-pass closing from 1 kHz to 400 Hz), swelling in from 15 ms after
    the pop, 3 dB under it, gone by about half a second. Nothing under 140 Hz."""
    lead = PEEL_LEAD
    d = lead + 0.58
    n = int(d * SR)
    u = np.arange(n) / SR - lead
    gl = glass_front("gwindows", 0.13, 0.3, 0.05, 1400.0)
    gl = dip(dip(dip(gl, 2982.0, 8.0, 20.0), 2207.0, 8.0, 10.0), 1529.0, 8.0, 10.0)
    gl = place(n, gl, lead - 0.003) * np.exp(-np.maximum(u - 0.02, 0) / 0.04)
    aw = dip(slow(cut("bamboo", 0.15, 0.62, fade=0.01), 0.7), 452.0 * 0.7, 6.0, 8.0)
    aw = place(n, aw, lead + 0.015)
    aw = moving_lp(aw, 400.0 + 600.0 * np.exp(-np.maximum(u, 0) / 0.15), 512, 2)
    aw = aw * np.where(u < 0.015, 0.0, np.sin(0.5 * np.pi * np.clip((u - 0.015) / 0.06, 0, 1)) ** 2
                       * 10 ** (np.interp(u, [0.0, 0.08, 0.2, 0.4, 0.58], [0.0, 0.0, -8.0, -24.0, -60.0]) / 20))
    r_p = np.sqrt(np.mean(gl[int(lead * SR):int((lead + 0.03) * SR)] ** 2)) + 1e-12
    r_a = np.sqrt(np.mean(aw[int((lead + 0.06) * SR):int((lead + 0.16) * SR)] ** 2)) + 1e-12
    x = gl / r_p + aw / r_a * 10 ** (-3 / 20)
    x = hp(lp(x, 9000.0, 4, zero=True), 140.0, 4, zero=True)
    return fades(x, 0.004, 0.1)


# the glass's own body after the pop: its partials (Hz, dB re the strongest) measured on the window's spectrum in its
# first 0.14-0.4 s after its onset (220 Hz-1.7 kHz, Welch), the rings `pop` lowers left out or lowered the same
RING_MODES = [(301, -3), (366, -1), (420, -3), (474, -4), (522, -2), (571, -1), (662, 0), (738, -1), (980, -6)]


def glass_ring(n, hit, drive, modes, tau0, level, ref, seed, room_wet=0.3, fc_end=None):
    """The glass ringing on after its pop, `n` samples with the pop at `hit` s: the recording's own glass (`drive`, from
    its onset, laid at `hit`) through a bank of its partials (`modes`), each a two-pole resonator dying in `tau0` s at
    350 Hz and sooner higher up (as the square root of the frequency), tilted 3 dB an octave down over 500 Hz (warm);
    so it is the recording's ring, its shards and grit left behind (each resonator a few Hz wide). Eased in from 5 to
    35 ms after the pop (the pop itself as it was), at `level` dB re `ref` (the pop's first 30 ms) over 0.1-0.2 s after
    it, with a little dark room (0.12 s, under 1.4 kHz); `fc_end` (Hz): its top closing to that by 0.5 s (drawing away)."""
    u = np.arange(n) / SR - hit
    ex = place(n, bp(drive, 250.0, 1700.0, 2, zero=True), hit)
    ex = ex * np.exp(-np.maximum(u, 0) / 0.08)
    ring = np.zeros(n)
    for f, db in modes:
        tau = tau0 * np.sqrt(350.0 / f)
        r = np.exp(-1.0 / (tau * SR))
        y = signal.lfilter([1.0 - r], [1.0, -2 * r * np.cos(2 * np.pi * f / SR), r * r], ex)
        y = y / (np.sqrt(np.mean(y[int(hit * SR):int((hit + 0.06) * SR)] ** 2)) + 1e-12)
        ring += y * 10 ** ((db - 3.0 * max(np.log2(f / 500.0), 0.0)) / 20)
    ring = ring * np.sin(0.5 * np.pi * np.clip((u - 0.005) / 0.03, 0, 1)) ** 2
    ring = room(ring, 0.12, 1400.0, room_wet, seed)
    if fc_end is not None:
        k = 512 - n % 512
        ring = moving_lp(np.concatenate([ring, np.zeros(k)]),
                         np.concatenate([fc_end + (1800.0 - fc_end) * (1 - smooth(np.clip(u / 0.5, 0, 1))), np.full(k, fc_end)]), 512, 2)[:n]
    ring = hp(lp(ring, 1800.0, 4, zero=True), 200.0, 2, zero=True)
    lv = np.sqrt(np.mean(ring[int((hit + 0.1) * SR):int((hit + 0.2) * SR)] ** 2)) + 1e-12
    return ring / lv * ref * 10 ** (level / 20)


def peel():
    """The sixth star popping out of the HUD (its hit `PEEL_LEAD` in, 1.0 s): `pop` to the pop and its pull of air, and
    under the pull the window's own partials (300 Hz-1 kHz) ringing out of the pop (`glass_ring`), 18 dB under it a
    tenth of a second on, darkening as it goes (its top closing from 1.8 kHz to 700 Hz by half a second, as if drawn
    away with the air), dying over about 0.7 s."""
    lead = PEEL_LEAD
    on = onset("gwindows", 0.13)
    drive = cut("gwindows", on - 0.003, on + 0.3, fade=0.002)
    x = pop()
    n = int((lead + 0.96) * SR)
    x = np.concatenate([x, np.zeros(max(n - len(x), 0))])[:n]
    ref = np.sqrt(np.mean(x[int(lead * SR):int((lead + 0.03) * SR)] ** 2))
    x = x + glass_ring(n, lead, drive, RING_MODES, 0.15, -18.0, ref, 2713, fc_end=700.0)
    return fades(x, 0.004, 0.12)


def flight():
    """The star flying off into the sky and hanging there burning (from 8.25, 7.25 s, to 15.5: under `fall`'s quiet
    opening till it has risen to meet it). As it flies (8.3-10.35) a smooth rush of air following it up and away: the band over 180 Hz
    of a real fire's roar (no crackle in it), two stretches of it summed so it doesn't flicker, read faster as the star
    lifts away (its pitch rising to 8.85) and slower as it recedes (its Doppler falling, two-thirds of an octave under
    its peak by 10.35), its top opening to 2.2 kHz and closing to 380 Hz; a stick's whoosh slowed to about half its
    speed and darkened swelling out of the pop under it. As it turns into the burning star and hangs (10.35-11.2) a low warm swell growing under it
    (D1, A1 and D2, the climb's drone, softly saturated for their harmonics, and the fire's own low body) and a first
    breath of fire (its 150-900 Hz) coming up into the fall, both held under its opening and fading over 13.5-15.5."""
    d = FLIGHT_LEN
    n = int(d * SR)
    t = FLIGHT + np.arange(n) / SR

    def curve(pts, w=0.15, db=False, tt=t):
        """A curve through (strike seconds, value) points at `tt`, its corners rounded over `w` s (in dB if `db`)."""
        y = np.interp(tt, *zip(*pts))
        k = int(w * SR) | 1
        h = np.hanning(k)
        y = np.convolve(np.pad(y, k // 2, mode="edge"), h / h.sum(), "valid")
        return 10 ** (y / 20) if db else y

    # ---- the rush (to RUSH_END)
    nr = int((RUSH_END - FLIGHT) * SR)
    tr = t[:nr]
    rate = curve([(FLIGHT, 0.6), (8.85, 0.8), (9.6, 0.62), (LIFT_UP, 0.5), (RUSH_END, 0.46)], 0.3, tt=tr)
    a = vary(cut("fire", 6.0, 9.5, fade=0.05), rate, nr)
    b = vary(cut("fire", 13.0, 16.5, fade=0.05), rate, nr)
    rush = hp(unit(a) + unit(b), 180.0, 4, zero=True)
    rush = moving_lp(rush, curve([(FLIGHT, 500.0), (8.85, 2200.0), (9.4, 1600.0), (LIFT_UP, 650.0), (11.0, 380.0)], tt=tr),
                     512, 2)
    rush = unit(rush) * curve([(FLIGHT, -40.0), (8.3, -24.0), (8.6, -11.0), (8.9, -6.0), (9.3, -3.5), (9.9, 0.0),
                               (LIFT_UP, -1.0), (10.8, -3.5), (11.2, -9.0), (RUSH_END, -60.0)], db=True, tt=tr)
    rush = place(n, rush, 0.0)
    # ---- the launch: a stick's whoosh slowed (its pitch rising a little), darkened, swelling out of the pop
    m = int(1.0 * SR)
    sw = vary(cut("stick", 0.0, 0.55, fade=0.01), np.linspace(0.44, 0.54, m), m)
    sw = lp(hp(sw, 150.0, 2, zero=True), 1100.0, 4, zero=True)
    sw = place(n, unit(sw) * np.hanning(m), 0.1)
    # ---- the swell: D1, A1, D2, softly saturated, and the fire's low body, slowed
    u = np.arange(n) / SR
    tones = np.zeros(n)
    g = rng(2801)
    for root, amp in ((36.71, 1.0), (55.0, 0.55), (73.42, 0.45), (110.0, 0.3), (146.83, 0.22)):
        for v in range(3):
            fr = root * (1 + g.uniform(-0.003, 0.003))
            tones += np.sin(2 * np.pi * fr * u + g.uniform(0, 6.28)) * amp / 3
    tones = lp(saturate(tones, 2.2, 0.3), 400.0, 4, zero=True)
    body = lp(hp(slow(cut("fire", 2.0, 2.0 + d * 0.7 + 0.2, fade=0.05), 0.7)[:n], 30.0, 2, zero=True), 200.0, 4, zero=True)
    swell = (unit(tones) + unit(body) * 0.8) * curve([(FLIGHT, -70.0), (10.0, -26.0), (LIFT_UP, -14.0), (10.8, -7.0),
                                                      (11.2, -4.0), (11.6, -3.0), (12.5, -3.5), (13.5, -4.0),
                                                      (14.5, -6.5), (15.2, -16.0), (FLIGHT + d, -60.0)], 0.2, db=True)
    # ---- the first breath of fire
    br = sum(unit(slow(cut("fire", a0, a0 + d * 0.75 + 0.2, fade=0.05), 0.75)[:n]) for a0 in (9.0, 14.0))
    br = bp(br, 150.0, 900.0, 2, zero=True)
    br = unit(br) * curve([(FLIGHT, -70.0), (10.5, -36.0), (10.9, -16.0), (11.2, -9.0), (11.6, -7.0), (12.5, -7.0),
                          (13.5, -9.0), (14.5, -14.0), (15.2, -25.0), (FLIGHT + d, -60.0)], 0.2, db=True)
    x = rush + sw * 10 ** (FLIGHT_MIX["launch"] / 20) + swell * 10 ** (FLIGHT_MIX["swell"] / 20) \
        + br * 10 ** (FLIGHT_MIX["breath"] / 20)
    x = hp(x, 20.0, 2)
    return fades(x, 0.03, 0.1)


FLIGHT_MIX = {"launch": -9.0, "swell": 0.0, "breath": -4.0}     # (dB re the rush's peak)


def fall():
    """The star hanging over the target and falling on it: 5.8 s from 11.2, ending on the impact."""
    d = HIT - HANG
    n = int(d * SR)
    t = np.arange(n) / SR
    fall_t = HIT - DROP
    tau = np.clip((t - (DROP - HANG)) / fall_t, 0, 1)          # (0 hanging, 1 striking)
    near = tau ** 1.7
    # (louder as it comes, its top opening, its pitch rising)
    level = 10 ** ((-15.0 + 15.0 * near) / 20)
    fc = 500.0 + 3000.0 * near ** 1.3
    rate = 1.0 + 0.2 * tau ** 2.2
    # ---- the burning mass: fire and rocket roar slowed for size, rising in pitch as it comes
    fire = vary(slow(cut("fire", 0.5, 19.5, fade=0.1), 0.7), 0.95 * rate, n)
    roar = vary(slow(cut("rocket", 0.0, 6.0, fade=0.05), 0.72), rate, n)
    core = unit(fire) * 0.8 + unit(roar)
    out = np.zeros(n)
    blk = 2048
    win = np.hanning(2 * blk)
    for s in range(-blk, n, blk):
        a, b = max(s, 0), min(s + 2 * blk, n)
        seg = core[a:b] * win[a - s:b - s]
        out[a:b] += lp(seg, fc[min(max(s + blk, 0), n - 1)], 2, zero=True)
    core = unit(out) * surges(n, 1.8, 1.5, 501)
    # ---- burning blocks shed off it: flame bursts flaring and gone, a few, more as it falls
    flare = np.zeros(n)
    g = rng(502)
    f_on = [onset("flame", a) for a in (4.45, 30.0, 56.9)]
    for k, tf in enumerate([0.9, 1.9, 2.7, 3.3, 3.9, 4.4, 4.9]):
        s0 = f_on[k % 3] + g.uniform(0.3, 6.0)
        y = slow(cut("flame", s0, s0 + 1.2, fade=0.08), 0.6)
        y = unit(lp(y, 1600.0, 2, zero=True)) * np.hanning(len(y)) ** 0.7
        flare += place(n, y, tf, 0.35 + 0.1 * k)
    flare *= level
    # ---- its mass in the air: a low roar under it and a tone of 30 Hz rising to 46
    low = unit(lp(rng(503).standard_normal(n), 70.0, 4, zero=True)) * surges(n, 2.5, 1.2, 504)
    ph = 2 * np.pi * np.cumsum(30.0 + 16.0 * tau ** 2) / SR
    mass = low + np.sin(ph) * 0.8 * np.sqrt(np.mean(low * low)) * 1.4
    mass = mass * 10 ** ((-20.0 + 20.0 * near) / 20)
    x = core * level + flare * 0.5 + mass * 0.55
    # ---- up in the sky while it is high: its sound coming back off the land, less as it comes down
    far = land_echoes(x, 505, 0.25, 2.2, 30, 1.2, 900.0, 1.0) - x
    x = x + far * env(n, [(0.0, 0.7), (DROP - HANG, 0.6), (d - 1.5, 0.25), (d, 0.15)])
    # (the hang's start eased in under the peel; the last 8 ms let go)
    x = x * env(n, [(0.0, 0.0), (0.4, 1.0), (d, 1.0)])
    x = hp(x, 20.0, 2)
    x[-int(0.008 * SR):] *= np.linspace(1, 0, int(0.008 * SR))
    return x


def ground():
    """The shock through the ground (its hit 0.03 s in): felt more than heard."""
    d = 8.0
    n = int(d * SR)
    q0 = onset("quake", 5.07)
    q = slow(cut("quake", q0, q0 + d * 0.8, fade=0.004), 0.8)[:n]
    q = place(n, unit(lp(hp(q, 18.0, 2), 160.0, 4)), GROUND_LEAD)
    th = saturate(boom(n, GROUND_LEAD, 48.0, 18.0, 0.18, 0.025, 0.7, 601, body=0.6), 1.6)
    roll = unit(lp(rng(602).standard_normal(n), 60.0, 4, zero=True)) * surges(n, 3.0, 2.5, 603)
    roll *= env(n, [(0.0, -60.0), (GROUND_LEAD + 0.05, -60.0), (0.4, -6.0), (1.5, -9.0), (4.0, -18.0), (d, -60.0)], db=True)
    x = th + q * 0.8 * np.sqrt(np.mean(th[:int(0.6 * SR)] ** 2)) / (np.sqrt(np.mean(q[:int(0.6 * SR)] ** 2)) + 1e-12)
    x = x + roll * np.sqrt(np.mean(th[:int(0.6 * SR)] ** 2)) * 0.8
    # (the land's own body shaken: 80-300 Hz of the earthquake, in its first second and a half)
    body = unit(bp(q, 80.0, 300.0, 2)) * env(n, [(0.0, 0.0), (GROUND_LEAD, 0.0), (GROUND_LEAD + 0.06, 1.0), (0.8, 0.7), (1.6, 0.25), (3.0, 0.0), (d, 0.0)])
    x = x + body * np.sqrt(np.mean(th[:int(0.6 * SR)] ** 2)) * 0.6
    x = lp(x, 500.0, 2)
    x[-int(0.5 * SR):] *= np.linspace(1, 0, int(0.5 * SR))
    return x


# The blast's roar: octave levels (dB, 31.5 Hz .. 16 kHz) over the seconds after the air's front reaches the player.
# Measured on REFS (four of the eleven large explosions, the first 6 s of each) and on the dynamite recording: those
# have 125-250 Hz loudest, the top falling away fast after 150 ms, a level held for about a second and 6 dB down by 2
# s; this is much bigger, so the 31.5-63 Hz octaves are raised (the references' microphones barely took them) and it
# holds longer and rolls on for 20 s. The top (2 kHz up) is kept 26, 32 and 40 dB under the whole after 150 ms; what
# is heard there comes from the recordings (thunder rolls, the fire) instead of shaped noise.
BLAST_T = np.array([0.0, 0.03, 0.08, 0.18, 0.45, 0.9, 1.6, 2.7, 4.5, 7.5, 11.0, 16.0, 21.5])
BLAST_DB = np.array([
    # 31.5   63    125   250   500    1k    2k    4k    8k   16k
    [-40.0, -40.0, -40.0, -40.0, -40.0, -40.0, -60.0, -70.0, -80.0, -90.0],
    [-10.0, -5.0, -4.0, -6.0, -9.0, -14.0, -30.0, -40.0, -52.0, -66.0],
    [-8.0, -3.0, -2.0, -4.0, -7.0, -12.0, -22.0, -32.0, -44.0, -60.0],
    [-7.0, -3.0, -2.5, -5.0, -9.0, -14.5, -24.0, -33.0, -45.0, -62.0],
    [-6.0, -3.0, -3.0, -6.0, -10.5, -16.0, -26.0, -35.0, -48.0, -66.0],
    [-6.0, -3.5, -4.0, -7.5, -12.0, -17.5, -28.0, -38.0, -52.0, -70.0],
    [-7.0, -5.0, -6.5, -10.0, -15.0, -20.5, -31.0, -42.0, -56.0, -74.0],
    [-9.0, -7.5, -9.5, -13.5, -18.5, -24.0, -35.0, -47.0, -60.0, -78.0],
    [-12.0, -11.0, -13.5, -18.0, -23.5, -29.0, -40.0, -52.0, -64.0, -80.0],
    [-16.0, -15.5, -18.5, -23.5, -29.0, -35.0, -46.0, -58.0, -70.0, -84.0],
    [-21.0, -21.0, -24.0, -29.5, -35.0, -41.0, -52.0, -64.0, -76.0, -88.0],
    [-29.0, -30.0, -33.0, -38.5, -44.0, -50.0, -61.0, -72.0, -82.0, -92.0],
    [-48.0, -50.0, -54.0, -60.0, -66.0, -72.0, -80.0, -88.0, -94.0, -100.0]])
# the front's parts against the boom's 63 Hz octave over its first 0.4 s (dB: the roar's 125 Hz octave, the knock's
# 250 Hz, the second blow's 63 Hz, the heave's 250 Hz), the rolls against the roar over 1-3 s, and how far the roar
# sits under the hit
FRONT_MIX = {"body": -12.0, "knock": -11.0, "boom2": -7.0, "heave": -12.0}
ROLL_MIX = {"fire": -5.0, "dust": 5.0, "thunder2": 7.0, "thunder1": 1.0, "bed": 5.0}
ROAR_UNDER = 5.0
BLAST_ROUND = 4.5                       # (the hit's peaks rounded off this far over its loudest 400 ms)


def blast_near(parts=None):
    """The blast reaching the player (its front 0.02 s in), 22 s. The front (the first 0.6 s: the knock, the boom,
    the fireball's heave a third of a second on) is its loudest moment; the roar after it sits ROAR_UNDER dB under,
    heaving, rolling on for seconds."""
    d = 22.0
    n = int(d * SR)
    t = np.arange(n) / SR
    t0 = BLAST_LEAD
    u = np.maximum(t - t0, 0)
    # ---- the roar, shaped to the table, its mids and top boiling unevenly
    body = shaped(d, BLAST_T + t0, BLAST_DB, 701)
    hi = hp(body, 250.0, 2)
    boil = surges(n, 2.6, 4.0, 702) * surges(n, 1.2, 14.0, 703)
    body = body - hi + hi * (1 + (boil - 1) * np.clip((u - 0.25) / 0.4, 0, 1))

    def oct_at(y, k, a, b):
        return oct_levels(y, t0 + a, t0 + b)[k]
    # ---- the boom: 62 Hz falling to 24 over a third of a second, broad, overdriven (the bigger the blast the more):
    # what every other part of the front is set against (its 63 Hz octave over the first 0.4 s)
    bm = boom(n, t0, 62.0, 24.0, 0.3, 0.018, 1.1, 704, body=0.55, hold=0.15)
    bm = saturate(bm, 2.4, 0.35)
    ref = oct_at(bm, 1, 0.0, 0.4)

    def put(y, k, a, b, rel):
        return y * 10 ** ((ref + rel - oct_at(y, k, a, b)) / 20)
    body = put(body, 2, 0.1, 0.5, FRONT_MIX["body"])
    # ---- the front: the low knock of the real dynamite blast, slowed to this size, nothing over 1.1 kHz
    k0 = onset("dynamite", 0.05)
    kn = slow(cut("dynamite", k0, k0 + 2.5 * 0.55, fade=0.004), 0.55)
    kn = place(n, lp(hp(kn, 25.0, 2), 1100.0, 4), t0)
    kn = put(kn, 3, 0.0, 0.3, FRONT_MIX["knock"])
    # ---- the fireball's heave a third of a second on: a second, lower blow, and the demolition's second blast
    bm2 = put(saturate(boom(n, t0 + 0.32, 46.0, 25.0, 0.25, 0.04, 0.8, 705, body=0.5), 1.8), 1, 0.3, 0.8, FRONT_MIX["boom2"])
    m0 = onset("merrimack", 10.05)
    hv = slow(cut("merrimack", m0, m0 + 3.0 * 0.5, fade=0.004), 0.5)
    hv = put(place(n, lp(hp(hv, 25.0, 2), 900.0, 4), t0 + 0.3), 3, 0.3, 0.9, FRONT_MIX["heave"])
    front = body + kn + bm + bm2 + hv
    # ---- what rolls on after the front, each from real recordings (their cracks left out: the rolls only), set
    # against each other here and against the front below
    # the rolls: two real thunders slowed for size, from just after their cracks, faded in
    # (the first: its crack too, but slowed and come in a tenth of a second after the hit, its top eased in over a
    # fifth of a second: the brightness blooming inside the roar, never on the front)
    c2 = onset("thunder2", 0.65)
    th2 = slow(cut("thunder2", c2, c2 + 12.0 * 0.7, fade=0.004), 0.7)
    th2 = lp(hp(place(n, th2, t0 + 0.1), 700.0, 2), 6000.0, 2)
    th2 = ease_top(th2, int((t0 + 0.1) * SR), 0.2, 700.0) * env(n, [(0.0, 0.0), (t0 + 0.1, 0.0), (t0 + 0.18, 1.0), (d, 1.0)])
    c1 = onset("thunder1", 2.25, 0) + 0.25
    th1 = slow(cut("thunder1", c1, c1 + 15.0 * 0.62, fade=0.2), 0.62)
    th1 = lp(hp(place(n, th1, t0 + 0.9), 500.0, 2), 3500.0, 2) * env(n, [(0.0, 0.0), (t0 + 0.9, 0.0), (t0 + 1.6, 1.0), (d, 1.0)])
    # the fireball: a massive fire slowed, swelling in over half a second, roaring for seconds
    fb = loop(slow(cut("fire", 0.3, 19.8, fade=0.1), 0.55), n)
    fb = lp(hp(fb, 110.0, 2, zero=True), 2400.0, 2, zero=True) * surges(n, 2.0, 1.2, 706)
    fb = fb * env(n, [(0.0, -60.0), (t0 + 0.12, -30.0), (t0 + 0.7, 0.0), (5.0, -3.0), (9.0, -10.0), (15.0, -22.0), (d, -60.0)], db=True)
    # the dust wall flattening the forest: a real avalanche's roar, slowed, from half a second
    av = loop(slow(cut("avalanche", 3.0, 30.0, fade=0.1), 0.75), n)
    av = lp(hp(av, 60.0, 2, zero=True), 3500.0, 2, zero=True) * surges(n, 2.0, 0.8, 707)
    av = av * env(n, [(0.0, -60.0), (t0 + 0.35, -40.0), (t0 + 1.2, -3.0), (2.5, 0.0), (6.0, -4.0), (11.0, -14.0), (17.0, -30.0), (d, -60.0)], db=True)
    # the weight: 25-60 Hz heaving under it all for seconds
    bed = unit(bp(rng(708).standard_normal(n), 25, 60, 3, zero=True)) * surges(n, 3.0, 0.8, 709) * surges(n, 1.5, 4.0, 710)
    bed = bed * env(n, [(0.0, -60.0), (t0 + 0.25, -12.0), (t0 + 0.6, 0.0), (3.0, -2.0), (7.0, -7.0), (12.0, -15.0), (18.0, -28.0), (d, -60.0)], db=True)

    def lvl(y, lo, hi, a, b):
        return 20 * np.log10(np.sqrt(np.mean(bp(y, lo, hi, 2, zero=True)[int((t0 + a) * SR):int((t0 + b) * SR)] ** 2)) + 1e-12)
    # (their balance, by band, against the roar's 300 Hz-1.5 kHz over 1-3 s: the fire's 300 Hz-1.5 kHz there, the
    # dust's 600 Hz-2.5 kHz, the thunders' 1-4 kHz (the first's over 0.3-2 s, the second's 1.5-3.5); the bed's 25-60 Hz
    # against the roar's)
    ref_mid = lvl(body, 300, 1500, 1.0, 3.0)
    ref_low = lvl(body, 25, 60, 1.0, 3.0)
    fb *= 10 ** ((ref_mid + ROLL_MIX["fire"] - lvl(fb, 300, 1500, 1.0, 3.0)) / 20)
    av *= 10 ** ((ref_mid + ROLL_MIX["dust"] - lvl(av, 600, 2500, 1.0, 3.0)) / 20)
    th2 *= 10 ** ((ref_mid + ROLL_MIX["thunder2"] - lvl(th2, 1000, 4000, 0.3, 2.0)) / 20)
    th1 *= 10 ** ((ref_mid + ROLL_MIX["thunder1"] - lvl(th1, 1000, 4000, 1.5, 3.5)) / 20)
    bed *= 10 ** ((ref_low + ROLL_MIX["bed"] - lvl(bed, 25, 60, 1.0, 3.0)) / 20)
    rolls = th2 + th1 + fb + av + bed
    x = ease_top(front + rolls, int(t0 * SR), 0.07)      # (nothing bright on the front: its top in over 70 ms)
    # (the roar after the hit ROAR_UNDER dB under the hit's loudest 400 ms (its first 0.45 s) at its loudest, eased
    # down from 0.45 s over a fifth of a second if it would stand higher)
    f_l = loudest(x[:int((t0 + 0.45) * SR)])
    r_l = loudest(x[int((t0 + 0.45) * SR):])
    duck = min(0.0, f_l - ROAR_UNDER - r_l)
    x = x * 10 ** (duck * np.clip((u - 0.45) / 0.2, 0, 1) / 20)
    if parts is not None:
        parts.update(body=body, knock=kn, boom=bm, boom2=bm2, heave=hv, thunder2=th2, thunder1=th1, fire=fb, dust=av, bed=bed)
    # ---- the land answering: echoes off the hills and the trees, dark, from a fifth of a second to 3 s
    x = land_echoes(x, 711, 0.2, 3.0, 40, 1.4, 1500.0, 0.25)
    # (the front rounded off a little over its loudest 400 ms: an overloaded air, dense, so the peaks are the
    # front's and not a single sample's)
    x = hp(x, 20.0, 2)
    x = round_off(x, BLAST_ROUND, until=t0 + 0.6)
    x = x * (t >= t0 - 0.001)
    x[-int(1.0 * SR):] *= np.linspace(1, 0, int(1.0 * SR))
    return x


def blast_far_of(near, dist, seed, ease, echo_wet, echo_to):
    """The near blast heard through `dist` blocks of air: its top taken by the air (highs first), its front softened,
    the land's echoes longer and more of them."""
    n = len(near)
    t0 = BLAST_LEAD
    x = air(near, dist, 0.4 * dist / 1000)
    x = ease_top(x, int(t0 * SR), ease, 500.0)
    x = land_echoes(x, seed, 0.3, echo_to, 60, echo_to * 0.6, 900.0, echo_wet)
    x[-int(1.0 * SR):] *= np.linspace(1, 0, int(1.0 * SR))
    return x


def plough():
    """The five points tearing out across the land (hit at 0.0), 6 s."""
    d = 6.0
    n = int(d * SR)
    t = np.arange(n) / SR
    # (each: the recording and where in it, when it starts, when it stops)
    spec = [("avalanche", 4.0, 0.00, 2.35), ("landslide", 5.0, 0.04, 2.55), ("avalanche", 18.0, 0.07, 2.2),
            ("landslide", 15.0, 0.11, 2.45), ("soil", 0.3, 0.15, 2.0)]
    x = np.zeros(n)
    for k, (key, a, start, stop) in enumerate(spec):
        # (slowing down as it ploughs to a stop: its speed and pitch falling from 0.8 to 0.45)
        tt_ = np.clip((t - start) / (stop - start), 0, 1)
        rate = 0.8 - 0.35 * tt_ ** 1.2
        y = vary(cut(key, a, a + 8.0, fade=0.05), rate, n)
        y = hp(y, 35.0, 2, zero=True)
        y = lp(y, 600.0, 1) * 0.8 + lp(y, 2000.0, 2) * 0.3        # (a natural slope, no wall)
        e = np.where(t < start, 0.0, np.clip((t - start) / 0.06, 0, 1) ** 2)
        e = e * 10 ** (np.interp(t, [start, start + 0.3, stop * 0.8, stop, stop + 0.5, d], [0.0, 0.0, -5.0, -10.0, -45.0, -80.0]) / 20)
        y = unit(y) * e * (1.0 - 0.08 * k) * surges(n, 2.0, 3.0, 800 + k)
        # (and coming to rest: a low thud as it stops)
        y = y + boom(n, stop - 0.05, 52.0, 30.0, 0.1, 0.03, 0.35, 810 + k, body=0.5) * 0.6
        x += y
    churn = unit(bp(rng(820).standard_normal(n), 22, 80, 3, zero=True)) * surges(n, 3.0, 2.0, 821)
    churn *= env(n, [(0.0, -60.0), (0.08, -3.0), (1.6, -6.0), (2.6, -16.0), (3.4, -50.0), (d, -80.0)], db=True)
    x = x + churn * 0.9
    x = ease_top(x, 0, 0.07)
    x = hp(x, 20.0, 2)
    x = round_off(x, 6.0)
    x[-int(0.3 * SR):] *= np.linspace(1, 0, int(0.3 * SR))
    return x


def after():
    """The crater burning and the land rumbling (from 18 s), settling over 20 s; 30 s."""
    d = 30.0
    n = int(d * SR)
    fire = loop(slow(cut("fire", 0.3, 19.8, fade=0.1), 0.7), n, 2.5)
    fire = lp(fire, 2600.0, 2, zero=True) * surges(n, 2.0, 0.6, 901)
    fire = unit(fire) * env(n, [(0.0, -30.0), (1.5, 0.0), (8.0, -2.0), (16.0, -9.0), (24.0, -18.0), (29.0, -30.0), (d, -70.0)], db=True)
    rum = loop(slow(cut("geofon", 120.0, 120.0 + d * 0.75 + 1.0, fade=0.1), 0.75), n)
    rum = unit(lp(hp(rum, 20.0, 2, zero=True), 200.0, 4, zero=True)) * surges(n, 3.0, 0.5, 902)
    rum *= env(n, [(0.0, -2.0), (4.0, 0.0), (10.0, -6.0), (18.0, -14.0), (26.0, -26.0), (d, -60.0)], db=True)
    roll = slow(cut("dthunder", 0.0, 21.0, fade=0.1), 0.85)
    roll = place(n, unit(lp(roll, 500.0, 2, zero=True)), 0.0) * env(n, [(0.0, 0.0), (6.0, -4.0), (14.0, -14.0), (22.0, -30.0), (d, -60.0)], db=True)
    thuds = np.zeros(n)
    for k, (tk, f0) in enumerate([(2.6, 44.0), (5.9, 40.0), (9.8, 47.0), (14.5, 38.0)]):
        thuds += boom(n, tk, f0 * 1.3, f0 * 0.8, 0.15, 0.14, 0.7, 910 + k, body=0.6) * (0.9 - 0.15 * k)
    thuds = lp(thuds, 300.0, 2)
    x = fire * 0.8 + rum * 0.9 + roll * 0.55 + thuds * 0.3 * np.sqrt(np.mean(rum * rum)) / (np.sqrt(np.mean(thuds ** 2)) + 1e-12) * 3
    x = x * env(n, [(0.0, 0.0), (0.6, 1.0), (d, 1.0)])
    x = hp(x, 20.0, 2)
    x[-int(1.0 * SR):] *= np.linspace(1, 0, int(1.0 * SR))
    return x


# ================================================================================================= levels and files
def level_gain(x, db):
    """The gain that puts `x` (less its mean) at `db` over its loudest 400 ms, lowered further if that would put a peak
    over PEAK."""
    x = x - np.mean(x)
    g = 10 ** ((db - loudest(x)) / 20)
    pk = np.max(np.abs(x)) * g
    if pk > PEAK:
        g *= PEAK / pk
    return g


def set_level(x, db):
    """`x` with its loudest 400 ms at `db`, lowered further if that would put a peak over PEAK."""
    return (x - np.mean(x)) * level_gain(x, db)


def write_ogg(path, x):
    tmp = str(path) + ".tmp.wav"
    from scipy.io import wavfile
    wavfile.write(tmp, SR, (np.clip(x, -1, 1) * 32767).astype("<i2"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "7", "-fflags", "+bitexact",
                    "-flags:a", "+bitexact", str(path)], check=True)          # (bit-exact: a rebuild is byte-identical)
    os.remove(tmp)


def decode(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def build():
    files = {"climb": climb(), "sirens": sirens()}
    for i in range(6):
        files[f"star{i + 1}"] = star(i)
    files["peel"] = peel()
    files["flight"] = flight()
    files["fall"] = fall()
    files["ground"] = ground()
    near = blast_near()
    files["blast_near"] = near
    files["blast_mid"] = blast_far_of(near, 600.0, 721, 0.12, 0.45, 3.5)
    files["blast_far"] = blast_far_of(near, 1300.0, 722, 0.25, 0.7, 5.0)
    files["plough"] = plough()
    files["after"] = after()
    return levelled(files)


def levelled(files):
    """Every file at its `LEVEL`; the peel at the gain its pop alone gets there (`pop`: the ring after it leaves the
    pop's level as it was); the sirens at the gain and offset the approved ones get (`sirens_to_peel`: so they are the
    same to the join)."""
    out = {k: set_level(v, LEVEL[k]) for k, v in files.items() if k not in ("peel", "sirens")}
    if "sirens" in files:
        p = sirens_to_peel()
        out["sirens"] = (files["sirens"] - np.mean(p)) * level_gain(p, LEVEL["sirens"])
    if "peel" in files:
        p = pop()
        b = p - np.mean(p)
        out["peel"] = (files["peel"] - np.mean(files["peel"])) * np.max(np.abs(set_level(p, LEVEL["peel"]))) / np.max(np.abs(b))
    return out


# ================================================================================================= the game's mixer
def cue_sheet(dist, tier="near"):
    """(when, file, volume) for a player `dist` blocks from the target."""
    cues = [(0.0, "climb"), (SIRENS_AT, "sirens")] + [(s, f"star{i + 1}") for i, s in enumerate(STARS)]
    cues += [(PEEL - PEEL_LEAD, "peel"), (FLIGHT, "flight"), (HANG, "fall"), (HIT + dist / GROUND_V - GROUND_LEAD, "ground"),
             (HIT + dist / AIR_V - BLAST_LEAD, f"blast_{tier}"), (HIT + dist / AIR_V, "plough"), (AFTER, "after")]
    return [(t, f, VOLUME[f]) for t, f in cues]


def game_mix(files, cues, length=END):
    """The cues summed as the game plays them: each voice 0.596 a side, the buffer limiter only over full scale."""
    n = int(length * SR)
    raw = np.zeros(n)
    for t0, f, v in cues:
        raw += place(n, files[f], t0, v)
    y = raw * 0.596
    out = np.empty_like(y)
    lvl = 1.0
    rel = np.exp(-1.0 / (0.2 * SR))
    worst = 0.0
    for b in range(0, n, 1024):
        blk = y[b:b + 1024]
        peak = max(1.0, np.abs(blk).max())
        lvl = max(lvl, peak)
        idx = np.arange(len(blk))
        g = 1.0 / np.maximum(lvl * rel ** idx, peak)
        lvl = max(lvl * rel ** len(blk), peak)
        out[b:b + 1024] = blk * g
        if 20 * np.log10(g.min()) < worst:
            worst, game_mix.at = 20 * np.log10(g.min()), b / SR
    return out, worst


def checks(files, mixes, mix_at):
    print(f"\n{'file':11s} {'len s':>6s} {'loud.4':>7s} {'peak':>6s} | after 150 ms, dB re whole: 2-4k 4-8k 8-16k")
    for k, x in files.items():
        hit = {"ground": GROUND_LEAD, "blast_near": BLAST_LEAD, "blast_mid": BLAST_LEAD, "blast_far": BLAST_LEAD, "peel": PEEL_LEAD}.get(k, 0.0)
        seg = x[int((hit + 0.15) * SR):int((hit + 1.3) * SR)] if k.startswith(("star", "blast", "ground", "plough", "peel")) else x[int(0.15 * len(x)):int(0.85 * len(x))]
        tot = 10 * np.log10(np.mean(seg * seg) + 1e-20)
        bands = [10 * np.log10(np.mean(bp(seg, lo, hi, 4, zero=True) ** 2) + 1e-20) - tot for lo, hi in ((2000, 4000), (4000, 8000), (8000, 16000))]
        flag = "  TOP" if bands[0] > -26 or bands[1] > -32 or bands[2] > -40 else ""
        print(f"{k:11s} {len(x) / SR:6.2f} {loudest(x):7.1f} {20 * np.log10(np.abs(x).max()):6.1f} | {bands[0]:17.1f} {bands[1]:5.1f} {bands[2]:5.1f}{flag}")
    for dist, (g, worst) in mixes.items():
        def l4(a, b):
            return loudest(g[int(a * SR):int(b * SR)])
        bt = HIT + dist / AIR_V
        pre = l4(0.0, HIT)
        g0 = g[:int(HIT * SR)]; k4 = int(0.4 * SR); cc = np.cumsum(np.concatenate([[0.0], g0 * g0]))
        pre_at = np.argmax(cc[k4:] - cc[:-k4]) / SR
        bl = l4(bt - 0.05, bt + 1.5)
        frames = [10 * np.log10(np.mean(g[int(s * SR):int((s + 0.1) * SR)] ** 2) + 1e-20) for s in np.arange(bt - 2.0, bt, 0.1)]
        stars = [l4(s, s + 0.9) for s in STARS]
        print(f"\nfrom {dist} blocks: limiter worst {worst:.1f} dB (at {mix_at[dist]:.2f} s); blast's loudest 400 ms {bl:.1f} dB, everything before it "
              f"{pre:.1f} at {pre_at:.1f} s ({bl - pre:+.1f}); the 2 s before it {min(frames):.1f}..{max(frames):.1f} dB (100 ms frames); "
              f"stars {' '.join(f'{s:.1f}' for s in stars)}; peel {l4(PEEL, PEEL + 2):.1f}, fall's last second {l4(HIT - 1, HIT):.1f}, "
              f"plough {l4(bt + 0.5, bt + 2.6):.1f}, after (25-30 s) {l4(25, 30):.1f}")


def mp3(path, x):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-b:a", "256k", str(path)],
                   input=np.asarray(x, dtype="<f4").tobytes(), check=True)


def main():
    global SRC
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", help="the recordings' folder(s), colon-separated (default: SS_SOUND_SRC)")
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"), help="the resource pack to write into")
    ap.add_argument("--review", help="also write mp3s of every file and the game mixdowns into this folder")
    ap.add_argument("--cuts", help="write the recordings' cuts (key, from, to) to this file")
    a = ap.parse_args()
    if a.src:
        SRC = [Path(p) for p in a.src.split(":")]
    files = build()
    snd = Path(a.out) / "assets" / "orbital" / "sounds" / TH
    snd.mkdir(parents=True, exist_ok=True)
    for nm, x in files.items():
        write_ogg(snd / f"{nm}.ogg", x)
    decoded = {nm: decode(snd / f"{nm}.ogg") for nm in files}
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text()) if path.exists() else {}
    for ev in [e for e in sounds if e.startswith(f"{TH}.")]:
        sounds.pop(ev)
    for nm in FILES:
        base = "star" if nm.startswith("star") else ("blast" if nm.startswith("blast") else nm)
        sounds[f"{TH}.{nm}"] = {"sounds": [{"name": f"orbital:{TH}/{nm}", "attenuation_distance": 256}],
                               "subtitle": f"subtitles.orbital.{TH}.{SUBTITLE[base]}"}
    path.write_text(json.dumps(sounds, indent=2))
    mixes, mix_at = {}, {}
    for d in (150, 400):
        game_mix.at = 0.0
        mixes[d] = game_mix(decoded, cue_sheet(d))
        mix_at[d] = game_mix.at
    checks(decoded, mixes, mix_at)
    if a.cuts:
        Path(a.cuts).write_text("".join(f"{k} {x:.3f} {y:.3f}\n" for k, x, y in sorted(set(CUTS))))
    if a.review:
        rv = Path(a.review)
        rv.mkdir(parents=True, exist_ok=True)
        for nm, x in decoded.items():
            mp3(rv / f"{nm}.mp3", x)
        for d, (g, _) in mixes.items():
            mp3(rv / f"mix_{d}_blocks.mp3", g[:int(50 * SR)])
    print(f"\n{len(files)} files in {snd}")


if __name__ == "__main__":
    main()
