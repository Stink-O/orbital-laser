"""The Colossi's sounds (five stone giants ~220 blocks tall, green-cracked, in a ring 300 out from the target), all
synthesised here from noise, pulse trains, swept tones, combs and filters, nothing sampled, and none of it borrowed from
another laser's sounds: stone, earth and an old green energy, not fire or metal.

Timeline the files are built for, as mod/src/strike/colossi.rs plays them (strike seconds; the times are read out of
colossi.rs: T_RISE0, T_RISE_STEP, slam1(g) = SLAM0 + SLAM_STEP g + a little, SLAM2, T_BEAM0, CL_HIT, CHARGE, BURST,
BURST_STEP, T_SWEEP0, T_SWEEP_STEP, CL_SWEEP). `late(p)` = the player's distance from p / 343 (the air), `quick(p)` the
same over GROUND_V (the ground carries the lows five times faster). A giant's sounds come from that giant ("at g":
positioned, attenuation_distance in sounds.json), the middle's from the middle; the rest are heard everywhere.

  quake       T_RISE0 + quick(nearest giant): the earth splitting as the giants start up, then the ground heaving under
              all five as they rise (their heaves summed), heard through the ground; ~10 s
  rise1-3     at g, T_RISE0 + T_RISE_STEP g + late: giant g heaving itself out of the earth in the pass's catches
              (`cl_rise`: 5 heaves, legs, torso, head each grinding up in turn); ~8.6 s
  stamp1-3    at g, slam - 3.2 - STAMP_LEAD + late: the foot stamped down into the stance (`cl_stomps`); ~2.6 s
  heave1-3    at g (its shoulders), slam - HEAVE_AHEAD + late: the hammer hauled to the chest and pressed up over the
              shoulder in the pass's catches, the stone joints grinding and groaning under the load, hung there
              straining; ~3 s, fading out under the swing
  slam1-3     at g's slam point, slam - SLAM_LEAD + late: the swing's whoosh (SLAM_LEAD s), then the hammer into the
              ground: the blow, the earth crushed and split, the green energy cracking out through the land, the land's
              echoes; slam_far1-3 the same takes through a kilometre of air, cross-faded in by that point's distance
              (`far_mix`, 250 to 800 blocks); ~7 s. At SLAM2 all five again at SLAM2_VOL.
  slam_all    SLAM2 + quick(nearest slam point) - SLAM2_LEAD, everywhere: what the five together add, through the
              ground: a deeper blow, the land heaving and rolling under them, the cracks' energy joined; ~8 s
  beam        at the middle (on the ground), T_BEAM0 + late(middle): the cracks racing in to meet, charging,
              BEAM_LEN s up to the hit, cut on it
  ground      CL_HIT + quick(middle) - GROUND_LEAD: the blast through the ground, ahead of the air
  blast       CL_HIT + late(middle) - BLAST_LEAD: the explosion; blast_far cross-faded in by distance (`far_mix`)
  rumble      CL_HIT + late(middle) + RUMBLE_AFTER: the land rolling on, dying away by the sweeps; ~14 s
  charge1-3   at g (its arms), CHARGE + BURST_STEP g + late: the blast's light running up the hammer into the arms,
              the stone straining under it; peaks CH_PEAK s in, as its burst lands
  burst1-3    at g (its arms), BURST + BURST_STEP g - BURST_LEAD + late: hammer and arms bursting apart, the energy let
              go, the rock coming down; burst_far1-3 cross-faded in by distance; ~7 s
  settle1-3   at g, T_SWEEP0 + T_SWEEP_STEP g + late: the glowing line going down the giant over CL_SWEEP s, the stone
              setting into blocks behind it, the glow dying, a last settling; then silence; ~8.6 s

The takes: the mod gives giant g take (g + seed) % 3 + 1 and a pitch of its own (`take`), so five in a row are never
the same twice. Every file is mono (the game sums a file to mono anyway, and places the giants' sounds itself).

How each is made (rebuilt 2026-11-13 for weight: the first set measured as sine drops with almost nothing over 800 Hz,
a constant low wall from the rise to the sweeps with the blows barely 2-4 dB over it):

  blows       every blow (the slams, slam_all, the blast, the bursts, the stamps, the kneels, the pieces landing) is a
              `mass`: one dense blow of noise in half-octave bands, each with its own front (slower the lower it is: a
              shove, never a click) and two-stage decay (the upper bands dying sooner, so it darkens as real blows do),
              its weight flat from 40 Hz to its peak and the 100-800 Hz body full, measured against real blasts (a
              quarry blast and a demolition, CC0, measured only) for its balance in the first half second; a sub and
              a falling tone under it (the tone a support now, not the blow), the ground answering in slow rolling
              heaves (`surges`), the earth settling in a slow churning roar. No grit, crackle, crack, patter or ring.
  grinding    stone on stone as a deep churning pressure (`churn`: bands boiling slowly), the joints' groan (a jittered
              pulse train at 26-60 Hz through a rock-body kernel and a comb: a growl, never a creak); the land tearing
              (`rip`) is the same churn swelling, not crackle.
  the green   a low detuned chord (E1 family) swelling through a comb whose delay sweeps (a phasing, hollow, old sound),
              pitch falling as it spreads: arcane and huge, not a laser and not a choir.

Take C (the game's files for the hammer blows, slam_all, the blast and the bursts):
built on how stylised sound design lands a colossal hit (measured from reference recordings, never copied).
A vacuum just before the blow (the swing, the beam and the charge each sucked out to near silence for 0.12-0.16 s), a
front of 2-5 ms, a WALL held within 6 dB of its loudest for 2-4 s (`wall`, peak ~5 dB over its loudest 400 ms by
`press`), a held low boom falling slowly (`held_boom`), a falling body over the biggest, the ground shuddering in slow
pulses (`shudder`); no debris, patter, grit, crackle or ring. Each of the five characters is its own blow (SLAM_C:
boom pitch and fall, wall colour and hold, shudder rate, a second bite or not). The mass/surges blows above (take A)
are kept for the stamps, the kneels and the rest.

Take B of the slams, the blast and the bursts (`--takes`, never in the game files): the breaking rock from real
recordings (CC0 1.0, Freesound; RECORDINGS, read from $COLOSSI_REFS), high-passed, slowed and lowered, over the same
sub, ground, green and tail; the take's folder gets a NOTICE of which recording went where.

    python3 tools/sounds_colossi.py                  # writes orbital-sounds/assets/orbital/sounds/colossi/*.ogg, the
                                                     # colossi.* events in sounds.json and their subtitles (en_us)
    python3 tools/sounds_colossi.py --only slam      # one family (slam builds slam1-3 and slam_far1-3)
    python3 tools/sounds_colossi.py --listen DIR     # also MP3s of each file, and the whole strike heard from 100, 300
                                                     # and 700 blocks (WAV, MP3, a spectrogram), with every distance's
                                                     # true peak and the spectral balance
    python3 tools/sounds_colossi.py --takes DIR      # take B of the slams, blast and bursts (CC0 recordings) into DIR
                                                     # only, its NOTICE, the strike heard with them from 300 and 700
    python3 tools/sounds_colossi.py --stems DIR      # the layers of slam1, slam4, the blast and burst1 apart (take A;
                                                     # with --takes, take B's too)
"""
import argparse, json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.signal import fftconvolve, resample_poly
import soundlib
from soundlib import SR, band
import sounds_pk_blast as PB          # (utilities only: seeded, slow_random, causal_lowcut, limit, write_ogg)
import sounds_themes as T             # (utilities only: unit, loudest, fade)

TH = "colossi"
ROOT = Path(__file__).resolve().parent.parent
PEAK = 10 ** (-1.2 / 20)              # every file's decoded peak at most this
TP_MAX = 10 ** (-1.0 / 20)            # every distance's whole-strike mix: true peak under this (`--listen` checks)
TAKES = 3
SPEED = 343.0
GROUND_V = 5 * SPEED


# ---- the strike's times, read out of colossi.rs (so a shifted constant shifts the sounds too) --------------------------
def _rs():
    src = (ROOT / "mod/src/strike/colossi.rs").read_text()
    out = {}
    for name in ("T_RISE0", "T_RISE_STEP", "SLAM0", "SLAM_STEP", "SLAM2", "T_BEAM0", "CL_HIT", "CHARGE", "BURST",
                 "BURST_STEP", "T_SWEEP0", "T_SWEEP_STEP", "CL_SWEEP", "CL_LEN"):
        m = re.search(rf"const {name}: f32 = ([0-9.]+);", src)
        out[name] = float(m.group(1))
    for name in ("CL_K",):
        m = re.search(rf"const {name}: f64 = ([0-9.]+);", src)
        out[name] = float(m.group(1))
    m = re.search(r"const RING_DEG: \[f64; 5\] = \[([^\]]+)\]", src)
    out["RING_DEG"] = [float(v) for v in m.group(1).split(",")]
    return out


RS = _rs()
T_RISE0, T_RISE_STEP = RS["T_RISE0"], RS["T_RISE_STEP"]
SLAM2, T_BEAM0, CL_HIT = RS["SLAM2"], RS["T_BEAM0"], RS["CL_HIT"]
CHARGE, BURST, BURST_STEP = RS["CHARGE"], RS["BURST"], RS["BURST_STEP"]
T_SWEEP0, T_SWEEP_STEP, CL_SWEEP, CL_LEN = RS["T_SWEEP0"], RS["T_SWEEP_STEP"], RS["CL_SWEEP"], RS["CL_LEN"]
RING_R = 68.0 * RS["CL_K"]
SLAM_IN = 40.0 * RS["CL_K"]            # (the hammer comes down about this far in front of the giant, towards the middle)
CL_RISE = 6.5                          # (shaders/colossi.wgsl's)


def _hash(x, z, s):
    """colossi.rs's `hash`."""
    M = 0xFFFFFFFF
    h = ((x & M) * 0x8DA6B343 & M) ^ ((z & M) * 0xD8163841 & M) ^ ((s * 0xCB1AB31F) & M)
    h ^= h >> 16
    h = (h * 0x7FEB352D) & M
    h ^= h >> 15
    h = (h * 0x846CA68B) & M
    h ^= h >> 16
    return float(np.float32(h) * np.float32(1.0 / 4294967296.0))


def slam1(g):
    return RS["SLAM0"] + RS["SLAM_STEP"] * g + 0.12 * (_hash(g, 7, 3) - 0.5)


def swing_seconds(g):
    return 1.6 + 0.15 * _hash(g, 5, 3)


# ---- where the files put their moments (colossi.rs has the same numbers) -----------------------------------------------
STAMP_LEAD = 0.05
HEAVE_AHEAD = 3.4
SLAM_LEAD = 1.25
SLAM2_LEAD = 0.05
SLAM2_VOL = 0.85
BEAM_LEN = CL_HIT - T_BEAM0
GROUND_LEAD = 0.02
BLAST_LEAD = 0.02
RUMBLE_AFTER = 1.0
CH_PEAK = BURST - CHARGE
CH_VAC = 0.12                          # (take C: the charge sucked out this long before its burst)
BURST_LEAD = 0.03
QUAKE_LEAD = 0.05
REACH = 2048                           # attenuation_distance of what is placed (the game's linear roll-off to it)
SETTLE_REACH = 1200
REACH_OF = {"settle": SETTLE_REACH}
SLAM0_T = RS["SLAM0"]
# (the heave is played faster or slower with the giant's wind-up (`leads`: 0.7-1.25), its pitch times lead^-HEAVE_FOLLOW,
# and started so its catch, HEAVE_CATCH s before the blow at lead 1, lands where the pass has it)
HEAVE_CATCH = 2.32
HEAVE_FOLLOW = 0.5
# (the blows: a take for each of the five characters (`CHARACTER` in colossi.rs: eager, stiff, showy, brute, wary), each
# played at its own pitch, a percent or two of jitter on it)
SLAM_PITCH = (1.04, 1.0, 0.97, 0.93, 1.01)
# (the kneel: the pass's weight `w` goes from the burst + 0.2 s to CL_SETTLE in three catches, the knee down at KNEE_F of
# the way (w 0.82), the shudder gone by 0.97 of it; the file puts the knee KNEE_LEAD s in)
KNEE_F = 0.74
KNEE_LEAD = 0.9
VOL = {"quake": 1.0, "rise": 0.75, "stamp": 0.75, "heave": 0.75, "slam": 0.65, "slam_all": 1.0, "beam": 1.0, "ground": 1.0,
       "blast": 1.0, "rumble": 1.0, "charge": 0.42, "burst": 0.3, "kneel": 0.3, "settle": 1.0}


def rng():
    return soundlib.rng


# ================================================================================================  shared building blocks
def nz(n):
    return rng().standard_normal(n)


def tilted(n, lo, hi, slope=-3.0):
    """Noise between lo and hi Hz with a spectral tilt of `slope` dB an octave (unit RMS)."""
    X = np.fft.rfft(nz(n))
    f = np.maximum(np.fft.rfftfreq(n, 1 / SR), 1.0)
    X *= (f / 100.0) ** (slope / 6.02)
    return T.unit(band(np.fft.irfft(X, n), lo, hi, 2))


def after(t, t0):
    return np.maximum(t - t0, 0.0), t >= t0


def ar(t, t0, att, dec):
    """An attack-decay envelope from t0."""
    u, on = after(t, t0)
    return (1 - np.exp(-u / att)) * np.exp(-u / dec) * on


def sweep_tone(t, t0, f0, f1, tau, parts=((1, 1.0),), detune=0.0, phase=None):
    """A tone gliding from f0 to f1 Hz (exponentially, `tau` s) from t0, with partials (ratio, amplitude)."""
    u, on = after(t, t0)
    f = (f1 + (f0 - f1) * np.exp(-u / tau)) * (1 + detune)
    ph = 2 * np.pi * np.cumsum(f * on) / SR + (rng().uniform(0, 6.28) if phase is None else phase)
    return sum(a * np.sin(r * ph + k) for k, (r, a) in enumerate(parts)) * on


def drive_lows(x, amount, lo=80, hi=500, cut=140):
    """The lows' own harmonics (a soft drive of what is under `cut`), banded lo-hi, added: weight on small speakers."""
    low = band(x, None, cut, 3)
    c = np.percentile(np.abs(low), 99.7) * 0.35 + 1e-12
    return x + band(np.tanh(low / c) * c, lo, hi, 2) * amount


def kernel(m_s, lo, hi, tau, att=0.0015):
    """A short burst of band-limited noise (a rock body struck): its impulse response."""
    m = int(m_s * SR)
    s = np.arange(m) / SR
    k = band(nz(m), lo, hi, 2) * (1 - np.exp(-s / att)) * np.exp(-s / tau)
    return k / (np.sqrt(np.sum(k ** 2)) + 1e-12)


def fconv(x, k):
    return fftconvolve(x, k)[:len(x)]


def comb(x, delay_s, gains=(0.75, 0.55, 0.38, 0.25)):
    """`x` with copies of itself at multiples of a (time-varying) delay: a hollow resonance at 1/delay and its
    harmonics, phasing as the delay moves."""
    n = len(x)
    d = np.broadcast_to(np.asarray(delay_s, dtype=float), (n,)) * SR
    idx = np.arange(n, dtype=float)
    out = x.copy()
    for k, gk in enumerate(gains, 1):
        out += gk * np.interp(idx - k * d, idx, x, left=0.0)
    return out


def groan(t, f0, amount, seed_jit=0.08):
    """A huge stone joint groaning under load: a pulse train at f0 Hz (26-60), jittered in period and size, through a low
    rock-body kernel and a comb on f0: a growl, rough, not a creak."""
    n = len(t)
    jit = 1 + seed_jit * PB.slow_random(n, 3.0, 25.0)
    ph = np.cumsum(f0 * jit) / SR
    hit = np.diff(np.floor(ph), prepend=0.0) > 0
    pulses = hit * (0.55 + 0.45 * rng().random(n)) * amount
    x = fconv(pulses, kernel(0.06, 60, 520, 0.011, 0.002)) + 0.5 * fconv(pulses, kernel(0.03, 180, 1300, 0.004))
    x = comb(x, 1.0 / (2.0 * np.maximum(f0, 10)), gains=(0.5, 0.3))
    return band(x, 35, 1500, 2)


def rip(t, t0, length, lo=90, hi=1400, density=None):
    """The land tearing open, as a mass moving rather than as grit: a deep churning swell between lo and hi Hz (its
    bands boiling slowly, never crackling), rising and dying over `length` s, a darker body under it."""
    u, on = after(t, t0)
    env = np.sin(np.pi * np.clip(u / length, 0, 1)) ** 1.5 * on
    env = env * np.exp(0.35 * PB.slow_random(len(t), 1.0, 4.0))
    n = len(t)
    return (churn(n, lo, hi, slope=-3.5, depth=6.0, turns=30.0) + churn(n, lo * 0.6, hi * 0.35, slope=-3.0, depth=5.0, turns=30.0) * 0.7) * env


def thud(t, t0, f0, f1, dec, size=1.0):
    """A heavy low blow: a falling sub, its octave a little, a 50-260 Hz body under it."""
    s = sweep_tone(t, t0, f0, f1, 0.07, ((1, 1.0), (2, 0.22), (3, 0.08))) * ar(t, t0, 0.003, dec)
    b = T.unit(band(nz(len(t)), 50, 260, 2)) * ar(t, t0, 0.002, dec * 0.35) * 0.45
    return (s + b) * size


def green(t, t0, root, swell, dec, fall=0.85, spread=1.0):
    """The green energy: a low detuned chord (root, fifth, octave, tenth) swelling in `swell` s, its pitch falling to
    `fall` of itself as it spreads, through a comb whose delay sweeps: a hollow, phasing, old sound."""
    u, on = after(t, t0)
    x = np.zeros(len(t))
    for r, a in ((1.0, 1.0), (1.5, 0.6), (2.0, 0.55), (2.52, 0.3), (3.0, 0.25), (4.0, 0.12)):
        for det in (-0.004 * spread, 0.0, 0.0047 * spread):
            f = root * r * (1 + det) * (fall + (1 - fall) * np.exp(-u / (dec * 0.6)))
            ph = 2 * np.pi * np.cumsum(f * on) / SR + rng().uniform(0, 6.28)
            x += a * (np.sin(ph) + 0.25 * np.sin(2 * ph + 1.0))
    env = (1 - np.exp(-u / swell)) ** 2 * np.exp(-u / dec) * on
    x = x * env
    d = 0.0035 + 0.0025 * np.sin(2 * np.pi * 0.35 * u + rng().uniform(0, 6.28)) + 0.004 * np.exp(-u / 0.6)
    return band(comb(x, d, gains=(0.6, 0.4, 0.25)), 30, 2500, 2)


def land_ir(length, seed, darken=(3500, 300), decay=1.2, clumps=26):
    """Echoes off the land: clumps of reflections arriving irregularly (each later one duller), over a diffuse tail."""
    g = np.random.default_rng(seed)
    n = int(length * SR)
    s = np.arange(n) / SR
    ir = np.zeros(n)
    for _ in range(clumps):
        tc = 0.03 + g.gamma(1.3, length / 6)
        if tc > length * 0.9:
            continue
        k = int(tc * SR)
        m = min(int(0.05 * SR), n - k)
        ir[k:k + m] += g.standard_normal(m) * np.exp(-np.arange(m) / (0.012 * SR)) * np.exp(-tc / decay) * g.uniform(0.3, 1.0)
    ir += g.standard_normal(n) * np.exp(-s / decay) * 0.25
    # (later is darker)
    hi = band(ir, darken[0] * 0.25, None, 1)
    ir = ir - hi + hi * np.exp(-s / (darken[0] / 10000.0))
    ir = band(ir, 25, darken[0], 2)
    ir[:int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


def verb(x, length, seed, wet, darken=(3500, 300), decay=1.2):
    ir = land_ir(length, seed, darken, decay)
    return x + fftconvolve(x, ir)[:len(x)] * wet


def far_of(x, seed, lp=2400.0, smear=0.02, wet=0.9, length=5.0):
    """A sound through most of a kilometre of air: the highs let down, its front smeared, more of the land's echo,
    its 100-500 Hz body kept (and the lows' harmonics) so it carries on small speakers."""
    # (the front smeared by a short diffusing burst: a dense noise kernel, its spectrum flat on average, plus the direct)
    s = np.arange(int(smear * SR)) / SR
    k = np.random.default_rng(seed).standard_normal(len(s)) * np.exp(-s / (smear / 3))
    k = k / np.sqrt(np.sum(k ** 2)) * 0.3
    k[0] += 1.0
    y = fftconvolve(x, k)[:len(x)]
    y = band(y, None, lp, 2) + band(y, 150, 1500, 2) * 0.25
    y = y - band(y, None, 45, 2) * 0.4
    y = verb(y, length, seed, wet, darken=(2600, 250), decay=1.8)
    return drive_lows(y, 0.4)


def pad_to(x, d):
    n = int(d * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def tone_blow(t, tp, f_hi, f_lo, f_end, drop, rise, decs, drive=3.0, octv=0.25, h3=0.08, harm=0.4, glide=0.9):
    """One tonal blow at `tp` s, the weight of every hit here: a sine falling from f_hi to f_lo Hz over `drop` s and on
    to f_end over ~`glide` s, rising over `rise`, dying by `decs` ((weight, time constant), ...), with its octave, its
    twelfth and its own harmonics (the sine driven `drive`, odd and some even, kept under 700 Hz) stacked on it, so it
    is felt as a drop and heard as a body on small speakers."""
    uu = np.maximum(t - tp, 0.0)
    m = t >= tp
    f = f_end + (f_lo - f_end) * np.exp(-uu / glide) + (f_hi - f_lo) * np.exp(-uu / drop)
    ph = 2 * np.pi * np.cumsum(f * m) / SR + rng().uniform(0, 6.28)
    env = (1 - np.exp(-uu / rise)) * sum(w * np.exp(-uu / tc) for w, tc in decs) * m
    s = np.sin(ph)
    hm = (np.tanh(drive * s + 0.3) - np.tanh(0.3)) / np.tanh(drive)
    hm = band(hm - s * 0.9, None, 700, 2)
    return (s + octv * np.sin(2 * ph + rng().uniform(0, 6.28)) + h3 * np.sin(3 * ph + rng().uniform(0, 6.28)) + harm * hm) * env


def churn(n, f0, f1, per_oct=2.5, slope=-3.0, turns=12.0, depth=6.0):
    """Stone grinding under a load, as turbulence (unit RMS): bands of noise from `f0` to `f1` Hz (`per_oct` an
    octave), each boiling on its own at a rate that goes with its pitch (a band at f swells and sinks about f/`turns`
    times a second, never faster than 40), `depth` dB of it at the bottom, less higher up: a deep heaving pressure low
    down, a fine seethe higher, never a tick or a creak (no catch is ever alone, nothing rings)."""
    k = max(int(np.log2(f1 / f0) * per_oct) + 1, 2)
    wide = 2 ** (0.62 / per_oct)
    y = np.zeros(n)
    for i in range(k):
        u = i / (k - 1)
        fc = f0 * (f1 / f0) ** u
        r = min(fc / turns, 40.0)
        g = np.exp(depth * (1 - 0.6 * u) / 8.686 * PB.slow_random(n, r * 0.22, r))
        y += T.unit(band(nz(n), fc / wide, fc * wide, 2)) * g * 10 ** (slope * np.log2(fc / f0) / 20)
    return T.unit(y)


def body_drive(x, t0, drive_db, hold=0.5, ease=1.4, bias=0.15):
    """The low-mid body (40-400 Hz) driven into a slightly lopsided tanh, as a huge blow heard too close: its own odd and
    a few even harmonics, band-limited to 35-2500 Hz (nothing new in the sub, no fizz), strongest for `hold` s from `t0`
    and easing off (`ease` s); small signals pass at unity, the sub and the top untouched. Weight on every speaker."""
    n = len(x)
    u = np.maximum(np.arange(n) / SR - t0, 0)
    g = 10 ** (drive_db * np.exp(-np.maximum(u - hold, 0) / ease) / 20)
    sub = band(x, None, 40.0, 2)
    rest = x - sub
    body = band(rest, None, 400.0, 2)
    top = rest - body
    ref = np.percentile(np.abs(body), 99.9) + 1e-12
    z = g * body / ref
    sat = (np.tanh(z + bias) - np.tanh(bias)) / (1 - np.tanh(bias) ** 2)
    return sub + top + band(sat * ref / g, 35, 2500, 2) * g ** 0.6


def landing(t, tl, size, f0=52.0):
    """A big piece of stone landing on the land `tl` s in: a deep blow (a short falling sub with its harmonics), the
    earth's dull body under it and a little earth thrown up; the bigger the deeper and longer. Low and dull: no click."""
    f = f0 * (1.15 - 0.15 * min(size, 2.0))
    x = tone_blow(t, tl, f, f * 0.66, f * 0.52, 0.05, 0.004, ((0.6, 0.12 + 0.06 * size), (0.4, 0.4 + 0.25 * size)), drive=2.5, harm=0.5)
    m = mass(t, tl, 1.0, att=0.006, short=0.05 + 0.03 * size, long=0.3 + 0.2 * size, peak=110.0, top=900.0, dark=1.4)
    return (x + m * np.abs(x).max() * 0.7) * size


# ---- the weight of a blow: masses, not tones or grit ----------------------------------------------------------------------
def mass(t, t0, size=1.0, att=0.004, short=0.09, long=0.7, peak=160.0, top=2400.0, dark=1.0, lo=28.0, wobble=1.5, fall=4.5):
    """A huge mass of stone meeting the ground at t0, as one dense blow of noise (no patter, nothing rings): band by
    band (half-octave bands from `lo` to `top` Hz) a front (`att`, slower the lower the band, so it lands as a shove, not a
    click) and a two-stage decay (`short`, then `long`), the upper bands dying sooner by `dark` (so it darkens as it
    goes, as real blows do); its weight flat from 40 Hz to `peak` and falling `fall` dB an octave over 2x`peak`, the 100-800
    Hz body full. Each band's level wanders a little (`wobble` dB, slowly: under 4 Hz) so it moves like a mass, not a
    hiss. Peak about `size`."""
    n = len(t)
    u, on = after(t, t0)
    out = np.zeros(n)
    fcs = np.geomspace(lo, top, max(int(np.log2(top / lo) * 2) + 1, 3))
    wide = 2 ** 0.3
    for fc in fcs:
        lvl = 1.0 if fc <= 2 * peak else (2 * peak / fc) ** (fall / 6.02)
        lvl *= 1.0 if fc >= 40 else (fc / 40.0) ** 0.5
        a = att * (1 + 50.0 / fc)
        k = (fc / peak) ** (-0.45 * dark)
        s_, l_ = np.clip(short * k, 0.012, 4 * short), np.clip(long * k, 0.05, 3 * long)
        env = (1 - np.exp(-u / a)) * (0.5 * np.exp(-u / s_) + 0.5 * np.exp(-u / l_)) * on
        g = np.exp(wobble / 8.686 * PB.slow_random(n, 0.5, 4.0))
        out += T.unit(band(nz(n), fc / wide, fc * wide, 2)) * lvl * env * g
    return out / (np.abs(out).max() + 1e-12) * size


def surges(t, t0, plan):
    """The ground answering a blow: swells of low noise rolling out after it, each (dt, size, lo, hi, rise, decay) a
    broad heave of the land arriving `dt` s after t0, slow in and slow out (no front of its own)."""
    n = len(t)
    out = np.zeros(n)
    for dt, sz, lo_, hi_, rs, dc in plan:
        u, on = after(t, t0 + dt)
        env = (1 - np.exp(-u / rs)) ** 2 * np.exp(-u / dc) * on
        out += churn(n, lo_, hi_, slope=-3.5, depth=5.0, turns=30.0) * env * sz
    return out


# ---- take B only: real rock (CC0 recordings, never in the game files) ----------------------------------------------------
REFS = Path(__import__("os").environ.get("COLOSSI_REFS", "dist/colossi-sound/refs"))
# (name: file, where its blow starts in it (s), page, author, title). All CC0 1.0 on Freesound.
RECORDINGS = {
    "quarry": ("ref1_blast_felixblume_475780.mp3", 0.145, "https://freesound.org/people/felix.blume/sounds/475780/", "felix.blume",
               "Big dynamite explosion in an open mine (Chile)"),
    "rockfall": ("ref2_rockfall_alancat_389303.mp3", 0.0, "https://freesound.org/people/AlanCat/sounds/389303/", "AlanCat", "rockfall2a.wav"),
    "demolition": ("ref3_demolition_alienistcog_125937.mp3", 10.035, "https://freesound.org/people/alienistcog/sounds/125937/", "alienistcog",
                   "merrimack-st-demolition.aif"),
    "rockslide": ("ref4_rockslide_betchkal_500638.mp3", 0.0, "https://freesound.org/people/betchkal/sounds/500638/", "betchkal",
                  "Cathedral Mountain rock slide, slow blocky chunks"),
}
_RECS = {}
USED = {}                                   # (what each take B file took from which recording, for the NOTICE)


def rec(key, start, length, rate, hp=100.0, fade_in=0.003, fade_out=0.6, user=None):
    """`length` s (as played) of recording `key` from `start` s after its blow, played at `rate` times its speed (under 1: slower and
    lower, a bigger thing breaking), high-passed at `hp` Hz before the change of speed (the Colossi's own lows go under
    it, and the recordings' wind and traffic rumble stays out), mono, unit RMS over its first half second."""
    f, onset = RECORDINGS[key][:2]
    if key not in _RECS:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(REFS / f), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                             capture_output=True, check=True).stdout
        _RECS[key] = np.frombuffer(raw, dtype="<f4").astype(float)
    x = _RECS[key]
    a = int((onset + start) * SR)
    x = x[max(a, 0):a + int(length * rate * SR)].copy()
    if hp:
        x = band(x, hp, None, 3)
    from fractions import Fraction
    fr = Fraction(1.0 / rate).limit_denominator(64)
    x = resample_poly(x, fr.numerator, fr.denominator)
    k = int(fade_in * SR)
    x[:k] *= np.linspace(0, 1, k)
    k = min(int(fade_out * SR), len(x))
    x[-k:] *= np.linspace(1, 0, k) ** 2
    if user:
        USED.setdefault(user, []).append(f"{key} ({RECORDINGS[key][3]}, \"{RECORDINGS[key][4]}\"): its {start:.2f}-{start + length * rate:.2f} s "
                                         f"after its blow, played at {rate:.2f}x speed ({length:.1f} s)")
    return x / (np.sqrt(np.mean(x[:int(0.5 * SR)] ** 2)) + 1e-12)


def lay(n, x, at):
    """`x` laid into n samples from `at` s."""
    out = np.zeros(n)
    k = int(at * SR)
    seg = x[:max(0, n - k)]
    out[k:k + len(seg)] = seg
    return out


# =================================================================================================  the pass's motions
def pt(a, b, x):
    u = np.clip((x - a) / (b - a), 0, 1)
    return u * u * (3 - 2 * u)


def grind_curve(p, n):
    x = p * n
    return p + ((np.floor(x) + pt(0.3, 1.0, x - np.floor(x))) / n - p) * 0.55


def speed(x):
    v = np.abs(np.gradient(x)) * SR
    return v / (v.max() + 1e-12)


def rise_motion(t):
    """How hard giant g is moving at `t` s into its rise (0-1), and how far up it is (0-1): `cl_rise` and `cl_pose`'s
    legs, torso and head each grinding up in their catches."""
    u = t / CL_RISE
    up = grind_curve(pt(0.0, CL_RISE, t), 5.0)
    leg = grind_curve(pt(0.28, 0.84, u), 4.0)
    tor = grind_curve(pt(0.42, 0.93, u), 4.0)
    hd = grind_curve(pt(0.66, 1.02, u), 3.0)
    m = speed(up) + 0.5 * speed(leg) + 0.4 * speed(tor) + 0.25 * speed(hd)
    return np.clip(m / m.max(), 0, 1), up


def heave_motion(t, sw=1.2):
    """The hammer's heave (`cl_pose`), `t` against the blow: (how hard the joints work, how much load they hold)."""
    prep = pt(-3.75, -3.15, t) * (1 - pt(-3.15, -2.45, t))
    a = grind_curve(pt(-3.20, -2.15, t), 4.0)
    cat = pt(-2.50, -2.15, t) * (1 - pt(-2.10, -1.70, t))
    bq = grind_curve(pt(-2.15, -1.40, t), 3.0)
    hang = pt(-1.50, -sw + 0.25, t)
    m = speed(a) + 0.9 * speed(bq) + 0.35 * speed(cat) + 0.2 * speed(hang) + 0.15 * speed(prep)
    load = np.clip(0.35 * a + 0.65 * bq, 0, 1) * (1 - pt(-sw, -sw + 0.3, t) * 0.6)
    return np.clip(m / m.max(), 0, 1), load


# ===========================================================================================================  the files
def quake():
    """The hook, the ground under all five as they start, through the earth: at once a deep groan of the land swelling
    up out of nothing in a quarter second (a sub at ~30 Hz and a growl on it), the land splitting open on it (a deep
    blow, a heavy tearing that runs on for a second and a half), then a sub bed heaving with the five giants' summed
    heaves, a dark grinding churn over it for small speakers, the land tearing again now and then; dying away as the last
    giant stands."""
    d = 10.0
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(51101):
        t0 = QUAKE_LEAD
        tot = np.zeros(n)
        for g in range(5):
            m, _ = rise_motion(t - T_RISE_STEP * g)
            tot += np.where(t >= T_RISE_STEP * g, m, 0)
        tot = band(tot / tot.max(), None, 3.0, 1)
        tot = np.clip(tot / tot.max(), 0, 1)
        live = pt(0.0, 0.25, t) * (1 - pt(7.0, 9.8, t))
        # (the groan of the land: a sub swelling at once, a growl on it, both following the giants after)
        swell = tone_blow(t, t0, 34.0, 30.0, 27.0, 0.6, 0.12, ((0.55, 1.6), (0.45, 6.0)), drive=2.0, octv=0.3, harm=0.6, glide=3.0)
        f0 = 27.0 + 6.0 * tot + 1.5 * PB.slow_random(n, 0.2, 1.2)
        gn = groan(t, f0, (0.5 + 0.5 * tot) * pt(0.0, 0.3, t), 0.1)
        gn = band(gn, None, 650, 2)
        # (the land splitting open: a deep blow on the swell, the tear running on from it)
        split = tone_blow(t, t0 + 0.06, 50.0, 31.0, 25.0, 0.07, 0.004, ((0.5, 0.35), (0.5, 1.4)), drive=3.0, harm=0.5)
        split += mass(t, t0 + 0.06, np.abs(split).max() * 0.9, att=0.008, short=0.15, long=1.1, peak=110.0, top=1200.0, dark=1.3)
        tear = rip(t, t0 + 0.1, 1.7, 50, 650) + rip(t, 2.5, 1.1, 45, 520) * 0.5 + rip(t, 4.9, 1.3, 45, 560) * 0.55
        bed = tilted(n, 18, 70, -4) * (0.4 + 0.6 * tot) * live
        grind = churn(n, 30, 420, slope=-4.0, depth=7.0) * (0.25 + 0.75 * tot ** 1.2) * live
        ref = np.sqrt(np.mean(band(split, 25, 120, 2)[int(t0 * SR):int((t0 + 0.5) * SR)] ** 2))
        x = split + swell * ref * 0.9 + T.unit(gn) * ref * 0.6 + T.unit(tear) * ref * 0.55 * live \
            + T.unit(bed) * ref * 0.55 + grind * ref * 0.45
        x = verb(x, 3.0, 5110, 0.3, (1800, 250), 1.4)
        x = drive_lows(x, 0.55)
        x = PB.causal_lowcut(x, 16.0)
    finish("quake", x, -13.5, tail=1.5, clip=True, clip_db=6.0)


def rise(k):
    """Giant g heaving itself out of the earth, in the pass's catches: stone grinding on stone as a deep churning
    pressure (following how hard it moves), its joints groaning, a low give of the ground at each heave and the earth
    tearing open round it, soil and boulders sliding off it in a low roar as it comes up; the land's echo round it."""
    d = CL_RISE + 2.1
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(52100 + k):
        m, up = rise_motion(t)
        m = band(m, None, 18.0, 1)
        m = np.clip(m / m.max(), 0, 1) * (1 - pt(CL_RISE, CL_RISE + 1.2, t))
        gr = churn(n, 32 + 3 * k, 480, slope=-3.5, depth=7.0) * (0.15 + m)
        f0 = (26.0 + 2.5 * k) + 14.0 * band(m, None, 2.0, 1) + 2.0 * PB.slow_random(n, 0.2, 1.5)
        gn = band(groan(t, f0, m ** 0.7), None, 700, 2)
        # (the heaves' starts: where it lurches on again)
        dm = np.gradient(band(m, None, 4.0, 1))
        starts = [i for i in range(1, n - 1) if dm[i - 1] > 0 >= dm[i] and m[i] > 0.45][:12]
        tear = np.zeros(n)
        gives = np.zeros(n)
        for j, i in enumerate(starts):
            ts = i / SR - 0.25
            tear += rip(t, ts, rng().uniform(0.5, 0.9), 55, 750) * rng().uniform(0.6, 1.0)
            gives += tone_blow(t, ts, rng().uniform(44, 50), 30.0, 25.0, 0.06, 0.006, ((0.6, 0.2), (0.4, 0.6)), drive=2.5) * rng().uniform(0.6, 1.0)
        slide = churn(n, 35, 500, slope=-5.0, depth=5.0) * band(np.clip(up, 0, 1) * (1 - pt(CL_RISE + 0.3, d, t)), None, 1.0, 1)
        sub = tilted(n, 18, 55, -3) * (0.2 + m)
        ref = np.std(gr) + 1e-12
        x = gr + T.unit(gn) * ref * (0.7 + 0.1 * k) + T.unit(tear) * ref * 0.4 + T.unit(gives) * ref * 1.2 \
            + slide * ref * 0.4 + T.unit(sub) * ref * 0.9
        x *= pt(0.0, 0.15, t)
        x = verb(x, 3.0, 520 + k, 0.35, (2200, 280), 1.0)
        x = drive_lows(x, 0.5)
        x = PB.causal_lowcut(x, 18.0)
    finish(f"rise{k + 1}", x, -19.0, tail=1.2, clip=True, clip_db=7.0)


def stamp(k):
    """A foot the size of a house stamped down into the ground: a deep falling thud, the earth packed under it, the
    ground shuddering, soil thrown off its edge in a low gush; short."""
    d = 2.8
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(53000 + k):
        t0 = STAMP_LEAD
        f0 = (56.0, 50.0, 61.0)[k]
        x = thud(t, t0, f0, 23.0 + k, 0.5, 1.0) * 0.8
        # (the foot's weight into the earth: one dense mass, its body 60-600 Hz, darkening)
        x += mass(t, t0, np.abs(x).max() * 1.1, att=0.005, short=0.07, long=0.45, peak=(130.0, 115.0, 145.0)[k], top=1500.0, dark=1.3)
        x += surges(t, t0, ((0.12, 0.35, 30, 220, 0.06, 0.4), (0.45, 0.2, 25, 160, 0.12, 0.6))) * np.abs(x).max()
        chop = np.clip(1 + 0.9 * PB.slow_random(n, 9.0, 14.0), 0.05, None)
        x += T.unit(band(nz(n), 28, 120, 2)) * chop * ar(t, t0 + 0.02, 0.04, 0.45) * np.std(x[:int(0.4 * SR)]) * 0.5
        x += T.unit(tilted(n, 60, 700, -5)) * ar(t, t0 + 0.08, 0.12, 0.6) * np.std(x[:int(0.4 * SR)]) * 0.22
        x = verb(x, 2.2, 530 + k, 0.3, (2800, 300), 0.8)
        x = drive_lows(x, 0.6)
        x = PB.causal_lowcut(x, 18.0)
    finish(f"stamp{k + 1}", x, -12.5, tail=0.8, clip=True, clip_db=7.5)


def heave(k):
    """The hammer heaved up, the way the pass moves it: hauled off the ground to the chest in four catches (each a
    surge of stone grinding on stone at the hips, knees and shoulders, a deep churning pressure), caught with a dip of
    the knees (a low thump), pressed up over the shoulder in three, hung there with the joints groaning under the load
    (the groan pitched up by it), letting go into the swing. Dust and grit pouring off the joints under it, low."""
    d = HEAVE_AHEAD - 0.4
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(54100 + k):
        tb = t - HEAVE_AHEAD                       # (against the blow)
        m, load = heave_motion(tb)
        m = np.clip(band(m, None, 20.0, 1), 0, None)
        m /= m.max()
        gr = churn(n, 36 + 4 * k, 520, slope=-3.0, depth=7.5) * (0.12 + m)
        f0 = (29.0 + 2.5 * k) + 24.0 * load ** 1.3 + 2.5 * PB.slow_random(n, 0.3, 2.0)
        strain = np.clip(0.45 * m + load * (0.4 + 0.6 * pt(-1.9, -1.4, tb)), 0, 1)
        gn = band(groan(t, f0, strain ** 0.8, 0.1), None, 750, 2)
        catch = tone_blow(t, HEAVE_AHEAD - HEAVE_CATCH, 46.0 + 3 * k, 31.0, 26.0, 0.06, 0.005, ((0.6, 0.18), (0.4, 0.5)), drive=2.5)
        dust = churn(n, 40, 400, slope=-5.0, depth=4.0) * (0.2 + 0.8 * band(m, None, 1.5, 1))
        sub = tilted(n, 20, 60, -3) * (0.15 + 0.6 * m + 0.4 * load)
        ref = np.std(gr) + 1e-12
        x = gr + T.unit(gn) * ref * 1.1 + T.unit(catch) * ref * 1.0 + dust * ref * 0.25 + T.unit(sub) * ref * 0.7
        x *= pt(0.0, 0.12, t) * (1 - pt(d - 0.55, d, t))
        x = verb(x, 2.5, 540 + k, 0.3, (2200, 280), 0.9)
        x = drive_lows(x, 0.5)
        x = PB.causal_lowcut(x, 18.0)
    finish(f"heave{k + 1}", x, -15.0, tail=0.05, clip=True, clip_db=7.5)


SLAM_D = 7.0
# The five characters' blows (colossi.rs's CHARACTER: eager, stiff, showy, brute, wary), each its own weight and shape:
#   boom   the blow's tone (f_hi, f_lo, f_end Hz) and how it dies ((weight, seconds), ...)
#   more   the ground's answers after it ((s after, f_hi, f_lo, size), ...)
#   knock  the short hard body's band and decay;  edge  the 0.4-3 kHz edge on its front (its level against the lows)
#   roar   the dark roar after it (level, decay);  crunch  the earth crushed (level);  green  the energy (root Hz, level)
#   swing  the swing's whoosh (level, how bright: its band's top at the blow, Hz);  db  its level;  ring  the land's echo
SLAM_TAKES = (
    dict(name="eager", boom=(68.0, 41.0, 31.0), decs=((0.5, 0.22), (0.5, 0.8)), more=((0.27, 50.0, 35.0, 0.45),),
         knock=(120, 520, 0.035), edge=-12.0, roar=(0.13, 0.55), crunch=0.5, green=(43.65, 0.22), swing=(0.24, 700.0),
         db=-8.8, ring=0.28),
    dict(name="stiff", boom=(63.0, 40.0, 31.0), decs=((0.65, 0.18), (0.35, 0.6)), more=(),
         knock=(110, 450, 0.026), edge=-13.0, roar=(0.07, 0.4), crunch=0.4, green=(41.2, 0.14), swing=(0.18, 560.0),
         db=-9.6, ring=0.22),
    dict(name="showy", boom=(65.0, 40.0, 29.0), decs=((0.4, 0.3), (0.35, 1.2), (0.25, 3.0)), more=((0.31, 49.0, 34.0, 0.6), (0.9, 42.0, 31.0, 0.3)),
         knock=(110, 480, 0.04), edge=-12.5, roar=(0.2, 0.9), crunch=0.55, green=(38.9, 0.4), swing=(0.32, 760.0),
         db=-8.6, ring=0.34),
    dict(name="brute", boom=(56.0, 34.0, 25.0), decs=((0.4, 0.35), (0.35, 1.4), (0.25, 3.6)), more=((0.22, 44.0, 30.0, 0.7), (0.6, 38.0, 27.0, 0.35)),
         knock=(85, 360, 0.05), edge=-15.0, roar=(0.17, 1.0), crunch=0.65, green=(36.7, 0.25), swing=(0.26, 520.0),
         db=-8.2, ring=0.32),
    dict(name="wary", boom=(61.0, 38.0, 29.0), decs=((0.5, 0.3), (0.5, 1.1)), more=((0.4, 46.0, 33.0, 0.35),),
         knock=(95, 400, 0.04), edge=-16.0, roar=(0.15, 0.8), crunch=0.45, green=(46.25, 0.2), swing=(0.22, 600.0),
         db=-9.2, ring=0.3),
)


def slam_parts(c, take="A"):
    """Character c's blow, mono, as its layers (a dict, summed for the file; `--stems` writes them apart): the swing
    (a house of stone through the air: a low pressure push opening up as it nears, no bright sweep), then the hammer
    into the ground: the sub and the tonal drop under it, the blow itself as one dense mass of noise (its weight 40-800
    Hz, darkening as it dies: no grit, no crack, no patter), the ground answering it in three rolling heaves, the earth
    settling in a slow churning roar, the green cracking out (a low chord through a sweeping comb), a few heavy pieces
    coming back down (low masses). Take B (`--takes` only): the blow's breaking from real rock (CC0 recordings, slowed
    and lowered: a building's fall for the mass breaking, a rockfall for what comes back down) over the same sub, ground
    and green, the synthesised mass kept only under 350 Hz."""
    P = SLAM_TAKES[c]
    n = int(SLAM_D * SR)
    t = np.arange(n) / SR
    t0 = SLAM_LEAD
    # ---- the swing: a low push building to the blow, its top opening from ~120 Hz to the character's
    s = np.clip((t - (t0 - 1.2)) / 1.2, 0, 1)
    v = (s ** 0.8) * (t < t0)
    fc = 120.0 + (0.7 * P["swing"][1] - 120.0) * s ** 1.4
    base = churn(n, 26, 900, slope=-4.0, depth=4.0)
    w = np.zeros(n)
    hop = 1024
    for i in range(0, min(n, int((t0 + 0.05) * SR)), hop):
        j = slice(max(0, i - hop), min(n, i + 2 * hop))
        y = band(base[j], None, fc[i], 2)
        w[j] += y * np.hanning(len(y)) * 0.66
    whoosh = T.unit(w) * v ** 1.8
    whoosh *= 1 - pt(t0 - 0.004, t0 + 0.02, t)
    # ---- the blow: the sub and the tone under it
    fh, fl, fe = P["boom"]
    sub = tone_blow(t, t0, 40.0, 33.0, 29.0, 0.05, 0.003, ((0.7, 0.2), (0.3, 0.9)), drive=1.0, octv=0.1, harm=0.1)
    boom = tone_blow(t, t0 + 0.006, fh, fl, fe, 0.06, 0.004, P["decs"]) * 0.7
    for dt, f1, f2, sz in P["more"]:
        boom += tone_blow(t, t0 + dt, f1, f2, f2 * 0.85, 0.06, 0.012, ((0.6, 0.25), (0.4, 1.0)), drive=2.5) * sz * 0.7
    low = sub * 0.65 + boom
    ref = np.sqrt(np.mean(band(low, 30, 120, 2)[int(t0 * SR):int((t0 + 0.4) * SR)] ** 2)) + 1e-12
    # ---- the mass of it: the earth taking a hammer the size of a hill
    long = 0.55 + 0.35 * sum(w_ * tc for w_, tc in P["decs"])
    peak = P["knock"][1] * 0.42
    top = 5000.0 * 10 ** ((P["edge"] + 12.0) / 20)
    hit = mass(t, t0, 1.0, att=0.003, short=0.11, long=long, peak=peak, top=top, dark=0.85)
    for dt, f1, f2, sz in P["more"]:
        hit += mass(t, t0 + dt, sz * 0.8, att=0.007, short=0.1, long=0.7, peak=peak * 0.8, top=top * 0.6, dark=1.3)
    hit *= ref * 4.2 * (0.8 + 0.4 * P["crunch"])
    # ---- the ground answering, the earth settling, the pieces coming down
    ground_ = surges(t, t0, ((0.22, 0.6, 25, 260, 0.07, 0.7), (0.65, 0.45, 22, 190, 0.14, 1.1), (1.35, 0.35, 20, 150, 0.3, 2.4), (2.6, 0.3, 18, 130, 0.5, 2.5))) * ref * 1.7
    roar = churn(n, 30, 650, slope=-4.5, depth=6.0, turns=30.0) * ar(t, t0 + 0.05, 0.2, 2.2 * P["roar"][1] + 1.2) * ref * (0.5 + 2.0 * P["roar"][0])
    en = band(green(t, t0 + 0.06, P["green"][0], 0.3, 0.8, 0.82), None, 900, 2)
    en = T.unit(en) * ref * P["green"][1]
    fall = np.zeros(n)
    for _ in range(4 + c % 2):
        fall += landing(t, t0 + rng().uniform(1.0, 3.2), rng().uniform(0.25, 0.7), rng().uniform(55, 70))
    L = dict(swing=whoosh * ref * P["swing"][0] * 2.4, sub=low, mass=hit, ground=ground_, roar=roar, green=en, fall=fall * 0.25)
    if take == "B":
        # (real rock: a building's fall slowed to the hammer's size for the breaking, a rockfall slowed for what comes back)
        rate = (0.62, 0.66, 0.58, 0.52, 0.6)[c]
        rock = rec("demolition", 0.0, 3.2, rate, hp=110.0, fade_out=1.5, user=f"slam{c + 1}")
        deb = rec("rockfall", 0.55, 2.2, 0.55 + 0.03 * c, hp=90.0, fade_in=0.05, fade_out=1.0, user=f"slam{c + 1}")
        L["rock"] = lay(n, rock, t0 - 0.004) * ref * 2.0
        L["debris"] = lay(n, deb, t0 + 0.3) * ref * 0.55 * ar(t, t0 + 0.3, 0.25, 2.5)
        L["mass"] = band(hit, None, 350, 2) * 0.8
        L["fall"] = L["fall"] * 0.5
    return L, P


def slam(c, take="A", dest=None, stems=None):
    with PB.seeded(55100 + c):
        L, P = slam_parts(c, take)
        x = sum(L.values())
        x = body_drive(x, SLAM_LEAD, 6.0, 0.3, 0.8)
        near = verb(x, 3.0, 550 + c, P["ring"], (2600, 280), 0.9)
        near = drive_lows(near, 0.55)
        near = PB.causal_lowcut(near, 18.0)
        far = far_of(x, 560 + c, lp=2600.0)
        far = PB.causal_lowcut(far, 18.0)
    g = finish(f"slam{c + 1}", near, P["db"] + 2.0, tail=1.5, clip=True, clip_db=3.5, dest=dest)
    finish(f"slam_far{c + 1}", far, P["db"] + 0.5, tail=2.0, clip=True, dest=dest)
    if stems:
        write_stems(stems, f"slam{c + 1}_{take}", L, g, lambda y: verb(y, 3.0, 550 + c, P["ring"], (2600, 280), 0.9))


def slam_all():
    """What the five blows together add, through the ground: a blow deeper than any one of them, the land heaving and
    rolling under the five (each giant's arriving in its turn, smaller), the cracks' green joined into one low swell
    that the cracks' run then rises out of."""
    d = 8.0
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(56101):
        t0 = SLAM2_LEAD
        x = tone_blow(t, t0, 50.0, 31.0, 24.0, 0.08, 0.008, ((0.4, 0.4), (0.35, 1.5), (0.25, 3.5)), drive=3.0, harm=0.5)
        for dt, sz in ((0.21, 0.55), (0.47, 0.45), (0.8, 0.35), (1.15, 0.25)):
            x += tone_blow(t, t0 + dt, rng().uniform(42, 48), 30.0, 25.0, 0.07, 0.02, ((0.6, 0.3), (0.4, 1.0)), drive=2.5) * sz
        ref = np.sqrt(np.mean(band(x, 25, 120, 2)[int(t0 * SR):int((t0 + 0.5) * SR)] ** 2))
        heave_ = tilted(n, 18, 80, -3) * ar(t, t0, 0.15, 1.6) * np.exp(0.8 * PB.slow_random(n, 0.4, 3.0))
        roll = churn(n, 30, 380, slope=-4.0, depth=8.0) * ar(t, t0 + 0.2, 0.3, 1.8)
        en = band(green(t, t0 + 0.05, 36.7, 0.35, 1.4, 0.9, spread=1.6), None, 900, 2)
        # (the weight of the five through the land: one huge dark mass, the followers' smaller, the land rolling after)
        hit = mass(t, t0, 1.0, att=0.006, short=0.18, long=1.6, peak=110.0, top=900.0, dark=1.2)
        for dt, sz in ((0.21, 0.5), (0.47, 0.4), (0.8, 0.3)):
            hit += mass(t, t0 + dt, sz, att=0.01, short=0.15, long=1.0, peak=95.0, top=700.0, dark=1.3)
        rolls = surges(t, t0, ((0.4, 0.7, 22, 220, 0.12, 1.0), (1.1, 0.55, 20, 180, 0.25, 1.4), (2.0, 0.4, 18, 150, 0.4, 2.0)))
        x = x + T.unit(heave_) * ref * 0.6 + roll * ref * 0.5 + T.unit(en) * ref * 0.35 + hit * ref * 2.4 + rolls * ref * 1.4
        x = body_drive(x, t0, 4.0, 0.6, 1.2)
        x = verb(x, 4.0, 5601, 0.35, (1800, 250), 1.5)
        x = drive_lows(x, 0.6)
        x = PB.causal_lowcut(x, 16.0)
    finish("slam_all", x, -9.5, tail=2.0, clip=True, clip_db=5.0)


def beam(dest=None):
    """The cracks racing in to the middle, BEAM_LEN s, cut on the hit, rising the whole way so it never goes quiet
    before the blast: a low rich drone climbing a fourth (D1 to G1), its voices beating faster as it charges, through a
    comb sweeping up (a rising hollow sound, old rather than electric); at each of the cracks' five lunges (the pass's
    `cl_run`) the land tearing and a deep jolt, each bigger; the ground's pressure building under it all as a sub swell,
    and in the last half second everything drawn in and up to the hit."""
    d = BEAM_LEN + 0.06
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(57101):
        u = np.clip(t / BEAM_LEN, 0, 1)
        f = 36.7 * 2 ** (5 * u ** 1.6 / 12)
        drone = np.zeros(n)
        for det in (-1.0, 0.0, 1.0):
            beat = det * (0.25 + 3.2 * u ** 2)
            ph = 2 * np.pi * np.cumsum(f + beat) / SR + rng().uniform(0, 6.28)
            for h in range(1, 30):
                if 36.7 * h * 1.4 > 6000:
                    break
                drone += np.sin(h * ph) / h ** 1.1
        drone = T.lowpass_glide(drone, 400.0, 1800.0, 1.8)
        drone = comb(drone, 0.009 * (1 - 0.82 * u ** 1.3) + 0.0007, gains=(0.6, 0.4, 0.25))
        pr = np.cumsum(2.5 + 6.5 * u ** 2) / SR
        drone = drone * (1 - 0.25 * (0.5 + 0.5 * np.cos(2 * np.pi * pr)) * pt(0.2, 0.8, t))
        # (the five lunges: the cracks jolting on, the land tearing in front of them, a deep jolt each, growing)
        lunge = np.zeros(n)
        jolt = np.zeros(n)
        for i in range(5):
            tl = i * BEAM_LEN / 4.35
            sz = 0.45 + 0.55 * i / 4
            lunge += rip(t, tl, 0.42, 45, 700) * sz
            jolt += tone_blow(t, tl, 44.0 + 2 * i, 31.0, 27.0, 0.06, 0.006, ((0.6, 0.2), (0.4, 0.55)), drive=2.5) * sz
        grind = churn(n, 30, 600, slope=-3.5, depth=6.0) * (0.3 + 0.7 * u ** 1.5)
        press = tone_blow(t, 0.0, 30.0, 30.0, 33.0, 1.0, 0.8, ((1.0, 60.0),), drive=1.5, octv=0.2, harm=0.3) * u ** 1.8
        # (drawn in: in the last half second a low rush rising to the hit)
        suck = churn(n, 40, 900, slope=-3.0, depth=3.0) * pt(BEAM_LEN - 0.55, BEAM_LEN - 0.02, t) ** 2
        ref = np.std(drone)
        x = drone + T.unit(lunge) * ref * 0.5 + T.unit(jolt) * ref * 0.9 + grind * ref * 0.45 + T.unit(press) * ref * 1.0 \
            + suck * ref * 0.6
        lvl = 10 ** ((-6.0 + 4.5 * u ** 1.2 + 1.5 * pt(BEAM_LEN - 0.4, BEAM_LEN - 0.02, t)) / 20)
        x = T.unit(x) * lvl
        x *= pt(0.0, 0.05, t)
        x = body_drive(x, 0.0, 5.0, BEAM_LEN, 1.0)
        x = drive_lows(x, 0.45)
        # (the finale's pre-roll, as the reference's climaxes do it: from 1.3 s out the rest drains away in a step while one
        # low tone dives under it, 160 down to 55 Hz, swelling (F3 only); then everything sucked out FIN_VAC s before
        # the hit: longer than any slam's vacuum)
        vac = FIN_VAC[FINALE]
        dive_on = FINALE == "F3"
        drain = 1 - (0.75 if dive_on else 0.0) * pt(BEAM_LEN - 1.35, BEAM_LEN - 1.15, t)
        dive = held_boom(t, BEAM_LEN - 1.2, 160.0, 50.0, 0.55, 1.2, 1.0, drive=2.5) * pt(BEAM_LEN - 1.35, BEAM_LEN - 1.1, t) * (0.6 + 0.4 * pt(BEAM_LEN - 1.1, BEAM_LEN - vac - 0.05, t))
        x = x * drain + (dive / (np.abs(dive).max() + 1e-12) * np.abs(x).max() * 0.8 if dive_on else 0.0)
        x *= 1 - 0.995 * pt(BEAM_LEN - vac - 0.04, BEAM_LEN - vac, t)
        x[int(BEAM_LEN * SR):] = 0
        x = PB.causal_lowcut(x, 18.0)
    finish("beam", x, -10.0, tail=0.01, clip=True, clip_db=5.0, dest=dest)


# ======================================================================================================  take C: the blows
# Take C of the hammer blows (slam1-5, slam_far1-5, slam_all), built on how stylised sound design lands a colossal hit
# (measured from reference recordings, never copied). What those hits are:
# the swing's pressure building and then sucked out to near silence for a tenth of a second; a front of 2-5 ms; a WALL:
# a dense, driven, full-band burst that stays within 6 dB of its loudest for 2.5-3 s (peak only 3-5 dB over its loudest
# 400 ms), its top end ringing half a second; under it a held low boom, one tone at 40-90 Hz falling slowly (a fifth or
# so over a second and a half) and held for 2-3 s, driven so its harmonics fill 100-500 Hz; the ground shuddering under
# it in slow pulses; then a decay of a second or two. No patter, trickle, grit or crackle anywhere: every noise in it
# is smooth and dense, and nothing after the front has a front of its own.
# The five characters (eager, stiff, showy, brute, wary): boom (f0, f1 Hz, seconds of fall), hold (s), shudder (Hz, dB),
# wall (hold s, brightness: its top Hz), a second blow (s after, size) or none (none now: one bang a blow),
# level (dB).
SLAM_C = (
    # eager: a bright, quick blow, a fast shudder
    dict(boom=(74.0, 50.0, 0.9), hold=2.0, shud=(5.6, 5.0), wall=(0.4, 11000.0), peak=320.0, again=None, body=None, db=-8.6),
    # stiff: a hard bright front (`front`: it cuts through the others' tails), then short, dull and thick, one blow, no
    # shudder, the boom barely falling
    dict(boom=(48.0, 40.0, 0.6), hold=1.6, shud=(0.0, 0.0), wall=(0.3, 6000.0), peak=200.0, again=None, body=None, front=1.0, db=-8.6),
    # showy: the widest, a falling body over a long falling boom
    dict(boom=(66.0, 38.0, 1.8), hold=2.8, shud=(3.8, 6.0), wall=(0.7, 12000.0), peak=360.0, again=None, body=(180.0, 50.0), db=-8.4),
    # brute: the deepest and darkest, a slow heavy shudder
    dict(boom=(42.0, 28.0, 1.6), hold=3.0, shud=(2.8, 8.0), wall=(0.6, 5500.0), peak=160.0, again=None, body=None, db=-8.7),
    # wary: a high, nearly level boom with a short body falling onto it, a fast light tremble
    dict(boom=(58.0, 52.0, 1.0), hold=2.2, shud=(6.8, 3.5), wall=(0.45, 8500.0), peak=260.0, again=None, body=(120.0, 60.0), db=-8.9),
)
SUCK = 0.14                                 # (the vacuum before the blow: the swing's pressure cut this long before it)


def held_boom(t, t0, f0, f1, fall, hold, decay, drive=3.0):
    """One held low tone from t0: f0 falling to f1 Hz (time constant `fall` s), its level sagging 4 dB over `hold` s and
    then dying (`decay` s), its pitch wavering a little; the tone and its driven harmonics (odd and some even, up to
    ~600 Hz) together: felt as one long BWOOM, heard on small speakers by its harmonics."""
    u, on = after(t, t0)
    n = len(t)
    f = (f1 + (f0 - f1) * np.exp(-u / fall)) * (1 + 0.006 * PB.slow_random(n, 0.3, 2.0))
    ph = 2 * np.pi * np.cumsum(f * on) / SR + rng().uniform(0, 6.28)
    env = (1 - np.exp(-u / 0.004)) * 10 ** (-4.0 * np.clip(u / hold, 0, 1) / 20) * np.exp(-np.maximum(u - hold, 0) / decay) * on
    s = np.sin(ph) + 0.3 * np.sin(2 * ph + 0.7)
    hm = (np.tanh(drive * s + 0.25) - np.tanh(0.25)) / np.tanh(drive)
    hm = band(hm - s * 0.8, None, 650, 2)
    return (s + 0.9 * hm) * env


def wall(t, t0, hold, top, tail, peak=250.0, dark=0.8):
    """The blow's wall of sound: smooth dense noise in half-octave bands from 30 Hz to `top`, each with a 2-5 ms front,
    held (sagging) for `hold` s and then dying over `tail` s, the upper bands shorter by `dark` (the top rings about half
    a second); flat to `peak` Hz, -3 dB an octave over it. Never grainy: each band's level moves only slowly."""
    n = len(t)
    u, on = after(t, t0)
    out = np.zeros(n)
    wide = 2 ** 0.3
    for fc in np.geomspace(30.0, top, int(np.log2(top / 30.0) * 2) + 1):
        lvl = 1.0 if fc <= peak else (peak / fc) ** 0.5
        k = (fc / peak) ** (-0.5 * dark) if fc > peak else 1.0
        h, tl = hold * min(k * 1.2, 1.0), tail * min(k * 1.3, 1.0)
        env = (1 - np.exp(-u / (0.0015 + 0.12 / fc))) * 10 ** (-6.0 * np.clip(u / max(h, 1e-3), 0, 1) / 20) \
            * np.exp(-np.maximum(u - h, 0) / tl) * on
        g = np.exp(1.0 / 8.686 * PB.slow_random(n, 0.3, 2.5))
        out += T.unit(band(nz(n), fc / wide, fc * wide, 2)) * lvl * env * g
    return out / (np.abs(out).max() + 1e-12)


def shudder(t, t0, rate, depth_db, hold, decay, lo=28.0, hi=700.0):
    """The ground shuddering under the blow: a low roar (smooth, 28-700 Hz) pulsing at `rate` Hz (`depth_db` deep, the
    pulses slowing a little as it dies), held and dying with the boom. Rate 0: no pulsing, the roar alone."""
    n = len(t)
    u, on = after(t, t0)
    roar = churn(n, lo, hi, slope=-4.0, depth=3.0, turns=40.0)
    env = (1 - np.exp(-u / 0.06)) * 10 ** (-5.0 * np.clip(u / hold, 0, 1) / 20) * np.exp(-np.maximum(u - hold, 0) / decay) * on
    if rate > 0:
        ph = 2 * np.pi * np.cumsum(rate * (1 - 0.25 * np.clip(u / (hold + decay), 0, 1)) * on) / SR
        env = env * 10 ** (-depth_db * (0.5 - 0.5 * np.cos(ph)) / 20)
    return roar * env


def slam_c_parts(c):
    """Character c's blow, take C, as its layers: `swing` (the hammer's push building for 1.2 s, then sucked out to near
    silence SUCK s before contact: the vacuum), `boom` (the held low tone), `wall` (the dense driven burst), `shudder`
    (the ground pulsing under it), `again` (a second, smaller wall and boom where the character's hammer bites twice),
    `green` (the cracks' energy, low), `space` is put on after."""
    P = SLAM_C[c]
    Q = SLAM_TAKES[c]
    n = int(SLAM_D * SR)
    t = np.arange(n) / SR
    t0 = SLAM_LEAD
    s = np.clip((t - (t0 - 1.2)) / 1.2, 0, 1)
    v = s ** 1.6 * (t < t0)
    push = churn(n, 24, 500, slope=-4.5, depth=3.0, turns=40.0)
    fc = 90.0 + 330.0 * s ** 1.5
    w = np.zeros(n)
    hop = 1024
    for i in range(0, min(n, int((t0 + 0.05) * SR)), hop):
        j = slice(max(0, i - hop), min(n, i + 2 * hop))
        y = band(push[j], None, fc[i], 2)
        w[j] += y * np.hanning(len(y)) * 0.66
    swing = T.unit(w) * v * (1 - pt(t0 - SUCK - 0.03, t0 - SUCK + 0.01, t) * 0.995)
    f0, f1, fall = P["boom"]
    boom = held_boom(t, t0, f0, f1, fall, P["hold"] * 0.85, 0.55)
    ref = np.sqrt(np.mean(boom[int(t0 * SR):int((t0 + 1.0) * SR)] ** 2)) + 1e-12
    wl = wall(t, t0, P["wall"][0], P["wall"][1], 0.75, peak=P["peak"]) * ref * 4.0
    if P.get("front"):
        # (a hard, bright front: a short full-band wall, 60 ms held and gone in 150 more; one front, not a crack)
        wl += wall(t, t0, 0.06, 12000.0, 0.15, peak=600.0, dark=0.5) * ref * 4.0 * P["front"]
    sh = shudder(t, t0 + 0.04, P["shud"][0], P["shud"][1], P["hold"] * 0.85, 0.6) * ref * 1.2
    if P["shud"][0] > 0:
        # (the whole wall pulses with the ground once the first half second has passed, as the reference's shuddering
        # blows do: slow, low, never a patter)
        u = np.maximum(t - t0, 0)
        ph = 2 * np.pi * np.cumsum(P["shud"][0] * (1 - 0.25 * np.clip(u / (P["hold"] + 1.1), 0, 1)) * (t >= t0)) / SR
        wl = wl * 10 ** (-P["shud"][1] * 0.8 * pt(0.3, 0.7, u) * (0.5 - 0.5 * np.cos(ph)) / 20)
    again = np.zeros(n)
    if P["again"]:
        dt, sz = P["again"]
        again = (wall(t, t0 + dt, 0.3, P["wall"][1] * 0.6, 0.6, peak=180.0, dark=1.1) * ref * 3.0
                 + held_boom(t, t0 + dt, f0 * 0.85, f1 * 0.9, fall, 0.8, 0.6) * 0.6) * sz
    en = band(green(t, t0 + 0.08, Q["green"][0], 0.4, 1.4, 0.82), None, 900, 2)
    body = np.zeros(n) if P["body"] is None else held_boom(t, t0 + 0.008, P["body"][0], P["body"][1], 0.4, 0.9, 0.5, drive=2.5) * 0.5
    L = dict(swing=swing * ref * 0.16, boom=boom, body=body, wall=wl, shudder=sh, again=again, green=T.unit(en) * ref * 0.25)
    return L, P


def press(x, t0, par_db=4.5):
    """Driven like the reference's hits: the whole blow into a lopsided soft saturation (lows and the rest apart, so the
    boom doesn't pump the top), gain set so its peak sits about `par_db` over its loudest 400 ms; the sub under 40 Hz
    left clean."""
    sub = band(x, None, 40.0, 2)
    rest = x - sub
    lo = band(rest, None, 160.0, 2)
    hi = rest - lo
    seg = slice(int(t0 * SR), int((t0 + 1.5) * SR))
    out = sub.copy()
    for part, bias in ((lo, 0.12), (hi, 0.05)):
        r = np.percentile(np.abs(part[seg]), 99.5) + 1e-12
        g = 2.2
        out += (np.tanh(g * part / r + bias) - np.tanh(bias)) / g * r
    # (one more gentle stage over the sum, which sets the peak to loudness)
    r = np.percentile(np.abs(out[seg]), 99.9) + 1e-12
    for g in np.linspace(1.0, 4.0, 13):
        y = np.tanh(g * out / r) / g * r
        if 20 * np.log10(np.abs(y).max() / (T.loudest(y) + 1e-12)) <= par_db:
            break
    return y


def slam_c(c, dest, stems=None):
    with PB.seeded(57300 + c):
        L, P = slam_c_parts(c)
        x = press(sum(L.values()), SLAM_LEAD)
        near = verb(x, 3.0, 570 + c, 0.25, (4000, 300), 1.1)
        near = drive_lows(near, 0.4)
        near = PB.causal_lowcut(near, 18.0)
        far = far_of(x, 580 + c, lp=2800.0, wet=0.8)
        far = PB.causal_lowcut(far, 18.0)
    g = finish(f"slam{c + 1}", near, P["db"], tail=1.0, clip=True, clip_db=4.0, dest=dest)
    finish(f"slam_far{c + 1}", far, P["db"] - 1.0, tail=1.5, clip=True, clip_db=4.0, dest=dest)
    if stems:
        write_stems(stems, f"slam{c + 1}_C", L, g, lambda y: verb(y, 3.0, 570 + c, 0.25, (4000, 300), 1.1))


def slam_all_c(dest, stems=None):
    """What the five together add (take C), through the ground: the deepest held boom of the strike (40 falling to 27 Hz,
    held three seconds), a darker wall, the land shuddering in slow pulses that slow as it dies, the five's blows under it
    as two smaller walls; no air, no top: it comes through the ground."""
    d = 8.0
    n = int(d * SR)
    t = np.arange(n) / SR
    t0 = SLAM2_LEAD
    with PB.seeded(57401):
        boom = held_boom(t, t0, 40.0, 27.0, 1.4, 1.9, 0.9, drive=3.5)
        ref = np.sqrt(np.mean(boom[int(t0 * SR):int((t0 + 1.0) * SR)] ** 2)) + 1e-12
        # (the shared ground roll under the five: no front of its own and nothing much over 600 Hz, so each giant's
        # own blow stays heard on top of it)
        wl = wall(t, t0, 0.8, 700.0, 1.4, peak=110.0, dark=1.3) * ref * 2.2 * pt(t0, t0 + 0.12, t)
        sh = shudder(t, t0 + 0.05, 3.2, 7.0, 1.9, 1.0, hi=420.0) * ref * 1.6
        en = band(green(t, t0 + 0.05, 36.7, 0.35, 1.8, 0.9, spread=1.6), None, 700, 2)
        L = dict(boom=boom, wall=wl, shudder=sh, green=T.unit(en) * ref * 0.25)
        x = press(sum(L.values()), t0, 5.0)
        x = verb(x, 4.0, 5701, 0.3, (1800, 250), 1.6)
        x = drive_lows(x, 0.5)
        x = PB.causal_lowcut(x, 16.0)
    g = finish("slam_all", x, -11.0, tail=2.0, clip=True, clip_db=5.0, dest=dest)
    if stems:
        write_stems(stems, "slam_all_C", L, g, lambda y: verb(y, 4.0, 5701, 0.3, (1800, 250), 1.6))


# ---- the finale: three takes, each a whole idea (a split flash-then-low take read as a scrunch).
# R4 (the game's): fitted to a reference, below. F1: the round-2 blast made bigger and longer: a vacuum, then one full-band wall 4 s long with the
# held deep boom and the falling body. F2: two waves: a full-band detonation whose low lands with its front, then a
# second, bigger wave 2.5 s later. F3: the reference's climax structure (150.35 s, 247.83 s, 166.08 s): a low dive into a
# cut, then a crushed, flat-topped plateau of the whole band held over two seconds as if frozen, a hard cut to near
# silence, and the land coming back in rolling swells. None has a bright layer without its low end, nor any grit.
FINALE = "R4"
FINALES = ("F1", "F2", "F3", "R4")
FIN_VAC = {"F1": 0.16, "F2": 0.18, "F3": 0.25, "R4": 0.16}  # (the beam's vacuum before the hit, per take)
F2_SECOND = 2.5                                  # (F2: the second wave, this long after the first)
F3_HOLD = 2.3                                    # (F3: the frozen plateau, then the cut)


def _rolls(t, t0, start, ref, top=420.0):
    plan, tr = [], start
    g_ = np.random.default_rng(59131)
    while tr < 17.0:
        far = min((tr - start) / 12.0, 1.0)
        plan.append((tr, 10 ** ((-11.0 * far + g_.uniform(-3, 1.5)) / 20), 24, top - 280 * far, 0.25 + 0.5 * far, 0.9 + 1.2 * far))
        tr += g_.gamma(1.8, 0.4 + 0.3 * far)
    return surges(t, t0, plan) * ref * 1.5


def _bed(t, t0, ref, start=0.3):
    n = len(t)
    u = np.maximum(t - t0, 0)
    return T.unit(band(nz(n), 20, 46, 3)) * pt(t0 + start, t0 + start + 0.6, t) \
        * 10 ** (np.interp(u, [0, 1, 3, 6, 10, 15, 19, BLAST_D], [-6, -6, -7, -10, -15, -21, -28, -50]) / 20) \
        * np.exp(3.0 * PB.slow_random(n, 0.2, 1.5) / 8.686) * (t >= t0) * ref


def _echoes(L):
    src = band(sum(L.values()), None, 600, 2)
    n = len(src)
    ech = np.zeros(n)
    for dt, gn, hi in ((1.0, 0.3, 600), (2.1, 0.24, 450), (3.4, 0.18, 330), (5.2, 0.14, 250), (7.8, 0.1, 190)):
        e = band(src, 22, hi * rng().uniform(0.85, 1.15), 2)
        e = verb(e, 0.6, int(dt * 100), 0.6, (hi, 100), 0.15) * gn
        k = int(dt * SR)
        ech[k:] += e[:n - k]
    return ech


# ---- R4: the finale, fitted to a reference explosion (measured only, never copied). Its shape, fitted to the hit at CL_HIT: a full-band explosion of ~1.7 s
# that bursts again and again (~6 big bursts a second, 4-14 dB over its roar; its weight low, flat from 250 Hz up, a
# resonance near 500 Hz), a breath 0.2 s long (5 dB down), a zap (a tone falling from ~1 kHz into the drone in a tenth
# of a second), then the drone: a hard-driven sine falling slowly from 55 to 35 Hz for 2.5 s (odd harmonics: the 3rd
# 9 dB under it, the 5th 16, the 7th 25), the sub rumbling under it, louder than the explosion, the top gone; a last
# full-band burst and a cut. Everything limited hard, as the reference is.
R4_BANDS = ((20, 60), (60, 120), (120, 250), (250, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 8000), (8000, 16000))
R4_A = (-4.4, -4.8, -10.1, -13.1, -13.5, -14.4, -14.9, -16.7, -19.1)   # (the explosion's band shares, dB of the whole)
# (It once sounded static: the roar held the reference's top steady under everything, a constant
# hiss 4-6 dB over the reference's over 2 kHz. Now the steady roar stops under 2 kHz, the top comes only with each
# burst and darker than measured, and the drone has no hiss under it.)
R4_ROAR = (-4.4, -4.8, -10.1, -13.1, -13.5, -17.0, -30.0, -42.0, -60.0)
R4_BURST = (-4.4, -4.8, -10.1, -13.1, -13.5, -14.4, -18.0, -24.0, -34.0)
# (the last burst before the cut: low only. Full band it came in as a split second of static over the drone, whose top
# had been empty for 2.5 s)
R4_LAST = (-4.4, -4.8, -10.1, -16.0, -26.0, -45.0, -60.0, -60.0, -60.0)
R4_GAP = (1.75, 1.95)                  # (the breath)
R4_ZAP = 0.0                           # (the zap into the drone: on the hit, under the explosion, so the bass lands with the
                                       # impact frames; the reference has it after the breath)
R4_END = 4.55                          # (the last burst; the drone cut at R4_CUT)
R4_CUT = 4.78
R4_DRONE = (55.0, 35.0)                # (the drone's fall, Hz)


def shaped_noise(n, shares, bands=R4_BANDS):
    """Noise whose power in each band is `shares` (dB of the whole)."""
    out = np.zeros(n)
    for (lo, hi), sdb in zip(bands, shares):
        out += T.unit(band(nz(n), lo, hi, 4)) * 10 ** (sdb / 20)
    return out


def r4_parts(t, t0):
    n = len(t)
    u = np.maximum(t - t0, 0)
    on = t >= t0
    g_ = np.random.default_rng(59441)
    # (the explosion: its roar, shaped to the reference's bands, a resonance near 500 Hz, its level wandering slowly)
    roar = shaped_noise(n, R4_ROAR) + T.unit(band(nz(n), 400, 620, 2)) * 10 ** (-12.0 / 20)
    a_env = (1 - np.exp(-u / 0.003)) * (1 - pt(R4_GAP[0] - 0.05, R4_GAP[0] + 0.02, u) * (1 - 10 ** (-9.0 / 20))) \
        * (1 - pt(R4_GAP[1], R4_GAP[1] + 0.08, u)) * on
    roar = roar * a_env * np.exp(2.0 / 8.686 * PB.slow_random(n, 1.0, 6.0))
    # (the bursts: ~6 a second, each a short full-band blow 4-14 dB over the roar)
    bursts = np.zeros(n)
    tb = 0.0
    while tb < R4_GAP[0] - 0.05:
        size = 10 ** (g_.uniform(4.0, 14.0) / 20) if tb > 0 else 10 ** (14.0 / 20)
        ub = np.maximum(t - (t0 + tb), 0)
        bursts += shaped_noise(n, R4_BURST) * (1 - np.exp(-ub / 0.002)) * np.exp(-ub / g_.uniform(0.05, 0.12)) * (t >= t0 + tb) * (size - 1) * 0.7
        tb += g_.uniform(0.09, 0.25)
    # (the zap: a tone falling from 1 kHz into the drone's pitch in a tenth of a second; then the drone, a hard-driven sine
    # falling slowly 55 -> 35 Hz, its odd harmonics from the drive)
    tz = t0 + R4_ZAP
    uz = np.maximum(t - tz, 0)
    f_dr = R4_DRONE[1] + (R4_DRONE[0] - R4_DRONE[1]) * np.exp(-uz / 1.6)
    f = f_dr + (1000.0 - R4_DRONE[0]) * np.exp(-uz / 0.025)
    ph = 2 * np.pi * np.cumsum(f * (t >= tz)) / SR
    d_env = (1 - np.exp(-uz / 0.004)) * (1 - pt(R4_CUT - 0.03, R4_CUT, u)) * (t >= tz)
    drone = np.tanh(5.5 * np.sin(ph)) / np.tanh(5.5) * d_env
    sub = T.unit(band(nz(n), 18, 60, 4)) * d_env * pt(tz + 0.05, tz + 0.25, t) * np.exp(1.5 / 8.686 * PB.slow_random(n, 0.5, 3.0))
    # (the last burst, low, then the cut)
    ue = np.maximum(t - (t0 + R4_END), 0)
    end = shaped_noise(n, R4_LAST) * (1 - np.exp(-ue / 0.003)) * (t >= t0 + R4_END) * (1 - pt(R4_CUT - 0.03, R4_CUT, u))
    return dict(explosion=roar, bursts=bursts, zap_drone=drone, sub=sub, last=end)


def blast_c_parts(take=None):
    """The finale's layers for `take` (FINALE by default); each layer named plainly for the stems."""
    take = take or FINALE
    n = int(BLAST_D * SR)
    t = np.arange(n) / SR
    t0 = BLAST_LEAD
    u = np.maximum(t - t0, 0)
    en = green(t, t0 + 0.02, 73.4, 0.08, 1.8, 0.66, spread=1.5) * 0.5 + green(t, t0 + 0.05, 36.7, 0.25, 2.6, 0.8, spread=2.0)
    en = T.unit(band(en, None, 1100, 2))
    if take == "F1":
        # (the round-2 blast, bigger and longer: the wall held 1.8 s and dying over 2.8, the boom held 4.5 s)
        boom = held_boom(t, t0, 34.0, 24.0, 2.0, 4.5, 2.5, drive=3.5) * 1.7
        ref = np.sqrt(np.mean(boom[int(t0 * SR):int((t0 + 1.0) * SR)] ** 2)) + 1e-12
        L = dict(
            wall=wall(t, t0, 1.8, 10000.0, 2.8, peak=260.0, dark=0.6) * ref * 2.8,
            boom=boom,
            body=held_boom(t, t0 + 0.01, 150.0, 40.0, 0.6, 1.8, 1.0, drive=2.5) * 0.6,
            surge=wall(t, t0 + SURGE_AT, 1.4, 1500.0, 2.0, peak=120.0, dark=1.3) * ref * 1.5 * pt(t0 + SURGE_AT - 0.3, t0 + SURGE_AT + 0.4, t),
            shudder=shudder(t, t0 + 0.05, 3.0, 6.0, 4.5, 2.5, hi=600.0) * ref * 1.0,
            column=band(churn(n, 35, 1800, slope=-3.0, depth=3.0, turns=40.0), None, 1500, 1)
            * (1 - np.exp(-np.maximum(u - 0.05, 0) / 0.6)) * (0.6 * np.exp(-u / 2.8) + 0.4 * np.exp(-u / 6.0)) * (t >= t0) * ref * 1.0,
            rolls=_rolls(t, t0, 1.8, ref), bed=_bed(t, t0, ref), green=en * ref * 0.14)
    elif take == "F2":
        # (two waves: the first full-band with its low on its front, the second 2.5 s on and bigger, swelling in fast)
        t2 = t0 + F2_SECOND
        boom1 = held_boom(t, t0, 40.0, 30.0, 1.0, 1.6, 0.8, drive=3.5) * 1.5
        ref = np.sqrt(np.mean(boom1[int(t0 * SR):int((t0 + 1.0) * SR)] ** 2)) + 1e-12
        sw = pt(t2 - 0.12, t2 + 0.12, t)
        L = dict(
            wall=wall(t, t0, 0.9, 9000.0, 1.0, peak=240.0, dark=0.7) * ref * 2.6,
            boom=boom1,
            wall2=wall(t, t2 - 0.1, 2.2, 11000.0, 2.6, peak=280.0, dark=0.5) * sw * ref * 4.0,
            boom2=held_boom(t, t2, 32.0, 22.0, 2.0, 3.2, 2.2, drive=3.8) * 2.4,
            body2=held_boom(t, t2 + 0.01, 170.0, 40.0, 0.7, 1.6, 0.9, drive=2.5) * 0.8,
            shudder=shudder(t, t2 + 0.05, 2.6, 7.0, 3.2, 2.2, hi=600.0) * ref * 1.3,
            rolls=_rolls(t, t0, F2_SECOND + 2.5, ref), bed=_bed(t, t0, ref), green=en * ref * 0.14)
    elif take == "R4":
        # (the reference's shape, levels set as measured: the explosion -6 dB RMS, the drone +2 over it, the sub under
        # it 3 dB down, the last burst as the explosion; the land rolling on after the cut, quieter, for the world)
        P = r4_parts(t, t0)
        ref = 1.0
        a = slice(int((t0 + 0.05) * SR), int((t0 + 1.7) * SR))
        b = slice(int((t0 + 2.1) * SR), int((t0 + 4.5) * SR))
        ra = np.sqrt(np.mean((P["explosion"] + P["bursts"])[a] ** 2)) + 1e-12
        rb = np.sqrt(np.mean(P["zap_drone"][b] ** 2)) + 1e-12
        rs = np.sqrt(np.mean(P["sub"][b] ** 2)) + 1e-12
        L = dict(explosion=P["explosion"] / ra, bursts=P["bursts"] / ra, drone=P["zap_drone"] / rb * 10 ** (2.0 / 20),
                 sub=P["sub"] / rs * 10 ** (-1.0 / 20), last=P["last"] / (np.sqrt(np.mean(P["last"][int((t0 + R4_END + 0.02) * SR):int((t0 + R4_END + 0.2) * SR)] ** 2)) + 1e-12))
        after = pt(t0 + R4_CUT, t0 + R4_CUT + 0.4, t)
        L["rolls"] = _rolls(t, t0, R4_CUT + 0.1, 0.25) * after
        L["bed"] = _bed(t, t0, 0.3, R4_CUT) * after
        # (no air under the drone: the reference's hiss there read as static)
        L["green"] = en * 0.06
    else:
        # (F3: the frozen plateau: everything at once, crushed flat, held level for F3_HOLD s with a pitched sweep falling
        # through it, cut to near silence for a fifth of a second, then the land coming back in rolling swells)
        boom = held_boom(t, t0, 36.0, 26.0, 1.6, F3_HOLD, 0.06, drive=4.0) * 1.7
        ref = np.sqrt(np.mean(boom[int(t0 * SR):int((t0 + 1.0) * SR)] ** 2)) + 1e-12
        hold = pt(t0, t0 + 0.01, t) * (1 - pt(t0 + F3_HOLD - 0.04, t0 + F3_HOLD, t))
        plateau = churn(n, 28, 9000, slope=-3.0, depth=2.0, turns=60.0)
        plateau = T.unit(band(plateau, None, 6000, 1)) * hold * (1 - 0.35 * pt(0.0, F3_HOLD, u))
        back = t0 + F3_HOLD + 0.2
        L = dict(
            plateau=plateau * ref * 2.6,
            boom=boom,
            body=held_boom(t, t0 + 0.01, 180.0, 45.0, 0.9, F3_HOLD - 0.1, 0.05, drive=2.5) * 0.7 * hold,
            shudder=shudder(t, t0 + 0.05, 4.2, 5.0, F3_HOLD, 0.05, hi=700.0) * hold * ref * 1.0,
            aftermath=(wall(t, back, 1.4, 2500.0, 2.0, peak=140.0, dark=1.2) * ref * 2.2
                       + held_boom(t, back, 30.0, 22.0, 1.5, 2.0, 2.0, drive=3.0) * 1.2) * pt(back, back + 0.5, t),
            rolls=_rolls(t, t0, F3_HOLD + 1.5, ref), bed=_bed(t, t0, ref, F3_HOLD + 0.2) * 1.0, green=en * ref * 0.14)
    if take != "R4":                          # (the reference is dry: no echoes in its body)
        L["echoes"] = _echoes(L)
    return L


def blast_c(dest=None, stems=None, take=None, stem_name=None):
    """The finale (`blast_c_parts`), driven like the reference's biggest hits, in a short dry space; the mids let down a
    little after its body so the bursts land over it (the lows roll on); the far take through a kilometre of air."""
    take = take or FINALE
    late = {"F1": 1.8, "F2": F2_SECOND + 1.6, "F3": F3_HOLD + 1.5, "R4": R4_CUT}[take]
    with PB.seeded(59301):
        L = blast_c_parts(take)
        x = press(sum(L.values()), BLAST_LEAD, 4.5)

        def space(y):
            near = verb(y, 4.0, 5931, 0.06 if take == "R4" else 0.25, (4000, 300), 1.6)
            tt_ = np.arange(len(near)) / SR
            mids = band(near, 160, None, 2)
            near = near - mids + mids * 10 ** (-6.0 * pt(BLAST_LEAD + late, BLAST_LEAD + late + 2.2, tt_) / 20)
            return near * 10 ** (-4.0 * pt(BLAST_LEAD + late, BLAST_LEAD + late + 3.5, tt_) / 20)
        near = drive_lows(space(x), 0.5)
        near = PB.causal_lowcut(near, 16.0)
        far = far_of(x, 5932, lp=2400.0, smear=0.03, wet=0.85, length=6.0)
        far = PB.causal_lowcut(far, 16.0)
        if take == "F3":
            # (the hard cut after the frozen plateau: everything, its space too, to near silence for a fifth of a second)
            tt0 = np.arange(len(near)) / SR - BLAST_LEAD
            cut = 1 - 0.985 * pt(F3_HOLD - 0.04, F3_HOLD, tt0) * (1 - pt(F3_HOLD + 0.2, F3_HOLD + 0.3, tt0))
            near, far = near * cut, far * cut[:len(far)]
    g = finish("blast", near, -4.3, tail=3.0, clip=True, clip_db=2.5, dest=dest)
    finish("blast_far", far, -4.0, tail=3.0, clip=True, clip_db=2.5, dest=dest)
    if stems:
        write_stems(stems, stem_name or "blast_C", L, g, space)


def finales(out):
    """Every finale take as a set (beam, ground, blast, blast_far) under `out`/F1.., its stems beside them, each as MP3,
    and the strike from 18.5 to 26 s at 300 blocks with it in place (`out`/F1_300.mp3 ...). The game's files are left
    as they are."""
    global FINALE
    out = Path(out)
    keep = FINALE
    for tk in FINALES:
        FINALE = tk
        d = out / tk
        fd = d / "files"
        fd.mkdir(parents=True, exist_ok=True)
        beam(dest=fd)
        ground(dest=fd)
        blast_c(dest=fd, stems=out, stem_name=tk)
        for f in sorted(fd.glob("*.ogg")):
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(f), "-c:a", "libmp3lame", "-b:a", "192k",
                            str(f.with_suffix(".mp3"))], check=True)
        x = mixdown(300, 0.0)[int(18.5 * SR):int(26.0 * SR)]
        p = out / f"{tk}_300.wav"
        write_wav(p, x)
        mp3(p)
        picture(out / f"{tk}_300.png", x.mean(axis=1), f"{tk} at 300 blocks, 18.5-26 s (the hit at {20 - 18.5:.2f} s in, with the impact frames)",
                [(20 - 18.5, "hit")], top=16000.0)
        _SRC.clear()
        _DEC.clear()
    FINALE = keep


# (the bursts, take C: per giant take, the held boom (f0, f1 Hz) and the falling body's start)
BURST_C = ((62.0, 44.0, 220.0), (56.0, 40.0, 200.0), (68.0, 46.0, 240.0))


def burst_c_parts(k):
    """Hammer and arms bursting apart, take C, as its layers: `wall` (the rupture's wall, held a third of a second), `boom`
    (a held tone falling a fifth over a second, held 1.5 s), `body` (a short falling body over it), `pieces` (the big
    pieces coming down as two or three dull dark walls, 1.4-3.5 s on: no grit), `green` (the energy let go). The vacuum
    before it is the charge's end (`CH_VAC`)."""
    n = int(BURST_D * SR)
    t = np.arange(n) / SR
    t0 = BURST_LEAD
    f0, f1, fb = BURST_C[k]
    boom = held_boom(t, t0, f0, f1, 0.9, 1.5, 0.8, drive=3.0)
    ref = np.sqrt(np.mean(boom[int(t0 * SR):int((t0 + 1.0) * SR)] ** 2)) + 1e-12
    body = held_boom(t, t0 + 0.005, fb, fb * 0.35, 0.35, 0.6, 0.4, drive=2.5) * 0.45
    wl = wall(t, t0, 0.35, 8000.0, 0.8, peak=240.0, dark=0.8) * ref * 3.6
    pieces = np.zeros(n)
    for j, (dt, sz) in enumerate(((1.5 + 0.2 * k, 0.5), (2.3 + 0.15 * k, 0.4), (3.2, 0.3))[:2 + k % 2]):
        pieces += (wall(t, t0 + dt, 0.15, 900.0, 0.45, peak=110.0, dark=1.4) * ref * 2.4
                   + held_boom(t, t0 + dt, 48.0 - 4 * j, 36.0 - 3 * j, 0.4, 0.3, 0.4) * 0.5) * sz
    en = T.unit(band(green(t, t0, (49.0, 46.25, 51.9)[k], 0.05, 1.0, 0.75, spread=1.4), None, 900, 2)) * ref * 0.3
    return dict(wall=wl, boom=boom, body=body, pieces=pieces, green=en)


def burst_c(k, dest=None, stems=None):
    with PB.seeded(61300 + k):
        L = burst_c_parts(k)
        x = press(sum(L.values()), BURST_LEAD, 5.0)
        near = verb(x, 3.0, 613 + k, 0.25, (4000, 300), 1.1)
        near = drive_lows(near, 0.45)
        near = PB.causal_lowcut(near, 18.0)
        far = far_of(x, 623 + k, lp=2800.0, wet=0.8)
        far = PB.causal_lowcut(far, 18.0)
    g = finish(f"burst{k + 1}", near, -9.5, tail=1.5, clip=True, clip_db=4.0, dest=dest)
    finish(f"burst_far{k + 1}", far, -11.0, tail=2.0, clip=True, clip_db=4.0, dest=dest)
    if stems:
        write_stems(stems, f"burst{k + 1}_C", L, g, lambda y: verb(y, 3.0, 613 + k, 0.25, (4000, 300), 1.1))


def take_c(out, stems=None):
    """Take C of the hammer blows (slam1-5, slam_far1-5, slam_all), written only under `out`/files (never into the game's
    folder), each as an MP3, and the whole strike with them in place of the game's heard from 300 blocks."""
    out = Path(out)
    fd = out / "files"
    fd.mkdir(parents=True, exist_ok=True)
    for c in range(len(SLAM_C)):
        slam_c(c, fd, stems if c == 0 else None)
    slam_all_c(fd, stems)
    for f in sorted(fd.glob("*.ogg")):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(f), "-c:a", "libmp3lame", "-b:a", "192k",
                        str(f.with_suffix(".mp3"))], check=True)
    for dist in (300,):
        report(f"colossi_C_{dist}", mixdown(dist, 0.0), out, cue_marks())
    _SRC.clear()
    _DEC.clear()


def ground(dest=None):
    """The finale through the ground, ahead of the air (by 0.7 s at 300 blocks, 1.6 s at 700): a deep falling thump and a
    dark mass under it, the land shuddering (low noise chopped at 10-13 Hz), dying away within about 0.6 s so the beam's
    vacuum still holds before the air's blast."""
    d = 4.0
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(58001):
        t0 = GROUND_LEAD
        x = thud(t, t0, 46.0, 19.0, 0.5, 1.0)
        r = np.std(x[:int(0.5 * SR)])
        x += mass(t, t0, np.abs(x).max() * 0.8, att=0.01, short=0.2, long=1.2, peak=80.0, top=500.0, dark=1.5)
        chop = np.clip(1 + 0.9 * PB.slow_random(n, 10.0, 13.0), 0.05, None)
        x += T.unit(band(nz(n), 25, 110, 2)) * chop * ar(t, t0, 0.04, 0.9) * r * 0.6
        x += T.unit(band(nz(n), 16, 45, 3)) * ar(t, t0, 0.1, 1.2) * r * 0.6
        x += surges(t, t0, ((0.12, 0.8, 20, 160, 0.06, 0.3),)) * r * 0.9
        x *= 1 - pt(0.35, 0.6, t) * 0.9
        x = drive_lows(x, 0.55, 70, 300)
        x = PB.causal_lowcut(x, 15.0)
    finish("ground", x, -13.0, tail=0.8, dest=dest)


BLAST_D = 22.0
SURGE_AT = 1.15                        # (the blast's surge passing the giants, seconds after the hit: CL_WAVE's 242 blocks a
                                       # second over the ring's 300, `cl_surge_r` in the pass)


def blast_parts(take="A"):
    """The blast, mono, as its layers (a dict, summed for the file; `--stems` writes them apart). The weight is in
    masses of noise, not tones: the sub (a push and a deep drop under it all); the blast itself, one huge dense mass
    whose body fills 40-800 Hz and darkens over two seconds, the ground's answer 0.33 s on and the column's 0.9 s in
    (each a deeper, darker mass), the surge going out past the giants at SURGE_AT (a broad low shove); the column
    climbing (a deep roar swelling over two seconds); the green let go (low detuned chords through sweeping combs,
    falling as they spread); then the long tail: the land rolling for fifteen seconds in slow heaving swells, a heaving
    22-60 Hz bed under it all, the boom back off the far land five times. Take B (`--takes` only): the blast's breaking
    from real rock (a quarry blast slowed, a building's fall slowed further under its front, a rockfall slowed for what
    rains back), over the same sub, swells, column, green and tail, the synthesised mass kept only under 300 Hz."""
    n = int(BLAST_D * SR)
    t = np.arange(n) / SR
    t0 = BLAST_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    sub = tone_blow(t, t0, 34.0, 28.0, 24.0, 0.05, 0.003, ((0.5, 0.35), (0.5, 2.2)), drive=1.0, octv=0.1, harm=0.1)
    boom = tone_blow(t, t0 + 0.008, 60.0, 35.0, 25.0, 0.08, 0.005, ((0.35, 0.35), (0.35, 1.8), (0.3, 5.0)), drive=3.5, harm=0.45) * 0.7
    low = sub * 1.2 + boom
    ref = np.sqrt(np.mean(band(low, 30, 120, 2)[int(t0 * SR):int((t0 + 0.4) * SR)] ** 2)) + 1e-12
    hit = mass(t, t0, 1.0, att=0.0025, short=0.25, long=2.2, peak=230.0, top=6000.0, dark=0.7)
    hit += mass(t, t0 + 0.33, 0.55, att=0.008, short=0.2, long=1.6, peak=150.0, top=1800.0, dark=1.2)
    hit += mass(t, t0 + 0.9, 0.45, att=0.02, short=0.3, long=2.4, peak=110.0, top=1200.0, dark=1.3)
    hit += mass(t, t0 + SURGE_AT, 0.4, att=0.08, short=0.4, long=2.0, peak=90.0, top=1000.0, dark=1.4)
    hit *= ref * 4.5
    # (the column climbing: a deep roar swelling as it goes up, slowly heaving)
    renv = (1 - np.exp(-np.maximum(u - 0.05, 0) / 0.6)) * (0.6 * np.exp(-u / 2.2) + 0.4 * np.exp(-u / 5.0)) * on
    roar = band(churn(n, 35, 3000, slope=-2.0, depth=6.0, turns=30.0), None, 2400, 1) * renv * ref * 3.0
    # (the tail: the land rolling, swell after swell, each further and darker; a heaving bed)
    plan, tr = [], 1.2
    g_ = np.random.default_rng(59131)
    while tr < 17.0:
        far = min((tr - 1.2) / 12.0, 1.0)
        plan.append((tr, 10 ** ((-12.0 * far + g_.uniform(-3, 1.5)) / 20), 24, 420 - 280 * far, 0.2 + 0.5 * far, 0.8 + 1.2 * far))
        tr += g_.gamma(1.8, 0.4 + 0.3 * far)
    rolls = surges(t, t0, plan) * ref * 1.3
    bed = T.unit(band(nz(n), 20, 46, 3)) * np.clip((u - 0.3) / 0.6, 0, 1) ** 2 \
        * 10 ** (np.interp(u, [0, 1, 3, 6, 10, 15, 19, BLAST_D], [-6, -6, -8, -12, -16, -21, -28, -50]) / 20) \
        * np.exp((3.0 * PB.slow_random(n, 0.2, 1.5) + 1.5 * PB.slow_random(n, 2.0, 6.0)) / 8.686) * on * ref * 1.1
    en = green(t, t0 + 0.02, 73.4, 0.08, 1.8, 0.66, spread=1.5) * 0.5 + green(t, t0 + 0.05, 36.7, 0.25, 2.6, 0.8, spread=2.0)
    en = T.unit(band(en, None, 1100, 2)) * ref * 0.22
    L = dict(sub=low, mass=hit, roar=roar, rolls=rolls, bed=bed, green=en)
    if take == "B":
        q = rec("quarry", 0.0, 9.0, 0.82, hp=45.0, fade_out=4.0, user="blast")
        d_ = rec("demolition", 0.0, 3.0, 0.5, hp=110.0, fade_out=1.5, user="blast")
        f_ = rec("rockfall", 0.55, 2.4, 0.5, hp=90.0, fade_in=0.1, fade_out=1.2, user="blast")
        L["quarry"] = lay(n, q, t0) * ref * 2.4 * (1 - 0.5 * pt(t0 + 3.0, t0 + 9.0, t))
        L["rock"] = lay(n, d_, t0 - 0.004) * ref * 1.6
        L["debris"] = lay(n, f_, t0 + 1.6) * ref * 0.6
        L["mass"] = band(hit, None, 300, 2) * 0.9
        L["roar"] = roar * 0.6
    src = band(sum(L.values()), None, 700, 2)
    ech = np.zeros(n)
    for dt, gn, hi in ((1.0, 0.32, 600), (2.1, 0.26, 450), (3.4, 0.2, 330), (5.2, 0.15, 250), (7.8, 0.1, 190)):
        e = band(src, 22, hi * rng().uniform(0.85, 1.15), 2)
        e = verb(e, 0.6, int(dt * 100), 0.6, (hi, 100), 0.15) * gn
        k = int(dt * SR)
        ech[k:] += e[:n - k]
    L["echoes"] = ech
    return L


def blast(take="A", dest=None, stems=None):
    """The explosion at the middle, the loudest, deepest and longest thing in the strike (`blast_parts`): in the land's
    space, the mids of its tail let down a little from 1.6 s so the bursts and the kneels are heard over it (its lows
    kept: the bed rolls on under them), its lows' harmonics for small speakers, the lows rounded off and the first
    instant into a soft clip. The far take: through a kilometre of air (the highs let down gently, the body kept)."""
    with PB.seeded(59101):
        L = blast_parts(take)
        x = body_drive(sum(L.values()), BLAST_LEAD, 5.0, 0.6, 1.8)

        def space(y):
            near = verb(y, 5.0, 5901, 0.3, (2400, 250), 1.8)
            tt_ = np.arange(len(near)) / SR
            mids = band(near, 160, None, 2)
            near = near - mids + mids * 10 ** (-6.0 * pt(BLAST_LEAD + 1.6, BLAST_LEAD + 4.0, tt_) / 20)
            return near * 10 ** (-4.5 * pt(BLAST_LEAD + 1.2, BLAST_LEAD + 5.0, tt_) / 20)
        near = space(x)
        near = drive_lows(near, 0.65)
        near = PB.causal_lowcut(near, 16.0)
        lows = band(near, None, 110, 4)
        near = near - lows + PB.soft_clip(lows, T.loudest(lows) * 10 ** (2.5 / 20), 0.5)
        far = far_of(x, 5902, lp=2200.0, smear=0.03, wet=0.9, length=6.0)
        far = PB.causal_lowcut(far, 16.0)
    g = finish("blast", near, -4.0, tail=3.0, clip=True, clip_db=4.0, dest=dest)
    finish("blast_far", far, -4.5, tail=3.0, clip=True, clip_db=3.0, dest=dest)
    if stems:
        write_stems(stems, f"blast_{take}", L, g, space)


def charge(k):
    """The blast's green light running up a hammer into the arms, CH_PEAK s to the burst: a low rich tone climbing an
    octave through a comb that tightens (rising, hollow, old), its voices beating faster; the stone straining under it
    as a deep churning pressure swelling up, deep fractures thudding in it more and more often, the pressure's sub
    building. All of it peaking as the burst lands, holding a little after."""
    d = CH_PEAK + 0.6
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(60100 + k):
        u = np.clip(t / CH_PEAK, 0, 1)
        r0 = (38.9, 41.2, 36.7)[k]
        f = r0 * 2 ** (u ** 1.5)
        tone = np.zeros(n)
        for det in (-1.0, 0.0, 1.0):
            ph = 2 * np.pi * np.cumsum(f + det * (0.3 + 4.0 * u ** 2)) / SR + rng().uniform(0, 6.28)
            for h in range(1, 24):
                if r0 * 2 * h * 1.4 > 5000:
                    break
                tone += np.sin(h * ph) / h ** 1.15
        tone = T.lowpass_glide(tone, 260.0, 1400.0, 1.4)
        tone = comb(tone, 0.0075 * (1 - 0.75 * u) + 0.0008, gains=(0.55, 0.35, 0.2))
        strain = churn(n, 40, 650, slope=-3.0, depth=7.0) * (0.15 + 0.85 * u ** 1.4)
        fr_t = np.sort(CH_PEAK * (1 - rng().random(5 + k) ** 1.8))
        frac = sum(tone_blow(t, ft, rng().uniform(55, 72), 36.0, 30.0, 0.05, 0.004, ((0.6, 0.1), (0.4, 0.3)), drive=2.5) * rng().uniform(0.4, 1.0) for ft in fr_t)
        press = tilted(n, 20, 60, -2) * u ** 2
        ref = np.std(tone[int(0.8 * CH_PEAK * SR):int(CH_PEAK * SR)])
        x = tone + strain * ref * 0.7 * u + T.unit(frac) * ref * 0.7 + T.unit(press) * ref * 0.9
        lvl = 10 ** ((-18.0 + 16.0 * u ** 1.8) / 20)
        x = T.unit(x) * lvl * pt(0.0, 0.1, t)
        # (the vacuum: sucked out CH_VAC s before the burst lands; the burst carries on from there)
        x *= 1 - 0.99 * pt(CH_PEAK - CH_VAC - 0.035, CH_PEAK - CH_VAC, t)
        x = drive_lows(x, 0.45)
        x = PB.causal_lowcut(x, 18.0)
    finish(f"charge{k + 1}", x, -15.0, tail=0.2, clip=True, clip_db=6.0)


BURST_D = 7.0


def burst_parts(k, take="A"):
    """Hammer and arms bursting apart, mono, as its layers: the stone ruptures (a tonal drop and its sub under one
    dense mass of noise), the green let go, the big pieces breaking off it in the first half second (smaller, darker
    masses), then the pieces landing all round over the next 1.4-4 s (deep heavy masses, a few, each its own size), the
    land rumbling under them. Low and heavy: nothing fine or bright, no patter. Take B (`--takes` only): the rupture's
    breaking from real rock (a rock slide's biggest block and a building's fall, slowed) and the pieces coming down from
    a rockfall slowed, over the same sub, green and rumble."""
    n = int(BURST_D * SR)
    t = np.arange(n) / SR
    t0 = BURST_LEAD
    f = (72.0, 66.0, 78.0)[k]
    boom = tone_blow(t, t0, f, f * 0.6, f * 0.46, 0.05, 0.003, ((0.55, 0.2), (0.45, 0.9)), drive=3.5, harm=0.5) * 0.7
    sub = tone_blow(t, t0, 42.0, 34.0, 29.0, 0.05, 0.003, ((0.7, 0.2), (0.3, 0.8)), drive=1.0, octv=0.1, harm=0.1)
    low = boom + sub * 0.7
    ref = np.sqrt(np.mean(band(low, 30, 120, 2)[int(t0 * SR):int((t0 + 0.4) * SR)] ** 2)) + 1e-12
    hit = mass(t, t0, 1.0, att=0.003, short=0.1, long=0.8, peak=(220.0, 200.0, 240.0)[k], top=2400.0, dark=1.0)
    for _ in range(3 + k % 2):
        tb = t0 + 0.06 + rng().uniform(0.0, 0.55) ** 1.4
        hit += mass(t, tb, rng().uniform(0.3, 0.55), att=0.005, short=0.06, long=0.35, peak=160.0, top=1400.0, dark=1.3)
    hit *= ref * 3.0
    en = T.unit(band(green(t, t0, (49.0, 46.25, 51.9)[k], 0.05, 1.0, 0.75, spread=1.4), None, 900, 2)) * ref * 0.45
    lands = np.zeros(n)
    times = np.sort(t0 + 1.4 + 2.6 * rng().random(6 + k) ** 1.3)
    for tl in times:
        lands += landing(t, tl, min(rng().pareto(2.5) * 0.4 + 0.4, 1.6), rng().uniform(44, 58))
    lands = lands * ref * 1.5 / (np.abs(lands).max() + 1e-9) * 1.4
    rumble_ = churn(n, 25, 300, slope=-4.0, depth=6.0) * pt(t0 + 1.3, t0 + 2.2, t) * (1 - pt(t0 + 3.5, BURST_D - 0.3, t)) * ref * 0.35
    roar = churn(n, 35, 900, slope=-3.5, depth=5.0, turns=30.0) * ar(t, t0 + 0.02, 0.08, 0.9) * ref * 0.6
    L = dict(sub=low, mass=hit, green=en, lands=lands, rumble=rumble_, roar=roar)
    if take == "B":
        sl = rec("rockslide", 7.93, 1.6, 0.6 + 0.05 * k, hp=120.0, fade_out=0.8, user=f"burst{k + 1}")
        d_ = rec("demolition", 0.0, 2.2, 0.7 + 0.04 * k, hp=120.0, fade_out=1.2, user=f"burst{k + 1}")
        f_ = rec("rockfall", 0.6 + 0.4 * k, 2.6, 0.6, hp=90.0, fade_in=0.05, fade_out=1.0, user=f"burst{k + 1}")
        L["rock"] = (lay(n, d_, t0 - 0.003) + 0.6 * lay(n, sl, t0 + 0.05)) * ref * 1.6
        L["debris"] = lay(n, f_, t0 + 1.2) * ref * 0.6
        L["mass"] = band(hit, None, 320, 2) * 0.8
        L["lands"] = lands * 0.6
    return L


def burst(k, take="A", dest=None, stems=None):
    with PB.seeded(61100 + k):
        L = burst_parts(k, take)
        x = body_drive(sum(L.values()), BURST_LEAD, 7.0, 0.4, 1.0)
        near = verb(x, 4.0, 610 + k, 0.35, (2400, 260), 1.2)
        near = drive_lows(near, 0.55)
        near = PB.causal_lowcut(near, 18.0)
        far = far_of(x, 620 + k, lp=2600.0)
        far = PB.causal_lowcut(far, 18.0)
    g = finish(f"burst{k + 1}", near, -10.5, tail=1.5, clip=True, clip_db=5.0, dest=dest)
    finish(f"burst_far{k + 1}", far, -12.5, tail=2.0, clip=True, dest=dest)
    if stems:
        write_stems(stems, f"burst{k + 1}_{take}", L, g, lambda y: verb(y, 4.0, 610 + k, 0.35, (2400, 260), 1.2))


KNEE_D = 2.6


def kneel(k):
    """A giant dropping to one knee, the knee KNEE_LEAD s in (the pass's kneel: its weight going down in three catches,
    the knee set down on the third, a shudder through it as the stone takes it, still by CL_SETTLE): two lurches of stone
    grinding down (a deep churn, a low groan), the knee into the ground (a deep heavy thud, the earth crushed dull under
    it), the shudder (a juddering grind at the pass's ~5.4 Hz, dying in a third of a second), the weight settling."""
    n = int(KNEE_D * SR)
    t = np.arange(n) / SR
    with PB.seeded(63100 + k):
        tk = KNEE_LEAD
        span = 1.4                                      # (a middling kneel: the lurches at its catches)
        lur = sum(np.exp(-0.5 * ((t - (tk + (c - 0.74) * span)) / 0.09) ** 2) * a for c, a in ((0.3, 0.7), (0.53, 0.85)))
        mot = lur + 0.25 * pt(0.0, 0.25, t) * (1 - pt(tk + 0.1, tk + 0.5, t))
        gr = churn(n, 28 + 3 * k, 420, slope=-3.5, depth=7.0) * mot
        gn = band(groan(t, (26.0 + 2.0 * k) + 6.0 * mot, mot, 0.1), None, 650, 2)
        thump = tone_blow(t, tk, (48.0, 44.0, 51.0)[k], 31.0, 25.0, 0.06, 0.004, ((0.55, 0.25), (0.45, 1.0)), drive=3.0, harm=0.5)
        ref = np.sqrt(np.mean(band(thump, 30, 120, 2)[int(tk * SR):int((tk + 0.4) * SR)] ** 2)) + 1e-12
        body = mass(t, tk, 1.0, att=0.005, short=0.08, long=0.5, peak=110.0, top=1000.0, dark=1.3)
        crush = np.zeros(n)
        shk = pt(tk - 0.15, tk + 0.02, t) * (1 - pt(tk + 0.05, tk + 0.33, t))
        judder = churn(n, 30, 380, slope=-4.0, depth=4.0) * shk * (0.55 + 0.45 * np.sin(2 * np.pi * 5.4 * t + 1.0)) ** 2
        settle_ = churn(n, 25, 260, slope=-4.5, depth=6.0) * ar(t, tk + 0.1, 0.3, 0.7)
        x = thump + body * ref * 2.2 + crush * ref * 0.5 + gr * ref * 0.55 + T.unit(gn) * ref * 0.35 \
            + judder * ref * 0.7 + settle_ * ref * 0.3
        x *= pt(0.0, 0.1, t)
        x = verb(x, 2.5, 640 + k, 0.3, (2000, 250), 1.0)
        x = drive_lows(x, 0.55)
        x = PB.causal_lowcut(x, 18.0)
    finish(f"kneel{k + 1}", x, -14.0, tail=0.6, clip=True, clip_db=6.0)


def rumble():
    """The land rolling on after the blast, low swells coming in off it and dying, a heaving sub bed, gone by the
    sweeps (they are heard over silence)."""
    d = 14.0
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(59101):
        x = np.zeros(n)
        tr = 0.3
        while tr < d - 4.0:
            far = min(tr / 10.0, 1.0)
            x += T.unit(band(nz(n), 28, 320 - 180 * far, 2)) * ar(t, tr, rng().uniform(0.15, 0.4) + 0.3 * far, rng().uniform(0.6, 1.2) + 0.6 * far) \
                * 10 ** ((-14.0 * far + rng().uniform(-3, 2)) / 20)
            tr += rng().gamma(1.7, 0.45 + 0.15 * far)
        bedv = 10 ** (np.interp(t, [0, 1.5, 5, 9, 12, 14], [-3, 0, -6, -16, -30, -60]) / 20)
        x = T.unit(x) * 0.8 + T.unit(tilted(n, 18, 70, -3)) * bedv * np.exp(0.7 * PB.slow_random(n, 0.1, 0.8))
        x *= pt(0.0, 0.8, t)
        x = drive_lows(x, 0.4, 70, 300)
        x = PB.causal_lowcut(x, 15.0)
    finish("rumble", x, -18.5, tail=3.0, clip=True, clip_db=7.0)


def settle(k):
    """The glowing line going down giant g, CL_SWEEP s: a soft breath of air sliding down with it, a warm low hum of
    the green dying away under it, the stone setting behind it (a slow sparse grinding, low, and three or four soft
    deep seats of weight), and as the line reaches the ground a last, deeper settling; then silence."""
    d = CL_SWEEP + 1.6
    n = int(d * SR)
    t = np.arange(n) / SR
    with PB.seeded(62000 + k):
        u = np.clip(t / CL_SWEEP, 0, 1)
        fc = 700.0 * (160.0 / 700.0) ** u
        noise = tilted(n, 60, 2000, -4)
        line = np.zeros(n)
        hop = 2048
        for i in range(0, n, hop):
            j = slice(max(0, i - hop), min(n, i + 2 * hop))
            y = band(noise[j], fc[i] * 0.6, fc[i] * 1.5, 2)
            line[j] += y * np.hanning(len(y)) * 0.66
        line *= pt(0.0, 0.6, t) * (1 - pt(CL_SWEEP - 0.6, CL_SWEEP + 0.3, t))
        f0 = (55.0, 51.9, 58.3)[k] * (1 - 0.06 * u)
        hum = np.zeros(n)
        for det in (-0.35, 0.0, 0.4):
            ph = 2 * np.pi * np.cumsum(f0 + det) / SR + rng().uniform(0, 6.28)
            hum += np.sin(ph) + 0.5 * np.sin(2 * ph + 0.4) + 0.3 * np.sin(3 * ph + 1.0) + 0.12 * np.sin(5 * ph)
        hum = comb(hum, 0.004 + 0.002 * np.sin(2 * np.pi * 0.2 * t), gains=(0.5, 0.3))
        hum *= pt(0.0, 0.8, t) * (1 - pt(1.0, CL_SWEEP + 0.4, t)) ** 1.3
        sett = churn(n, 30, 500, slope=-4.5, depth=6.0) * (0.25 + 0.2 * np.sin(np.pi * u))
        seats = sum(thud(t, ts, rng().uniform(40, 52), 24.0, 0.4, rng().uniform(0.5, 0.9))
                    for ts in np.sort(rng().uniform(0.8, CL_SWEEP - 0.8, 3 + (k % 2))))
        last = thud(t, CL_SWEEP + 0.05, 42.0, 21.0, 0.7, 1.4) + T.unit(tilted(n, 40, 400, -5)) * ar(t, CL_SWEEP + 0.1, 0.25, 0.6) * 0.05
        ref = np.std(hum[int(1.0 * SR):int(3.0 * SR)])
        x = hum + T.unit(line) * ref * 0.25 + T.unit(sett) * ref * 0.45 + T.unit(seats) * ref * 0.9 + T.unit(last) * ref * 1.1
        x = verb(x, 3.0, 630 + k, 0.35, (2500, 250), 1.2)
        x *= 1 - pt(d - 0.8, d, t)
        x = drive_lows(x, 0.35)
        x = PB.causal_lowcut(x, 20.0)
    finish(f"settle{k + 1}", x, -21.0, tail=0.3)


# ==========================================================================================================  the writing
def finish(name, x, db, tail=0.3, clip=False, clip_db=8.0, dest=None):
    """Mono, its loudest 400 ms at `db` dB (None: as built), the first peaks rounded by a soft clip (`clip`), held at
    PEAK decoded by the look-ahead limiter, band-limited to 15 kHz (no overshoot once the encoder cuts it). Written to the
    game's folder, or to `dest` (a take B). Returns the gain it put on `x` (for the stems)."""
    x = band(x - x.mean(), None, 15000, 4)
    gain = 1.0
    if db is not None:
        gain = 10 ** (db / 20) / (T.loudest(x) + 1e-12)
        x = x * gain
    if clip:
        c = min(T.loudest(x) * 10 ** (clip_db / 20), PEAK * 0.97)
        x = PB.soft_clip(x, c, 0.55)
    nf = int(tail * SR)
    if nf > 1:
        x[-nf:] *= np.linspace(1, 0, nf)
    path = f"{dest}/{name}" if dest else f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"
    if dest:
        _SRC[name] = path + ".ogg"
        _DEC.pop(name, None)
    c = PEAK * 0.985
    for _ in range(6):
        y = PB.limit(x[:, None], c)[:, 0] if np.abs(x).max() > c else x.copy()
        PB.write_ogg(path, y, 1)
        pk = PB._decoded_peak(path + ".ogg")
        if pk <= PEAK * 1.004:
            break
        c = c * PEAK / pk
    print(f"wrote {TH}/{name:11s} {len(x) / SR:5.2f}s  loudest {20 * np.log10(T.loudest(y) + 1e-12):6.1f} dB  decoded peak {20 * np.log10(pk):6.2f} dBFS"
          + (f"  ({dest})" if dest else ""))
    return gain


def write_stems(out, name, L, gain, space):
    """Each layer of a file on its own (`L`: name to mono), at the level it has in the file (its space put on, the
    file's gain; before the drive and the limiter, so the stems add up to nearly the file), all turned down together
    so their sum peaks at -1 dBFS, as WAV and MP3 under `out`/`name`/, with `all` (the sum) beside them."""
    d = Path(out) / name
    d.mkdir(parents=True, exist_ok=True)
    zs = {k: band(space(y) * gain, None, 15000, 4) for k, y in list(L.items()) + [("all", sum(L.values()))]}
    zs = {k: z - z.mean() for k, z in zs.items()}
    trim = min(1.0, 10 ** (-1.0 / 20) / (np.abs(zs["all"]).max() + 1e-12))
    for k, z in zs.items():
        p = d / f"{k}.wav"
        write_wav(p, z * trim)
        mp3(p)
    print(f"stems {name}: {', '.join(L)} (+ all) in {d}  (all turned down {-20 * np.log10(trim):.1f} dB to peak at -1 dBFS: "
          f"the file's own drive, clip and limiter hold it under that)")


FAMILIES = {
    "quake": lambda: quake(), "rise": lambda: [rise(k) for k in range(TAKES)], "stamp": lambda: [stamp(k) for k in range(TAKES)],
    "heave": lambda: [heave(k) for k in range(TAKES)], "slam": lambda: [slam_c(c, None) for c in range(len(SLAM_C))], "slam_all": lambda: slam_all_c(None),
    "beam": lambda: beam(), "ground": lambda: ground(), "blast": lambda: blast_c(), "rumble": lambda: rumble(),
    "charge": lambda: [charge(k) for k in range(TAKES)], "burst": lambda: [burst_c(k) for k in range(TAKES)],
    "kneel": lambda: [kneel(k) for k in range(TAKES)], "settle": lambda: [settle(k) for k in range(TAKES)],
}
TAKEN = {"rise": TAKES, "stamp": TAKES, "heave": TAKES, "slam": 5, "slam_far": 5, "charge": TAKES, "burst": TAKES,
         "burst_far": TAKES, "kneel": TAKES, "settle": TAKES}
SINGLE = ("quake", "slam_all", "beam", "ground", "blast", "blast_far", "rumble")
FILES = [f"{f}{k}" for f, m in TAKEN.items() for k in range(1, m + 1)] + list(SINGLE)
PLACED = ("rise", "stamp", "heave", "slam", "slam_far", "charge", "burst", "burst_far", "kneel", "settle", "beam")
SUBTITLES = {
    "quake": "The earth splits", "rise": "A stone giant heaves out of the earth", "stamp": "A giant stamps",
    "heave": "Stone grinds as a giant heaves", "slam": "A hammer slams the earth", "slam_far": "A distant hammer blow",
    "slam_all": "The earth heaves", "beam": "Cracks race to the middle", "ground": "Ground jolts", "blast": "Colossal blast",
    "blast_far": "Distant blast", "rumble": "The land rumbles", "charge": "Stone strains with energy",
    "burst": "A giant's arms burst apart", "burst_far": "Distant stone bursts", "kneel": "A giant drops to one knee",
    "settle": "Stone settles into blocks",
}


def write_events(out):
    path = Path(out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    new = {}
    for f in FILES:
        fam = f.rstrip("0123456789")
        reach = (SETTLE_REACH if fam == "settle" else REACH) if fam in PLACED else 256
        new[f"{TH}.{f}"] = {"sounds": [{"name": f"orbital:{TH}/{f}", "attenuation_distance": reach}], "subtitle": f"subtitles.orbital.{TH}.{fam}"}
    out_ = {k: v for k, v in sounds.items() if not k.startswith(f"{TH}.")}
    out_.update(new)
    path.write_text(json.dumps(out_, indent=2) + ("\n" if path.read_text().endswith("\n") else ""))
    lang = ROOT / "orbital-laser-mod" / "assets" / "orbital" / "lang" / "en_us.json"
    if lang.exists():
        text = lang.read_text()
        tab = json.loads(text)
        tab = {k: v for k, v in tab.items() if not k.startswith(f"subtitles.orbital.{TH}.")}
        tab.update({f"subtitles.orbital.{TH}.{fam}": s for fam, s in SUBTITLES.items()})
        lang.write_text(json.dumps(tab, indent=2, ensure_ascii=False) + ("\n" if text.endswith("\n") else ""))


# ===========================================================================================================  listening
_DEC = {}
_SRC = {}                                   # (a file taken from elsewhere: a take B)


def decoded(name):
    """A file as the game plays it (decoded, summed to mono, as the game sums every file), cached for the mixdowns."""
    if name in _DEC:
        return _DEC[name]
    path = _SRC.get(name, f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}.ogg")
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    _DEC[name] = np.frombuffer(raw, dtype="<f4").astype(float)
    return _DEC[name]


def far_mix(d):
    u = np.clip((d - 250.0) / 550.0, 0, 1)
    return float(u * u * (3 - 2 * u))


# ---- colossi.rs's per-strike choices, for a target block `blk` = (x, y, z) -----------------------------------------------
CHARACTER_LEAD = (1.25, 0.78, 1.05, 1.12, 0.9)          # (CHARACTER's first column: eager, stiff, showy, brute, wary)
CL_SETTLE = 24.3                                       # (shaders/colossi.wgsl's: every giant holds its statue's crouch)


def character_of(blk, g):
    """colossi.rs's `character`: which of the five characters giant g is dealt (0 eager, 1 stiff, 2 showy, 3 brute, 4 wary)."""
    return (g + int(_hash(blk[0], blk[2], 41) * 5.0)) % 5


def leads(blk, g):
    """colossi.rs's `leads`: the wind-up's scale before each of giant g's blows."""
    l = CHARACTER_LEAD[character_of(blk, g)]
    up = T_RISE0 + T_RISE_STEP * g + CL_RISE
    return (max(min(l, (slam1(g) - up - 0.3) / 3.75), 0.7), max(min(l, (slam2(blk, g) - slam1(g) - 0.7) / 3.75), 0.7))


# (colossi.rs's combined blow: each slot's hammer this long before SLAM2; every blow heard as it lands, so 0.3 s apart)
ROLL = (-1.2, -0.9, -0.6, -0.3, 0.0)
_LISTENER = [None]                     # (where the player stands: `schedule` sets it)


def _perm(k):
    left, order = list(range(5)), []
    for i in range(5):
        f = (24, 6, 2, 1, 1)[i]
        order.append(left.pop((k // f) % len(left)))
        k %= f
    return order


def slam2_order(blk):
    """colossi.rs's `slam2_order`: the strike's own deal."""
    return _perm(int(_hash(blk[0], blk[2], 43) * 120.0))


def slam2(blk, g):
    """colossi.rs's `slam2`: giant g's hammer in the ragged combined blow (ROLL: over 1.2 s, the last at SLAM2), its slot
    dealt each strike (`slam2_order`)."""
    slot = slam2_order(blk).index(g)
    jit = 0.0 if slot == 4 else 0.04 * (_hash(g, 17, blk[0]) - 0.5)
    return SLAM2 + ROLL[slot] + jit


def burst_at(g):
    return BURST + BURST_STEP * g


def knee_at(g):
    """When giant g's knee comes down (the pass's `cl_pose`: the kneel from its burst + 0.2 to CL_SETTLE, the knee down
    as its weight `w` passes KNEE_W): the same fraction KNEE_F of the way for every giant."""
    a = burst_at(g) + 0.2
    return a + KNEE_F * (CL_SETTLE - a)


def take(g, s):
    """colossi.rs's choice of take and pitch for giant g (`s` the strike's seed bits)."""
    return (g + s) % TAKES + 1, 0.97 + 0.06 * _hash(g, 11, s)


def strike_seed(blk):
    bx, by, bz = blk
    m = (1 << 64) - 1
    s = ((bx * 73_856_093) & m) ^ ((bz * 19_349_663) & m) ^ (by & m)
    return s


def geometry():
    """The giants (ring), their slam points and the middle, x z from the target's middle (as the mod has them, near
    enough: the slam point straight in from the giant)."""
    gs, sp = [], []
    for deg in RS["RING_DEG"]:
        th = np.radians(deg)
        gs.append((RING_R * np.cos(th), RING_R * np.sin(th)))
        sp.append(((RING_R - SLAM_IN) * np.cos(th), (RING_R - SLAM_IN) * np.sin(th)))
    return gs, sp


def schedule(me, blk=(0, 64, 0)):
    """(file, start, at or None, volume, pitch) as colossi.rs's `colossi_plan` queues them for a player at `me` = (x, y,
    z) from the target's middle (y up from the ground), the target block `blk`. `at` is (x, y, z) for a placed sound.
    Keep in step with colossi.rs: every line here is one of its."""
    gs, sp = geometry()
    _LISTENER[0] = me
    late = lambda p: float(np.linalg.norm(np.subtract(p, me))) / SPEED
    dist = lambda p: float(np.linalg.norm(np.subtract(p, me)))
    out = []
    giant = lambda g, up: (gs[g][0], up, gs[g][1])
    slam_at = lambda g: (sp[g][0], 0.0, sp[g][1])
    mid = (0.0, 0.0, 0.0)
    s3 = (strike_seed(blk) & 0xFFFFFFFF) % 3

    def placed(f, t, at, vol, pitch):
        if vol > 0.003:
            out.append((f, t + late(at), at, min(vol, 1.0), pitch))

    def now(f, t, at, vol, pitch):
        # (a giant's stamp, its hammer hauled up and its blow: heard with the picture, never late by the distance)
        if vol > 0.003:
            out.append((f, t, at, min(vol, 1.0), pitch))

    near_g = min(dist(giant(g, 0)) for g in range(5))
    out.append(("quake", T_RISE0 + near_g / GROUND_V - QUAKE_LEAD, None, VOL["quake"], 1.0))
    for g in range(5):
        k, p = take(g, s3)
        placed(f"rise{k}", T_RISE0 + T_RISE_STEP * g, giant(g, 0), VOL["rise"], p)
    for second in (False, True):
        for g in range(5):
            k, p = take(g + second, s3)
            c = character_of(blk, g)
            ti = slam2(blk, g) if second else slam1(g)
            ld = leads(blk, g)[second]
            vs = SLAM2_VOL if second else 1.0
            fm = far_mix(dist(slam_at(g)))
            hp = p * ld ** -HEAVE_FOLLOW
            now(f"heave{k}", ti - HEAVE_CATCH * ld - (HEAVE_AHEAD - HEAVE_CATCH) / hp, giant(g, 150), VOL["heave"] * vs, hp)
            sp_ = SLAM_PITCH[c] * (0.985 + 0.03 * _hash(g, 11, s3))
            now(f"slam{c + 1}", ti - SLAM_LEAD / sp_, slam_at(g), VOL["slam"] * vs * (1 - fm), sp_)
            now(f"slam_far{c + 1}", ti - SLAM_LEAD / sp_, slam_at(g), VOL["slam"] * vs * fm, sp_)
            now(f"stamp{k}", ti - 3.2 * ld - STAMP_LEAD / p, giant(g, 0), VOL["stamp"] * vs, p)
    out.append(("slam_all", SLAM2 - SLAM2_LEAD, None, VOL["slam_all"], 1.0))
    dm = dist(mid)
    out.append(("beam", T_BEAM0, (0.0, 2.0, 0.0), VOL["beam"], 1.0))   # (the finale with the impact frames, never late)
    gap = dm / SPEED - dm / GROUND_V
    gv = float(np.clip(1.0 / (1.0 + dm / 1200.0), 0.35, 1.0) * np.clip((gap - 0.05) / 0.9, 0.3, 1.0) ** 1.2)
    out.append(("ground", CL_HIT - GROUND_LEAD, None, VOL["ground"] * gv, 1.0))
    fm = far_mix(dm)
    # (an equal-power cross-fade: the far take is the near one smeared, the two do not add up in phase)
    out.append(("blast", CL_HIT - BLAST_LEAD, None, VOL["blast"] * np.sqrt(1 - fm), 1.0))
    out.append(("blast_far", CL_HIT - BLAST_LEAD, None, VOL["blast"] * np.sqrt(fm) * min(1.25 / (1.0 + dm / 2000.0), 1.0), 1.0))
    out.append(("rumble", CL_HIT + RUMBLE_AFTER, None, VOL["rumble"], 1.0))
    for g in range(5):
        k, p = take(g, s3)
        tb = burst_at(g)
        arms = giant(g, 130)
        fm = far_mix(dist(arms))
        placed(f"charge{k}", tb - CH_PEAK / p, arms, VOL["charge"], p)
        placed(f"burst{k}", tb - BURST_LEAD / p, arms, VOL["burst"] * (1 - fm), p)
        placed(f"burst_far{k}", tb - BURST_LEAD / p, arms, VOL["burst"] * fm, p)
        placed(f"kneel{k}", knee_at(g) - KNEE_LEAD / p, giant(g, 20), VOL["kneel"], p)
    for g in range(5):
        k, p = take(g, s3)
        placed(f"settle{k}", T_SWEEP0 + T_SWEEP_STEP * g, giant(g, 100), VOL["settle"], p)
    return [e for e in out if e[3] > 0.003]


def stereo_gains(d, fwd):
    """The game's stereo gains (audio.rs's `stereo_gains`, OpenAL Soft's) for a mono source `d` from the listener, who
    faces `fwd` (horizontal): a centred source 0.596 in each ear, fully to one side 60 degrees off the front."""
    up = np.array([0.0, 1.0, 0.0])
    f = np.array([fwd[0], 0.0, fwd[1]])
    r = np.cross(f, up)
    x, y, z = float(np.dot(d, r)), float(np.dot(d, up)), float(np.dot(d, f))
    ln = np.sqrt(x * x + y * y + z * z)
    if ln < 1e-6:
        x, y, z, ln = 0.0, 0.0, 1.0, 1.0
    el = np.arcsin(np.clip(y / ln, -1, 1))
    az = np.arctan2(x, z)
    if abs(az) < np.pi / 2:
        az = np.copysign(min(abs(az) * 1.5, np.pi / 2), az)
    side = np.sin(az) * np.cos(el)
    front = np.cos(az) * np.cos(el) * 0.0956608
    return 0.5 - 0.5 * side + front, 0.5 + 0.5 * side + front


def mixdown(dist, bearing=0.0, blk=(0, 64, 0), only=None):
    """The whole strike for a player `dist` blocks from the target (at `bearing` degrees round it, 1.7 blocks up,
    facing it), from strike time 0: stereo, as the game places and rolls off each sound (its output limiter not
    applied: the mix is held under it). `only`: a list of file families to keep (the rest left out)."""
    th = np.radians(bearing)
    me = (dist * np.cos(th), 1.7, dist * np.sin(th))
    look = (-np.cos(th), -np.sin(th)) if dist > 0 else (1.0, 0.0)
    ev = schedule(me, blk)
    if only is not None:
        ev = [e for e in ev if e[0].rstrip("0123456789") in only]
    end = max(CL_LEN + 4.0, max(at + len(decoded(f)) / SR / p for f, at, _, _, p in ev) + 0.5)
    out = np.zeros((int(end * SR) + 1, 2))
    for f, at, pos, vol, p in ev:
        c = decoded(f)
        if p != 1.0:
            m = int(len(c) / p)
            c = np.interp(np.arange(m) * p, np.arange(len(c)), c)
        if pos is None:
            gl = gr = min(vol, 1.0) * 0.596
        else:
            fam = f.rstrip("0123456789")
            reach = REACH_OF.get(fam, REACH) * max(vol, 1.0)
            dd = float(np.linalg.norm(np.subtract(pos, me)))
            gain = min(vol, 1.0) * max(0.0, 1.0 - dd / reach)
            l, r = stereo_gains(np.subtract(pos, me), look)
            gl, gr = gain * l, gain * r
        k = int(round(at * SR))
        seg = c[:len(out) - k]
        out[k:k + len(seg), 0] += seg * gl
        out[k:k + len(seg), 1] += seg * gr
    return out


def write_wav(path, x):
    import wave
    x = x if x.ndim == 2 else x[:, None]
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1]); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def true_peak(x):
    return 20 * np.log10(np.abs(resample_poly(x, 4, 1, axis=0)).max() + 1e-12)


def octaves(x):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    tot = X.sum()
    return [(lo, hi, 10 * np.log10(X[(f >= lo) & (f < hi)].sum() / tot + 1e-12)) for lo, hi in
            ((20, 40), (40, 80), (80, 160), (160, 320), (320, 640), (640, 1280), (1280, 2560), (2560, 5120), (5120, 16000))]


# ---- what the ear would catch: loudness over time, the bands, the banned textures ---------------------------------------
def ebur128(path):
    """(integrated LUFS, true peak dBTP, loudness range LU, [(t, momentary LUFS, short-term LUFS)] every 0.1 s) by
    ffmpeg's ebur128."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true",
                        "-f", "null", "-"], capture_output=True, text=True).stderr
    curve = []
    for line in r.splitlines():
        m = re.search(r"t:\s*([0-9.]+)\s+TARGET:.*?M:\s*(-?[0-9.inf]+)\s+S:\s*(-?[0-9.inf]+)", line)
        if m:
            curve.append(tuple(float(v) if "inf" not in v else -120.0 for v in m.groups()))
    tail = r[r.rfind("Summary:"):]

    def grab(key):
        i = tail.find(key)
        return float(tail[i:].split(":")[1].split()[0]) if i >= 0 else float("nan")
    return grab("I:"), grab("Peak:"), grab("LRA:"), curve


BANDS = ((20, 60, "sub"), (60, 200, "low"), (200, 800, "body"), (800, 4000, "mid"), (4000, 16000, "air"))


def frames(m, hop=0.05, win=0.1):
    """Band levels (dB) of mono `m`, a frame every `hop` s: (times, {band: levels}) and its spectrogram (|STFT|^2, freqs)."""
    nw, nh = int(win * SR), int(hop * SR)
    w = np.hanning(nw)
    idx = range(0, len(m) - nw, nh)
    S = np.array([np.abs(np.fft.rfft(m[i:i + nw] * w)) ** 2 for i in idx])
    f = np.fft.rfftfreq(nw, 1 / SR)
    t = np.array([(i + nw / 2) / SR for i in idx])
    lv = {nm: 10 * np.log10(S[:, (f >= lo) & (f < hi)].sum(axis=1) + 1e-12) for lo, hi, nm in BANDS}
    return t, lv, S, f


def textures(m, a=0.0, b=None):
    """Numbers for the banned textures over a..b s of mono `m`:
       air      the share of energy over 4 kHz (grain, hiss, crinkle) in dB of the whole;
       ticks    sharp onsets a second in 1.5-8 kHz (a jump of 9 dB within 10 ms, 30 ms apart at least): patter, taps,
                clinks, snare cracks;
       ring     how much of the time a narrow peak (one bin 18 dB over its +-1/3-octave neighbourhood's median) holds over
                0.25 s anywhere in 250-5000 Hz: chimes, dings, ringing combs;
       crest    peak over RMS (dB): punch."""
    seg = m[int(a * SR):int((b if b else len(m) / SR) * SR)]
    X = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
    f = np.fft.rfftfreq(len(seg), 1 / SR)
    air = 10 * np.log10(X[f >= 4000].sum() / (X.sum() + 1e-30) + 1e-12)
    hi = band(seg, 1500, 8000, 2)
    e = np.sqrt(np.convolve(hi ** 2, np.ones(int(0.002 * SR)) / int(0.002 * SR), "same")) + 1e-9
    ed = 20 * np.log10(e)
    # (only what can be heard over the rest: within 26 dB of the whole's level over the 50 ms round it)
    ea = 20 * np.log10(np.sqrt(np.convolve(seg ** 2, np.ones(int(0.05 * SR)) / int(0.05 * SR), "same")) + 1e-9)
    lag = int(0.010 * SR)
    jump = ed[lag:] - ed[:-lag]
    cand = np.where((jump > 9.0) & (ed[lag:] > ea[lag:] - 26.0))[0]
    ticks, last = 0, -10 ** 9
    for i in cand:
        if i - last > int(0.03 * SR):
            ticks += 1
            last = i
    tps = ticks / max(len(seg) / SR, 1e-9)
    # (tonal ringing: narrow peaks held)
    nw, nh = 8192, 2048
    w = np.hanning(nw)
    ff = np.fft.rfftfreq(nw, 1 / SR)
    sel = np.where((ff >= 250) & (ff <= 5000))[0]
    held, prev = 0, None
    run = np.zeros(len(ff))
    nfr = 0
    for i in range(0, len(seg) - nw, nh):
        P = 10 * np.log10(np.abs(np.fft.rfft(seg[i:i + nw] * w)) ** 2 + 1e-20)
        if P.max() < -200:
            continue
        nfr += 1
        pk = np.zeros(len(ff), bool)
        for j in sel:
            lo, hi_ = int(j / 1.26), int(j * 1.26) + 1
            if P[j] == P[lo:hi_].max() and P[j] - np.median(P[lo:hi_]) > 18 and P[j] > P.max() - 45:
                pk[j - 1:j + 2] = True
        run = np.where(pk, run + 1, 0)
        if (run * nh / SR > 0.25).any():
            held += 1
    ring = held / max(nfr, 1)
    crest = 20 * np.log10(np.abs(seg).max() / (np.sqrt(np.mean(seg ** 2)) + 1e-12) + 1e-12)
    return air, tps, ring, crest


def picture(path, m, title, cues, curve=None, top=8000.0):
    """A spectrogram of mono `m` (log frequency 20 Hz to `top`, 0.05 s a column) with its band levels and momentary
    loudness drawn under it and the plan's moments marked: a PNG to look at."""
    from PIL import Image, ImageDraw
    t, lv, S, f = frames(m)
    W, H, Hb = max(len(t), 200), 360, 240
    fr = np.geomspace(20, top, H)
    col = np.array([np.interp(fr, f, s) for s in S]).T[::-1]
    db = 10 * np.log10(col + 1e-14)
    vmax = np.percentile(db, 99.7)
    v = np.clip((db - (vmax - 70)) / 70, 0, 1)
    rgb = np.stack([np.clip(1.6 * v - 0.3, 0, 1), np.clip(1.8 * v - 0.9, 0, 1) ** 0.8, np.clip(np.sin(np.pi * v) * 0.9, 0, 1)], -1)
    img = Image.new("RGB", (W + 60, H + Hb + 40), (16, 16, 20))
    img.paste(Image.fromarray((rgb * 255).astype(np.uint8)), (50, 20))
    d = ImageDraw.Draw(img)
    d.text((50, 4), title, fill=(230, 230, 230))
    for fq in (30, 60, 120, 250, 500, 1000, 2000, 4000, 8000):
        if fq <= top:
            y = 20 + H - 1 - int(np.log(fq / 20) / np.log(top / 20) * (H - 1))
            d.text((2, y - 5), f"{fq}", fill=(170, 170, 170))
            d.line((46, y, 50, y), fill=(170, 170, 170))
    y0 = 20 + H + 10
    tops = max(max(l.max() for l in lv.values()), -100)
    cols = {"sub": (230, 90, 70), "low": (240, 170, 60), "body": (120, 210, 90), "mid": (90, 170, 240), "air": (200, 120, 230)}
    for nm, l in lv.items():
        y = y0 + Hb - 1 - np.clip((l - (tops - 60)) / 60, 0, 1) * (Hb - 1)
        d.line([(50 + i, float(y[i])) for i in range(len(t))], fill=cols[nm], width=1)
    if curve:
        ct = np.array([c[0] for c in curve]); cm = np.array([c[1] for c in curve])
        y = y0 + Hb - 1 - np.clip((np.interp(t, ct, cm) + 60) / 60, 0, 1) * (Hb - 1)
        d.line([(50 + i, float(y[i])) for i in range(len(t))], fill=(255, 255, 255), width=2)
    for i, (nm, c) in enumerate(cols.items()):
        d.text((54 + 46 * i, y0 + Hb + 4), nm, fill=c)
    d.text((54 + 46 * 5, y0 + Hb + 4), "momentary LUFS (white, -60..0)", fill=(255, 255, 255))
    for s in range(0, int(len(m) / SR) + 1):
        x = 50 + int(s / 0.05)
        d.line((x, 20 + H, x, 20 + H + 5), fill=(150, 150, 150))
        if s % 2 == 0:
            d.text((x - 4, 20 + H + 5 + Hb + 18), f"{s}", fill=(150, 150, 150))
    for tc, nm in cues:
        x = 50 + int(tc / 0.05)
        d.line((x, 20, x, 20 + H + Hb + 10), fill=(90, 255, 160), width=1)
        d.text((x + 2, 22), nm, fill=(90, 255, 160))
    img.save(path)


def cue_marks(blk=(0, 64, 0)):
    """The moments on screen (strike time) to mark in the pictures."""
    cues = [(T_RISE0, "rise"), (SLAM0_T, "blows"), (SLAM2 - 0.55, "ragged"), (SLAM2, "18"), (CL_HIT, "BLAST"),
            (CHARGE, "charge"), (BURST, "burst"), (CL_SETTLE, "still"), (T_SWEEP0, "sweep"), (T_SWEEP0 + 1.2 + CL_SWEEP, "end")]
    return cues


def mp3(p):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(p), "-c:a", "libmp3lame", "-b:a", "192k", str(p.with_suffix(".mp3"))], check=True)


def others(dist):
    """The Nuke's (both blasts) and the Rod's whole strikes at `dist` blocks, as the game plays them (every file summed to
    mono, 0.596 in each ear: a sound not placed is centred), for the levels to sit beside."""
    import sounds_nuke as NK, sounds_rod as RD
    out = {}
    for nm, th, fn in (("nuke", "nuke", lambda: NK.mixdown(dist)[0]), ("nuke_alt", "nuke", lambda: NK.mixdown(dist, alt=True)[0]),
                       ("rod", "rod", lambda: RD.mixdown(dist)[0])):
        NK.TH = th                     # (the Rod's script points the Nuke's helpers at its own files)
        x = fn()
        m = x.mean(axis=1) * 0.596
        out[nm] = np.stack([m, m], axis=1)
    return out


def report(name, x, out, cues=None, ref=False):
    """Write `x` (stereo) as NAME.wav and .mp3 under `out`, its picture, and print its numbers."""
    p = out / f"{name}.wav"
    write_wav(p, x)
    mp3(p)
    I, tp, lra, curve = ebur128(p)
    m = x.mean(axis=1)
    picture(out / f"{name}.png", m, f"{name}: {I:.1f} LUFS, {tp:.1f} dBTP", cues or [], curve)
    mom = np.array([c[1] for c in curve]); ct = np.array([c[0] for c in curve])
    print(f"\n{name}: {len(x) / SR:.1f} s  integrated {I:6.1f} LUFS  true peak {tp:6.2f} dBTP  LRA {lra:4.1f} LU  "
          f"loudest momentary {mom.max():6.1f} LUFS at {ct[np.argmax(mom)] - 0.4:.1f} s")
    if not ref:
        print("  momentary LUFS each half second from 0: " + " ".join(f"{np.interp(s + 0.4, ct, mom):.0f}" for s in np.arange(0, min(len(m) / SR, 36), 0.5)))
        for a, b, nm in ((0, 1.0, "hook"), (0, 8, "rise"), (8, 10.4, "wind-up"), (10.4, 14.5, "blows"), (14.5, 17.4, "between"),
                         (17.4, 18.3, "ragged"), (18.3, 20.0, "build"), (20, 22.3, "blast"), (22.3, 24.3, "bursts+kneel"),
                         (25, 31, "sweep"), (31, 36, "after")):
            air, tps, ring, crest = textures(m, a, b)
            ob = " ".join(f"{v:5.1f}" for _, _, v in octaves(m[int(a * SR):int(b * SR)]))
            lo = np.interp(np.arange(a, b, 0.1) + 0.4, ct, mom)
            print(f"  {nm:13s} {a:5.1f}-{b:4.1f}s  M min {lo.min():5.1f} max {lo.max():5.1f}  air {air:6.1f} dB  ticks {tps:4.1f}/s  "
                  f"ring {ring:4.2f}  crest {crest:4.1f}  oct {ob}")
    return I, tp, mom.max()


def listen(out, blk=(0, 64, 0)):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"\n{'file':16s} {'len':>5s} {'peak':>7s} {'TP':>7s} {'loud':>6s}  {'air':>6s} {'tick/s':>6s} {'ring':>5s} {'crest':>5s}  octave balance 20/40/80/160/320/640/1k3/2k6/5k (dB of total)")
    for f in FILES:
        x = decoded(f)
        air, tps, ring, crest = textures(x)
        ob = " ".join(f"{v:5.1f}" for _, _, v in octaves(x))
        print(f"{f:16s} {len(x) / SR:5.1f} {20 * np.log10(np.abs(x).max()):7.2f} {true_peak(x):7.2f} {20 * np.log10(T.loudest(x)):6.1f}  "
              f"{air:6.1f} {tps:6.1f} {ring:5.2f} {crest:5.1f}  {ob}")
    worst = -99.0
    print()
    for dist in (0, 60, 100, 200, 300, 450, 600, 850, 1000, 1300):
        for bearing in (0.0, -18.0, 36.0):
            tp = true_peak(mixdown(dist, bearing, blk))
            worst = max(worst, tp)
        print(f"  the whole strike {dist:4d} blocks off: true peak (worst of three bearings so far) {worst:6.2f} dBTP")
    print(f"  worst true peak over every distance and bearing: {worst:.2f} dBTP {'OK' if worst < 20 * np.log10(TP_MAX) else 'OVER'}")
    cues = cue_marks(blk)
    rows = []
    fd = out / "files"
    fd.mkdir(exist_ok=True)
    for f in FILES:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", _SRC.get(f, f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{f}.ogg"),
                        "-c:a", "libmp3lame", "-b:a", "192k", str(fd / f"{f}.mp3")], check=True)
    for dist, nm in ((100, "100"), (300, "300"), (700, "700")):
        rows.append((f"colossi_{nm}",) + report(f"colossi_{nm}", mixdown(dist, 0.0, blk), out, cues))
    for dist in (300, 700):
        for nm, x in others(dist).items():
            rows.append((f"{nm}_{dist}",) + report(f"{nm}_{dist}", x, out, ref=True))
    print(f"\n{'mixdown':16s} {'LUFS':>6s} {'TP':>6s} {'max M':>6s}")
    for r in rows:
        print(f"{r[0]:16s} {r[1]:6.1f} {r[2]:6.2f} {r[3]:6.1f}")


def takes(out, stems=None):
    """Take B of the slams, the blast and the bursts (their breaking rock from the CC0 recordings in RECORDINGS, read
    from $COLOSSI_REFS), written only under `out`/files (never into the game's folder), with a NOTICE of which recording
    went where, each as an MP3, and the whole strike with them in place of take A heard from 300 and 700 blocks."""
    out = Path(out)
    fd = out / "files"
    fd.mkdir(parents=True, exist_ok=True)
    USED.clear()
    for c in range(len(SLAM_TAKES)):
        slam(c, "B", fd, stems if c in (0, 3) else None)
    blast("B", fd, stems)
    for k in range(TAKES):
        burst(k, "B", fd, stems if k == 0 else None)
    for f in sorted(fd.glob("*.ogg")):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(f), "-c:a", "libmp3lame", "-b:a", "192k",
                        str(f.with_suffix(".mp3"))], check=True)
    lines = ["Take B of the Colossi's slams, blast and bursts: NOT in the game files, for comparison only.",
             "Their breaking rock is real: slices of these recordings, each dedicated to the public domain (CC0 1.0) by its author",
             "on Freesound, high-passed, slowed and lowered, laid over the Colossi's own synthesised sub, ground, green and tail.", ""]
    for key, (f, onset, page, who, title) in RECORDINGS.items():
        lines.append(f"  {key}: \"{title}\" by {who}, {page} (CC0 1.0)")
    lines += ["", "Which recording went where (seconds after the recording's own blow; speed under 1 is slower and lower):"]
    for user, uses in sorted(USED.items()):
        for u_ in dict.fromkeys(uses):
            lines.append(f"  {user}: {u_}")
    (out / "NOTICE.txt").write_text("\n".join(lines) + "\n")
    cues = cue_marks()
    for dist in (300, 700):
        report(f"colossi_B_{dist}", mixdown(dist, 0.0), out, cues)
    _SRC.clear()
    _DEC.clear()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=list(FAMILIES))
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write listening MP3s of every file and the full-strike mixdowns (100, 300 and 700 "
                                     "blocks) here")
    ap.add_argument("--takes", help="write take B of the slams, the blast and the bursts (CC0 recordings) here, never into "
                                    "the game's folder, with the strike heard from 300 and 700 blocks with them")
    ap.add_argument("--finales", help="write the three finale takes (F1-F3: beam, ground, blast and blast_far as a set each), "
                                      "their stems and the strike from 18.5 to 26 s at 300 blocks with each, here; the game's "
                                      "files keep FINALE")
    ap.add_argument("--takec", help="write take C of the hammer blows (the reference model) here, never into the game's "
                                    "folder, with the strike heard from 300 blocks with them")
    ap.add_argument("--stems", help="write the layers of slam1 (eager), slam4 (brute), the blast and burst1 apart here, take A "
                                    "(and take B with --takes)")
    a = ap.parse_args()
    soundlib.init(a.out)
    for fam in a.only if a.only is not None else FAMILIES:
        FAMILIES[fam]()
    if a.stems:
        slam_c(0, None, a.stems); slam_all_c(None, a.stems); blast_c(None, a.stems); burst_c(0, None, a.stems)
    write_events(a.out)
    if a.listen:
        listen(a.listen)
    if a.finales:
        finales(a.finales)
    if a.takec:
        take_c(a.takec, a.stems)
    if a.takes:
        takes(a.takes, a.stems)


if __name__ == "__main__":
    main()
