#!/usr/bin/env python3
"""The Convergence's sounds: the Nether breaks out of the ground as a column of fire, the Aether opens a rift in the
sky, the two columns fire at each other and strike in mid-air, fight for ten seconds (six surges, each with a
shockwave), and the Aether drives the meeting point down into the blast that splits the land in two (the Sundering).

One sound with one shape: the beats on the picture, a held breath before each big hit (the beds drawn under for a
beat, never silent). The explosions (the cracks giving and the eruption, the hit in the air, the six surges, the blast
and the land's tear) are built in two takes (TAKES, TAKE_OWN, `name_of`), of which take 2 ships, under plain names
(`shipped`): take 2 this laser's own: each kind built, as the Payload's were, to the measurements of one explosion of a
reference (`sounds_cv_blasts`' OWN, `own_blast`: octave levels over time, the low blows' times and pitches, how dense
its start is), sized and pitched here (OWN_EVENTS, `own_surge`), the Nether's with its fire boiling in the roar, the
Aether's with a clean ringing weight in it; take 1 the Payload's alternative builders as the Sky Breaks' slam plays
them (`blast_alt`, `ground_alt`, `rush`, `tail`; `slam_*`), built only to level the layers by (`build_ref`). Each file is placed so its hit lands on the
picture's frame. The sequence round the blast is the same in both takes: the drive cut 0.13 s before it, the wall,
stunned from 27.05 (the roar ducked, `stunned`) and sucked back in to the tear at 27.5, the second release, the choir
at its height after.
Over it all, hell and heaven (LAYERS, each its own event): hell's many-throated voice from under the ground and the
furnace under the Nether's column; heaven's choir on one open chord (its own low end a pedal under it on heaven's
moments) and the rift's thunder. Each side's voice swells where its side pushes and is pressed where the other does;
all of them duck under the hits and with the held breaths. They and the win are levelled (`room`) under a levelling strike
(`build_ref`, `cues`' `then`), built for that alone.
The beds and hell's voice are CC0 recordings (credited in NOTICE), slowed and laid on the shapes of synthesized ones
(built only to level them and the layers by); the explosions are synthesized, their top
over 1 kHz on the Nether's, the hit's and the tear's recorded (`dark_top`).

Every file is mono (the game sums a stereo file to mono as it loads it) and sits at a fixed loudness against the
others (the loudest 400 ms; the blast the loudest), so a cue's volume is its distance only, times CV_BOOST for the
explosions (more voices of the same file). Every event comes in three tiers, `_near`, `_mid` and `_far` (see `tier`
and `weights`), cross-faded by the player's distance: mid and far are the same sound through the air's absorption of
250 and 700 m (the highs going first, as they do outdoors) and a dark outdoor tail; nothing is low-passed flat.

The beats the player watches are heard as they are seen, never late by the distance: the cracks opening (5.0), the
eruption (6.0), the rift opening (5.0-6.5), the hit in the air (13.0), each surge's push at its peak, the blast (26.0).
Only the quake (through the ground, ahead) and the aftermath come late by the burst's distance; the builders' ground
thump lands with the air's blow (on the strike clock nothing is late, and ahead of it would fill the held breaths).

Strike clock (seconds), as the files are built for (tK_: take K's own file, for the events in TAKE_OWN; take 2's
ship without it):
  nether       0      the ground before the launch: the tremor (0-5), the fountain's voice (6-12), drawing back
  aether       0.5    the sky before the launch: the seam, the rift opening (5.0 on, its weight 5.0-6.5), the stub of
                      light, drawing back
  hell         3.0    hell's voice: stirring (3-6), the bellow (6.0), answering the Nether's surges, choked (23-26)
  choir        5.0    heaven's choir: rising as the rift parts, lifting on the Aether's surges, full on the drive and
                      the blast, a calm chord over the aftermath, gone as the rift shuts (40)
  thunder      4.8    the rift's thunder: as it opens (5.25) and after each of the Aether's surges
  furnace      6.0    the furnace under the Nether's column, from the eruption to the blast
  tK_erupt     3.0    the ground straining (3-5), the cracks giving (5.0, 2.0 in: a small one), the build (5-6), the
                      held breath, the fire erupting (6.0, 3.0 in) and its roar
  fire         5.0    fire and ash out of the cracks, the fountain's roar 6-12, drawn back, burning on under the clash
  tK_impact    12.0   the held breath, the two rushing at each other, the hit at 13.0 (1.0 in), its roar
  clash        13.0   both columns standing, pressed together, to their cut into the blast
  tK_surge_I   each surge I (1-6), SURGE_HIT before its push peaks (SURGE_ATK after it starts): its blow on the peak
  drive        23.0   heaven driving the meeting point down into the ground, louder and brighter, accelerating, cut
                      dead 0.13 s before the blast (3.0 s)
  tK_blast     25.75  the blast, BLAST_AT in, on 26.0 (take 1: with its ground and the rush); stunned 27.05-27.5;
                      sucked back in
  tK_sunder    26.0   the land's tear on 27.5 (1.5 in), its roll going on under the aftermath (take 1: its ground, the
                      tail)
  win          26.9   heaven's choir arriving on the win, over the islands (`win`)
  quake        26     the ground's answer, through the ground ahead of the air (one file, no tiers)
  after        30.5   the land settling, the burning, the rift shutting (35.5: 5.0 in), the roll dying out

    python3 sounds_convergence.py --src RECORDINGS                       # the .ogg files and their events
    python3 sounds_convergence.py --src RECORDINGS --picture PNG --table MD
                        # also the level over time and the measurements against other lasers' blasts
"""
import argparse
import warnings
import hashlib
import json
import os
import subprocess
import wave
from pathlib import Path

import sys

import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sounds_cv_blasts as CB     # noqa: E402  (the Payload's explosion builders, sized: the explosions)
import sounds_payload as P        # noqa: E402

SR = 44100
TH = "convergence"
SPEED = 343.0
ROOT = Path(__file__).resolve().parent.parent

# ---- the strike clock
BREAK = 5.0      # the cracks open
ERUPT = 6.0      # the fire erupts out of the ground (CV_RED0)
RIFT = 5.0       # the rift starts opening (its weight over RIFT..RIFT + 1.5)
CV_GOLD0 = 7.5   # the stub of light under the rift
CROUCH = 12.0    # both draw back
FIRE = 12.45     # both fire and race at each other
MEET = 13.0      # they strike each other in the air: the impact
BURST_Y = 14.0   # the blast's point over the target (its sounds' distance)
DRAW = 23.0      # heaven drives the meeting point down
BLAST = 26.0     # the blast
AFTER = 30.5     # the aftermath's file starts
SHUT = 5.0       # the rift shuts this far into `after`
SURGES = (14.4, 16.2, 17.6, 19.4, 20.9, 22.2)   # the code's CV_SURGES
SURGE_SIGN = (1, -1, 1, -1, 1, -1)               # the Nether's push up, the Aether's holding (CV_SURGE_SIGN)
SURGE_AMP = (22.0, 34.0, 18.0, 40.0, 28.0, 26.0) # how big each is (CV_SURGE_AMP)
SURGE_ATK = (0.16, 0.12, 0.28, 0.11, 0.22, 0.14) # its force peaks this long after it starts (CV_SURGE_ATK)
BLAST_HIT = 0.05  # where the hit lands in the levelling strike's blast file (BLAST_AT: in the file that ships)
IMPACT_AT = 1.0   # where the hit lands in the impact's file (it starts at CROUCH)
QUAKE_HIT = 0.02  # where the thud lands in the quake's file
ERUPT0 = 3.0      # the eruption's file starts
FIRE0 = BREAK     # the fire's file starts
DRAW_LEN = 3.0
TEAR = 1.5        # the land tears into its two halves this far into the sunder's file (27.5)
COLLAPSE = 0.34   # the picture's held breath before the blast (the pass's cvg_collapse: 25.66 to 26.0)
FRAMES = 0.2      # the impact frames (26.0 to 26.2); the picture comes back on the white-out into the sheet
WIN0 = 26.9       # the win's file starts (heaven's choir arriving)
# The explosions' two takes (only SHIP's is written, `shipped`): 2 this laser's own (built to a reference's measurements), 1 the
# Payload's alternative builders as the Sky Breaks' slam plays them; the sequence round the blast the same in both
# (the drive cut 0.13 s before the hit, the wall, stunned to the tear, the tear as the second release, the choir).
TAKES = ("1", "2")
DEFAULT = SHIP = "2"
NAMES = {"1": "the Payload's alternative builders (the Sky Breaks' slam)", "2": "its own, built to a reference's measurements"}
BREATH = {"1": COLLAPSE, "2": 0.13}   # (the held breaths before the blast in the levelling strike, s: the drive ships take 2's)
# The events whose files differ by take (cv_sounds' `cv_file` mirrors this): the explosions; every other event is one
# file. OLD_OWN: the levelling strike's own (the drive, the blast, the sunder and the win), the layers and the win
# levelled under them (`cues`' `then`).
TAKE_OWN = ("erupt", "impact", "surge", "blast", "sunder")
OLD_OWN = ("drive", "blast", "sunder", "win")
# Every explosion is blown out at amount AMOUNT (BLOWOUT); the layers of hell and heaven are levelled (`room`) under
# the strike as it stands with the explosions at both ROOM_AMOUNTS and the one-hit blast (`build_ref`, REF_OWN), so
# what plays before the drive is the same whichever take is picked.
AMOUNT = "2"
ROOM_AMOUNTS = ("1", "2")
REF_OWN = ("erupt", "impact", "surge", "blast", "sunder")
# The layers of hell and heaven, each its own event (cv_sounds' CV_LAYERS mirrors this): (event, its file's start on
# the strike clock, whose).
LAYERS = (("hell", 3.0, "hell"), ("furnace", 6.0, "hell"), ("choir", 5.0, "heaven"), ("thunder", 4.8, "heaven"))
SEED = 99            # (the seed offset of the columns' push, the quake's rumble and the aftermath's roll)


def name_of(take, base, tier=None, own=TAKE_OWN):
    """The file of event `base` (`blast`, `surge_3`, ...) in tier `tier` for take `take`: `tK_base_tier` for the
    events in `own` (TAKE_OWN), `base_tier` for the rest (the quake: one file, no tier)."""
    nm = f"t{take}_{base}" if base.split("_")[0] in own else base
    return f"{nm}_{tier}" if tier else nm


def event_of(nm):
    """The event a file name plays (`impact`, `surge`, `blast`, ...)."""
    return nm.split("_")[1] if nm[:1] == "t" and nm[1:2].isdigit() else nm.split("_")[0]


def shipped(nm):
    """The name file `nm` ships as: take 2's own files without their `t2_`, everything else as it is (take 1 is built
    only to level the layers by, never written)."""
    return nm[3:] if nm.startswith(f"t{SHIP}_") else nm


def takes_in(files):
    return sorted({nm[1] for nm in files if nm[:1] == "t" and nm[1:2].isdigit()})


# The loudness (LUFS, the loudest 400 ms) each near file is set to; the blast the loudest by a clear margin.
LUFS = dict(blast=-10.0, impact=-14.0, surge=-15.5, erupt=-16.5, drive=-15.0, sunder=-16.0, nether=-29.0, aether=-23.0,
            fire=-24.0, clash=-23.5, after=-25.0, quake=-22.0,
            hell=-21.0, furnace=-25.0, choir=-22.0, thunder=-22.0, tear=-12.5, win=-17.0)
# How hard each hit is driven before it is levelled (a soft saturation of its loudest moment: a lower crest, so it is
# loud under the -1 dBFS ceiling, and the sub's harmonics in the body, where small speakers can play them).
SAT = {"blast": 2.3, "impact": 1.8, "surge": 1.6, "erupt": 1.6, "sunder": 1.4}
# The subtitle each event shows (the lang file's keys).
SUBTITLE = {"impact": "blast", "clash": "surge", "quake": "ground", "sunder": "blast", "erupt": "ground", "fire": "nether",
            "drive": "drawin", "surge": "surge", "nether": "nether", "aether": "aether", "blast": "blast", "after": "after",
            "hell": "hell", "furnace": "furnace", "choir": "choir", "thunder": "thunder", "win": "win"}


def N(s):
    return int(round(s * SR))


def T(n):
    return np.arange(n) / SR


def rng(seed):
    return np.random.default_rng(seed)


def smooth(x):
    return x * x * (3 - 2 * x)


def ramp(t, a, b):
    """0 before a, 1 after b, smooth between."""
    return smooth(np.clip((t - a) / (b - a), 0, 1))


def ease_out(t, a, b):
    """0 before a, 1 after b, fast first."""
    u = np.clip((t - a) / (b - a), 0, 1)
    return 1 - (1 - u) ** 2


def wander(n, rate, seed):
    """A smooth random curve in about [-1, 1], changing at about `rate` Hz: slow roughness, never grain."""
    from scipy.interpolate import CubicSpline
    k = max(4, int(n / SR * rate) + 4)
    xs = np.linspace(0, n - 1, k)
    return np.clip(CubicSpline(xs, rng(seed).uniform(-1, 1, k))(np.arange(n)), -1.5, 1.5)


def lp(x, f, o=4):
    return signal.sosfilt(signal.butter(o, f, "low", fs=SR, output="sos"), x)


def hp(x, f, o=2):
    return signal.sosfilt(signal.butter(o, f, "high", fs=SR, output="sos"), x)


def unit(x):
    return x / (np.sqrt(np.mean(x * x)) + 1e-12)


def phase(f):
    return 2 * np.pi * np.cumsum(f) / SR


def shaped_noise(n, gain, seed, nper=4096):
    """Noise whose spectrum is `gain(times, freqs)` frame by frame (moving bands and roars, no filter's ringing)."""
    hop = nper // 4
    x = rng(seed).standard_normal(n + nper)
    f, t, Z = signal.stft(x, SR, nperseg=nper, noverlap=nper - hop, boundary=None, padded=True)
    G = gain(t[None, :], f[:, None])
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")      # (NOLA: the edges' frames; trimmed off below)
        _, y = signal.istft(Z * G, SR, nperseg=nper, noverlap=nper - hop, boundary=False)
    return y[:n] if len(y) >= n else np.pad(y, (0, n - len(y)))


def bell(f, fc, oct_w):
    """A band centred on fc, `oct_w` octaves wide, as a smooth gain over frequency f."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / oct_w) ** 2)


def drive(x, k):
    return np.tanh(k * x) / np.tanh(k)


def fade(x, a=0.01, b=0.05):
    x = x.copy()
    ka, kb = N(a), N(b)
    if ka:
        x[:ka] *= np.linspace(0, 1, ka) ** 2
    if kb:
        x[-kb:] *= np.linspace(1, 0, kb) ** 2
    return x


def movavg(x, w):
    """The mean of x over a centred window of w samples."""
    c = np.concatenate([[0.0], np.cumsum(x)])
    i = np.arange(len(x))
    a = np.clip(i - w // 2, 0, len(x))
    b = np.clip(i + (w - w // 2), 0, len(x))
    return (c[b] - c[a]) / w


def fit(x, n):
    return x[:n] if len(x) >= n else np.pad(x, (0, n - len(x)))


def rms_at(x, a, b):
    return np.sqrt(np.mean(x[max(N(a), 0):N(b)] ** 2)) + 1e-12


# ==================================================================================================  loudness, peaks
def _kweight_coefs():
    """BS.1770's K-weighting (a high shelf and a high pass) at SR."""
    G, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
    A = 10 ** (G / 40)
    w0 = 2 * np.pi * fc / SR
    al, c, sA = np.sin(w0) / (2 * Q), np.cos(w0), np.sqrt(A)
    b1 = [A * ((A + 1) + (A - 1) * c + 2 * sA * al), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - 2 * sA * al)]
    a1 = [(A + 1) - (A - 1) * c + 2 * sA * al, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - 2 * sA * al]
    Q2, f2 = 0.5003270373253953, 38.13547087613982
    w0 = 2 * np.pi * f2 / SR
    al, c = np.sin(w0) / (2 * Q2), np.cos(w0)
    return (b1, a1), ([(1 + c) / 2, -(1 + c), (1 + c) / 2], [1 + al, -2 * c, 1 - al])


KW = _kweight_coefs()


def kweight(x):
    return signal.lfilter(*KW[1], signal.lfilter(*KW[0], x))


def lufs_m(x, win=0.4):
    """The loudest `win` s, K-weighted (LUFS momentary max for 0.4, short-term max for 3.0)."""
    k = kweight(x)
    return -0.691 + 10 * np.log10(np.max(movavg(k * k, N(min(win, len(x) / SR)))) + 1e-20)


def limit(x, ceil_db, look=0.012):
    """Peaks held under `ceil_db` dBFS by a gain that never rises within `look` s of a peak it must hold (a look-ahead
    limiter: no clipping, no bend in the wave, the gain riding slowly enough for the sub)."""
    return x * limit_gain(x, ceil_db, look)


def limit_gain(x, ceil_db, look=0.012):
    """The gain `limit` applies to x (1 where it need not act)."""
    c = 10 ** (ceil_db / 20)
    need = np.minimum(1.0, c / (np.abs(x) + 1e-12))
    if need.min() >= 1.0:
        return np.ones(len(x))
    L = N(look)
    g = minimum_filter1d(need, 2 * L + 1, mode="nearest")
    g = movavg(g, L)
    return np.minimum(g, minimum_filter1d(need, 3, mode="nearest"))


def set_lufs(x, db, ceil=-3.0, sat=0.0):
    """Its loudest 400 ms at `db` LUFS, its peaks under `ceil` dBFS (limited, then levelled again); `sat` > 0 drives
    it softly first (tanh, its peak at `sat`)."""
    if sat:
        x = drive(x / (np.abs(x).max() + 1e-12), sat)
    for _ in range(8):
        x = x * 10 ** ((db - lufs_m(x)) / 20)
        x = limit(x, ceil)
        if abs(lufs_m(x) - db) < 0.15:
            break
    return limit(x, ceil)


def peak_db(x):
    return 20 * np.log10(np.abs(x).max() + 1e-20)


# ============================================================================================  distance: the tiers
def absorb(x, metres):
    """`x` heard through `metres` of air: each frequency let down by the air's absorption (about 0.45 (f/1 kHz)^1.7
    dB a hundred metres: 2 kHz 3.6 dB and 4 kHz 12 dB at 250 m), a gentle slope, never a wall."""
    n = len(x)
    m = 1 << int(np.ceil(np.log2(n + 1)))
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1 / SR)
    db = np.minimum(0.45 * (f / 1000.0) ** 1.7 * metres / 100.0, 70.0)
    return np.fft.irfft(X * 10 ** (-db / 20), m)[:n]


def reverb(n_tail, dark, seed):
    """An outdoor tail: decaying noise, darker as it goes (`dark` Hz at its start, a third of that at its end)."""
    m = N(n_tail)
    t = T(m)
    ir = rng(seed).standard_normal(m) * np.exp(-6.9 * t / n_tail)
    lo, lo2 = lp(ir, dark, 2), lp(ir, dark / 3, 2)
    w = t / n_tail
    ir = lo * (1 - w) + lo2 * w
    ir[:N(0.015)] = 0
    return ir / np.sqrt(np.sum(ir * ir))


def conv(x, ir):
    return signal.fftconvolve(x, ir)[:len(x)]


def tier(x, kind, seed=7, wet=1.0):
    """The same sound heard near (as made), mid (past 500 blocks: through 250 m of air, a short outdoor tail) or far
    (past 1100: through 700 m, a long dark tail). Loudness matched to the
    near file's, less a little for the distance the cue's volume does not carry (mid 1 dB, far 2.5 dB)."""
    if kind == "near":
        return x
    ref = lufs_m(x)
    pad = np.concatenate([x, np.zeros(N(2.5 if kind == "mid" else 4.5))])
    if kind == "mid":
        y = absorb(pad, 250.0)
        y = y + 0.45 * wet * conv(y, reverb(1.6, 2500, seed))
        target = ref - 1.0
    else:
        y = absorb(pad, 700.0)
        y = (1 - 0.35 * wet) * y + 0.8 * wet * conv(y, reverb(3.6, 1100, seed + 1))
        target = ref - 2.5
    y = y[:len(x) + N(1.5 if kind == "mid" else 3.0)]
    return fade(set_lufs(y, target, ceil=min(-1.5, max(-3.0, peak_db(x) + 0.05))), 0, 0.8)


def tiers(x, seed=7, wet=1.0):
    return {k: tier(x, k, seed, wet) for k in ("near", "mid", "far")}


def gain_then(kind, dist):
    """`gain` as the layers of hell and heaven are levelled with (falling off from the target itself), for their
    `room` only."""
    if kind in ("nether", "aether", "clash"):
        return float(np.clip(1 / (1 + dist / 1500), 0.6, 1))
    return float(np.clip(1 / (1 + dist / 700), 0.45, 1))


def tiers_near(x, seed=7, wet=1.0):
    """`tiers` for an explosion built near, in layers: mid and far no louder than the near file (its loudest 400 ms,
    RMS) less 1 and 2.5 dB (levelling a hit whose crack and body the air has taken back up to the near file's loudness
    would bring its sub up past the near file's own)."""
    out = tiers(x, seed, wet)

    def top(y):
        return np.sqrt(np.max(movavg(y * y, N(0.4))))
    for k, d in (("mid", 1.0), ("far", 2.5)):
        out[k] = out[k] * min(1.0, top(x) * 10 ** (-d / 20) / top(out[k]))
    return out


def weights(dist):
    """How much of each tier plays at `dist` blocks: the near files alone out to 500, near to mid 500-900, mid to far
    1100-2000 (smooth)."""
    a = smooth(np.clip((dist - 500) / 400, 0, 1))
    b = smooth(np.clip((dist - 1100) / 900, 0, 1))
    return {"near": 1 - a, "mid": a * (1 - b), "far": a * b}


def gain(kind, dist):
    """The distance part of a cue's volume, whole out to 450 blocks: the columns are as tall as the sky and carry; the
    rest falls off."""
    far = max(dist - 450, 0)
    if kind in ("nether", "aether", "clash"):
        return float(np.clip(1 / (1 + far / 1500), 0.6, 1))
    return float(np.clip(1 / (1 + far / 700), 0.45, 1))


# ===================================================================================================  the recordings
# What breaks, burns or rushes is real: CC0 recordings from Freesound (credited in NOTICE), read from SRC (`--src`, or
# the CV_SOUND_SRC environment variable; they are not in the repository), named ROW_I_*.mp3. Every one is used at its
# own speed and bandwidth; only its ticks are held down after its front, its hum cut under 25 Hz. The beds and hell's
# voice (`columns_rec`, `hell_rec`) are slowed and rolled off gently; the top of take 2's hits (`dark_top`) is cut
# over 1 kHz. The files that ship hold impact_2, fire_1-3, roar_1-2, choir_1, choir_3, thunder_1-2, basalt_1,
# basalt_3, vent_1-2, crack_1 and fissure_1; the rest are read only by the levelling strike (`build_ref`, `blast_of`,
# `sunder_take`), built to level the layers and the win by.
#   blast_2   "Distant Explosion" (VanEngelen, 784660): a defined punch (2.37 s)
#   impact_1  "Sonic boom from Falcon 9 rocket landing" (g0ggs, 668561): the sky's boom (1.94 s)
#   impact_2  "G08-18-Aircraft-Sonic Boom.wav" (craigsmith, 437881): air booms (2.28, 3.31 s; a spoken slate at 0.3-1.4 s: nothing is cut from before 2 s): the Aether
#   impact_3  "Real explosion recording (new year's eve, no effects)" (modusmogulus, 784163): a close edge (0.09 s)
#   fissure_2 "glacierCalving.mp3" (CCCanary, 271008): the land giving: breaks at 10.31, 13.45 and 73.76 s, the
#             mass's roar from 14.7 s
#   fire_1    "Fire -massive no cracking.wav" (Aegersum, 387924): the fire's bed and roar
#   fire_2    "Flamethrower.wav" (sidequesting, 494085): bursts of fire (4.79 s and on)
#   blast_1   "R28-38-Eleven Large Explosions.wav" (craigsmith, 483286): surge 5's front (8.9 s)
#   fire_3    "Seamless Rocket Booster Roar & Crackle" (NickTimesAudio, 494827): the furnace's jet, its top under 900 Hz
# and, for the knock only (their lows, `knock_rec`; with blast_2's punches and impact_2's last shock at 6.59 s):
#   blast_3   "huge explosion in distance.wav" (SuperPhat, 417691): a deep blast's first swell (0.50 s)
#   fissure_3 "Cathedral Mountain rock slide, slow blocky chunks.wav" (betchkal, 500638): blocks landing (2.66, 3.39,
#             5.09, 11.93 s)
# and, for the explosions' cracks (CRACK_*: each front's first sample) and what follows them:
#   blast_3, fissure_3, blast_2, blast_1, impact_1, impact_2 as above; thunder_1, thunder_2 (from SRC9) at their cracks
#             (2.57, 0.67 s) and their rattle after
#   fissure_1 "S24-18 Landslide.wav" (craigsmith, 675736): rubble after the Nether's surges, the eruption and the tear
#             (from 3.5 s on: nothing from the tape's first seconds)
# and, from SRC9, for the layers of hell and heaven:
#   roar_2    "tiger, roar, growl, wild" (FALL-E, 696476): the roars under hell's bellows (ROARS)
#   choir_1   "CRWDSing_Ahh Vowel Sung Near F 02" (ShangusBurger, 764003): a crowd's held "ah" on F3
#   choir_3   "Voice Choir OOOH.wav" (Uzbazur, 413713): a held "ooh" on C3
#   thunder_1 "Thunder big crack explosive close" (TRP, 574412), thunder_2 "Closeup Thunder Strike 01" (loganzsound,
#             840628): their rolls after the crack (THUNDER_REC; the cracks are the surges', CRACK_SURGE)
# and, for the beds, hell's voice and the top of take 2's hits (`columns_rec`, `hell_rec`, HIT_TEX):
#   basalt_1  "Heavy stone door opens 2" (PostProdDog, 578491): stone grinding (its held line at 680 Hz notched out)
#   basalt_3  "stonegrind1.mp3" (j1987, 95007): stone grinding in bursts
#   vent_1    "Lava Loop 3" (Fission9, 474851, from SRC9): the lava's churn
#   vent_2    "Mud Volcano Field - Salton Sea" (RTB45, 415608, from SRC9): a heave of mud, slowed and dark
#   roar_1    "Lions Roaring 2" (Filmscore, 869003, from SRC9): lions, slowed to a growl
#   crack_1   "Ice - Lake fractures" (Vrymaa, 737896): a frozen lake straining and cracking, heard far off
#   impact_2 (from 2.3 s), thunder_1-2, choir_3, fire_1-3, fissure_1 (from 10 s) as above
SRC = Path(os.environ.get("CV_SOUND_SRC", "convergence-sound-src"))
# (the layers of hell and heaven read theirs (rows choir, roar, thunder) from SRC9 (`--src9`, or CV_SOUND_SRC9))
SRC9 = Path(os.environ.get("CV_SOUND_SRC9", "convergence-sound-src-9"))
_RECS = {}


def rec(row, i):
    """Recording `i` of `row`, mono at SR (decoded by ffmpeg), its hum cut under 25 Hz."""
    if (row, i) not in _RECS:
        hits = sorted(SRC.glob(f"{row}_{i}_*.mp3")) or sorted(SRC9.glob(f"{row}_{i}_*.mp3"))
        if not hits:
            raise SystemExit(f"no recording {row}_{i}_*.mp3 in {SRC} or {SRC9} (set CV_SOUND_SRC, CV_SOUND_SRC9 or --src, --src9)")
        raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(hits[0]), "-ac", "1", "-ar", str(SR),
                              "-f", "f32le", "-"], check=True, capture_output=True).stdout
        _RECS[(row, i)] = hp(np.frombuffer(raw, "<f4").astype(np.float64), 25, 4)
    return _RECS[(row, i)]


def cut(x, a, b):
    return x[max(N(a), 0):N(b)].copy()


def soften(x, k=2.0, keep=0):
    """Ticks and crackle held down: wherever the 2 ms level jumps past k times the 40 ms level it is held to that;
    the first `keep` samples (a front) left as they are."""
    fast = np.sqrt(movavg(x * x, N(0.002)) + 1e-14)
    slw = np.sqrt(movavg(x * x, N(0.04)) + 1e-14)
    g = movavg(np.minimum(1.0, k * slw / fast), N(0.003))
    if keep:
        g[:keep] = 1.0
        w = min(N(0.02), len(g) - keep)
        g[keep:keep + w] = np.linspace(1, 0, w) + g[keep:keep + w] * np.linspace(0, 1, w)
    return x * g


def declick(x, k=2.0, keep=0):
    """`soften` on the lows (under 2 kHz, at k) and harder on the highs (at 1.5): a recording's pops, crackle and ticks
    out of its top, where they stand out, its body left whole; its front (the first `keep` samples) untouched."""
    lo = lp(x, 2000, 2)
    return soften(lo, k, keep) + soften(x - lo, 1.5, keep)


def strike_point(x, search=1.0):
    """Where a front lands: the first 5 ms window within 6 dB of the loudest in its first `search` s."""
    e = np.sqrt(movavg(x * x, N(0.005)))
    m = e[:N(search)].max()
    return int(np.argmax(e > m * 0.5))


def front(row, i, peak, length, pre=0.6, k=3.0):
    """A recorded hit cut round its peak (`peak` s into the recording): from `pre` before it, `length` long, its ticks
    held down after its first 60 ms, its top dying after the front, faded in. Returns (sound, the sample its front lands on)."""
    x = cut(rec(row, i), peak - pre, peak + length)
    s = strike_point(x[:N(pre + 0.3)] if len(x) > N(pre + 0.3) else x, pre + 0.3)
    x = declick(x, k, keep=s + N(0.06))
    # (its top dies with the front, as a real blast's does: full band for its first 0.15 s, under 2.5 kHz from 0.6 s;
    # the tail's pops and echoes' ticks go with it)
    w = np.clip((np.arange(len(x)) - s - N(0.15)) / N(0.45), 0, 1)
    x = x * (1 - w) + lp(x, 2500, 4) * w
    x = fade(x, min(0.25, pre * 0.5), 0.3)
    return x, s


def lay(acc, x, s, at, g=1.0):
    """`x` added into `acc` with its sample `s` at `at` seconds."""
    i0 = N(at) - s
    a, b = max(i0, 0), min(i0 + len(x), len(acc))
    if b > a:
        acc[a:b] += g * x[a - i0:b - i0]
    return acc


def rec_front(n, at, row, i, peak, length, g_db=0.0, pre=0.6, k=3.0, decay=None):
    """A recorded front laid at `at` in an n-sample buffer, its loudest 400 ms after the front at unit RMS times g;
    `decay` (s): its tail let down with that time constant from a second after the front."""
    x, s = front(row, i, peak, length, pre, k)
    x = x / (np.sqrt(np.mean(x[s:s + N(0.4)] ** 2)) + 1e-12)
    out = lay(np.zeros(n), x, s, at, 10 ** (g_db / 20))
    if decay:
        t = T(n)
        out *= np.exp(-np.maximum(t - at - 1.0, 0) / decay)
    return out


def rec_bed(row, i, a, b, n, speed=1.0, k=2.0):
    """A stretch of a recording as a bed `n` long (looped with cross-fades if short), ticks held down."""
    x = declick(cut(rec(row, i), a, b), k)
    if speed != 1.0:
        from fractions import Fraction
        fr = Fraction(1 / speed).limit_denominator(100)
        x = signal.resample_poly(x, fr.numerator, fr.denominator)
    return unit(loop(x, n, 1.0))


def loop(x, n, xf=1.0):
    """`x` repeated to `n` samples, each join cross-faded over `xf` s (equal power)."""
    k = N(xf)
    out = x.copy()
    w = np.sin(0.5 * np.pi * np.linspace(0, 1, k))
    while len(out) < n:
        out = np.concatenate([out[:-k], out[-k:] * w[::-1] + x[:k] * w, x[k:]])
    return out[:n]


# ===================================================================================================  the synthesized
def hit_env(t, at, atk, parts):
    """0 before `at`; rises in `atk` s; then the sum of (weight, time constant) decays."""
    tt = np.maximum(t - at, 0)
    d = sum(w * np.exp(-tt / tau) for w, tau in parts)
    return np.where(t >= at, (1 - np.exp(-tt / max(atk, 1e-4))) * d, 0)


def thump(n, at, f_hi, f_lo, tau_f, atk, parts, k=1.4):
    """A sub blow on `at`: a sine falling from f_hi to f_lo (time constant tau_f), rising in `atk`, decaying by
    `parts`, driven a little (its second harmonic gives it body on small speakers)."""
    t = T(n)
    tt = np.maximum(t - at, 0)
    f = np.where(t >= at, f_lo + (f_hi - f_lo) * np.exp(-tt / tau_f), f_hi)
    x = np.sin(phase(f)) * hit_env(t, at, atk, parts)
    return drive(x * 1.1, k)


def roar(n, at, lo, hi, atk, parts, seed, tilt=0.0, move=0.25):
    """A broad roar between lo and hi Hz (its spectrum sloping `tilt` dB an octave), rising in `atk` and decaying by
    `parts`, its level moving slowly (`move`: how much, under 1.2 Hz: weight that breathes, never flickers)."""
    t = T(n)
    c = np.sqrt(lo * hi)
    w = np.log2(hi / lo) / 2.4

    def g(tt, ff):
        return bell(ff, c, w) * (np.maximum(ff, 20) / c) ** (tilt / 6.02) * (1 + 0 * tt)
    x = shaped_noise(n, g, seed)
    x = unit(x) * (1 - move + move * (0.5 + 0.5 * wander(n, 1.1, seed + 1)))
    return x * hit_env(t, at, atk, parts)


def nwave(n, at, width, seed):
    """A pressure front's own edge: one N-shaped wave (a step up in 0.4 ms, a fall through zero over `width` s, back
    up), its spectrum broad to several kHz, then a few ms of dense rough air dying with it: the 'crack' of a big front,
    heavy, not a snap."""
    t = T(n) - at
    x = np.zeros(n)
    on = (t >= 0) & (t < width)
    u = t[on] / width
    x[on] = (1 - 2 * u) * np.minimum(1.0, t[on] / 0.0004)
    tail = (t >= width) & (t < width * 1.6)
    x[tail] = -np.cos(0.5 * np.pi * (t[tail] - width) / (0.6 * width)) * 0.6
    air = rng(seed).standard_normal(n) * np.where(t >= 0, np.exp(-np.maximum(t, 0) / 0.012), 0)
    air = hp(lp(air, 7000, 2), 900, 2)
    return x + 0.35 * air / (np.abs(air).max() + 1e-12)


def pk_norm(x, at):
    """x scaled so the 400 ms after `at` is at unit RMS."""
    return x / rms_at(x, at, at + 0.4)


# ======================================================================================  the smaller explosions' front
# The cracks giving, the eruption, the hit in the air and the six surges start on a knock: a fast low blow (60-500 Hz,
# rising in a millisecond or two), every layer of the hit starting on its sample and nothing of them before it, nothing
# over about 1.5 kHz in its first instant, taken from the lows of real close events (`knock_rec`). Past its first
# instant each hit is as it is built over its plain front, an N-wave's edge (`nwave`, which the blast keeps), and
# set by the same gain (`level_like`).
ROLL_F = 1500.0            # (where the hits' top starts, Hz)
ROLL = (0.04, 0.12)        # (their top held to its own steady level to the first, left as it is from the second, s after the hit)


def zlp(x, f, o=4):
    """x low-passed at f without delay (forward and back: no lag between the layers, no ringing behind an onset)."""
    return signal.sosfiltfilt(signal.butter(o, f, "low", fs=SR, output="sos"), x)


def zhp(x, f, o=2):
    return signal.sosfiltfilt(signal.butter(o, f, "high", fs=SR, output="sos"), x)


def gate(x, at, rise=0.0004):
    """x from `at` on only: nothing before it, in over `rise` s (a raised cosine)."""
    u = np.clip((T(len(x)) - at) / rise, 0, 1)
    return x * (0.5 - 0.5 * np.cos(np.pi * u))


def true_onset(x, near, look=0.04, frac=0.1):
    """The sample a front truly starts on: from its loudest moment within `look` s before sample `near` and 20 ms
    after it, back to where its envelope (Hilbert, smoothed over 0.25 ms) last rose past `frac` of that, or past
    2.5 times the level of the 50 ms before the search if that is higher."""
    a, b = max(0, near - N(look)), min(len(x), near + N(0.02))
    lo = max(0, a - N(0.06))
    e = movavg(np.abs(signal.hilbert(x[lo:b])), max(1, N(0.00025)))
    pk = (a - lo) + int(np.argmax(e[a - lo:]))
    floor = np.median(e[:max(1, a - lo - N(0.01))]) if a - lo > N(0.02) else 0.0
    thr = max(frac * e[pk], 2.5 * floor)
    i = pk
    while i > a - lo and e[i] > thr:
        i -= 1
    return lo + i


def rec_front_at(n, at, row, i, peak, length, g_db=0.0, pre=0.6, k=3.0, decay=None):
    """`rec_front` with the front's true first sample (not its loudest stretch) on `at` and nothing of it before, as
    loud from 60 ms to a second after it as `rec_front` lays it."""
    x, s = front(row, i, peak, length, pre, k)
    x = x / (np.sqrt(np.mean(x[s:s + N(0.4)] ** 2)) + 1e-12)
    was = lay(np.zeros(n), x, s, at, 10 ** (g_db / 20))
    out = gate(lay(np.zeros(n), x, true_onset(x, s), at, 10 ** (g_db / 20)), at)
    out *= rms_at(was, at + 0.06, at + 1.0) / rms_at(out, at + 0.06, at + 1.0)
    if decay:
        t = T(n)
        out *= np.exp(-np.maximum(t - at - 1.0, 0) / decay)
    return out


def instant(x, at):
    """x with its top (over ROLL_F) held, from just before `at` through its first instant, to no more than the level
    that top keeps over the 40-200 ms after it (the recordings' own air): no burst on the front and no hole after it;
    left as it is from ROLL[1] s on."""
    t = T(len(x))
    lo = zlp(x, ROLL_F, 4)
    hi = x - lo
    e = np.sqrt(movavg(hi * hi, N(0.004)) + 1e-14)
    c = np.median(e[N(at + 0.04):N(at + 0.2)])
    g = movavg(minimum_filter1d(np.minimum(1.0, c / e), N(0.004)), N(0.002))
    w = ramp(t, at - 0.003, at - 0.0005) * (1 - ramp(t, at + ROLL[0], at + ROLL[1]))
    return lo + hi * (1 - w * (1 - g))


# (the knock for each hit: the close events whose lows make it (row, i, where its onset is (s), share), its top
# (Hz), how long it holds (s) and then its time constant (s). Each one a single clean blow: up 20-40 dB in 2-4 ms out of
# a quiet floor, no rattle after it: the explosion's punches (blast_2 at 2.363, 2.750, 3.466 s), a deep blast's first
# swell (blast_3 at 0.504), the rock slide's blocks landing (fissure_3 at 2.660, 3.387, 5.085, 11.933) and an air
# boom's last shock (impact_2 at 6.592))
KNOCK_REC = {
    "crack": dict(parts=(("fissure", 3, 5.085, 1.0), ("fissure", 3, 11.933, 0.5)), f=520, hold=0.012, tau=0.022),
    "erupt": dict(parts=(("blast", 2, 2.363, 1.0), ("fissure", 3, 2.660, 0.7), ("blast", 3, 0.504, 0.4)), f=450, hold=0.02, tau=0.04),
    "impact": dict(parts=(("blast", 2, 2.363, 1.0), ("impact", 2, 6.592, 0.8), ("fissure", 3, 5.085, 0.5)), f=480, hold=0.016, tau=0.032),
    "surge": dict(f=450, hold=0.014, tau=0.028),
    "surge_air": dict(f=520, hold=0.012, tau=0.022),
}
# (each surge's: the Nether's (odd) the ground's blocks and the explosion's punches, the Aether's (even) the air
# boom's shock and the sharper punches; each different from the last)
KNOCK_REC_SURGE = (
    (("fissure", 3, 2.660, 1.0), ("blast", 2, 3.466, 0.5)),
    (("impact", 2, 6.592, 1.0), ("blast", 2, 2.750, 0.5)),
    (("blast", 2, 2.363, 1.0), ("fissure", 3, 5.085, 0.6)),
    (("blast", 2, 2.750, 1.0), ("impact", 2, 6.592, 0.7)),
    (("fissure", 3, 5.085, 1.0), ("fissure", 3, 2.660, 0.5)),
    (("fissure", 3, 11.933, 1.0), ("impact", 2, 6.592, 0.5)),
)


def rec_lows(row, i, where, f):
    """The lows of a recorded event round `where` s: under f Hz (steeply) and over 35 Hz, both without delay; the
    sample its own onset is on and the sample its rise passes half its first peak (within 20 ms of the onset)."""
    x = cut(rec(row, i), where - 0.1, where + 0.35)
    x = np.pad(x, (max(0, N(0.1 - where)), 0))
    lo = zhp(zlp(zlp(x, f, 4), f, 4), 35, 2)
    s = true_onset(lo, N(0.1), look=0.03)
    e = movavg(np.abs(signal.hilbert(lo)), max(1, N(0.00025)))
    w = e[s:s + N(0.02)]
    return lo, s, s + int(np.argmax(w > 0.5 * w.max()))


def knock_rec(n, at, parts, f, hold, tau):
    """Take 2's knock on `at`: the lows of real close events (`parts`) laid so their rises pass half way on the same
    sample (one onset, no flam) and the earliest starts on `at`, nothing of them before it, their tops rolled off under
    f Hz, held `hold` s and dying with `tau` (a knock, not a held weight; gone by 0.2 s). Unit peak."""
    got = [(rec_lows(row, i, where, f), g) for row, i, where, g in parts]
    lead = max(h - s for (_, s, h), _ in got)
    out = np.zeros(n)
    for (lo, s, h), g in got:
        out = lay(out, lo / (np.abs(lo[s:s + N(0.03)]).max() + 1e-12), h, at + lead / SR, g)
    t = T(n) - at
    env = np.exp(-np.maximum(t - hold, 0) / tau) * (1 - ramp(t, 0.12, 0.2))
    x = gate(out * env, at)
    return x / (np.abs(x).max() + 1e-12)


# (the knock's peak against the peak the plain front has in the same hit, at most; and the most the first 30 ms
# may then carry over what they carry with the plain front, dB: weight moved down, not a louder hit)
KNOCK_GAIN = {"crack": 1.0, "erupt": 1.0, "impact": 1.0, "surge": 1.0}
KNOCK_CAP = 1.5


def with_knock(x, kn, ref, at, g_max):
    """x with knock `kn` laid on `at`: at `g_max` times its unit peak, or less if the first 30 ms would then carry
    more than KNOCK_CAP dB over ref's first 30 ms."""
    a, b = N(at), N(at + 0.03)
    xs, ks = x[a:b], kn[a:b]
    want = float(ref[a:b] @ ref[a:b]) * 10 ** (KNOCK_CAP / 10)
    c, bb, aa = float(ks @ ks), float(xs @ ks), float(xs @ xs)
    disc = bb * bb - c * (aa - want)
    g = (-bb + np.sqrt(disc)) / c if disc > 0 and c > 0 else 0.0
    return x + float(np.clip(g, 0.0, g_max)) * kn


def knock(n, at, kind, i=0):
    """The knock (unit peak) for a hit of `kind` (`crack`, `erupt`, `impact`, `surge`; surge `i`, at its own pitch:
    the lows sped up or slowed by SURGE_PITCH[i], from their onset, so the onset stays on `at`)."""
    air = kind == "surge" and SURGE_SIGN[i] < 0
    m = KNOCK_REC["surge_air" if air else kind]
    parts = KNOCK_REC_SURGE[i] if kind == "surge" else m["parts"]
    x = knock_rec(n, at, parts, m["f"], m["hold"], m["tau"])
    if kind == "surge":
        from fractions import Fraction
        fr = Fraction(2 ** (-SURGE_PITCH[i] / 12)).limit_denominator(200)
        seg = signal.resample_poly(x[N(at):], fr.numerator, fr.denominator)
        y = np.zeros(n)
        m = min(len(seg), n - N(at))
        y[N(at):N(at) + m] = seg[:m]
        x = gate(y, at)
        x = x / (np.abs(x).max() + 1e-12)
    return x


def level(kind, x, at, i=0):
    """Hit x (its hit at `at` s) driven softly and set to its loudness (a surge's less by its reach)."""
    lvl = LUFS[kind] + (0.75 * 20 * np.log10(SURGE_AMP[i] / max(SURGE_AMP)) if kind == "surge" else 0.0)
    return set_lufs(x, lvl, ceil=-2.0 if kind == "blast" else -3.0, sat=SAT[kind])


def level_like(kind, x, ref, at, i=0):
    """Hit x levelled as `level` levels `ref` (the same hit over its plain front): driven against ref's peak, by the
    gain ref got, held under the same ceiling; so past its first instant x is as ref was."""
    p = np.abs(ref).max() + 1e-12
    y_ref = drive(ref / p, SAT[kind])
    r = level(kind, ref, at, i)
    m = np.abs(y_ref) > 1e-3 * np.abs(y_ref).max()
    g = float(np.median(r[m] / y_ref[m]))
    return limit(drive(x / p, SAT[kind]) * g, -3.0)


# =====================================================================================  the explosions blown out
# Every explosion overloads the air by its size: its lows and body (40 Hz-1.5 kHz) through a soft clip and a second
# and third order shaper, four times oversampled, the products alone (DC and the sub under 90 Hz out, nothing over
# 4.2 kHz) laid over the clean hit from its first sample through its first second or so and gone by its end. The
# products grow with the square and the cube of the level, so they follow the hit down and never lift a quiet tail or
# a recording's floor. Their energy over the first 300 ms is set against the clean hit's (BLOWOUT, dB; amount 2 that
# plus AMOUNT2_DB); the body's products come in over the first 30 ms after the lows' (the knock's onset stays one
# clean onset).
BLOWOUT = {"crack": -27.0, "erupt": -13.5, "impact": -12.5, "blast": -8.0, "tear": -11.0}
AMOUNT2_DB = 6.0
BLOW_LEN = {"crack": 0.7, "erupt": 1.6, "impact": 1.6, "blast": 2.2, "surge": 1.2, "tear": 1.8}
BLOW_UP = {"blast": (2.5, 3.0)}   # (how much louder the loudest 400 ms comes out, dB, amounts 1 and 2; the rest BLOW_UP0)
BLOW_UP0 = (0.0, 0.3)


def blow_db(kind, i=0, take=AMOUNT):
    """The products' energy against the clean hit's over its first 300 ms (dB) for a hit of `kind` (surge `i`) at
    amount `take` (None: the base, without AMOUNT2_DB): the surges from -22 (18 blocks of reach) to -16 (40), 1.2 dB
    a step by size."""
    if kind == "surge":
        v = -22.0 + 1.2 * sorted(SURGE_AMP).index(SURGE_AMP[i])
    else:
        v = BLOWOUT[kind]
    return v + (AMOUNT2_DB if take == "2" else 0.0)


def blow_size(kind, i=0):
    """0 (the cracks) to 1 (the blast): how hot the clip is driven."""
    return float(np.clip((blow_db(kind, i, None) - BLOWOUT["crack"]) / (BLOWOUT["blast"] - BLOWOUT["crack"]), 0, 1))


def blow_products(x, at, kind, i=0):
    """The overdriven products of hit x (its hit at `at` s), unscaled, windowed to the hit: (products, window)."""
    n = len(x)
    t = T(n)
    sz = blow_size(kind, i)
    L = BLOW_LEN[kind]
    w = ramp(t, at - 0.003, at - 0.0005) * (1 - ramp(t, at + 0.45 * L, at + L))
    b = zhp(zlp(x, 1500, 4), 40, 2)
    lo = zlp(b, 220, 4)
    hi = b - lo
    out = np.zeros(n)
    a0, a1 = max(0, N(at - 0.01)), min(n, N(at + L + 0.05))
    for part, delay in ((lo, 0.0), (hi, 0.03)):
        seg = part[a0:a1]
        pk = np.abs(part[N(at):N(at + 0.3)]).max() + 1e-12
        u = signal.resample_poly(seg / pk, 4, 1)
        k = 1.2 + 2.0 * sz                       # (hotter into the clip for the bigger)
        uc = np.tanh(k * u) / np.tanh(k)
        y = 1.4 * uc * uc + 2.0 * uc ** 3 + 2.0 * (uc - u)   # (all of them of the second order and up; the last flattens the peaks)
        y = signal.resample_poly(y, 1, 4)[:len(seg)] * pk
        prod = np.zeros(n)
        prod[a0:a0 + len(y)] = y
        prod = zhp(zlp(prod, 4200, 8), 90, 4)
        if delay:
            prod = prod * ramp(t, at + 0.002, at + delay)
        out += prod * (1.0 if delay == 0.0 else 0.8)
    return out * w, w


def blowout(x, at, kind, i=0, take=AMOUNT, extra=0.0):
    """Hit x with its explosion at `at` s blown out by its size at amount `take` (see BLOWOUT): the products laid on
    it at their energy, `extra` dB more (`relevel` then sets its loudness)."""
    p, _ = blow_products(x, at, kind, i)
    a, b = N(at), N(at + 0.3)
    g = np.sqrt(float(x[a:b] @ x[a:b]) / (float(p[a:b] @ p[a:b]) + 1e-20) * 10 ** ((blow_db(kind, i, take) + extra) / 10))
    return x + g * p


def blowout_held(x, at, kind, i=0, take=AMOUNT, extra=0.0):
    """`blowout` for a hit whose sub is its own layer: the products' energy set against the clean hit's over BLOW_HP
    (where the products are), not against a sub that does not drive them, the products kept under BLOW_TOP (the crack
    owns 2-6 kHz) and held under the clean hit's own peak less BLOW_HEAD dB (their sharp corners never stand over the
    hit: a denser block, not spikes); `blown` solves for the energy."""
    p, _ = blow_products(x, at, kind, i)
    a, b = N(at), N(at + 0.3)
    xh = zhp(x, BLOW_HP, 4)[a:b]
    g = np.sqrt(float(xh @ xh) / (float(p[a:b] @ p[a:b]) + 1e-20) * 10 ** ((blow_db(kind, i, take) + extra) / 10))
    return x + limit(zlp(g * p, BLOW_TOP, 4), peak_db(x) - BLOW_HEAD, 0.004)


BLOW_HEAD = 4.0
BLOW_HP = 90.0
BLOW_TOP = 2500.0   # (and kept under this: the crack's band stays the crack's)


def relevel(y, ref, take, ceil, kind=None):
    """y set to ref's loudest 400 ms plus BLOW_UP for its kind and amount, its peaks under `ceil`."""
    return set_lufs(y, lufs_m(ref) + BLOW_UP.get(kind, BLOW_UP0)[1 if take == "2" else 0], ceil=ceil)


# ======================================================================================================  the columns
def nether_voice(t):
    """The ground's voice (both before the launch and as the standing column): a throat (noise shaped into a 27.5 Hz
    tube's harmonics) with a heaving sub."""
    n = len(t)

    def g(tt, ff):
        comb = sum(bell(ff, k * 27.5, 0.035) / k ** 0.4 for k in range(1, 40))
        return comb * bell(ff, 220, 1.8)
    x = lp(shaped_noise(n, g, 41, nper=8192), 3000, 2)
    heave = np.sin(phase(np.full(n, 18.0))) * (0.6 + 0.4 * wander(n, 0.3, 42))
    return unit(drive(unit(x) * 0.35, 1.6)) + 0.6 * unit(heave)


def aether_voice(t):
    """The sky's voice: a narrow pressure front swaying, over a 25 Hz swell. Bright as air is, never a whistle."""
    n = len(t)
    t0 = t[0]

    def g(tt, ff):
        tt = tt + t0
        c = 620 * (1 + 0.06 * np.sin(0.9 * tt))
        return bell(ff, c, 0.14) + 0.7 * bell(ff, c * 1.5, 0.16) + 0.4 * bell(ff, c * 2.25, 0.2) + 0.35 * bell(ff, c / 2, 0.3)
    x = shaped_noise(n, g, 71)
    sw = np.sin(phase(np.full(n, 25.0))) * (0.7 + 0.3 * wander(n, 0.25, 72))
    return unit(x) + 0.55 * unit(sw)


def rift_open(n, t, mass=None):
    """The rift opening in the sky from RIFT (t: strike seconds): weight, not a chime. Pressure gathering under it
    (a sub swell from RIFT - 0.8), the sky giving way (a real sonic boom's roll, at its own speed, on RIFT + 0.25) and
    its mass settling over a second and a half, no overshoot: a tight air boom with a held breath (the stub of light
    pulled under) before it. `mass`: the settling mass from `mass(n, at)` (a recording) in place of the shaped noise."""
    at = RIFT + 0.25
    ai = at - t[0]          # (where that is in the buffer, which starts at t[0])
    swell = np.sin(phase(22 + 6 * ramp(t, RIFT - 0.8, at))) * ramp(t, RIFT - 0.9, at) ** 2 * (1 - ramp(t, at + 0.2, at + 2.5))
    boom = rec_front(n, ai, "impact", 2, 2.28, 2.6, -1.0)
    sub = thump(n, ai, 70, 26, 0.12, 0.004, ((0.6, 0.35), (0.4, 1.6)))
    mass = roar(n, ai, 40, 900, 0.25, ((0.6, 0.8), (0.4, 2.2)), 461, tilt=-3) if mass is None else mass(n, ai)
    return 0.3 * unit(swell) + pk_norm(boom, ai) + 0.7 * pk_norm(sub, ai) + 0.45 * pk_norm(mass, ai)


def column_env(t, t0, floor_db, break_db, stub_from, stub_db, swell_at=None):
    """A column's level (dB under the clash's start) over the strike before the launch: from t0 a floor rising to
    `break_db` by BREAK, from `stub_from` the fountain or the stub of light; CROUCH to FIRE the draw-back, 9 dB away,
    gone by FIRE."""
    r = ramp(t, t0, BREAK) ** 0.7
    e = floor_db * (1 - r) + break_db * r
    e = e + (stub_db - break_db) * ramp(t, stub_from, stub_from + 2.5) ** 0.8 + 1.0 * ramp(t, stub_from + 2.5, CROUCH)
    e = e - 9.0 * ease_out(t, CROUCH, FIRE)
    return 10 ** (e / 20) * (1 - ramp(t, FIRE - 0.07, FIRE + 0.04))


def clash_gain(t):
    """The clash's level over the strike clock `t`: in from the hit (a 2 dB flare dying over half a second), rising
    4 dB to the drive and 3 more to the blast, cut into it."""
    tt = np.maximum(t - MEET, 0)
    c = 2.0 * np.exp(-tt / 0.5) + 4.0 * ramp(t, MEET + 0.6, DRAW) + 3.0 * ramp(t, DRAW, BLAST)
    return 10 ** (c / 20) * np.where(t >= MEET, 1 - np.exp(-tt / 0.012), 0) * (1 - ramp(t, BLAST - 0.03, BLAST + 0.004))


def columns():
    """Both columns over the strike, as one voice each: the ground's and the sky's before the launch (`nether`,
    `aether`: no column yet, thinner, no sub; the rift's opening in the sky's), and the two standing columns pressed
    together from the hit (`clash`), each giving way as the other pushes, cut into the blast."""
    nn = N(BLAST + 0.3)
    t = T(nn)
    vn = nether_voice(t)
    thin = hp(vn, 55, 2)
    full = ramp(t, FIRE, MEET)
    vn = vn * full + thin * (1 - full)
    ta = T(N(BLAST + 0.3 - 0.5)) + 0.5
    va = aether_voice(ta)
    push = wander(nn, 0.55, 300 + SEED) * ramp(t, MEET + 0.5, MEET + 2.5)
    pa = np.interp(ta, t, push)
    # before the launch
    en = column_env(t, 0.0, -14.0, -9.0, ERUPT, -3.0)
    ea = column_env(ta, 0.5, -18.0, -12.0, CV_GOLD0, -4.0)
    pre_n = hp(vn, 18, 4) * en
    pre_a = hp(va, 18, 4) * ea
    i0 = N(FIRE + 0.12)
    pre_n = fade(set_lufs(pre_n[:i0], LUFS["nether"]), 0.5, 0.02)
    # (the rift opening on top of the sky's voice, its loudest moment)
    ra = rift_open(len(ta), ta)
    pre_a = unit(pre_a[:i0 - N(0.5)]) * 0.3 + ra[:i0 - N(0.5)] / rms_at(ra, RIFT + 0.25 - 0.5, RIFT + 0.65 - 0.5) * 1.0
    pre_a = fade(set_lufs(pre_a, LUFS["aether"]), 0.5, 0.02)
    # the clash: both standing from the hit (the fire's bed burns on under them in `fire`)
    gc = clash_gain(t)
    xn = hp(vn, 18, 4) * gc * (1 + 0.22 * push)
    xa = hp(va, 18, 4) * np.interp(ta, t, gc) * (1 - 0.22 * pa)
    cl = xn[N(MEET):]
    ca = xa[N(MEET - 0.5):]
    m = min(len(cl), len(ca))
    clash = unit(cl[:m]) + 1.0 * unit(ca[:m])
    # (the held breath before the blast, with the drive's)
    clash = clash * (1 - 0.68 * ramp(T(m) + MEET, BLAST - 0.11, BLAST - 0.085))
    clash = fade(set_lufs(clash, LUFS["clash"]), 0.0, 0.05)
    return pre_n, pre_a, clash


# ---------------------------------------------------------------------------------  the columns, on recordings
# The beds as they ship: the same jobs, cues, lengths and shapes as `columns` (column_env, clash_gain, the push, the
# held breaths, the rift's opening), made of recordings slowed and rolled off gently (`rec_layer`), then
# held to the level over time of the beds the strike was levelled with (`held_like`).
def rec_layer(row, i, a, b, n, speed=1.0, top=None, notch=()):
    """Recording `i` of `row` from `a` to `b` s as a bed n long (`rec_bed`: looped, ticks held down), slowed by
    `speed`, rolled off at 6 dB an octave from `top` Hz (on the recording's own roll-off), with narrow notches at `notch` (Hz, after the slowing: a
    held line in the recording). Unit RMS."""
    x = rec_bed(row, i, a, b, n, speed)
    for fq in notch:
        bq, aq = signal.iirnotch(fq, 6.0, fs=SR)
        x = signal.lfilter(bq, aq, x)
    return unit(lp(x, top, 1) if top else x)


def held_like(y, ref, win=0.5, rounds=3, most=12.0):
    """y with its level over time held to ref's: the gain between their RMS over `win` s, smoothed over `win` and at
    most `most` dB up; what moves inside the window is y's own."""
    k = N(win)
    for _ in range(rounds):
        g = np.sqrt((movavg(ref * ref, k) + 1e-12) / (movavg(y * y, k) + 1e-12))
        y = y * movavg(np.minimum(g, 10 ** (most / 20)), k)
    return y


def far_air(x, metres, seed, wet=0.6, length=3.6, dark=900):
    """x far off: through `metres` of air (`absorb`) and a long dark outdoor tail."""
    y = absorb(x, metres)
    return y + wet * unit(conv(y, reverb(length, dark, seed))) * np.sqrt(np.mean(y * y))


def nether_rec(t):
    """The ground before the launch (t: strike seconds from 0): stone grinding and heaving under it (a heavy stone
    door's grind and a lava vent's churn, slowed), and from the eruption the fountain's voice (lions slowed to a
    growl, a fire's roar under it)."""
    n = len(t)
    ground = (rec_layer("vent", 1, 0.5, 39.0, n, 0.7) + 0.75 * rec_layer("basalt", 1, 0.3, 13.6, n, 0.8, 300, (544.0,))
              + 0.4 * rec_layer("basalt", 3, 13.0, 29.8, n, 0.7, 400))
    fountain = rec_layer("roar", 1, 0.5, 16.5, n, 0.55, 500) + 0.7 * rec_layer("fire", 1, 1.0, 19.0, n, 0.75)
    return unit(ground) + 0.75 * unit(fountain) * ramp(t, ERUPT - 0.1, ERUPT + 1.2)


def aether_rec(ta):
    """The sky before the launch (ta: strike seconds from 0.5): a frozen lake straining and cracking far off (at half
    speed, its ringing glides slow and low, through 1200 m of air), the air of a thunder roll slowed, and from the rift's opening a choir very soft and far."""
    n = len(ta)
    far = far_air(rec_layer("crack", 1, 8.0, 22.0, n, 0.5), 1200.0, 1501)
    air = rec_layer("thunder", 1, 3.0, 9.5, n, 0.8, 600)
    voices = hall(absorb(rec_layer("choir", 3, 0.8, 8.4, n), 500.0), 4.5, 1200, 0.8, 1502)
    return 0.7 * unit(far) + 0.8 * unit(air) + 0.3 * unit(voices) * ramp(ta, RIFT, CV_GOLD0 + 1.0)


def rift_mass(n, at):
    """The rift's settling mass from `at` s: a real thunder's roll after its crack, slowed, dying over two seconds."""
    x = cut(rec("thunder", 2), 0.95, 0.95 + n / SR)
    x = lp(signal.resample_poly(x, 5, 4), 900, 2)[:n]
    tt = np.maximum(T(len(x)), 0)
    x = fade(x, 0.04, 0.3) * (0.6 * np.exp(-tt / 0.8) + 0.4 * np.exp(-tt / 2.2))
    return lay(np.zeros(n), x, 0, at)


def columns_rec(old):
    """`columns` made of recordings: (nether, aether, clash), each held to `old`'s (`columns`' own) level over time.
    The clash: the fire's side (a rocket's roar, a flamethrower and the lava's churn, low) against the light's (the lake's cracking
    far off, a thunder's roll, a choir far), each heaving as the other pushes, stone grinding between them as hard
    as they push."""
    nn = N(BLAST + 0.3)
    t = T(nn)
    ta = T(N(BLAST + 0.3 - 0.5)) + 0.5
    i0 = N(FIRE + 0.12)
    # before the launch: no column yet, no sub
    vn = hp(nether_rec(t), 55, 2)
    pre_n = hp(vn, 18, 4) * column_env(t, 0.0, -14.0, -9.0, ERUPT, -3.0)
    pre_n = fade(set_lufs(pre_n[:i0], LUFS["nether"]), 0.5, 0.02)
    va = aether_rec(ta)
    pre_a = hp(va, 18, 4) * column_env(ta, 0.5, -18.0, -12.0, CV_GOLD0, -4.0)
    ra = rift_open(len(ta), ta, rift_mass)
    pre_a = unit(pre_a[:i0 - N(0.5)]) * 0.3 + ra[:i0 - N(0.5)] / rms_at(ra, RIFT + 0.25 - 0.5, RIFT + 0.65 - 0.5) * 1.0
    pre_a = fade(set_lufs(pre_a, LUFS["aether"]), 0.5, 0.02)
    # the clash
    push = wander(nn, 0.55, 300 + SEED) * ramp(t, MEET + 0.5, MEET + 2.5)
    gc = clash_gain(t)
    fire_ = (rec_layer("fire", 3, 0.2, 5.9, nn, 0.85, 400) + 0.8 * rec_layer("fire", 2, 30.5, 46.0, nn, 0.8, 300)
             + 0.8 * rec_layer("vent", 1, 0.5, 39.0, nn, 0.8))
    light = (0.6 * unit(far_air(rec_layer("crack", 1, 22.5, 40.0, nn, 0.5), 600.0, 1503)) + 0.6 * rec_layer("thunder", 2, 1.0, 6.0, nn, 0.85, 500)
             + 0.3 * unit(hall(rec_layer("choir", 3, 0.8, 8.4, nn), 4.5, 1200, 0.8, 1504)))
    grind = rec_layer("basalt", 3, 13.0, 21.0, nn, 0.75, 400)
    xn = hp(unit(fire_), 18, 4) * gc * (1 + 0.22 * push)
    xa = hp(unit(light), 18, 4) * gc * (1 - 0.22 * push)
    xg = hp(grind, 30, 2) * gc * (0.25 + 0.5 * np.abs(push))
    clash = (unit(xn) + unit(xa) + 1.0 * unit(xg))[N(MEET):]
    clash = clash * (1 - 0.68 * ramp(T(len(clash)) + MEET, BLAST - 0.11, BLAST - 0.085))
    clash = fade(set_lufs(clash, LUFS["clash"]), 0.0, 0.05)
    return tuple(fade(held_like(fit(x, len(o)), o), 0.0, 0.02) for x, o in zip((pre_n, pre_a, clash), old))


# ==========================================================================================  the eruption and fire
def erupt():
    """From ERUPT0: the ground straining (a groan rising under the tremor), the cracks giving on BREAK (2.0 in: a
    close explosion's front, a sub blow), the build (BREAK to ERUPT: the fire's roar swelling out of the cracks and
    the sub rising under it: something gathers and strains), the fire erupting on ERUPT (3.0 in: a real explosion's
    front, a flamethrower's burst, the sub on the hit) and its roll settling, no overshoot; a held breath before it
    (the build drawn down for a tenth of a second); each front on its knock (`knock`), the bass on the hit."""
    d = 9.5
    n = N(d)
    t = T(n)
    b, e = BREAK - ERUPT0, ERUPT - ERUPT0
    groan = roar(n, 0.0, 30, 180, 1.0, ((1.0, 1e9),), 601, tilt=-4, move=0.35)
    groan *= (0.15 + 0.85 * ramp(t, 0.0, e) ** 1.5) * (1 - ramp(t, e + 0.3, e + 2.5))
    # the cracks giving
    bnw = nwave(n, b, 0.006, 602) * 0.7
    brec = rec_front(n, b, "impact", 3, 0.09, 1.5, -6.0)
    gb = 0.4 / rms_at(bnw + brec, b, b + 0.4)
    bsub = thump(n, b, 60, 28, 0.1, 0.006, ((0.6, 0.3), (0.4, 1.2)))
    # the build: fire roaring up the cracks, louder and louder (15 dB over the second), the sub rising
    fl = lp(rec_bed("fire", 2, 4.4, 14.4, n, 1.0, 2.2), 2500, 4)
    build = ramp(t, b + 0.1, e - 0.02) ** 2
    fl_env = 10 ** ((-18 + 18 * build) / 20) * (1 - ramp(t, e + 0.6, e + 4.0)) * ramp(t, b, b + 0.1)
    # (the held breath: drawn 11 dB under for the last tenth of a second before the hit)
    fl_env = fl_env * (1 - 0.72 * ramp(t, e - 0.14, e - 0.05) * (t < e))
    rise = np.sin(phase(24 + 10 * ramp(t, b, e))) * ramp(t, b + 0.2, e) ** 2 * (1 - ramp(t, e, e + 0.05))
    # the eruption
    hnw = nwave(n, e, 0.009, 603) * 1.2
    hrec = rec_front(n, e, "blast", 2, 2.37, 3.0, -2.0)
    gh = 1.0 / rms_at(hnw + hrec, e, e + 0.4)
    burst = lp(rec_front(n, e, "fire", 2, 4.79, 3.5, 0.0, pre=0.2, k=2.2), 3500, 2)
    sub = thump(n, e, 75, 34, 0.09, 0.003, ((0.5, 0.3), (0.5, 1.6)))
    body = roar(n, e, 70, 700, 0.012, ((0.5, 0.5), (0.5, 2.0)), 604, tilt=-2)
    rest = (0.35 * unit(groan) + 0.5 * pk_norm(bsub, b) * 0.5 + 0.5 * fl * fl_env + 0.25 * unit(rise)
            + 0.9 * pk_norm(sub, e) + 0.45 * pk_norm(body, e))
    gu = 0.55 / rms_at(burst, e, e + 0.4)
    ref = fade(rest + gb * (bnw + brec) + gh * (hnw + hrec) + gu * burst, 0.3, 0.6)
    # (the same over the knock: the recorded fronts from their own first sample, the burst from the hit's)
    x = (rest + gb * rec_front_at(n, b, "impact", 3, 0.09, 1.5, -6.0) + gh * rec_front_at(n, e, "blast", 2, 2.37, 3.0, -2.0)
         + gu * gate(burst, e))
    x = instant(instant(x, b), e)
    x = with_knock(x, knock(n, b, "crack"), ref, b, KNOCK_GAIN["crack"] * gb * np.abs(bnw).max())
    x = with_knock(x, knock(n, e, "erupt"), ref, e, KNOCK_GAIN["erupt"] * gh * np.abs(hnw).max())
    return level_like("erupt", fade(x, 0.3, 0.6), ref, e)


def fire():
    """Fire and ash out of the cracks (BREAK), the fountain's roar standing out of the ground (ERUPT to CROUCH),
    drawn down with the draw-back (16 dB, fast first), its bed burning on under the clash, cut into the blast. A
    massive fire (the bed), the same from another stretch (the fountain), a flamethrower's roar; ticks held down,
    the top under 1.8 kHz (the crackle out: the presence is the hits')."""
    d = BLAST + 0.3 - FIRE0
    n = N(d)
    t = T(n)
    ts = t + FIRE0
    top = 1800
    bed = lp(rec_bed("fire", 1, 0.4, 19.9, n, 1.0, 1.8), top, 4)
    jet = lp(rec_bed("fire", 2, 15.0, 30.0, n, 1.0, 2.0), top, 4)
    draw = ease_out(ts, CROUCH, FIRE)
    eb = 10 ** ((-10 * (1 - ramp(ts, BREAK, ERUPT + 0.5)) - 16 * draw + 10 * ramp(ts, MEET + 0.3, MEET + 2.0)) / 20)
    eb = eb * np.clip((ts - BREAK) / 0.25, 0, 1) * (0.82 + 0.18 * wander(n, 0.7, 621))
    er = ramp(ts, ERUPT + 0.4, ERUPT + 1.6) * 10 ** ((3.0 * ramp(ts, ERUPT + 1.5, CROUCH)) / 20) * (0.8 + 0.2 * wander(n, 0.5, 622))
    er = er * 10 ** (-24 * draw / 20) * (1 - ramp(ts, FIRE - 0.05, FIRE + 0.1))
    x = unit(bed) * eb + 0.9 * unit(jet) * er
    # (the held breaths before the eruption and the blast)
    x = x * (1 - 0.7 * ramp(ts, ERUPT - 0.14, ERUPT - 0.05) * (ts < ERUPT)) * (1 - 0.68 * ramp(ts, BLAST - 0.11, BLAST - 0.085))
    x = x * (1 - ramp(ts, BLAST - 0.04, BLAST + 0.004))
    return fade(set_lufs(hp(x, 20, 4), LUFS["fire"]), 0.0, 0.1)


# ========================================================================================  the draw-back and the hit
def impact():
    """From CROUCH: the held breath (0-0.45: the air pulled in and down, a sub swelling), the two rushing at each
    other (0.45-1.0: the Nether's fire roaring up, the Aether's air coming down, both swelling 30 dB into the hit) and
    the hit (1.0, on MEET), then the sky's roll: a held breath before the blow (the rush drawn under for 70 ms), a
    hard defined front (the knock under close explosions' fronts), the bass on the hit, a short ring."""
    d = 5.5
    n = N(d)
    t = T(n)
    h = IMPACT_AT
    u0 = np.clip(t / (FIRE - CROUCH), 0, 1)
    pull = shaped_noise(n, lambda T_, ff: bell(ff, 420 * (0.6 ** np.clip(T_ / 0.45, 0, 1)), 1.0), 401)
    back = 0.4 * unit(pull) * (0.35 + 0.65 * u0 ** 1.5) * (1 - ramp(t, 0.45, 0.7))
    back = back + 0.5 * np.sin(phase(22 + 8 * u0)) * (0.2 + 0.8 * u0 ** 2) * (1 - ramp(t, 0.6, 0.9))
    # the rush
    u = np.clip((t - (FIRE - CROUCH)) / (MEET - FIRE), 0, 1)
    went = (t >= FIRE - CROUCH).astype(float)
    lev = 10 ** ((-30 * (1 - u) ** 1.3) / 20) * went
    lev = lev * (1 - 0.75 * ramp(t, h - 0.085, h - 0.06))
    lev = lev * (1 - ramp(t, h + 0.004, h + 0.03))
    up = lp(rec_bed("fire", 2, 4.6, 8.0, n, 1.0, 2.2), 2500, 4)
    down = shaped_noise(n, lambda T_, ff: bell(ff, 900, 1.1) * np.exp(-np.maximum(ff - 3500, 0) / 1200), 403)
    rush = (unit(up) + 0.7 * unit(down)) * lev + 0.6 * np.sin(phase(30 + 20 * u)) * lev
    # the hit
    nw = nwave(n, h, 0.008, 406)
    r3 = rec_front(n, h, "impact", 3, 0.09, 1.5, 0.0)
    g3 = 0.54 / rms_at(r3, h, h + 0.4)
    rb = rec_front(n, h, "blast", 2, 2.37, 2.5, -3.0)
    gf = 1.0 / rms_at(nw + g3 * r3 + rb, h, h + 0.4)
    sub = thump(n, h, 110, 40, 0.05, 0.002, ((0.6, 0.25), (0.4, 1.1)), k=1.8)
    body = roar(n, h, 90, 900, 0.004, ((0.7, 0.18), (0.3, 0.9)), 407, tilt=-2)
    hit = 0.85 * pk_norm(sub, h) + 0.45 * pk_norm(body, h)
    lr = rms_at(gf * (nw + g3 * r3 + rb) + hit, h, h + 0.4)
    bed = rush / rms_at(rush, h - 0.25, h - 0.1) * 10 ** (-9 / 20) + back * 0.25
    ref = fade((gf * (nw + g3 * r3 + rb) + hit) / lr + bed, 0.05, 0.8)
    # (the same over the knock: the recorded fronts from their own first sample)
    fr = g3 * rec_front_at(n, h, "impact", 3, 0.09, 1.5, 0.0) + rec_front_at(n, h, "blast", 2, 2.37, 2.5, -3.0)
    x = instant((gf * fr + hit) / lr + bed, h)
    x = with_knock(x, knock(n, h, "impact"), ref, h, KNOCK_GAIN["impact"] * gf * np.abs(nw).max() / lr)
    return level_like("impact", fade(x, 0.05, 0.8), ref, h)


def quake():
    """The ground's answer to the blast, through the ground ahead of the air: a soft-fronted sub thud and a low rumble
    dying over two seconds; no rock, nothing breaking. QUAKE_HIT s in."""
    d = 4.0
    n = N(d)
    t = T(n)
    lng = 1.5
    thud = thump(n, QUAKE_HIT, 40, 18, 0.15, 0.008, ((0.4, 0.3), (0.6, lng)), k=1.3)
    rum = roar(n, QUAKE_HIT, 30, 140, 0.15, ((1.0, lng * 0.8),), 501 + SEED, tilt=-3, move=0.3)
    x = hp(lp(unit(thud) + 0.8 * unit(rum), 300, 4), 16, 4)
    return fade(set_lufs(x, LUFS["quake"]), 0.0, 0.8)


# =======================================================================================================  the surges
def push(t, atk):
    """A shove's force over its file (the pass's cv_push): 0 at its start, 1 at `atk`, then dying away."""
    x = np.maximum(t, 0) / atk
    return x * np.exp(1 - x)


# (each surge's recorded front, each a different blow: the Nether's pushes a close explosion's edge or a defined punch,
# the Aether's an air boom: row, i, peak)
SURGE_FRONTS = (("impact", 3, 0.09), ("impact", 1, 1.94), ("blast", 2, 2.75), ("impact", 2, 2.28), ("blast", 1, 8.9),
                ("impact", 2, 3.31))
SURGE_FIRE = (4.79, None, 37.4, None, 62.3, None)   # the flamethrower bursts under the Nether's pushes (s in it)
SURGE_FIRE_G = (0.55, 0.0, 0.3, 0.0, 0.45, 0.0)      # (and how loud: the bigger, the more)
# Each surge's pitch, semitones over the root (a sub from 88 Hz to 39): the Nether's 4 under, the Aether's 3 over, and
# the smaller up to 6 higher (40 blocks of reach the lowest, 18 the highest); no two neighbours alike.
SURGE_PITCH = tuple(round(-4.0 * (s > 0) + 3.0 * (s < 0) + 6.0 * (40.0 - a) / 22.0, 2) for s, a in zip(SURGE_SIGN, SURGE_AMP))


def surge(i):
    """Surge `i`: the push swelling from its start to its peak (SURGE_ATK[i] in, the pass's cv_push), the shockwave's
    boom on the peak, then the strain held and let go. The Nether's (odd) a blow of fire driving up: an explosion's
    front and a flamethrower's burst over a sub; the Aether's (even) holding the line: an air boom, higher and harder,
    over a sub. Sized by its reach (SURGE_AMP[i]: 0.75 x 20 log10(amp / 40) dB): the bigger, the lower (SURGE_PITCH),
    the longer its ring and the more sub under it. A hard defined front (the knock, at the surge's pitch), the bass on
    the peak, a short ring."""
    atk, amp, up = SURGE_ATK[i], SURGE_AMP[i], SURGE_SIGN[i] > 0
    sz = (amp - min(SURGE_AMP)) / (max(SURGE_AMP) - min(SURGE_AMP))
    r = 2 ** (SURGE_PITCH[i] / 12)
    d = 2.6 + atk
    n = N(d)
    t = T(n)
    pk = atk
    swell = push(t, atk) * (1 - ramp(t, atk, atk + 0.03))
    row, k, p = SURGE_FRONTS[i]
    fr = rec_front(n, pk, row, k, p, d, 0.0, pre=0.25, decay=0.5)
    nw = 0.8 * pk_norm(nwave(n, pk, 0.006 if up else 0.004, 820 + i), pk)
    gf = 1.0 / rms_at(fr + nw, pk, pk + 0.4)
    lng = (0.15 + 0.12 * sz, 0.55 + 0.45 * sz)
    sub = thump(n, pk, 88 * r, 39 * r, 0.07 + 0.03 * sz, 0.004, ((0.55, lng[0]), (0.45, lng[1])))
    lo, hi = (50 * r, 650 * r) if up else (85 * r, min(1200 * r, 1250.0))   # (no more top on the front for the higher)
    body = roar(n, pk, lo, hi, 0.01, ((0.6, lng[0]), (0.4, lng[1])), 830 + i, tilt=-2.5 if up else -1.5)
    g_sub, g_body = (0.95 + 0.15 * sz, 0.38) if up else (0.7 + 0.15 * sz, 0.55)
    rest = g_sub * pk_norm(sub, pk) + g_body * pk_norm(body, pk)
    # the swell into the peak (no wind-up before the start): a roar rising with the push
    rest = rest + 0.5 * roar(n, 0.0, 60 * r, 600 * r, 0.001, ((1.0, 1e9),), 840 + i, tilt=-3) * swell
    burst = np.zeros(n)
    if up and SURGE_FIRE[i] is not None:
        b = lp(rec_front(n, pk, "fire", 2, SURGE_FIRE[i], 3.0, 0.0, pre=0.2, k=2.2), 2500 + 2000 * sz, 2)
        burst = SURGE_FIRE_G[i] * pk_norm(b, pk)
    ref = fade(gf * (fr + nw) + rest + burst, 0.0, 0.4)
    # (the same over the knock: the recorded front from its own first sample, the burst from the peak's)
    x = instant(gf * rec_front_at(n, pk, row, k, p, d, 0.0, pre=0.25, decay=0.5) + rest + gate(burst, pk), pk)
    x = with_knock(x, knock(n, pk, "surge", i), ref, pk, KNOCK_GAIN["surge"] * gf * np.abs(nw).max())
    return level_like("surge", fade(x, 0.0, 0.4), ref, pk, i)


# ========================================================================================================  the drive
def drive_down():
    """Heaven driving the meeting point down into the ground (DRAW to BLAST): the last build, never quiet. A roar
    coming down (the Aether's air, a band that opens a little as it nears, to about 3 kHz: 12 dB louder over the three
    seconds, accelerating), the Nether's fire pressed under it, the sub rising, the ground straining; it ends on the
    blast, drawn under for 90 ms just before the hit (a held breath, never silence). The strike the layers are
    levelled under (`build_ref`); each take's own drive is `drive_take`."""
    x, t, acc = drive_parts()
    env = 10 ** (-12 * (1 - acc) / 20)
    env = env * (1 - 0.68 * ramp(t, DRAW_LEN - 0.11, DRAW_LEN - 0.085))
    env = env * (1 - ramp(t, DRAW_LEN - 0.012, DRAW_LEN - 0.001))
    x = hp(x, 18, 4) * env
    return fade(set_lufs(x, LUFS["drive"]), 0.25, 0.01)


def drive_parts():
    """The drive's roar before its envelope: (sound, times, how far on (0..1, accelerating))."""
    d = DRAW_LEN + 0.06
    n = N(d)
    t = T(n)
    u = np.clip(t / DRAW_LEN, 0, 1)
    acc = u ** 2

    def g(tt, ff):
        uu = np.clip(tt / DRAW_LEN, 0, 1) ** 2
        top = 1000 * (2.6 ** uu)
        return bell(ff, 400 + 300 * uu, 1.4) * np.exp(-np.maximum(ff - top, 0) / (0.35 * top))
    air = shaped_noise(n, g, 91)
    fl = lp(rec_bed("fire", 2, 40.0, 52.0, n, 1.0, 2.2), 2500, 4)
    f = 24 * 2 ** (0.8 * acc)
    sub = drive(np.sin(phase(f)) + 0.3 * np.sin(phase(2 * f)), 1.5)
    x = unit(air) * (0.3 + 0.7 * acc) + 0.55 * unit(fl) * (1 - 0.4 * acc) + 0.7 * unit(sub) * (0.4 + 0.6 * acc)
    return x, t, acc


def drive_take(k):
    """Take k's drive: the same roar, louder and brighter as it accelerates down, and its held breath (BREATH[k]) on
    the picture's. 1: drawn into the point over the picture's own held breath (COLLAPSE, 25.66-26.0): its top first,
    then the sub, the low middle last and narrowing (a pressed tone, never a drop-out), near nothing for its last 40
    ms. 2: pressed harder to the last, then cut dead: 0.13 s of near silence before the hit."""
    x, t, acc = drive_parts()
    x = hp(x, 18, 4)
    y = set_lufs(x * 10 ** (-12 * (1 - acc) / 20), LUFS["drive"])
    a = DRAW_LEN - BREATH[k]
    if k == "1":
        sub = zlp(y, 70, 4)
        top = zhp(y, 900, 4)
        mid = y - sub - top
        narrow = zhp(zlp(mid, 600, 2), 140, 2)
        mid = mid + (narrow - mid) * ramp(t, a + 0.05, a + 0.25)
        gt = 10 ** (-34 * ramp(t, a - 0.06, a + 0.16) / 20)
        gs = 10 ** (-30 * ramp(t, a + 0.02, a + 0.22) / 20)
        gm = 10 ** ((-6 * ramp(t, a, a + 0.2) - 24 * ramp(t, a + 0.2, DRAW_LEN - 0.04)) / 20)
        y = sub * gs + mid * gm + top * gt
    else:
        y = y * 10 ** (2.5 * ramp(t, DRAW_LEN - 0.7, a - 0.01) / 20)
        y = y * (1 - 0.994 * ramp(t, a - 0.012, a + 0.006))
    y = limit(y, -3.0) * (1 - ramp(t, DRAW_LEN - 0.012, DRAW_LEN - 0.001))
    return fade(y, 0.25, 0.01)


# ========================================================================================================  the blast
def blast():
    """The Sundering's hit on BLAST (BLAST_HIT in): the loudest thing in the strike. A hard cut: a hard defined
    front (a pressure wave's edge, a sonic boom's crack, a close explosion) after the drive's held breath, the bass on
    the hit (a sub dropping from 110 Hz), a body that rings and a short clean tail."""
    h = BLAST_HIT
    d = 8.0
    n = N(d)
    t = T(n)
    fr = (nwave(n, h, 0.012, 121) * 1.0 + 0.8 * pk_norm(rec_front(n, h, "impact", 2, 2.28, 3.0, 0.0), h)
          + 0.7 * pk_norm(rec_front(n, h, "impact", 3, 0.09, 1.5, 0.0), h) + 0.8 * pk_norm(rec_front(n, h, "blast", 2, 2.37, 3.0, 0.0), h))
    sub = thump(n, h, 110, 38, 0.06, 0.002, ((0.45, 0.35), (0.55, 1.8)), k=1.8)
    body = roar(n, h, 90, 900, 0.004, ((0.6, 0.25), (0.4, 1.4)), 122, tilt=-2.0)
    ring = roar(n, h, 40, 160, 0.05, ((1.0, 2.2),), 123, tilt=-3, move=0.15)
    x = pk_norm(fr, h) + 1.1 * pk_norm(sub, h) + 0.5 * pk_norm(body, h) + 0.35 * pk_norm(ring, h)
    x = hp(x, 18, 4) * (1 - ramp(t, d - 4.5, d - 0.1))
    x = fade(x, 0.0, 0.1)
    return level("blast", x, h)


def sunder():
    """The land torn in two along the seam (its file starts on BLAST; the tear at TEAR, 27.5): it groans open under
    the hit's roll, gives at TEAR (the glacier's big break at its own speed and bandwidth, a sub blow under it), and
    the two halves go their own ways: fire and ash roaring out one side (flamethrower bursts, the massive fire), air
    rushing out the other (a sonic boom's roll at its own speed), in after the hit's front: the break defined (the
    bass on the tear), the halves short (limited with the blast as one sum)."""
    d = 7.5
    n = N(d)
    t = T(n)
    k = TEAR
    brk = rec_front(n, k, "fissure", 2, 13.45, 3.5, 0.0, pre=1.4)
    brk *= np.where(t < k - 0.05, 10 ** ((-12 + 8 * ramp(t, 0.2, k - 0.05)) / 20), 1.0)
    # (the blast's own sub and roll carry the lows under the tear: the tear's thump is a body, over 45 Hz)
    bsub = hp(thump(n, k, 90, 48, 0.08, 0.004, ((0.5, 0.3), (0.5, 1.2))), 45, 2)
    tear = pk_norm(brk, k) + 0.7 * pk_norm(bsub, k)
    # the Nether half
    f1 = rec_front(n, 0.5, "fire", 2, 57.0, 4.0, 0.0, pre=0.2, k=2.2)
    f2 = rec_front(n, k - 0.1, "fire", 2, 30.6, 4.0, 1.0, pre=0.2, k=2.2)
    bed = lp(rec_bed("fire", 1, 6.0, 19.9, n, 1.0, 1.8), 2200, 4)
    end = (3.5, 6.0)
    fire_env = ramp(t, 0.35, 1.0) * (0.7 + 0.3 * np.exp(-((t - k) / 1.2) ** 2)) * (1 - ramp(t, *end))
    xf = (0.8 * lp(f1 + f2, 3500, 2) + 0.7 * bed) * fire_env
    # the Aether half
    xa = rec_front(n, k - 0.3, "impact", 1, 1.94, 6.0, 0.0) + rec_front(n, k + 0.6, "impact", 2, 3.31, 3.2, -3.0)
    xa = xa * ramp(t, 0.6, k) * (1 - ramp(t, end[0] - 1.0, end[1] - 1.0))
    tear, xf, xa = tear / rms_at(tear, k, k + 0.8), 0.8 * xf / rms_at(xf, k - 0.5, k + 0.5), 0.6 * xa / rms_at(xa, k, k + 1.0)
    x = hp(tear + xf + xa, 38, 2)
    x = fade(x, 0.25, 1.0)
    return set_lufs(x, LUFS["sunder"], sat=SAT["sunder"])


# ---- the blast's two designs (TAKES): the drive's end (`drive_take`), the blast, the land's tear, heaven's win
def closing(x, at, falls):
    """x from `at` on with its bands dying in order, as a big blast's roll closes down: `falls` gives, for under 150
    Hz, 150-800 Hz, 0.8-3 kHz and over 3 kHz, how long after `at` each is 20 dB down (s; each held whole for its first
    tenth). Zero-phase bands, so they sum back to x before `at`."""
    t = T(len(x))
    lo = zlp(x, 150, 4)
    b1 = zlp(x, 800, 4) - lo
    b2 = zlp(x, 3000, 4) - lo - b1
    b3 = x - lo - b1 - b2
    out = np.zeros(len(x))
    for part, f20 in zip((lo, b1, b2, b3), falls):
        hold = 0.1 * f20
        out += part * 10 ** (-20 * np.maximum(t - at - hold, 0) / (f20 - hold) / 20)
    return out


def ring(n, at, f0, f1, glide, life, seed, parts=8):
    """The air ringing after a blast: a low pitched roar, noise gathered round the partials of a note that falls from
    f0 to f1 Hz over `glide` s (most of the fall early), each partial a band a few Hz wide (a roar with a pitch, never a
    clean tone), the higher ones fainter and shorter; in over 0.15 s, gone by `life` s."""
    t = T(n)
    tt = np.maximum(t - at, 0)
    f = f0 * (f1 / f0) ** (np.clip(tt / glide, 0, 1) ** 0.6)
    rg = rng(seed)
    out = np.zeros(n)
    for k in range(1, parts + 1):
        w = zlp(rg.standard_normal(n), 2.5 + 0.8 * k, 2)
        w = w / (np.sqrt(np.mean(w * w)) + 1e-12)
        car = np.sin(phase(k * f * (1 + 0.003 * wander(n, 0.5, seed + k))) + rg.uniform(0, 6.28))
        dk = np.exp(-tt / (life * (0.55 - 0.04 * k)))
        out += w * car * dk / k ** 1.1
    env = np.where(t >= at, (1 - np.exp(-tt / 0.15)), 0) * (1 - ramp(t, at + 0.8 * life, at + life))
    return out * env


def body_rec(n, at, peak, g_db=0.0, length=6.0):
    """A real large explosion's body (blast_1, its blow round `peak` s: 16.05, 22.05, both clear of the tape's spoken
    slates at 0.2-1.2 and 35.3-36.7 s) with its first sample on `at`, at unit RMS over its first 400 ms."""
    return rec_front_at(n, at, "blast", 1, peak, length, g_db)


def blast_take(k):
    """Take k's blast (BLAST_HIT in, on 26.0), clean: (its body, levelled; `shape`, what is done to it once it is
    blown out; what is laid over it then, at the body's scale). The shaping and what is laid over come after the drive
    and the blow-out, so its dips and its roll keep their depth.
    1, two releases: the hit on the impact frames (the lows of close blasts, a pressure edge, a close explosion's edge,
    the bass dropping from 150 Hz to 30 within a tenth of a second), all of it let go in its last 40 ms (20 dB down),
    then on the frames' end (FRAMES, as the picture comes back) the bigger release: a real large explosion, a deep
    blast's swell, a body to 1.2 kHz, the sky's boom (the sheet tearing the air up to the rift) and a sub blooming from
    75 Hz to 27; its roll closing down from the top (`closing`: over 3 kHz 20 dB down by 1.0 s, 0.8-3 kHz by 1.6, the
    body by 3.6, the lows by 4.4) under the air ringing on a note falling five semitones (`ring`, 55 to 41 Hz).
    2, one wall: everything at once on the hit and held flat (the recorded fronts and bodies, the sky's boom, a sub
    from 120 Hz to 32, a body to 3 kHz) for a second; then stunned at 1.05 s (27.05): all of it over 150 Hz down 20 dB
    in 60 ms, the top 16 more, the lows down 12, a low ring left; sucked back in from 1.25 s (a low roar swelling to
    the tear, 80-700 Hz) and let go on the tear (TEAR in the sunder's file, 27.5), where the land's file takes over;
    what is left of it comes back under the tear and rolls away closing down."""
    h = BLAST_HIT
    d = 8.0
    n = N(d)
    t = T(n)
    kn = knock_rec(n, h, KNOCK_REC["impact"]["parts"], 900, 0.03, 0.05)
    edge = nwave(n, h, 0.010, 131)
    near = pk_norm(rec_front_at(n, h, "impact", 3, 0.09, 1.2), h)
    front_ = 1.2 * kn + 0.8 * edge / (np.abs(edge).max() + 1e-12) + 1.4 * near / (np.abs(near).max() + 1e-12)
    if k == "1":
        r = h + FRAMES
        sub = thump(n, h, 150, 30, 0.035, 0.002, ((0.7, 0.07), (0.3, 0.2)), k=2.0)
        punch = pk_norm(rec_front_at(n, h, "blast", 2, 2.75, 0.6), h)
        hit = (front_ + 1.6 * near / (np.abs(near).max() + 1e-12) + 0.8 * punch / (np.abs(punch).max() + 1e-12) + 1.1 * sub) * (1 - ramp(t, r - 0.01, r + 0.03))
        big = pk_norm(body_rec(n, r, 22.1), r)
        swell = pk_norm(rec_front_at(n, r, "blast", 3, 0.504, 6.0), r)
        boom = pk_norm(rec_front_at(n, r + 0.02, "impact", 1, 1.94, 5.0), r)
        bsub = thump(n, r, 75, 27, 0.12, 0.004, ((0.35, 0.5), (0.65, 3.2)), k=1.8)
        body = roar(n, r, 70, 1200, 0.006, ((0.5, 0.45), (0.5, 2.6)), 141, tilt=-1.5)
        rel = big + 0.7 * swell + 0.55 * boom + 1.3 * pk_norm(bsub, r) + 0.6 * pk_norm(body, r)
        x = hit / rms_at(hit, h, r - 0.05) * 0.6 + 1.3 * rel
        extra = 0.3 * pk_norm(ring(n, r + 0.1, 55, 41, 3.0, 5.5, 151), r + 0.3) * rms_at(x, r, r + 1.0)

        def shape(y):
            t = T(len(y))
            dip = 1 - 0.9 * ramp(t, r - 0.05, r - 0.015) * (1 - ramp(t, r - 0.004, r + 0.002))
            return closing(y * dip, r, (4.4, 3.6, 1.6, 1.0))
    else:
        st = h + 1.05
        tr = h + TEAR
        sub = thump(n, h, 120, 32, 0.07, 0.002, ((0.5, 0.4), (0.5, 3.0)), k=2.0)
        big = pk_norm(body_rec(n, h, 16.1), h)
        swell = pk_norm(rec_front_at(n, h, "blast", 3, 0.504, 6.0), h)
        boom = pk_norm(rec_front_at(n, h + 0.01, "impact", 1, 1.94, 5.0), h)
        body = roar(n, h, 70, 3000, 0.004, ((1.0, 1e9),), 142, tilt=-2.0)
        x = front_ + big + 0.7 * swell + 0.6 * boom + 1.3 * pk_norm(sub, h) + 0.8 * pk_norm(body, h)
        # (held flat: the recordings' own fall evened out over the first second)
        lvl = np.sqrt(movavg(x * x, N(0.25)) + 1e-12)
        ref = np.sqrt(np.mean(x[N(h + 0.02):N(h + 0.3)] ** 2))
        x = x * np.clip(ref / lvl, 1.0, 3.0) ** (ramp(t, h + 0.25, h + 0.4) * (1 - ramp(t, st - 0.05, st)))
        x = x * (1 - 0.7 * ramp(t, tr + 1.0, tr + 4.0))
        lw = rms_at(x, st - 0.3, st - 0.05)
        rg_ = 0.12 * pk_norm(ring(n, st, 78, 70, 1.5, 4.0, 152, parts=7), st + 0.05) * (1 - 0.6 * ramp(t, tr - 0.012, tr))
        suck = roar(n, h + 1.25, 80, 700, 0.01, ((1.0, 1e9),), 143, tilt=-2.0)
        suck = suck * (np.exp((np.minimum(t, tr) - tr) / 0.09) * (t >= h + 1.25)) * (1 - ramp(t, tr - 0.01, tr + 0.002))
        extra = (rg_ + 0.25 * suck / (rms_at(suck, tr - 0.1, tr) + 1e-12)) * lw

        def shape(y):
            t = T(len(y))
            lo = zlp(y, 150, 4)
            hi_ = y - lo
            top = zhp(hi_, 2000, 4)
            on = ramp(t, st, st + 0.06) * (1 - ramp(t, tr - 0.012, tr))
            g_hi, g_top, g_lo = (10 ** (-v * on / 20) for v in (20, 16, 12))
            return closing(lo * g_lo + (hi_ - top) * g_hi + top * g_hi * g_top, tr, (4.0, 3.0, 1.4, 0.8))
    x = hp(x, 18, 4) * (1 - ramp(t, d - 1.5, d - 0.1))
    x = fade(x, 0.0, 0.1)
    y = level("blast", x, h)
    g = rms_at(y, h + 0.3, h + 1.0) / rms_at(x, h + 0.3, h + 1.0)
    return y, shape, hp(extra, 18, 4) * g


CRUSH = (3.0, 1.6)   # (how hard the blast's lows and body are driven into the clip, and for how long after the hit, s)


def crush(y, at):
    """The blast's lows and body (under 1.5 kHz) driven into a soft clip for its first CRUSH[1] s, four times
    oversampled, the clip's products kept under 4.2 kHz: its peaks flattened into a dense block (a crest of a few dB, as
    a blast overloading everything), the top and the tail as they were."""
    t = T(len(y))
    lo = zlp(y, 1500, 4)
    pk = np.abs(lo[N(at):N(at + CRUSH[1])]).max() + 1e-12
    u = signal.resample_poly(lo / pk, 4, 1)
    c = signal.resample_poly(np.tanh(CRUSH[0] * u) / np.tanh(CRUSH[0]), 1, 4)[:len(y)] * pk
    c = lo + zlp(c - lo, 4200, 8)
    w = ramp(t, at - 0.002, at) * (1 - ramp(t, at + 0.6 * CRUSH[1], at + CRUSH[1]))
    return y - lo + lo * (1 - w) + c * w


def blast_of(k, clean=None):
    """Take k's blast as it ships, {tier: file}: its body blown out at AMOUNT and crushed (`crush`) and put in its
    tiers, then shaped (so its dips and its roll keep their depth at every distance, not filled by the tier's tail),
    what lies over it laid on in the same tier, at the body's loudness, its peaks under -2 dBFS. `clean` gets it near
    without the blow-out and the crush (for the measurements)."""
    x, shape, extra = blast_take(k)
    y = blown({"blast": (x, [(BLAST_HIT, "blast", 0)], -2.0)}, AMOUNT)["blast"]
    y = crush(y, BLAST_HIT)
    if clean is not None:
        clean[f"t{k}_blast"] = limit(shape(x) + extra, -2.0)
    tb, te = tiers(y, *TIER_SEED["blast"]), tiers(extra, *TIER_SEED["blast"])
    return {tr: set_lufs(shape(tb[tr]) + fit(te[tr], len(tb[tr])), lufs_m(tb[tr]), ceil=-2.0) for tr in tb}


def sunder_take(k):
    """Take k's land tearing (its file from BLAST; the tear at TEAR, 27.5). 1: `sunder` (a defined break under the
    blast's roll, the halves going their ways). 2: the tear as the second release, out of the stunned moment: the
    glacier's big break and a real large explosion on the tear, its lows from 100 Hz to 26, blown out (`blown`, kind
    `tear`), the halves as in 1 after it, its roll closing down and falling in pitch (62 to 46 Hz)."""
    if k == "1":
        return sunder()
    d = 7.5
    n = N(d)
    t = T(n)
    tr = TEAR
    brk = pk_norm(rec_front_at(n, tr, "fissure", 2, 13.45, 4.0), tr)
    big = pk_norm(body_rec(n, tr, 22.1), tr)
    kn = knock_rec(n, tr, KNOCK_REC["erupt"]["parts"], 700, 0.03, 0.06)
    tsub = thump(n, tr, 100, 26, 0.08, 0.003, ((0.4, 0.5), (0.6, 2.4)), k=1.9)
    hit = brk + 0.8 * big + 0.8 * kn / rms_at(kn, tr, tr + 0.1) * rms_at(big, tr, tr + 0.1) + 1.2 * pk_norm(tsub, tr)
    hit = closing(gate(hit, tr - 0.002), tr, (4.0, 3.0, 1.5, 0.9))
    f2 = rec_front(n, tr - 0.1, "fire", 2, 30.6, 4.0, 1.0, pre=0.2, k=2.2)
    bed = lp(rec_bed("fire", 1, 6.0, 19.9, n, 1.0, 1.8), 2200, 4)
    fire_env = ramp(t, tr, tr + 0.5) * (0.7 + 0.3 * np.exp(-((t - tr - 0.6) / 1.2) ** 2)) * (1 - ramp(t, 3.8, 6.2))
    xf = (0.8 * lp(f2, 3500, 2) + 0.7 * bed) * fire_env
    xa = rec_front(n, tr + 0.5, "impact", 2, 3.31, 3.2, -3.0) * ramp(t, tr + 0.3, tr + 0.8) * (1 - ramp(t, 3.0, 5.5))
    rg_ = ring(n, tr + 0.1, 62, 46, 2.5, 5.0, 153)
    x = hit / rms_at(hit, tr, tr + 0.5) + 0.45 * xf / rms_at(xf, tr, tr + 1.0) + 0.3 * xa / rms_at(xa, tr + 0.5, tr + 1.5) + 0.3 * pk_norm(rg_, tr + 0.3)
    x = hp(x, 22, 4) * gate(np.ones(n), tr - 0.002)
    x = fade(x, 0.0, 1.0)
    return set_lufs(x, LUFS["tear"], ceil=-2.0, sat=SAT["sunder"])


# (heaven's win: the chord the choir resolved to (F-A-C), each section's notes (Hz), and how loud each section is)
WIN_NOTES = {"bass": (87.31, 130.81), "tenor": (174.61, 220.0), "alto": (261.63, 349.23), "soprano": (440.0, 523.25)}
WIN_SEC = {"bass": 1.0, "tenor": 0.85, "alto": 0.7, "soprano": 0.5}


def win(k):
    """Heaven's choir arriving on the win (from WIN0), on the chord the choir resolved to, as big as it gets: 24 singers
    (as `choir`'s, each its own detuning and vibrato), the recorded choirs on F and C, a low F under them (the organ's
    weight, felt more than heard), in a large space. 1: rising with the islands from 28.2 to its height at 29.4, held to
    30.5, then down into the choir's calm chord and gone by 36. 2: heard alone in the stunned moment (in on 27.05 at
    half its height), let under the tear, then rising to its height at 28.6, held to 30.5, the same way down."""
    d = 36.5 - WIN0
    n = N(d)
    ts = T(n) + WIN0
    rg = rng(1500 + int(k))
    out = np.zeros(n)
    for sec, notes in WIN_NOTES.items():
        part = np.zeros(n)
        for f_ in notes:
            for j in range(3):
                det = 2 ** (rg.uniform(-9, 9) / 1200)
                f0 = f_ * det * (1 + 0.0015 * wander(n, 0.3, int(rg.integers(1e6))))
                vib = rg.uniform(0.003, 0.0055) * ramp(ts, WIN0 + rg.uniform(0.3, 1.2), WIN0 + 2.5)
                f0 = f0 * (1 + vib * np.sin(2 * np.pi * np.cumsum(np.full(n, rg.uniform(4.7, 5.8))) / SR + rg.uniform(0, 6.28)))
                src, _ = glottal(f0, int(rg.integers(1e6)), tp=0.5, tn=0.22, jit=0.004, shim=0.05)
                br = hp(rng(int(rg.integers(1e6))).standard_normal(n), 300, 2)
                v = formants(src + 0.12 * br, CHOIR_AH[sec], rg.uniform(0.96, 1.04))
                part += unit(v) * (0.8 + 0.2 * wander(n, 0.4, int(rg.integers(1e6))))
        out += part * WIN_SEC[sec]
    out = unit(out)
    for (row, i), (a_, b_), tune, g in CHOIR_REC:
        x = cut(rec(row, i), a_, b_)
        if tune != 1.0:
            from fractions import Fraction
            fr = Fraction(1 / tune).limit_denominator(400)
            x = signal.resample_poly(x, fr.numerator, fr.denominator)
        lvl = np.sqrt(movavg(x * x, N(0.6)) + 1e-12)
        x = x / (lvl / np.median(lvl)) ** 0.8
        out += g * unit(loop(x, n, 1.2))
    out = lp(out, 5000, 2)
    ped = drive(np.sin(phase(np.full(n, 43.65))) + 0.5 * np.sin(phase(np.full(n, 87.31))), 1.3)
    out = out + 0.35 * unit(ped) * np.sqrt(np.mean(out * out))
    out = hall(out, 4.5, 3000, 0.9, 1510)
    if k == "1":
        db = -30 + 30 * ramp(ts, 28.2, 29.4)
    else:
        db = np.where(ts < TEAR + BLAST, -30 + 24 * ramp(ts, BLAST + 1.05, BLAST + 1.15),
                      -6 - 10 * ramp(ts, BLAST + TEAR - 0.05, BLAST + TEAR) * (1 - ramp(ts, BLAST + TEAR + 0.3, BLAST + TEAR + 0.8)) + 6 * ramp(ts, 27.9, 28.6))
        db = db - 10 * ramp(ts, BLAST + TEAR - 0.06, BLAST + TEAR - 0.01) * (ts < BLAST + TEAR + 0.3)
    db = db - 9 * ramp(ts, 30.5, 32.5)
    env = 10 ** (db / 20) * (1 - ramp(ts, 33.0, 36.0)) * ramp(ts, WIN0, WIN0 + 0.02)
    x = hp(out, 40, 2) * env
    return fade(set_lufs(x, LUFS["win"]), 0.0, 0.3)


def after():
    """The land settling after the blast (AFTER + the burst's distance): the low roll dying away, the Nether half
    burning (the massive fire, its top rolled off), the rift shutting SHUT in (a pressure swell into a deep closing
    thump, weight, no ring)."""
    d = 14.0
    n = N(d)
    t = T(n)
    roll = roar(n, 0.0, 30, 160, 0.2, ((1.0, 4.0),), 111 + SEED, tilt=-3, move=0.3)
    burn = lp(rec_bed("fire", 1, 2.0, 19.9, n, 1.0, 1.8), 1800, 4)
    burn = burn * ramp(t, 0, 1.5) * 10 ** (-10 * np.clip(t / 11.0, 0, 1) / 20) * (1 - ramp(t, 11.0, 13.9))
    sw = ramp(t, SHUT - 1.6, SHUT) ** 2 * (1 - ramp(t, SHUT, SHUT + 0.15))
    swell = roar(n, 0.0, 60, 400, 0.01, ((1.0, 1e9),), 113, tilt=-3) * sw
    thump_ = thump(n, SHUT, 60, 24, 0.1, 0.006, ((0.5, 0.3), (0.5, 1.4)))
    x = 0.8 * unit(roll) + 0.45 * unit(burn) + 0.5 * swell + 1.4 * thump_ / (np.abs(thump_).max() + 1e-12)
    x = hp(x, 18, 4)
    return fade(set_lufs(x, LUFS["after"]), 0.3, 2.0)


# ===========================================================================================  the explosions: two takes
# Every explosion that ships (the cracks giving and the eruption, the hit in the air, the six surges, the blast and the
# land's tear) comes in two takes (TAKES; SHIP's ships), each file placed so its hit lands on the picture's
# frame (the hit's place in its file: IMPACT_AT, ERUPT - ERUPT0, SURGE_HIT, BLAST_AT, TEAR):
#   2  this laser's own (`own_*`): each kind built to one explosion of a reference as measured (`CB.OWN`,
#      `CB.calibrated_own`), sized and pitched to the picture (OWN_EVENTS, `own_surge`), at its loudest 400 ms (OWN_DB);
#   1  the Payload's alternative builders as the Sky Breaks' slam plays them (`slam_*`: `blast_alt` with `ground_alt`,
#      the blast with the Payload's `rush`, the tear with its `tail`), at fixed settings (SLAM: their seeds, sizes
#      and levels).
SURGE_HIT = {"1": 0.25, "2": 0.45}   # (where each surge's hit is in its file, which starts that long before its push
                                     # peaks; cv_sounds' CV_SURGE_HIT)
SURGE_AT = SURGE_HIT["1"]
BLAST_AT = 0.25                    # (where the blast's hit is in its file)
EX_PEAK = 10 ** (-1.4 / 20)        # (the finish's peak ceiling)


def place(x, at, n):
    """x laid into n samples with its first sample at `at` s (what falls before 0 cut off)."""
    out = np.zeros(n)
    k = N(at)
    if k < 0:
        x, k = x[-k:], 0
    m = min(len(x), n - k)
    if m > 0:
        out[k:k + m] = x[:m]
    return out


def low_peak(x, a, b, lo=25.0, hi=110.0):
    """Where x's lo-hi Hz is loudest (10 ms) between a and b s."""
    y = zhp(zlp(x, hi, 4), lo, 2)
    e = movavg(y * y, N(0.01))
    return (N(a) + int(np.argmax(e[N(a):N(b)]))) / SR


def mono(L, R):
    return (L + R) / 2


LEAD_UNDER = {"erupt": 10.7, "impact": 11.7}   # (how far the lead-in sits under the hit, dB)


def lead_under(lead, hit, at, win, under):
    """A lead-in set `under` dB under the hit's loudest 400 ms (its level over `win`), and eased down where the two
    would add up past the finish's ceiling (`CB.duck_under`, as the Payload eases its rush and tail under its blast)."""
    lead = lead * np.sqrt(np.max(movavg(hit * hit, N(0.4)))) * 10 ** (-under / 20) / rms_at(lead, *win)
    return CB.duck_under(lead, lead, [(hit, hit)], 0.0, ceiling=EX_PEAK)[0]


def erupt_lead(n):
    """What leads into the eruption, from ERUPT0: the ground straining (a groan rising), the fire roaring up the
    cracks from BREAK louder and louder, the sub rising under it, the held breath (drawn 11 dB under for its last
    tenth of a second)."""
    t = T(n)
    b, e = BREAK - ERUPT0, ERUPT - ERUPT0
    groan = roar(n, 0.0, 30, 180, 1.0, ((1.0, 1e9),), 601, tilt=-4, move=0.35)
    groan *= (0.15 + 0.85 * ramp(t, 0.0, e) ** 1.5) * (1 - ramp(t, e + 0.3, e + 2.5))
    fl = lp(rec_bed("fire", 2, 4.4, 14.4, n, 1.0, 2.2), 2500, 4)
    build = ramp(t, b + 0.1, e - 0.02) ** 2
    fl_env = 10 ** ((-18 + 18 * build) / 20) * (1 - ramp(t, e + 0.6, e + 4.0)) * ramp(t, b, b + 0.1)
    fl_env = fl_env * (1 - 0.72 * ramp(t, e - 0.14, e - 0.05) * (t < e))
    rise = np.sin(phase(24 + 10 * ramp(t, b, e))) * ramp(t, b + 0.2, e) ** 2 * (1 - ramp(t, e, e + 0.05))
    return 0.35 * unit(groan) + 0.5 * fl * fl_env + 0.25 * unit(rise)


def impact_lead(n):
    """What leads into the hit in the air, from CROUCH: the held breath (the air pulled in and down, a sub swelling),
    the two rushing at each other (the Nether's fire roaring up, the Aether's air coming down, 30 dB into the hit),
    drawn under for 70 ms before it and cut on it."""
    t = T(n)
    h = IMPACT_AT
    u0 = np.clip(t / (FIRE - CROUCH), 0, 1)
    pull = shaped_noise(n, lambda T_, ff: bell(ff, 420 * (0.6 ** np.clip(T_ / 0.45, 0, 1)), 1.0), 401)
    back = 0.4 * unit(pull) * (0.35 + 0.65 * u0 ** 1.5) * (1 - ramp(t, 0.45, 0.7))
    back = back + 0.5 * np.sin(phase(22 + 8 * u0)) * (0.2 + 0.8 * u0 ** 2) * (1 - ramp(t, 0.6, 0.9))
    u = np.clip((t - (FIRE - CROUCH)) / (MEET - FIRE), 0, 1)
    went = (t >= FIRE - CROUCH).astype(float)
    lev = 10 ** ((-30 * (1 - u) ** 1.3) / 20) * went
    lev = lev * (1 - 0.75 * ramp(t, h - 0.085, h - 0.06))
    lev = lev * (1 - ramp(t, h + 0.004, h + 0.03))
    up = lp(rec_bed("fire", 2, 4.6, 8.0, n, 1.0, 2.2), 2500, 4)
    down = shaped_noise(n, lambda T_, ff: bell(ff, 900, 1.1) * np.exp(-np.maximum(ff - 3500, 0) / 1200), 403)
    rush_ = (unit(up) + 0.7 * unit(down)) * lev + 0.6 * np.sin(phase(30 + 20 * u)) * lev
    return rush_ / rms_at(rush_, h - 0.25, h - 0.1) + back * 0.25 * 10 ** (9 / 20)


def stunned(y, st, tr):
    """y ducked for the stunned moment from `st` to the tear at `tr`: over 150 Hz down 20 dB within 60 ms, over 2 kHz
    16 more, the lows down 12; back whole on the tear."""
    t = T(len(y))
    lo = zlp(y, 150, 4)
    hi_ = y - lo
    top = zhp(hi_, 2000, 4)
    on = ramp(t, st, st + 0.06) * (1 - ramp(t, tr - 0.012, tr))
    g_hi, g_top, g_lo = (10 ** (-v * on / 20) for v in (20, 16, 12))
    return lo * g_lo + (hi_ - top) * g_hi + top * g_hi * g_top


def stun_parts(x, h):
    """The blast x (its hit `h` s in) stunned from 1.05 s after the hit to the tear (`stunned`: the roar ducked, not
    ended), a low ring left in it (78 -> 70 Hz), sucked back in over the last moment before the tear (TEAR after it)."""
    n = len(x)
    t = T(n)
    st, tr = h + 1.05, h + TEAR
    x = stunned(x, st, tr)
    lw = rms_at(x, st - 0.3, st - 0.05)
    rg_ = 0.12 * pk_norm(ring(n, st, 78, 70, 1.5, 4.0, 152, parts=7), st + 0.05) * (1 - 0.6 * ramp(t, tr - 0.012, tr))
    suck = roar(n, h + 1.25, 80, 700, 0.01, ((1.0, 1e9),), 143, tilt=-2.0)
    suck = suck * (np.exp((np.minimum(t, tr) - tr) / 0.09) * (t >= h + 1.25)) * (1 - ramp(t, tr - 0.01, tr + 0.002))
    return x + hp(rg_ + 0.25 * suck / (rms_at(suck, tr - 0.1, tr) + 1e-12), 18, 4) * lw


# ---------------------------------------------------------------------------------------  take 2: this laser's own
# Each event's kind (CB.OWN: which measured explosion it is built to), how its time after the first half second is
# scaled (`k`: under 1 shorter; the blast's wall held half as long as its reference's, so what comes back after the
# stunned moment is the tear and the choir over it, not the wall), how it falls away past its own measured rows (dB a second at 31.5 Hz and at 16 kHz),
# its length (s) and what is added on top (`boil` for the Nether's, `ring` for the Aether's: OWN_ADD); the hit's place
# after its onset (OWN_HIT: its heaviest blow, or for the blast the wall's lows up and its first blow 30 ms after, for
# the tear its first blow); its file's loudest 400 ms (OWN_DB, dBFS, before CV_BOOST) and its seed.
OWN_EVENTS = {"erupt": ("erupt", 0.6, 0.0, (9.0, 18.0), 8.0), "crack": ("erupt", 0.3, 4.0, (30.0, 45.0), 2.4),
              "impact": ("impact", 1.0, 0.0, (20.0, 36.0), 4.0), "blast": ("blast", 0.5, 0.0, (12.0, 24.0), 9.0),
              "sunder": ("tear", 1.25, 0.0, (3.0, 9.0), 18.0)}
OWN_HIT = {"nether": 0.36, "aether": 0.095, "impact": 0.07, "erupt": 0.05, "blast": 0.10, "tear": 0.06}
OWN_DB = {"erupt": -9.0, "crack": -17.5, "impact": -6.9, "blast": -6.6, "sunder": -8.0}
OWN_SURGE_DB = (-8.9, 1.0)         # (a surge's loudest 400 ms: this plus the second times its size, 0-1)
OWN_SEED = {"erupt": 7301, "crack": 7311, "impact": 7321, "blast": 7331, "sunder": 7341, "surge": 7401}
# The surges: the Nether's (1, 3, 5) built to its own measured explosion, the Aether's (2, 4, 6) to another; each its
# own pitch (semitones on its reference's), the bigger (SURGE_AMP) lower and longer, yet 20 dB down before the next
# one lands.
OWN_SURGE_SEMI = (1.0, -1.0, 3.5, -4.0, -2.0, 2.5)
BOIL_DB = 3.0
RING_DB, RING_LIFE = -9.0, 0.7
AETHER_F0 = 62.6                   # (the Aether's reference's blows' pitch, Hz: its ring's partials are on it)


def own_surge(i):
    """Surge i's (kind, k, f, fall, length, extra, dB): `nether` for the Nether's pushes, `aether` for the Aether's;
    the bigger the longer (k), the slower it falls and the louder."""
    up = SURGE_SIGN[i] > 0
    sz = (SURGE_AMP[i] - min(SURGE_AMP)) / (max(SURGE_AMP) - min(SURGE_AMP))
    f = 2 ** (OWN_SURGE_SEMI[i] / 12)
    if up:
        k, fall, extra = 0.35 + 0.15 * sz, (30.0 - 8.0 * sz, 45.0 - 10.0 * sz), CB.boil(BOIL_DB)
    else:
        k, fall, extra = 0.5 + 0.15 * sz, (30.0 - 8.0 * sz, 42.0 - 10.0 * sz), CB.ring(AETHER_F0 * f, RING_DB, RING_LIFE)
    return ("nether" if up else "aether"), k, f, fall, 2.6 + 0.8 * sz, extra, OWN_SURGE_DB[0] + OWN_SURGE_DB[1] * sz


def own_hit(kind, seed, k, f, fall, d, extra, db, at, n):
    """One of this laser's own explosions (`CB.calibrated_own`) finished to `db` (its loudest 400 ms, `CB.finish`),
    mono in n samples with its hit (OWN_HIT) on `at` s."""
    x = CB.calibrated_own(kind, seed, d, k, f, fall, extra=extra)[0]
    x = CB.finish(x, x, db, EX_PEAK, 0.3)[0]
    return place(x, at - OWN_HIT[kind] - 0.02, n)


def own_event(ev, at, n, extra=None):
    kind, k, semi, fall, d = OWN_EVENTS[ev]
    return own_hit(kind, OWN_SEED[ev], k, 2 ** (semi / 12), fall, d, extra, OWN_DB[ev], at, n)


def own_surge_file(i):
    """Surge i, take 2: its own explosion (`own_surge`), the hit SURGE_HIT in on the peak of its push, gone before
    the blast's held breath."""
    kind, k, f, fall, d, extra, db = own_surge(i)
    h = SURGE_HIT["2"]
    start = SURGES[i] + SURGE_ATK[i] - h
    n = N(h + d)
    x = own_hit(kind, OWN_SEED["surge"] + 10 * i, k, f, fall, d, extra, db, h, n)
    if kind == "nether":
        x = dark_top(x, HIT_TEX[f"surge_{i + 1}"], (h - OWN_HIT["nether"],), h, dirt=DIRT_DB)
    end = BLAST - BREATH["2"] - 0.06 - start
    return fade(x * (1 - ramp(T(n), end - 0.8, end)), 0.0, 0.3)


def own_erupt():
    """From ERUPT0, take 2: the lead-in (`erupt_lead`), the cracks giving on BREAK (a small one, higher), the fire
    erupting on ERUPT (its own explosion, the fire boiling in it)."""
    e = ERUPT - ERUPT0
    n = N(e + OWN_EVENTS["erupt"][4])
    x = own_event("erupt", e, n, CB.boil(BOIL_DB)) + own_event("crack", BREAK - ERUPT0, n)
    x = dark_top(x, HIT_TEX["erupt"], (BREAK - ERUPT0 - OWN_HIT["erupt"], e - OWN_HIT["erupt"]), e, dirt=DIRT_DB)
    return fade(x + lead_under(hp(erupt_lead(n), 18, 4), x, e, (e - 0.4, e - 0.15), LEAD_UNDER["erupt"]), 0.3, 1.0)


def own_impact():
    """From CROUCH, take 2: the lead-in (`impact_lead`) and the hit on MEET (IMPACT_AT in)."""
    h = IMPACT_AT
    n = N(h + OWN_EVENTS["impact"][4])
    x = dark_top(own_event("impact", h, n), HIT_TEX["impact"], (h - OWN_HIT["impact"],), h, TEX_DB_OF["impact"],
                 SPLIT_OF["impact"])
    return fade(x + lead_under(hp(impact_lead(n), 18, 4), x, h, (h - 0.25, h - 0.1), LEAD_UNDER["impact"]), 0.05, 1.0)


def wall_blast_file():
    """The blast with its own explosion held as a wall, stunned to the tear: the tear is limited with this one
    (`build`)."""
    h = BLAST_AT
    n = N(h + OWN_EVENTS["blast"][4])
    return fade(stun_parts(own_event("blast", h, n), h), 0.0, 1.5)


def own_blast_file():
    """The blast (BLAST_AT in, on 26.0), take 2: its own explosion as a peak and a roar under it (`blast_body`), over
    1 kHz recorded (`dark_top`), its peak at BLAST_PEAK, stunned to the tear (`stun_parts`)."""
    h = BLAST_AT
    n = N(h + OWN_EVENTS["blast"][4])
    x = place(blast_body(), h - OWN_HIT["blast"] - 0.02, n)
    x = x * 10 ** (-12.0 / 20) / np.abs(x).max()
    x = stun_parts(dark_top(x, HIT_TEX["blast"], (h - OWN_HIT["blast"],), h, TEX_DB_OF["blast"], rise=BLAST_RISE), h)
    x = x * 10 ** ((BLAST_PEAK + BLAST_TAKE - peak_db(x)) / 20)
    return fade(limit(x, BLAST_PEAK), 0.0, 1.5)


# The blast's body: its own explosion (OWN_EVENTS "blast", calibrated to its table) built without the two
# soft clips. Its roar (the shaped noise, before the blows) at the table's level through the hit's first BLAST_HOLD s,
# then down BLAST_DROP dB over BLAST_FALL s; from 0.25 s after its onset heaving: its own 25-120 Hz level (150 ms,
# less its 0.6 s mean) times BLAST_HEAVE, and sinking by a slow curve (BLAST_WAVE Hz, unit spread, less 1 and never
# over 0) times BLAST_WOB dB: it sinks and comes back, never over where it was set. Its noise
# under 100 Hz BLAST_RLO dB down: the weight is a boom, the first blow carried on as a sine falling BLAST_F Hz (its
# phase BLAST_BPH), BLAST_BOOM dB over the whole's level in the hit's first 150 ms, down BLAST_BDROP dB with the roar,
# heaving on the same curve (BLAST_BWOB dB), falling BLAST_TAIL dB a second from BLAST_TAIL_AT s after the hit (a sine
# carrying the weight peaks about 3 dB over its level, noise 10 or more: the file's peak stays near its loudness
# without a limiter). The first two blows BLAST_EARLY dB on their measured levels, the rest BLAST_LATER. Then
# (`own_blast_file`) over 1 kHz recorded (HIT_TEX "blast", rising over BLAST_RISE) and its peak at BLAST_PEAK dBFS,
# the last BLAST_TAKE dB of it held off by `limit`.
BLAST_HOLD, BLAST_FALL, BLAST_DROP = 0.35, 0.25, 6.0
BLAST_HEAVE, BLAST_WOB, BLAST_WAVE = 0.6, 2.5, (0.6, 3.0)
BLAST_RLO = 12.0
BLAST_F = (79.0, 45.0)
BLAST_BOOM, BLAST_BDROP, BLAST_BWOB, BLAST_BPH = 15.0, 6.0, 2.5, 5.6
BLAST_TAIL, BLAST_TAIL_AT = 10.0, 0.8
BLAST_EARLY, BLAST_LATER = -12.0, -6.0
BLAST_PEAK, BLAST_TAKE = -1.97, 1.0
BLAST_RISE = 0.35                  # (its recorded top rising this long from the onset: dark on the hit, opening after)
BLAST_SEED = 7336


def blast_body():
    """The blast's body (see BLAST_HOLD), mono, its onset 0.02 s in and its hit OWN_HIT["blast"] after it, at about
    its table's level."""
    kind, k, semi, fall, d = OWN_EVENTS["blast"]
    seed = OWN_SEED["blast"]
    hit = OWN_HIT["blast"]
    trim, btrim, mid = CB.calibrated_own(kind, seed, d, k, 2 ** (semi / 12), fall)[3]
    n = N(d)
    r = np.random.default_rng(BLAST_SEED)
    m = n // 441 + 4
    wv = signal.sosfiltfilt(signal.butter(2, [BLAST_WAVE[0] / 50, BLAST_WAVE[1] / 50], "band", output="sos"),
                            r.standard_normal(m))
    wv = np.minimum(np.interp(np.arange(n) / 441, np.arange(m), wv / np.std(wv)), 1.0) - 1.0
    heave = {}

    def roar(x, u):
        down = -BLAST_DROP * smooth(np.clip((u - hit - BLAST_HOLD) / BLAST_FALL, 0, 1))
        lo = band_of(x, 25, 120)
        le = 20 * np.log10(np.sqrt(movavg(lo * lo, N(0.15))) + 1e-12)
        heave["w"] = smooth(np.clip((u - 0.25) / 0.15, 0, 1)) * wv
        x = x * 10 ** ((down + heave["w"] * BLAST_WOB + smooth(np.clip((u - 0.25) / 0.15, 0, 1)) * BLAST_HEAVE
                        * (le - movavg(le, N(0.6)))) / 20)
        return x - zlp(x, 100, 4) * (1 - 10 ** (-BLAST_RLO / 20))

    def boom(x, u, on, rg):
        uu = u - hit
        f = BLAST_F[1] + (BLAST_F[0] - BLAST_F[1]) * np.exp(-np.maximum(uu, 0) / 0.25)
        y = np.sin(2 * np.pi * np.cumsum(f * (uu > -0.01)) / SR + BLAST_BPH)
        lv = -BLAST_BDROP * smooth(np.clip((uu - BLAST_HOLD) / BLAST_FALL, 0, 1)) + BLAST_BWOB * heave["w"]
        lv = lv - BLAST_TAIL * np.maximum(uu - BLAST_TAIL_AT, 0)
        y = y * 10 ** (lv / 20) * np.where(uu < 0, np.exp(-0.5 * (uu / 0.008) ** 2), 1.0) * (uu > -0.03)
        a, b = N(0.02 + hit), N(0.02 + hit + 0.15)
        return x + y * np.sqrt(np.mean(x[a:b] ** 2) / np.mean(y[a:b] ** 2)) * 10 ** (BLAST_BOOM / 20)

    bt = np.array(btrim, dtype=float)
    bt[:2] += BLAST_EARLY
    bt[2:] += BLAST_LATER
    return CB.own_blast(kind, seed, d, k, 2 ** (semi / 12), fall, trim, 0.02, boom, bt, mid, roar=roar, clips=False)


def own_sunder():
    """The land's tear (its file from BLAST; the tear at TEAR, 27.5), take 2: its own explosion, the top closing first,
    its roll going on under the aftermath: (with its top recorded (`dark_top`); and without it (the blast is limited
    with that one, `limit_pair`))."""
    n = N(TEAR + OWN_EVENTS["sunder"][4])
    x = own_event("sunder", TEAR, n)
    return fade(dark_top(x, HIT_TEX["sunder"], (TEAR - OWN_HIT["tear"],), TEAR), 0.0, 2.0), fade(x, 0.0, 2.0)


# ---------------------------------------------------------------------------  take 2's hits: their top recorded
# The Nether's hits (its surges, the eruption and the cracks giving), the hit in the air and the land's tear keep
# what is built under TOP_SPLIT (1 kHz); over it the shaped noise is left out and recorded texture is laid in its place
# (HIT_TEX: fire and grinding stone for the Nether's, a sonic boom's roll and thunder for the hit, tearing rock and a
# landslide for the tear). The texture follows the hit's own body (its 300 Hz-1 kHz level over 40 ms), rises
# from nothing over TEX_IN after each explosion's onset, is rolled off at 12 dB an octave from TEX_TOP, and is set so that from
# 0.15 to 1.3 s after the main hit its 2-4 kHz sits TEX_DB under the whole.
TOP_SPLIT = 1000.0
TEX_LO, TEX_TOP = 1000.0, 2600.0
TEX_IN = 0.08
TEX_DB = -31.0
DIRT_DB = -6.0                  # (the Nether's: its fire and stone this far under its own 250 Hz-1 kHz)
TEX_DB_OF = {"impact": -34.0,   # (the hit in the air: its body is the brightest round 1 kHz: split lower, its top darker)
             "blast": -26.0}    # (the blast, the biggest: a little more of its top kept than the others')
SPLIT_OF = {"impact": 800.0}
# (per file: for each hit, the recordings laid from it: (row, number, from s, weight))
HIT_TEX = {
    "surge_1": ((("fire", 1, 2.0, 1.0), ("basalt", 3, 18.7, 0.8)),),
    "surge_3": ((("fire", 1, 7.4, 1.0), ("basalt", 3, 27.1, 0.8)),),
    "surge_5": ((("fire", 1, 12.9, 0.7), ("basalt", 3, 3.55, 1.0)),),
    "erupt": ((("basalt", 3, 23.05, 1.0), ("fire", 1, 15.5, 0.5)), (("fire", 1, 0.6, 1.0), ("basalt", 3, 18.7, 0.7))),
    "impact": ((("impact", 2, 2.3, 1.0), ("thunder", 2, 0.95, 0.5)),),
    "sunder": ((("basalt", 3, 13.75, 1.0), ("fissure", 1, 10.0, 0.4)),),
    "blast": ((("thunder", 1, 3.3, 1.0), ("thunder", 2, 1.6, 0.5)),),
}


def texture(n, at, parts, until=None, lo=TEX_LO, top=TEX_TOP, rise=TEX_IN):
    """HIT_TEX's recordings for one hit, n samples, from `at` s: each with only its sharpest pops held down (its own
    crackle and grain left in), over `lo`, rolled off from `top`, at unit
    RMS over its first 1.2 s times its weight; risen over `rise` s from `at`, gone by `until` (the next hit)."""
    t = T(n)
    y = np.zeros(n)
    for row, i, a, w in parts:
        r = rec(row, i)
        seg = soften(cut(r, a, min(a + (n - N(at)) / SR, len(r) / SR)), 6.0)
        seg = lp(hp(seg, lo, 2), top, 2)
        seg = fade(seg, 0.0, 0.3) / (np.sqrt(np.mean(seg[:N(1.2)] ** 2)) + 1e-12)
        y = lay(y, w * seg, 0, at)
    y = y * ramp(t, at, at + rise) ** 2
    if until is not None:
        y = y * (1 - ramp(t, until - 0.06, until))
    return y


def band_of(x, lo, hi):
    return signal.sosfiltfilt(signal.butter(4, [lo, hi], "band", fs=SR, output="sos"), x)


def dark_top(x, tex, ats, hit, db=TEX_DB, split=TOP_SPLIT, dirt=None, rise=TEX_IN):
    """x (one of take 2's hit files) under `split`, and over it recorded texture (`texture`, `tex` one entry an
    explosion, from its onset at `ats` s) following its body, set to `db` (2-4 kHz under the whole) over 0.15-1.3 s
    after the main hit (`hit` s); its loudest 400 ms as x's. `dirt` (dB): the same recordings' 250 Hz-1 kHz laid in
    too, that far under the hit's own there over the same stretch (the Nether's: real fire and stone in its
    low-mids). `rise`: how long the texture takes to rise from each onset (s)."""
    n = len(x)
    low = zlp(x, split, 8)
    body = np.sqrt(movavg(zhp(low, 300, 2) ** 2, N(0.04)))
    top = np.zeros(n)
    for j, (at, parts) in enumerate(zip(ats, tex)):
        top += texture(n, at, parts, ats[j + 1] if j + 1 < len(ats) else None, rise=rise)
    top = top * body
    a, b = N(hit + 0.15), N(hit + 1.3)
    if dirt is not None:
        mud = np.zeros(n)
        for j, (at, parts) in enumerate(zip(ats, tex)):
            mud += texture(n, at, parts, ats[j + 1] if j + 1 < len(ats) else None, 250.0, 1000.0)
        mud = zlp(mud * body, split, 8)
        have = np.sqrt(np.mean(band_of(low, 250, 1000)[a:b] ** 2))
        got_ = np.sqrt(np.mean(band_of(mud, 250, 1000)[a:b] ** 2)) + 1e-12
        low = low + mud * have / got_ * 10 ** (dirt / 20)
    g = 1.0
    for _ in range(4):
        y = low + g * top
        got = 10 * np.log10(np.mean(band_of(y, 2000, 4000)[a:b] ** 2) + 1e-14) - 10 * np.log10(np.mean(y[a:b] ** 2) + 1e-14)
        g *= 10 ** ((db - got) / 20)
    # (at the loudness it had: its loudest 400 ms kept, its peaks held under the files' ceiling)
    y = low + g * top
    k = N(0.4)
    want = np.max(movavg(x * x, k))
    u = 1.0
    for j in range(5):
        z = y * u
        if peak_db(z) > -1.3:
            z = limit(z, -1.3)
        if j < 4:
            u *= np.sqrt(want / np.max(movavg(z * z, k)))
    return z


# ------------------------------------------------------------------  take 1: the Payload's alternative builders, as made
# (`blast_alt` and `ground_alt` with this laser's sizes and pitches, the blast with the Payload's `rush`, the tear with
# its `tail`; every value fixed for them: SLAM is the key they are made under, and their seeds' offset)
SLAM = "2"
BLOW = {SLAM: 0.17}                # (the heavy blow in `blast_alt`'s output, s: its boom, 0.15 after its arrival)
PL_DB = {SLAM: P.ALT_LEVEL}        # (the Payload's own blast's loudest 400 ms: its ground, rush and tail are set
                                   # against it, so they are scaled by the same as the blast)
GROUND_WITH = (1.0 / (1.0 + 150.0 / 900.0)) * 0.25 ** 1.5   # (the Payload's ground where the air's blow lands on it:
                                                            # its plan's volume at 150 blocks with no gap)
EX_DB = {SLAM: {"erupt": -9.0, "impact": -8.9, "blast": -7.1, "sunder": -9.4, "crack": -17.5}}
EX_SURGE = {SLAM: (-9.2, 1.4)}
EX_SIZE = {"blast": {SLAM: (1.6, 18.0)}, "sunder": {SLAM: (1.3, 15.0)}, "impact": {SLAM: (0.75, 9.0)},
           "erupt": {SLAM: (0.75, 9.0)}}
EX_COLOUR = {"erupt": (0.92, -1.0, 1.4), "impact": (1.06, 0.5, 1.0), "blast": (1.0, 0.0, 1.0), "sunder": (0.95, -0.5, 1.2),
             "crack": (1.15, 0.0, 1.0)}
SURGE_TILT, SURGE_GRIT = 1.5, {SLAM: (1.6, 0.8)}   # (the Nether's grit, the Aether's)
EX_SEED = {"erupt": 7101, "crack": 7111, "impact": 7121, "blast": 7131, "sunder": 7141, "surge": 7201, "rush": 7401,
           "tail": 7411}


def ex_seed(kind, take, i=0):
    return EX_SEED[kind] + 20 * i + int(take)


def boom(take, seed, d, stretch, f=1.0, tilt=0.0, grit=1.0):
    """`blast_alt` at this size: (L, R), its arrival 0.02 s in, its blow BLOW in."""
    return CB.blast_alt(seed, d, stretch=stretch, f=f, tilt=tilt, crackle=grit)


def thud(take, seed, f=1.0):
    """`ground_alt` at the Payload's level: (L, R)."""
    return CB.ground_alt(seed, f)


def ex_hit(take, kind, at, n, i=0, size=None, colour=None, db=None, ground=False):
    """Event `kind`'s explosion by `blast_alt`, mono in n samples, its blow on `at` s: finished at its loudest
    400 ms (`CB.finish`), with its ground under it where `ground` (at the Payload's level against it, GROUND_WITH).
    (the sound, the builder's own (L, R) as finished, where its arrival is (s), its gain against the Payload's)."""
    stretch, d = size or EX_SIZE[kind][take]
    f, tilt, grit = colour or EX_COLOUR[kind]
    db = EX_DB[take][kind] if db is None else db
    L, R = CB.finish(*boom(take, ex_seed(kind, take, i), d, stretch, f, tilt, grit), db, EX_PEAK, 1.0)
    t0 = at - BLOW[take]
    x = place(mono(L, R), t0, n)
    g = 10 ** ((db - PL_DB[take]) / 20)
    if ground:
        gL, gR = thud(take, ex_seed(kind, take, 50 + i), f)
        x = x + place(mono(gL, gR), t0, n) * g * GROUND_WITH
    return x, (L, R), t0 + 0.02, g


def surge_size(take, i):
    """Surge i's (stretch, length, f, tilt, grit, dB): the bigger (SURGE_AMP) the longer and the louder, its pitch
    SURGE_PITCH, the Nether's (odd) darker and grittier, the Aether's (even) brighter."""
    up = SURGE_SIGN[i] > 0
    sz = (SURGE_AMP[i] - min(SURGE_AMP)) / (max(SURGE_AMP) - min(SURGE_AMP))
    st = 0.35 + 0.25 * sz
    d = 0.47 + 10.07 * st + 0.8
    g = SURGE_GRIT[take][0 if up else 1]
    return st, d, 2 ** (SURGE_PITCH[i] / 12), -SURGE_TILT if up else SURGE_TILT, g, EX_SURGE[take][0] + EX_SURGE[take][1] * sz


def slam_surge(take, i):
    """Surge i: `blast_alt` at its size and pitch (`surge_size`), the blow SURGE_AT in (on the peak of its push), gone
    before the blast's held breath."""
    st, d, f, tilt, grit, db = surge_size(take, i)
    start = SURGES[i] + SURGE_ATK[i] - SURGE_AT
    n = N(SURGE_AT + d)
    x, _, _, _ = ex_hit(take, "surge", SURGE_AT, n, i, (st, d), (f, tilt, grit), db)
    t = T(n)
    end = BLAST - BREATH["2"] - 0.06 - start
    return fade(x * (1 - ramp(t, end - 0.8, end)), 0.0, 0.6)


def slam_erupt(take):
    """From ERUPT0: the lead-in (`erupt_lead`), the cracks giving on BREAK (the builder's ground alone, small), the
    fire erupting on ERUPT (its ground and `blast_alt` at the eruption's size, darker and grittier)."""
    e = ERUPT - ERUPT0
    n = N(e + EX_SIZE["erupt"][take][1])
    x, _, _, _ = ex_hit(take, "erupt", e, n, ground=True)
    gL, gR = thud(take, ex_seed("crack", take), EX_COLOUR["crack"][0])
    cg = mono(gL, gR)
    b = BREAK - ERUPT0
    cr = place(cg, b - low_peak(cg, 0.0, 0.4), n)
    cr = cr * 10 ** (EX_DB[take]["crack"] / 20) / (np.sqrt(np.max(movavg(cr * cr, N(0.4)))) + 1e-12)
    return fade(x + cr + lead_under(hp(erupt_lead(n), 18, 4), x + cr, e, (e - 0.4, e - 0.15), LEAD_UNDER["erupt"]), 0.3, 1.0)


def slam_impact(take):
    """From CROUCH: the lead-in (`impact_lead`) and the hit on MEET (IMPACT_AT in): `blast_alt` at the impact's size;
    in the air, no ground."""
    h = IMPACT_AT
    n = N(h + EX_SIZE["impact"][take][1])
    x, _, _, _ = ex_hit(take, "impact", h, n)
    return fade(x + lead_under(hp(impact_lead(n), 18, 4), x, h, (h - 0.25, h - 0.1), LEAD_UNDER["impact"]), 0.05, 1.0)


def slam_blast(take):
    """The blast (BLAST_AT in, on 26.0): `blast_alt` at the blast's size with its ground and the Payload's rush (its
    front on the blow, eased under the blast as the Payload's is); stunned to the tear (`stun_parts`)."""
    h = BLAST_AT
    n = N(h + max(EX_SIZE["blast"][take][1], 9.0))
    x, (bL, bR), arrive, g = ex_hit(take, "blast", h, n, ground=True)
    r0 = arrive - CB.RUSH_FRONT
    rL, rR = CB.rush(ex_seed("rush", take), [(bL / g, bR / g)], CB.RUSH_FRONT - 0.02)
    x = x + place(mono(rL, rR), r0, n) * g
    return fade(stun_parts(x, h), 0.0, 1.5)


def slam_sunder(take):
    """The land's tear (its file from BLAST; the tear at TEAR, 27.5): `blast_alt` a little smaller than the blast, on
    its own seed, with its ground, and the Payload's tail after it (TAIL_AFTER after its arrival, eased under it)."""
    k = TEAR
    n = N(k + 0.05 + CB.TAIL_AFTER + 22.0)
    x, (bL, bR), arrive, g = ex_hit(take, "sunder", k, n, ground=True)
    tL, tR = CB.tail(ex_seed("tail", take), [(bL / g, bR / g)], -(CB.TAIL_AFTER + 0.02))
    x = x + place(mono(tL, tR), arrive + CB.TAIL_AFTER, n) * g
    return fade(x, 0.0, 1.5)


def cv_explosions(take):
    """Take `take`'s explosions: {base: file} (`erupt`, `impact`, `surge_I`, `blast`, `sunder`)."""
    if take == "2":
        su, su_then = own_sunder()
        out = {"erupt": own_erupt(), "impact": own_impact(), "blast": own_blast_file(), "sunder": su, "sunder_then": su_then,
               "blast_then": wall_blast_file()}
        for i in range(len(SURGES)):
            out[f"surge_{i + 1}"] = own_surge_file(i)
        return out
    out = {"erupt": slam_erupt(SLAM), "impact": slam_impact(SLAM), "blast": slam_blast(SLAM), "sunder": slam_sunder(SLAM)}
    for i in range(len(SURGES)):
        out[f"surge_{i + 1}"] = slam_surge(SLAM, i)
    return out


# ================================================================================================  hell and heaven
# Four layers over the strike, each its own event (LAYERS): hell's voice (`hell_voice`) and the furnace (`furnace`),
# heaven's choir (`choir`) and the rift's thunder (`thunder`). Each one's moments are on the picture's clock; each
# side's voice swells after its side's surges and is pressed by the other's (`answers`); all of them duck under every
# hit and with the held breaths (`duck`), so the explosions stay the loudest things and the breaths stay held.
HITS = (BREAK, ERUPT, MEET, *(s + a for s, a in zip(SURGES, SURGE_ATK)), BLAST)
BREATHS = (ERUPT, MEET, BLAST)


def duck(ts, under=11.0, breath=14.0):
    """A layer's gain on the strike clock `ts`: `breath` dB under over the held breaths (the last 0.14 s before the
    eruption, the hit and the blast) and `under` dB under each hit from its sample, back over half a second."""
    db = np.zeros(len(ts))
    for h in BREATHS:
        db -= breath * ramp(ts, h - 0.15, h - 0.09) * (ts < h + 0.02)
    for h in HITS:
        u = np.clip((ts - h) / 0.5, 0, 1)
        db -= under * np.where(ts >= h - 0.005, (1 - u) ** 2, 0) * (ts < h + 0.5)
    return 10 ** (db / 20)


def answers(ts, side, tau=0.45, lag=0.05):
    """How hard `side`'s surges (+1 the Nether's, -1 the Aether's) are pushing on the strike clock: for each, 0 until
    `lag` after its peak, a swell to its size at `tau` past that (by its reach against the biggest), then dying."""
    out = np.zeros(len(ts))
    for s, a, sg, amp in zip(SURGES, SURGE_ATK, SURGE_SIGN, SURGE_AMP):
        if sg == side:
            u = np.maximum(ts - (s + a + lag), 0) / tau
            out += (amp / max(SURGE_AMP)) * u * np.exp(1 - u)
    return out


def bump(ts, at, rise, tau):
    """0 before `at`, up to 1 over `rise` s (eased), then dying with `tau`."""
    tt = np.maximum(ts - at, 0)
    return np.where(ts >= at, smooth(np.clip(tt / rise, 0, 1)) * np.exp(-np.maximum(tt - rise, 0) / tau), 0.0)


def glottal(f0, seed, tp=0.42, tn=0.16, jit=0.012, shim=0.08):
    """A voice's source: a train of glottal pulses (a Rosenberg flow's derivative) at f0 (Hz, per sample), its periods
    and heights drifting a little from pulse to pulse (jitter, shimmer). Unit RMS."""
    n = len(f0)
    ph = np.cumsum(f0 * (1 + jit * wander(n, 30, seed))) / SR
    p = ph % 1.0
    g = np.where(p < tp, 0.5 * (1 - np.cos(np.pi * p / tp)), np.where(p < tp + tn, np.cos(0.5 * np.pi * (p - tp) / tn), 0.0))
    x = np.gradient(g) * (1 + shim * wander(n, 18, seed + 1))
    return unit(x), ph


def formants(x, fmts, scale=1.0):
    """x through a vowel's resonances in parallel: (centre Hz, bandwidth Hz, gain) each, the centres times `scale`."""
    out = np.zeros(len(x))
    for f, bw, g in fmts:
        fc = min(f * scale, SR * 0.45)
        b, a = signal.iirpeak(fc, fc / bw, fs=SR)
        out += g * signal.lfilter(b, a, x)
    return out


def hall(x, length, dark, wet, seed):
    """x in a large space: `wet` of a smooth tail `length` s long, darker as it goes (`reverb`), 30 ms after it."""
    ir = reverb(length, dark, seed)
    y = conv(x, ir)
    return x + wet * unit(y) * np.sqrt(np.mean(x * x))


# (hell's throat: a huge vocal tract's vowels, open (the bellow) and closed (a choked murmur): centre, width, gain)
HELL_OPEN = ((400, 130, 1.0), (760, 160, 0.7), (1450, 220, 0.3), (2300, 260, 0.1))
HELL_SHUT = ((250, 90, 1.0), (540, 120, 0.55), (1250, 180, 0.2), (2100, 260, 0.06))
HELL_THROATS = (0.74, 0.8, 0.86, 0.92, 0.97, 1.0, 1.05, 1.12, 1.2, 1.3)
# (the tiger's roars under the bellows: when (strike s), which stretch of the recording (s), how loud: the eruption's
# the longest, the hit's, the Nether's three surges by their size)
ROARS = ((ERUPT, (1.05, 3.6), 1.0), (MEET, (14.5, 16.6), 0.9), (SURGES[0] + SURGE_ATK[0], (7.4, 8.9), 0.7),
         (SURGES[2] + SURGE_ATK[2], (12.3, 13.1), 0.55), (SURGES[4] + SURGE_ATK[4], (9.95, 12.25), 0.8))


def hell_shape(ts, t0):
    """Hell's voice over the strike clock `ts` (its file from `t0`): its pitch (Hz), its level (the gain, ducked under
    the hits and cut on the blast's held breath), how open its throat is and how hard it growls (0-1)."""
    n = len(ts)
    nth, aeth = answers(ts, 1), answers(ts, -1)
    drv = ramp(ts, DRAW, BLAST - 0.2)
    bel = bump(ts, ERUPT + 0.12, 0.5, 1.7)
    roar_ = bump(ts, MEET + 0.06, 0.3, 1.0)
    race = ramp(ts, FIRE, MEET - 0.02) * (ts < MEET + 0.1)
    crouch = ease_out(ts, CROUCH, FIRE) * (1 - ramp(ts, FIRE, MEET))
    f = 50 + 4 * ramp(ts, t0, ERUPT) + 26 * bel + 14 * roar_ + 18 * nth - 5 * aeth + 8 * race - 5 * crouch
    f = f * (1 - 0.3 * drv) * (1 + 0.025 * wander(n, 0.4, 950))
    db = (-26 + 14 * ramp(ts, t0, ERUPT - 0.2) ** 0.8) * (ts < ERUPT) + (ts >= ERUPT) * -12.0
    # (between its moments it lies low: room for the dips between the surges)
    db = db - 4 * ramp(ts, ERUPT + 2.5, ERUPT + 4.0) - 3 * ramp(ts, MEET + 1.2, MEET + 2.0) * (1 - ramp(ts, DRAW, DRAW + 0.8))
    db = db + 9 * bel + 10 * roar_ + 9 * nth - 5 * aeth + 6 * race - 6 * crouch
    db = db + drv * (4 - 12 * ramp(ts, BLAST - 1.8, BLAST - 0.2))
    env = 10 ** (db / 20) * duck(ts) * (1 - ramp(ts, BLAST - 0.1, BLAST - 0.085))
    opn = np.clip(0.3 + 0.7 * np.maximum(bel, np.maximum(roar_, nth)) - 0.4 * drv, 0, 1)
    growl = np.clip(0.15 + 0.3 * np.maximum(bel, nth) + 0.55 * drv, 0, 0.8)
    return f, env, opn, growl


def hell_voice():
    """Hell's voice from HELL0 (LAYERS): a huge deep roar of many throats under the ground. Each throat a train of
    glottal pulses (34-110 Hz, each its own pitch and size of throat) through a giant vowel, with breath roaring
    through the same throat and the pulses' alternate beats uneven (a growl); stirring 3-6 s, a bellow with the
    eruption, a roar after the hit, answering each of the Nether's surges and pressed by the Aether's, forced down and
    choked 23-26 (the pitch sinking, the throat closing, the growl rising) and cut off on the held breath before the
    blast."""
    t0 = 3.0
    n = N(BLAST + 0.1 - t0)
    ts = T(n) + t0
    f, env, opn, growl = hell_shape(ts, t0)
    out = np.zeros(n)
    rg = rng(951)
    for j, rto in enumerate(HELL_THROATS):
        fj = f * rto * (1 + 0.02 * wander(n, 0.3, 960 + j))
        src, ph = glottal(fj, 970 + j, jit=0.02, shim=0.12)
        src = src * (1 - growl * 0.5 * (1 - np.cos(np.pi * ph)))
        br = hp(rng(980 + j).standard_normal(n), 80, 2)
        sc = 0.78 + 0.22 * rg.random()
        exc = src + 0.35 * br * (0.6 + 0.4 * opn)
        v = opn * formants(exc, HELL_OPEN, sc) + (1 - opn) * formants(exc, HELL_SHUT, sc)
        out += unit(v) * (0.75 + 0.25 * wander(n, 0.5, 990 + j))
    out = lp(drive(unit(out) * 0.6, 1.5), 2600, 4)
    # (a real throat in the bellows: a tiger's roars, a different phrase each, a fifth of an octave down at 0.8 speed,
    # their top under 2.2 kHz, laid under the throats from just after each bellow's start)
    roars = np.zeros(n)
    for at, (a_, b_), g in ROARS:
        ph = declick(cut(rec("roar", 2), a_, b_), 2.5)
        ph = lp(signal.resample_poly(ph, 5, 4), 2200, 4)
        ph = fade(ph, 0.12, 0.4) / (np.sqrt(np.mean(ph * ph)) + 1e-12)
        roars = lay(roars, ph, 0, at + 0.15 - t0, g)
    out = unit(out) + 0.45 * roars
    out = hp(out, 25, 4) * env
    return fade(set_lufs(out, LUFS["hell"]), 0.3, 0.015)


def hell_rec():
    """Hell's voice (`hell_voice`'s moments and level, `hell_shape`) made of recordings: a tiger's growl and lions'
    roars slowed far down (0.6 and 0.5 speed) over a lava vent's churn and a mud volcano's heave, slowed; in the
    bellows the tiger's roars (ROARS) at 0.62 speed; brighter as the throat opens (over 450 Hz with `opn`), rolled off
    gently."""
    t0 = 3.0
    n = N(BLAST + 0.1 - t0)
    ts = T(n) + t0
    _, env, opn, _ = hell_shape(ts, t0)
    growl = rec_layer("roar", 2, 7.0, 18.9, n, 0.6) + 0.8 * rec_layer("roar", 1, 0.5, 16.5, n, 0.5, 400)
    churn = rec_layer("vent", 1, 0.5, 39.0, n, 0.6) + 0.7 * rec_layer("vent", 2, 40.0, 120.0, n, 0.7, 300)
    roars = np.zeros(n)
    for at, (a_, b_), g in ROARS:
        ph = declick(cut(rec("roar", 2), a_, b_), 2.5)
        ph = signal.resample_poly(ph, 50, 31)
        ph = fade(ph, 0.12, 0.5) / (np.sqrt(np.mean(ph * ph)) + 1e-12)
        roars = lay(roars, ph, 0, at + 0.15 - t0, g)
    out = unit(growl) + 1.3 * unit(churn) + 0.8 * roars
    dark = lp(out, 450, 1)
    out = dark + (0.5 + 0.5 * opn) * (out - dark)
    out = hp(out, 25, 4) * env
    return fade(set_lufs(out, LUFS["hell"]), 0.3, 0.015)


def furnace():
    """The furnace under the Nether's column from ERUPT (LAYERS): a vent's jet (a rocket booster's roar, its top
    under 900 Hz) and the lava's heavy churn (four low bands, 35-560 Hz, heaving on slow uneven lumps); in after the
    eruption's hit, drawn down with the fountain, surging after each of the Nether's pushes and pressed by the
    Aether's, choked as heaven drives down, cut on the held breath before the blast."""
    t0 = ERUPT
    n = N(BLAST + 0.1 - t0)
    ts = T(n) + t0
    jet = lp(rec_bed("fire", 3, 0.2, 5.9, n, 1.0, 2.0), 900, 4)
    churn = np.zeros(n)
    for j, (lo, hi) in enumerate(((35, 70), (70, 140), (140, 280), (280, 560))):
        band = zlp(zhp(rng(1100 + j).standard_normal(n), lo, 2), hi, 4)
        lump = np.clip(0.55 + 0.45 * wander(n, 2.5 + 0.7 * j, 1110 + j), 0.05, 1.5) ** 2
        churn += unit(band) * lump / (1 + j * 0.6)
    x = unit(jet) + 0.8 * unit(churn)
    nth, aeth = answers(ts, 1, tau=0.5), answers(ts, -1, tau=0.5)
    db = -12 + 6 * ramp(ts, ERUPT + 0.15, ERUPT + 1.6) - 10 * ease_out(ts, CROUCH, FIRE) * (1 - ramp(ts, FIRE, MEET))
    db = db + 7 * nth - 4 * aeth - 7 * ramp(ts, DRAW, BLAST - 0.3) - 5 * ramp(ts, MEET + 1.2, MEET + 2.0) * (1 - ramp(ts, DRAW - 0.5, DRAW))
    env = 10 ** (db / 20) * ramp(ts, ERUPT + 0.05, ERUPT + 0.4) * duck(ts) * (1 - ramp(ts, BLAST - 0.1, BLAST - 0.085))
    x = hp(x, 22, 4) * env
    return fade(set_lufs(x, LUFS["furnace"]), 0.0, 0.015)


# (heaven's choir on one open vowel, a (as in father), each section's resonances: centre, width, gain)
CHOIR_AH = {"bass": ((600, 70, 1.0), (1040, 80, 0.45), (2250, 120, 0.12), (2450, 130, 0.1)),
            "tenor": ((650, 80, 1.0), (1080, 90, 0.5), (2650, 130, 0.12), (2900, 140, 0.1)),
            "alto": ((800, 90, 1.0), (1150, 100, 0.55), (2800, 140, 0.07), (3500, 160, 0.03)),
            "soprano": ((800, 90, 1.0), (1150, 100, 0.45), (2900, 150, 0.06), (3900, 170, 0.02))}
# (the chord, on F (the recorded choirs' notes: an "ah" on F3, an "ooh" on C3): each section's two notes (Hz), and the
# note each moves to at the win, CHORD_AT (the suspended fourth to the third); one change)
CHOIR_NOTES = {"bass": ((87.31, 87.31), (130.81, 130.81)), "tenor": ((174.61, 174.61), (233.08, 220.0)),
               "alto": ((261.63, 261.63), (349.23, 349.23)), "soprano": ((466.16, 440.0), (349.23, 349.23))}
# (the recorded choirs: a crowd singing "ah" on F3 (choir_1, its held stretch, tuned 176 -> 174.6 Hz) and voices on
# "ooh" on C3 (choir_3, its level evened out), as shares of the choir's sum)
CHOIR_REC = ((("choir", 1), (1.6, 7.0), 174.61 / 176.0, 0.75), (("choir", 3), (0.8, 8.4), 1.0, 0.4))
CHOIR_IN = {"bass": 5.3, "tenor": 7.5, "alto": 9.0, "soprano": 10.4}   # (when each section comes in)
CHORD_AT = BLAST + 0.7
CHOIR_END = 40.5


def choir():
    """Heaven's choir from CHOIR0 (LAYERS): a great choir on one open vowel, 24 singers, each a glottal source (its own
    detuning, a slow vibrato of its own, breath through its own resonances, a breath taken now and then) through its
    section's a, over two recorded choirs on the chord's notes (CHOIR_REC). One chord, suspended until the win (CHORD_AT) and resolving there: the one change. The sections come
    in as the rift parts (5-12 s); it lifts on the Aether's surges and is pressed by the Nether's; full voice as heaven
    drives down (its height the last second before the blast), held under the blast and the land's tearing (their peaks
    leave no room over them), a calm chord over the aftermath, gone as the rift shuts (40 s). In a large space
    (`hall`)."""
    t0 = 5.0
    n = N(CHOIR_END - t0)
    ts = T(n) + t0
    rg = rng(1200)
    out = np.zeros(n)
    move = ramp(ts, CHORD_AT, CHORD_AT + 0.35)
    for sec, notes in CHOIR_NOTES.items():
        part = np.zeros(n)
        for a_, b_ in notes:
            for j in range(3):
                det = 2 ** (rg.uniform(-9, 9) / 1200)
                f0 = (a_ * (1 - move) + b_ * move) * det * (1 + 0.0015 * wander(n, 0.3, int(rg.integers(1e6))))
                vib = rg.uniform(0.003, 0.0055) * ramp(ts, CHOIR_IN[sec] + rg.uniform(0.5, 2.0), CHOIR_IN[sec] + 3.5)
                f0 = f0 * (1 + vib * np.sin(2 * np.pi * np.cumsum(np.full(n, rg.uniform(4.7, 5.8))) / SR + rg.uniform(0, 6.28)))
                src, _ = glottal(f0, int(rg.integers(1e6)), tp=0.5, tn=0.22, jit=0.004, shim=0.05)
                br = hp(rng(int(rg.integers(1e6))).standard_normal(n), 300, 2)
                v = formants(src + 0.12 * br, CHOIR_AH[sec], rg.uniform(0.96, 1.04))
                # (a breath taken now and then: out for a third of a second, every 5-11 s, never all at once)
                g = np.ones(n)
                tb = CHOIR_IN[sec] + rg.uniform(3, 9)
                while tb < CHOIR_END - 2:
                    g *= 1 - 0.9 * ramp(ts, tb, tb + 0.12) * (1 - ramp(ts, tb + 0.3, tb + 0.6))
                    tb += rg.uniform(5, 11)
                part += unit(v) * g * (0.8 + 0.2 * wander(n, 0.4, int(rg.integers(1e6))))
        enter = ramp(ts, CHOIR_IN[sec], CHOIR_IN[sec] + 2.0)
        out += part * enter * {"bass": 1.0, "tenor": 0.85, "alto": 0.7, "soprano": 0.55}[sec]
    out = unit(out)
    for (row, i), (a_, b_), tune, g in CHOIR_REC:
        x = cut(rec(row, i), a_, b_)
        if tune != 1.0:
            from fractions import Fraction
            fr = Fraction(1 / tune).limit_denominator(400)
            x = signal.resample_poly(x, fr.numerator, fr.denominator)
        lvl = np.sqrt(movavg(x * x, N(0.6)) + 1e-12)
        x = x / (lvl / np.median(lvl)) ** 0.8             # (its swells evened out: a held chord)
        x = unit(loop(x, n, 1.2))
        out += g * x * ramp(ts, CHOIR_IN["bass"] if i == 3 else CHOIR_IN["tenor"], CHOIR_IN["tenor"] + 2.5)
    out = lp(out, 5000, 2)
    out = hall(out, 4.5, 3000, 0.9, 1210)
    nth, aeth = answers(ts, 1, tau=0.5), answers(ts, -1, tau=0.45, lag=0.1)
    db = -12 + 5 * ramp(ts, RIFT, CROUCH) - 1.5 * ramp(ts, MEET, MEET + 1.0) - 6 * ease_out(ts, CROUCH, FIRE) * (1 - ramp(ts, FIRE, MEET))
    db = db + 7 * aeth - 4 * nth + 7 * ramp(ts, DRAW, BLAST - 0.2) ** 1.3
    db = db - 4.5 * ramp(ts, MEET + 1.2, MEET + 2.0) * (1 - ramp(ts, DRAW - 0.5, DRAW + 0.5))
    # (the win: held under the blast and the land's tearing, then the calm chord from 28.5, gone as the rift shuts)
    db = np.where(ts >= BLAST, -10 + 3 * ramp(ts, BLAST + 2.5, BLAST + 3.5), db)
    env = 10 ** (db / 20) * duck(ts) * (1 - ramp(ts, BLAST - 0.1, BLAST - 0.085) * (1 - ramp(ts, BLAST + 0.05, BLAST + 0.35)))
    env = env * (1 - ramp(ts, CV_CLOSE, CHOIR_END - 0.5))
    x = hp(out, 60, 2) * env
    return fade(set_lufs(x, LUFS["choir"]), 0.5, 0.5)


CV_CLOSE = 31.0      # the rift starts shutting (the code's CV_CLOSE; gone by 40)
# (the thunder's rolls: when each starts (strike s), how long it rolls (s), how big; the rift opening, then after each
# of the Aether's surges, each gone before the next surge starts)
# (each roll's recorded stretch: a real thunder's roll from after its crack (the crack itself not in it): row, i, from (s))
THUNDER_REC = (("thunder", 1, 2.85), ("thunder", 2, 0.95), ("thunder", 1, 4.6), ("thunder", 2, 2.2))
THUNDER = ((RIFT + 0.45, 3.2, 0.5), *((SURGES[i] + SURGE_ATK[i] + 0.12, min(2.6, (SURGES[i + 1] if i + 1 < len(SURGES) else DRAW + 1.5) - SURGES[i] - SURGE_ATK[i] - 0.25),
                                       SURGE_AMP[i] / max(SURGE_AMP)) for i in range(len(SURGES)) if SURGE_SIGN[i] < 0))


def thunder():
    """The rift's thunder from THUNDER0 (LAYERS): the sky's answer as the rift opens and after each of the Aether's
    surges: a roll, not a crack: real thunder's rolls from after their cracks (THUNDER_REC), many big low claps
    (60-500 Hz bursts, 80-300 ms each) coming thick then thinning out on uneven swells under them, a sub rumble, far up
    in the sky (through 400 m of air, a dark tail)."""
    t0 = 4.8
    n = N(DRAW + 1.6 - t0)
    ts = T(n) + t0
    rg = rng(1300)
    out = np.zeros(n)
    for (row, ri, frm), (at, ln, size) in zip(THUNDER_REC, THUNDER):
        real = declick(cut(rec(row, ri), frm, frm + ln + 0.5), 2.0)
        real = fade(real, 0.15, 0.6)
        real = lay(np.zeros(n), real / (np.sqrt(np.mean(real[:N(1.0)] ** 2)) + 1e-12), 0, at - t0)
        roll = np.zeros(n)
        tc = at
        while tc < at + ln:
            u = (tc - at) / ln
            dens = (1 - np.exp(-u * 12)) * np.exp(-2.2 * u) * (0.6 + 0.4 * np.sin(7 * u + rg.uniform(0, 3)) ** 2)
            dur = rg.uniform(0.08, 0.3)
            m = N(dur)
            fc = np.exp(rg.uniform(np.log(60), np.log(500)))
            burst = zlp(zhp(rg.standard_normal(m), fc / 1.6, 2), fc * 1.6, 2) * np.hanning(m) ** 1.5
            i0 = N(tc - t0)
            k = min(m, n - i0)
            if k > 0:
                roll[i0:i0 + k] += burst[:k] / (np.abs(burst).max() + 1e-12) * dens * np.exp(rg.normal(0, 0.5))
            tc += rg.exponential(1 / 22.0)
        rum = roar(n, at - t0, 25, 110, 0.12, ((1.0, ln * 0.4),), int(rg.integers(1e6)), tilt=-3, move=0.3)
        env = ramp(ts, at, at + 0.1) * (1 - ramp(ts, at + ln * 0.7, at + ln))
        out += size * (unit(real) + 0.35 * unit(roll + 1e-9) + 0.4 * unit(rum)) * env * np.sqrt(ln)
    out = absorb(out, 400.0)
    out = out + 0.5 * conv(out, reverb(1.6, 900, 1310))
    x = hp(out, 20, 4) * duck(ts)
    return fade(set_lufs(x, LUFS["thunder"]), 0.0, 0.5)


ROOM_CEIL = -1.3     # (the ceiling the strike and its layers share, heard close, dBFS)
ROOM_SHARE = 0.45    # (each layer's share of the room left under it: two of them may peak together)


def room(x, t0, top):
    """The gain that holds layer x (its file starting at `t0` on the strike clock) to its share of the room left under
    the ceiling by the rest of the strike (`top`: its peaks, heard close, sample by sample): 1 wherever there is room,
    riding down slowly (over 0.2 s, ahead of the peaks it must clear) where there is not."""
    n = len(x)
    seg = fit(top[N(t0):], n)
    left = np.maximum(10 ** (ROOM_CEIL / 20) - minimum_filter1d(-seg, N(0.02), mode="nearest") * -1, 0.0)
    env = -minimum_filter1d(-np.abs(x), N(0.02), mode="nearest")
    g = np.minimum(1.0, ROOM_SHARE * left / (env + 1e-9))
    g = minimum_filter1d(g, N(0.2), mode="nearest")
    return np.minimum(movavg(g, N(0.2)), minimum_filter1d(g, 3, mode="nearest"))


def layers():
    """The layers of hell and heaven: {event: (file, its start on the strike clock)}."""
    made = {"hell": hell_voice, "furnace": furnace, "choir": choir, "thunder": thunder}
    return {ev: (made[ev](), t0) for ev, t0, _ in LAYERS}


# ==========================================================================================================  output
def explosions():
    """The explosions clean, before they are blown out: {base: (file, [(where a hit is, kind, surge index)], ceiling)}."""
    out = {"erupt": (erupt(), [(BREAK - ERUPT0, "crack", 0), (ERUPT - ERUPT0, "erupt", 0)], -3.0),
           "impact": (impact(), [(IMPACT_AT, "impact", 0)], -3.0),
           "blast": (blast(), [(BLAST_HIT, "blast", 0)], -2.0)}
    for i in range(len(SURGES)):
        out[f"surge_{i + 1}"] = (surge(i), [(SURGE_ATK[i], "surge", i)], -3.0)
    return out


def added_of(y, x, at, over=False):
    """The energy a blown-out hit y carries over its clean x (`blown_facts`); `over`: both over BLOW_HP (for the hits
    whose sub is their own layer, see `blowout_held`)."""
    return blown_facts(zhp(y, BLOW_HP, 4), zhp(x, BLOW_HP, 4), at)["added"] if over else blown_facts(y, x, at)["added"]


def blown(clean, take, keep=False):
    """Every explosion blown out at amount `take`: {base: file}. The products' gain is corrected twice so that what the
    finished file carries over its clean self (`blown_facts`'s added energy) is each hit's `blow_db`. `keep`: the
    clean layers stay at their own level (the products on top, the whole held under its ceiling) rather than the
    whole being levelled back to the clean loudness (which would let the crack and the sub down under the products)."""
    out = {}
    for base, (x, hits, ceil) in clean.items():
        corr = [0.0] * len(hits)
        for _ in range(3):
            y = x
            for (at, kind, i), c in zip(hits, corr):
                y = (blowout_held if keep else blowout)(y, at, kind, i, take, extra=c)
            y = limit(y, ceil) if keep else relevel(y, x, take, ceil, hits[-1][1])
            got = [added_of(y, x, at, keep) for at, _, _ in hits]
            corr = [c + blow_db(kind, i, take) - g for c, g, (_, kind, i) in zip(corr, got, hits)]
        out[base] = y
    return out


TIER_SEED = {"erupt": (655, 0.6), "impact": (208, 0.6), "blast": (205, 0.5), "sunder": (209, 1.0), "drive": (204, 0.6),
             **{f"surge_{i + 1}": (203 + 10 * i, 0.6) for i in range(6)}}
BED_SEED = {"nether": (201, 1.0), "aether": (202, 1.0), "clash": (207, 1.0)}
LAYER_SEED = {"hell": (1401, 0.6), "furnace": (1402, 0.8), "choir": (1403, 0.6), "thunder": (1404, 1.0), "win": (1405, 0.6)}


def limit_pair(files, blast_nm, sunder_nm, at):
    """The blast and the sunder always play together, the sunder's file from `at` s into the blast's: their sum is
    limited as one, so the tear landing on the blast's roll never clips."""
    for tr in ("near", "mid", "far"):
        nb, ns = f"{blast_nm}_{tr}", f"{sunder_nm}_{tr}"
        bl, su_ = files[nb], files[ns]
        j = N(at)
        both = np.zeros(max(len(bl), j + len(su_)))
        both[:len(bl)] += bl
        both[j:j + len(su_)] += su_
        g = limit_gain(both, -1.6, 0.02)
        files[nb], files[ns] = bl * g[:len(bl)], su_ * g[j:j + len(su_)]


def under_with(bl, su_, at, rounds=4):
    """The sunder's file su_ (from `at` s into the blast's bl, already limited) held so their sum stays under the
    ceiling `limit_pair` sets, by taking only su_ down."""
    j = N(at)
    for _ in range(rounds):
        both = np.zeros(max(len(bl), j + len(su_)))
        both[:len(bl)] += bl
        both[j:j + len(su_)] += su_
        su_ = su_ * limit_gain(both, -1.6, 0.02)[j:j + len(su_)]
    return su_


def blast_under(bl, su_, at, rounds=4):
    """The blast's file bl held so its sum with the sunder's su_ (from `at` s into it) stays under the ceiling
    `limit_pair` sets, by taking only bl down."""
    j = N(at)
    for _ in range(rounds):
        both = np.zeros(max(len(bl), j + len(su_)))
        both[:len(bl)] += bl
        both[j:j + len(su_)] += su_
        bl = bl * limit_gain(both, -1.6, 0.02)[:len(bl)]
    return bl


def build_ref(clean):
    """The strike the layers of hell and heaven are levelled under (`room`), as {name: mono array} named with REF_OWN:
    every event before the drive as it ships, the explosions at both ROOM_AMOUNTS, the drive, blast and sunder of one
    hit (`drive_down`, `blast`, `sunder`). `clean` gets the explosions clean, for the measurements."""
    files = {}
    pre_n, pre_a, clash = columns()
    made = {"nether": (pre_n, 201, 1.0), "aether": (pre_a, 202, 1.0), "clash": (clash, 207, 1.0),
            "fire": (fire(), 656, 1.0), "drive": (drive_down(), 204, 0.6), "after": (after(), 206, 1.0)}
    files["quake"] = quake()
    ex = explosions()
    clean.update({b: v[0] for b, v in ex.items()})
    su = sunder()
    for k in ROOM_AMOUNTS:
        for base, x in blown(ex, k).items():
            made[name_of(k, base, own=REF_OWN)] = (x, *TIER_SEED[base])
        made[name_of(k, "sunder", own=REF_OWN)] = (su, *TIER_SEED["sunder"])
    for base, (x, sd, wet) in made.items():
        for nm, y in tiers(x, sd, wet).items():
            files[f"{base}_{nm}"] = y
    for k in ROOM_AMOUNTS:
        limit_pair(files, name_of(k, "blast", own=REF_OWN), name_of(k, "sunder", own=REF_OWN), BLAST_HIT)
    return files


def build(takes=TAKES, with_layers=True, clean_out=None):
    """Every file: {name: mono array}: the beds, the drive, the layers of hell and heaven and the win once (the layers
    levelled under the levelling strike (`build_ref`), the win under that strike
    with take 2's drive, blast and sunder and the layers (`cues`' `then`)), the explosions once for each take
    (`cv_explosions`, TAKE_OWN). `clean_out`, a dict, gets the levelling strike's explosions clean."""
    clean = {} if clean_out is None else clean_out
    ref = build_ref(clean)
    files, then = {}, {}
    for nm, x in ref.items():
        ev = event_of(nm)
        if nm[:1] == "t" and nm[1:2].isdigit():
            if nm[1] == AMOUNT and ev in ("erupt", "impact", "surge"):
                then[nm[3:]] = x
        elif ev != "drive":
            files[nm] = x
    then.update(files)
    # (take 2's drive ships; its blast and sunder without their recorded top, for levelling the win)
    for nm, z in tiers(drive_take("2"), *TIER_SEED["drive"]).items():
        files[f"drive_{nm}"] = then[f"t2_drive_{nm}"] = z
    su = blown({"sunder": (sunder_take("2"), [(TEAR, "tear", 0)], -2.0)}, AMOUNT)["sunder"]
    for nm, z in tiers(su, *TIER_SEED["sunder"]).items():
        then[f"t2_sunder_{nm}"] = z
    for nm, z in blast_of("2", clean).items():
        then[f"t2_blast_{nm}"] = z
    limit_pair(then, "t2_blast", "t2_sunder", BLAST_HIT)
    if with_layers:
        # (the layers leave room under the strike's own peaks: where everything else, heard close, comes near the
        # ceiling, each layer is held to its share of what is left (`room`); the win under the strike with the layers)
        top = np.zeros(N(46.0))
        for k in ROOM_AMOUNTS:
            top = np.maximum(top, np.abs(mix(ref, cues(0.0, k, layers=(), own=REF_OWN, then=True), length=46.0)))
        for ev, (x, t0) in layers().items():
            x = x * room(x, t0, top)
            for nm, y in tiers(x, *LAYER_SEED[ev]).items():
                files[f"{ev}_{nm}"] = then[f"{ev}_{nm}"] = y
            if ev == "hell":
                # (hell's voice ships made of recordings, held to this one's level over time; the win stays levelled
                # under this one)
                y = held_like(fit(hell_rec(), len(x)), x)
                for nm, z in tiers(y * room(y, t0, top), *LAYER_SEED[ev]).items():
                    files[f"{ev}_{nm}"] = z
        tk = np.abs(mix(then, cues(0.0, "2", layers=("hell", "furnace", "choir", "thunder"), own=OLD_OWN, then=True), length=46.0))
        x = win("2")
        x = x * room(x, WIN0, tk)
        for nm, y in tiers(x, *LAYER_SEED["win"]).items():
            files[f"win_{nm}"] = y
    # (the beds ship made of recordings, held to the level over time of those the layers were levelled under)
    for base, x in zip(("nether", "aether", "clash"), columns_rec(columns())):
        for nm, y in tiers(x, *BED_SEED[base]).items():
            files[f"{base}_{nm}"] = y
    for nm, x in files.items():
        if peak_db(x) > -1.2:
            files[nm] = limit(x, -1.3)
    # (the explosions, each take's: the Payload's builders at this laser's sizes, `cv_explosions`)
    for k in takes:
        ex = cv_explosions(k)
        su = ex.pop("sunder_then", None)
        bt = ex.pop("blast_then", None)
        for base, x in ex.items():
            for nm, z in tiers_near(x, *TIER_SEED[base]).items():
                files[f"{name_of(k, base)}_{nm}"] = z
        if su is None:
            limit_pair(files, name_of(k, "blast"), name_of(k, "sunder"), BLAST_AT)
        else:
            # (the wall blast limited with the tear without its recorded top; the tear as it ships then held under the same
            # ceiling with that blast as limited; the blast as it ships then held under that ceiling with the tear as it
            # ships, by taking only the blast down)
            bl, sn = name_of(k, "blast"), name_of(k, "sunder")
            was = {**{f"{bl}_{nm}": z for nm, z in tiers_near(bt, *TIER_SEED["blast"]).items()},
                   **{f"{sn}_{nm}": z for nm, z in tiers_near(su, *TIER_SEED["sunder"]).items()}}
            limit_pair(was, bl, sn, BLAST_AT)
            for tr in ("near", "mid", "far"):
                files[f"{sn}_{tr}"] = under_with(was[f"{bl}_{tr}"], files[f"{sn}_{tr}"], BLAST_AT)
                files[f"{bl}_{tr}"] = blast_under(files[f"{bl}_{tr}"], files[f"{sn}_{tr}"], BLAST_AT)
    for nm, x in files.items():
        if peak_db(x) > -1.2:
            files[nm] = limit(x, -1.3)
    return files


def write_wav(path, x):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def write_ogg(path, x, q=6):
    tmp = str(path) + ".tmp.wav"
    write_wav(tmp, x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q),
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)], check=True)
    os.remove(tmp)


# ===================================================================================================  the cue model
def lates(dist):
    """(the burst's delay, the burst's distance) for a player on the ground `dist` blocks from the target."""
    db = float(np.hypot(dist, BURST_Y))
    return db / SPEED, db


def quake_share(dist):
    """The quake's part: 0.15 close by (the blast's own hit is on top of it there), all of it past 300 blocks."""
    return 0.15 + 0.85 * float(smooth(np.clip((dist - 50) / 250, 0, 1)))


# How much louder than its file each explosion plays (cv_sounds's CV_BOOST: more voices of the same file in the game).
BOOST = {"surge": 1.0, "impact": 1.35, "erupt": 1.2, "sunder": 1.6, "blast": 2.0}


LAYER_GAIN = {"hell": "blast", "furnace": "blast", "choir": "blast", "thunder": "blast"}   # (which `gain` each follows)


def cues(dist, take=DEFAULT, layers=None, base=True, own=TAKE_OWN, then=False):
    """(start on the strike clock, file, volume) as cv_sounds plays them `dist` blocks from the target (on the
    ground), take `take`'s files for the events in `own` (TAKE_OWN, `name_of`): everything on the strike clock, the
    aftermath late by the burst's distance, the quake through the ground ahead of it; the layers of hell and heaven
    (`layers`: which of them, `win` among them; all by default) on the strike clock. `base` False: the layers alone.
    `then`: as the strike played when the layers of hell and heaven and the win were levelled under it (`room`):
    one voice of each file, the volume falling off from the target itself (`gain_then`), the blast's hit BLAST_HIT
    into its file and each surge's file from its start. Otherwise each explosion's blow on its frame: the surge's
    SURGE_HIT[take] into its file on the peak of its push, the blast's BLAST_AT in on BLAST."""
    late, db = lates(dist)
    bo = {} if then else BOOST
    gain_ = gain_then if then else gain
    blast_at = BLAST_HIT if then else BLAST_AT
    lay_ = [l for l in LAYERS if layers is None or l[0] in layers]
    out = []
    for tr, wt in weights(db).items():
        if wt <= 1e-3:
            continue
        gc, gr = wt * gain_("nether", db), wt * gain_("blast", db)

        def f(b):
            return name_of(take, b, tr, own)
        for ev, t0, _ in lay_:
            out.append((t0, f(ev), wt * gain_(LAYER_GAIN[ev], db)))
        if not then and (layers is None or "win" in layers):
            out.append((WIN0, f("win"), wt * gain_("blast", db)))
        if not base:
            continue
        out.append((0.0, f("nether"), gc))
        out.append((0.5, f("aether"), gc))
        out.append((ERUPT0, f("erupt"), gr * bo.get("erupt", 1.0)))
        out.append((FIRE0, f("fire"), gr))
        out.append((MEET - IMPACT_AT, f("impact"), gr * bo.get("impact", 1.0)))
        out.append((MEET, f("clash"), gc))
        for i, s_ in enumerate(SURGES):
            out.append((s_ if then else s_ + SURGE_ATK[i] - SURGE_HIT[take], f(f"surge_{i + 1}"), gr * bo.get("surge", 1.0)))
        out.append((DRAW, f("drive"), gr))
        out.append((BLAST - blast_at, f("blast"), gr * bo.get("blast", 1.0)))
        out.append((BLAST, f("sunder"), gr * bo.get("sunder", 1.0)))
        out.append((AFTER + late, f("after"), gr))
    if base:
        out.append((BLAST + db / (5 * SPEED) - QUAKE_HIT, name_of(take, "quake", own=own), gain_("blast", db) * quake_share(db)))
    return out


def mix(files, cue_list, length=46.0, parts=False):
    acc = np.zeros(N(length))
    layers = {}
    for t0, f, v in cue_list:
        if f not in files:       # (a set without the layers: the strike without them)
            continue
        x = files[f] * v
        i0 = N(t0)
        m = min(len(x), len(acc) - i0)
        if m <= 0:
            continue
        acc[i0:i0 + m] += x[:m]
        if parts:
            key = event_of(f)
            layers.setdefault(key, np.zeros(len(acc)))[i0:i0 + m] += x[:m]
    return (acc, layers) if parts else acc


def short_term(x, win=0.4, hop=0.05):
    """Level (dBFS RMS) over a sliding `win` s, every `hop` s: (times, dB)."""
    w, h = N(win), N(hop)
    p = movavg(x * x, w)[::h]
    return np.arange(len(p)) * hop, 10 * np.log10(p + 1e-12)


def facts(files, take=DEFAULT, dist=150.0):
    """The numbers the checks and pictures use: the blast's margin over everything before it (400 ms), the largest dip
    in the 2 s before its held breath (100 ms windows), the held breath (how long the 50 ms level is 10 dB or more
    under the drive's loudest second before it, and how long 30 dB or more), the impact's level, the surges over the
    clash bed, the mix's peak."""
    x, layers = mix(files, cues(dist, take), parts=True)
    ts, db = short_term(x)
    hit = BLAST
    pre = ts < hit - 0.21
    blast_win = (ts >= hit) & (ts < hit + 3.0)
    tq, dq = short_term(x, 0.1, 0.01)
    br = BREATH["2"]
    last2 = (tq >= hit - 2.0) & (tq < hit - br - 0.06)
    run = np.maximum.accumulate(np.where(last2, dq, -200))
    dip2 = float(np.max((run - dq)[last2]))
    tb, b5 = short_term(x, 0.05, 0.005)
    before = b5[(tb >= hit - br - 1.0) & (tb < hit - br - 0.05)].max()
    lastb = (tb >= hit - 0.6) & (tb < hit - 0.03)
    breath10 = float(np.sum(b5[lastb] <= before - 10.0) * 0.005)
    breath30 = float(np.sum(b5[lastb] <= before - 30.0) * 0.005)
    depth = float(before - b5[lastb].min())
    imp = (tq >= MEET - 0.1) & (tq < MEET + 1.0)
    _, dk = short_term(layers["clash"], 0.1, 0.01)
    over = []
    for i, s0 in enumerate(SURGES):
        w0 = (tq >= s0) & (tq < s0 + SURGE_ATK[i] + 0.4)
        over.append(float(dq[w0].max() - np.median(dk[(tq >= s0 - 0.6) & (tq < s0)])))
    k = kweight(x)
    lm = -0.691 + 10 * np.log10(movavg(k * k, N(0.4)) + 1e-20)
    return {"blast_st": float(db[blast_win].max()), "pre_st": float(db[pre].max()),
            "margin_st": float(db[blast_win].max() - db[pre].max()),
            "blast_peak": peak_db(x[N(hit):N(hit + 3)]), "pre_peak": peak_db(x[:N(hit - 0.01)]),
            "dip2": dip2, "breath10": breath10, "breath30": breath30, "breath_depth": depth, "last2_min": float(dq[last2].min()), "last2_max": float(dq[last2].max()),
            "impact_st": float(dq[imp].max()), "surge_over_bed": over, "mix_peak": peak_db(x), "mix_peak_at": float(np.argmax(np.abs(x)) / SR),
            "blast_lufs": float(lm[N(hit):N(hit + 3)].max()), "pre_lufs": float(lm[:N(hit - 0.25)].max())}, (x, ts, db)


def blows_at(take):
    """Every explosion's hit: (label, base, where it is in its near file (s))."""
    return (("eruption 6.0", "erupt", ERUPT - ERUPT0), ("hit 13.0", "impact", IMPACT_AT),
            *((f"surge {i + 1}", f"surge_{i + 1}", SURGE_HIT[take]) for i in range(len(SURGES))),
            ("blast 26.0", "blast", BLAST_AT), ("tear 27.5", "sunder", TEAR))
BLOW_OFF = 0.035    # (the most a blow's 40-100 Hz peak may sit off its frame, s)


def blow_off(x, at, lo=40.0, hi=100.0, within=3.0):
    """How far (s) from `at` the nearest blow is: a peak of x's lo-hi Hz (10 ms) within `within` dB of the loudest in
    the 60 ms either side (a run of blows as heavy as each other has its hit on the frame and the others round it)."""
    y = zhp(zlp(x, hi, 4), lo, 2)
    e = 10 * np.log10(movavg(y * y, N(0.01)) + 1e-20)
    a, b = N(at - 0.06), N(at + 0.06)
    seg = e[a:b]
    pk = [i for i in range(1, len(seg) - 1) if seg[i] >= seg[i - 1] and seg[i] >= seg[i + 1] and seg[i] >= seg.max() - within]
    pk = pk or [int(np.argmax(seg))]
    return min(((a + i) / SR - at for i in pk), key=abs)


def band_db(seg, lo, hi):
    F = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 16)) ** 2
    f = np.fft.rfftfreq(1 << 16, 1 / SR)
    return 10 * np.log10(F[(f >= lo) & (f < hi)].sum() + 1e-30), 10 * np.log10(F[f >= 20].sum() + 1e-30)


def blown_facts(y, x, at):
    """A blown-out hit y against its clean x over the first 300 ms from `at`: the added energy (what is left of y
    past the best-fitting copy of x, dB re x), the 150 Hz-2 kHz band's share (dB), the crest (dB), the shares over
    2 kHz and 5 kHz (dB)."""
    a, b = N(at - 0.001), N(at + 0.3)
    ys, xs = y[a:b], x[a:b]
    g = float(ys @ xs) / float(xs @ xs)
    res = 10 * np.log10(float((ys - g * xs) @ (ys - g * xs)) / (g * g * float(xs @ xs)) + 1e-20)
    out = {"added": res}
    for nm, z in (("clean", xs), ("blown", ys)):
        b1, tot = band_db(z, 150, 2000)
        out[nm] = dict(body=b1 - tot, crest=20 * np.log10(np.abs(z).max() / np.sqrt(np.mean(z * z))),
                       over2=band_db(z, 2000, 20000)[0] - tot, over5=band_db(z, 5000, 20000)[0] - tot)
    return out


def sub_hz(x, at):
    """The sub's frequency in the 80 ms from `at` (the loudest peak between 28 and 160 Hz of its spectrum, the window
    zero-padded, the peak interpolated)."""
    seg = x[N(at):N(at + 0.08)]
    F = np.abs(np.fft.rfft((seg - seg.mean()) * np.hanning(len(seg)), 1 << 17))
    f = np.fft.rfftfreq(1 << 17, 1 / SR)
    m = np.where((f >= 28) & (f <= 160))[0]
    j = m[int(np.argmax(F[m]))]
    a_, b_, c_ = np.log(F[j - 1:j + 2] + 1e-20)
    return float(f[j] + 0.5 * (a_ - c_) / (a_ - 2 * b_ + c_) * (f[1] - f[0]))


def third_octaves(seg):
    F = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 16)) ** 2
    f = np.fft.rfftfreq(1 << 16, 1 / SR)
    cs = 25 * 2 ** (np.arange(0, 26) / 3)
    return np.array([10 * np.log10(F[(f >= c * 2 ** (-1 / 6)) & (f < c * 2 ** (1 / 6))].sum() + 1e-30) for c in cs])


def surge_facts(files, take=DEFAULT):
    """Per surge (its near file): the sub over the 80 ms from the blow and from 200 ms later (Hz), the centroid of its
    first 300 ms under 1 kHz (Hz); and between every two surges the correlation of their third-octave spectra over
    the 600 ms from 0.15 s before the blow."""
    rows, spec = [], []
    for i in range(len(SURGES)):
        x = files[name_of(take, f"surge_{i + 1}", "near")]
        at = SURGE_HIT[take]
        seg = x[N(at - 0.001):N(at + 0.3)]
        F = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), 1 << 16)) ** 2
        f = np.fft.rfftfreq(1 << 16, 1 / SR)
        m = (f >= 20) & (f < 1000)
        rows.append(dict(sub0=sub_hz(x, at), sub200=sub_hz(x, at + 0.2), cen=float((f[m] * F[m]).sum() / F[m].sum())))
        spec.append(third_octaves(x[N(at - 0.15):N(at + 0.45)]))
    return rows, np.corrcoef(np.array(spec))


SURGE_APART = (1.0, 0.985)   # (every two surges: their sub or their centroid this many semitones apart, and their
                             # spectra's correlation at most this: reported only)


def surge_pairs(rows, corr):
    """Every two surges: (i, j, semitones apart (the larger of the sub's and the centroid's), correlation)."""
    out = []
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            st = max(abs(12 * np.log2(rows[i][k] / rows[j][k])) for k in ("sub200", "cen"))
            out.append((i, j, st, float(corr[i, j])))
    return out


def layer_margins(files, take, dist):
    """At every hit: how far the loudest layer of hell and heaven sits under the hit's own file in the mix (100 ms
    levels, the 300 ms from the hit), dB: [(hit time, layer, margin)]."""
    _, layers_ = mix(files, cues(dist, take), parts=True)
    own = {BREAK: "erupt", ERUPT: "erupt", MEET: "impact", BLAST: "blast"}
    out = []
    for h in HITS:
        ev = own.get(h, "surge")
        _, dh = short_term(layers_[ev][N(h - 0.05):N(h + 0.35)], 0.1, 0.01)
        for lay_ in (l[0] for l in LAYERS):
            if lay_ in layers_:
                _, dl = short_term(layers_[lay_][N(h - 0.05):N(h + 0.35)], 0.1, 0.01)
                out.append((h, lay_, float(dh.max() - dl.max())))
    return out


LAYER_UNDER = 6.0   # (the least a layer sits under a hit, dB)
BREATH_SILENT = 0.15   # (the longest the held breath may be near silent, s)


def tail_fall(x, at, by=20.0):
    """How long after its loudest 100 ms (from `at`) x is first `by` dB under it (s)."""
    w, h = N(0.1), N(0.05)
    r = np.array([10 * np.log10(np.mean(x[k:k + w] ** 2) + 1e-20) for k in range(N(at), len(x) - w, h)])
    k0 = int(np.argmax(r))
    idx = np.where(r[k0:] < r[k0] - by)[0]
    return float(idx[0] * 0.05) if len(idx) else float("nan")


GAME_SIDE = 0.596    # (a centred voice's share of each side in the game's mixer)
GAME_LIMIT = 2.0     # (the most the game's limiter may take off anywhere, dB)
BLAST_OVER_ALL = 4.0   # (the least the blast's loudest 400 ms stands over anything before it, dB, where the near
BLAST_OVER_FAR = 1.5   # files play (to 600 blocks); and past that)
# The explosions' loudest 400 ms as the game puts them out at 150 blocks (dBFS a side): (label, from, to, low, high).
GAME_LEVELS = (("impact", MEET, MEET + 0.8, -13.0, -9.5), ("blast", BLAST, BLAST + 1.0, -7.5, -6.5))
GAME_SURGE = {"1": (-14.0, -12.0), "2": (-14.0, -12.0)}   # (each surge alone, out of the game's mixer, per take)


def game_out(x, buf=1024):
    """x (the strike's mono sum) as the game's mixer puts it out: each side GAME_SIDE of it, then its limiter (the peak
    of each callback buffer held under full scale, released over 0.2 s): (the side, the most it took off, dB)."""
    y = x * GAME_SIDE
    out = np.empty_like(y)
    lp_ = 1.0
    rel = np.exp(-1.0 / (0.2 * SR))
    worst = 0.0
    for b in range(0, len(y), buf):
        blk = y[b:b + buf]
        peak = max(1.0, float(np.abs(blk).max()))
        lp_ = max(lp_, peak)
        g = 1.0 / np.maximum(lp_ * rel ** np.arange(len(blk)), peak)
        lp_ = max(lp_ * rel ** len(blk), peak)
        out[b:b + buf] = blk * g
        worst = min(worst, 20 * np.log10(g.min()))
    return out, worst


def loudest_in(x, a, b, w=0.4):
    """x's loudest `w` s between a and b s (dBFS RMS)."""
    s_ = x[N(a):N(b)]
    k = N(w)
    c = np.cumsum(np.r_[0.0, s_ * s_])
    return float(10 * np.log10(((c[k:] - c[:-k]) / k).max() + 1e-12))


def checks(files, out_dir=None, clean=None):
    """The sound's checks, printed and returned as (name, ok, detail) rows, for every take: no file
    shared with another laser (by hash), no dip over 10 dB in the 2 s before the blast's held breath, the held breath
    no longer than the picture's and near silent (30 dB down) for no more than BREATH_SILENT s, the blast the loudest by
    BLAST_OVER_ALL dB, every file's peak under -1 dBFS and the game's limiter taking GAME_LIMIT dB at most, near, mid
    and far for every event cued from more than one distance, every explosion's blow on its frame (BLOW_OFF), the
    explosions at their levels in the game (GAME_LEVELS, GAME_SURGE), no layer of hell or heaven the loudest at any
    hit; the tails' length and how far apart the surges are, reported."""
    rows = []
    snd = ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds"
    ours = {hashlib.sha256((Path(out_dir) / f"{shipped(nm)}.ogg").read_bytes()).hexdigest(): nm for nm in files
            if takes_in([nm]) in ([], [SHIP])} if out_dir else {}
    others = {}
    for f in snd.rglob("*.ogg"):
        if f.parent.name != TH:
            others.setdefault(hashlib.sha256(f.read_bytes()).hexdigest(), []).append(str(f.relative_to(snd)))
    shared = [(ours[h], others[h]) for h in ours if h in others]
    rows.append(("no file shared with another laser (sha256)", not shared and bool(ours), f"{len(ours)} files against {sum(len(v) for v in others.values())} of other lasers; shared: {shared or 'none'}"))
    pk = max((peak_db(x), nm) for nm, x in files.items())
    rows.append(("every file's peak under -1 dBFS", pk[0] < -1.0, f"loudest {pk[1]} {pk[0]:.2f} dBFS"))
    for k in takes_in(files):
        for dist in (30.0, 150.0, 600.0, 1000.0):
            f, _ = facts(files, k, dist)
            tag = f"take {k}, {dist:.0f} blocks"
            rows.append((f"no dip over 10 dB in the 2 s before the blast's held breath ({tag})", f["dip2"] <= 10.0, f"largest dip {f['dip2']:.1f} dB ({f['last2_min']:.1f}..{f['last2_max']:.1f} dB)"))
            rows.append((f"the held breath on the picture's, near silent at most {BREATH_SILENT} s ({tag})",
                         f["breath10"] <= COLLAPSE + 0.02 and f["breath30"] <= BREATH_SILENT,
                         f"at most {f['breath_depth']:.1f} dB under the drive (50 ms), 10 dB or more for {f['breath10']:.3f} s (the picture's {COLLAPSE} s), 30 dB or more for {f['breath30']:.3f} s"))
            over = BLAST_OVER_ALL if dist <= 600.0 else BLAST_OVER_FAR
            rows.append((f"the blast the loudest by {over:.1f} dB ({tag})", f["margin_st"] >= over,
                         f"+{f['margin_st']:.1f} dB over anything before it (400 ms RMS), {f['blast_lufs'] - f['pre_lufs']:+.1f} LUFS-M, peaks {f['blast_peak'] - f['pre_peak']:+.1f} dB"))
            g_, red = game_out(mix(files, cues(dist, k), length=46.0))
            rows.append((f"the game's limiter takes {GAME_LIMIT:.0f} dB at most ({tag})", red >= -GAME_LIMIT,
                         f"the mix {f['mix_peak']:.2f} dBFS (at {f['mix_peak_at']:.2f} s), {f['mix_peak'] + 20 * np.log10(GAME_SIDE):.2f} a side; the limiter {red:.1f} dB at most"))
            if dist == 150.0:
                lv = [(lbl, loudest_in(g_, a, b), lo, hi) for lbl, a, b, lo, hi in GAME_LEVELS]
                lo_, hi_ = GAME_SURGE[k]
                lv += [(f"surge {i + 1} alone", loudest_in(files[name_of(k, f"surge_{i + 1}", "near")] * BOOST["surge"] * GAME_SIDE, 0.0, 9.0), lo_, hi_)
                       for i in range(len(SURGES))]
                mixed = [loudest_in(g_, s_ + SURGE_ATK[i], s_ + SURGE_ATK[i] + 0.9) for i, s_ in enumerate(SURGES)]
                rows.append((f"the explosions at their levels in the game ({tag})", all(lo <= v <= hi for _, v, lo, hi in lv),
                             ", ".join(f"{lbl} {v:.1f}" for lbl, v, _, _ in lv) + f" dBFS a side (the impact -13..-9.5, the blast -7.5..-6.5, "
                             f"each surge alone {lo_:g}..{hi_:g}); the surges in the mix " + ", ".join(f"{v:.1f}" for v in mixed)
                             + f", the eruption {loudest_in(g_, ERUPT, ERUPT + 0.8):.1f}, the tear {loudest_in(g_, BLAST + TEAR, BLAST + TEAR + 0.8):.1f}"))
        missing = []
        for _, f_, _ in cues(400.0, k):
            if f_ == "quake":
                continue
            base = f_.rsplit("_", 1)[0]
            missing += [f"{base}_{t}" for t in ("near", "mid", "far") if f"{base}_{t}" not in files]
        rows.append((f"near, mid and far for every event (take {k})", not missing, f"missing: {sorted(set(missing)) or 'none'} (the quake: one file by design)"))
        off = [(lbl, blow_off(files[name_of(k, base, "near")], at)) for lbl, base, at in blows_at(k)]
        rows.append((f"every explosion's blow on its frame (take {k})", all(abs(v) <= BLOW_OFF for _, v in off),
                     "the 40-100 Hz blow nearest the frame (10 ms peaks within 3 dB of the loudest within 60 ms) " + ", ".join(f"{lbl} {1000 * v:+.0f}" for lbl, v in off) + f" ms off it (at most {1000 * BLOW_OFF:.0f})"))
        tails = [(lbl, tail_fall(files[name_of(k, base, "near")], at)) for lbl, base, at in blows_at(k)]
        rows.append((f"how long each rolls on (take {k})", None, "20 dB down after " + ", ".join(f"{lbl} {v:.1f}" for lbl, v in tails) + " s"))
        if any(l[0] + "_near" in files for l in LAYERS):
            worst = min((m for dist in (30.0, 150.0, 600.0) for m in layer_margins(files, k, dist)), key=lambda r: r[2])
            rows.append((f"no layer of hell or heaven the loudest at any hit (take {k})", worst[2] >= LAYER_UNDER,
                         f"the closest: {worst[1]} {worst[2]:.1f} dB under the hit at {worst[0]:.2f} s (at least {LAYER_UNDER:.0f})"))
        r_, c_ = surge_facts(files, k)
        pairs = surge_pairs(r_, c_)
        near_ = min(pairs, key=lambda q: q[2])
        like = max(pairs, key=lambda q: q[3])
        rows.append((f"how far apart the surges are (take {k}; their pitches SURGE_PITCH, reported)", None,
                     f"closest in pitch: surges {near_[0] + 1} and {near_[1] + 1}, {near_[2]:.2f} semitones (at least {SURGE_APART[0]}); "
                     f"most alike: surges {like[0] + 1} and {like[1] + 1}, correlation {like[3]:.3f} (at most {SURGE_APART[1]}); "
                     "subs 200 ms on " + ", ".join("%.0f" % q["sub200"] for q in r_) + " Hz"))
    for name, ok, detail in rows:
        print(("info  " if ok is None else "ok    " if ok else "FAIL  ") + name + ": " + detail)
    return rows


# ============================================================================================  measuring the blasts
BANDS = (("sub", 20, 60), ("low", 60, 100), ("body", 100, 800), ("mid", 800, 2000), ("pres", 2000, 6000), ("air", 6000, 20000))
# Other lasers' blasts, measured only for comparison (nothing from them is used): (label, file, where the front is
# (s), or None to find the loudest).
OTHERS = (("Payload blast", "payload/blast.ogg", None), ("Payload alt blast", "payload/blast_alt.ogg", None), ("Nuke alt blast", "nuke/blast_alt.ogg", None),
            ("Planet Killer impact (cutoff)", "planetkiller/cutoff.ogg", None), ("Meteor impact", "meteor/impact.ogg", None),
            ("Meteor hit 1", "meteor/hit1.ogg", None))


def load(path):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64)


def _onset(x, hint=None):
    """The front: where the 1 ms level first comes within 20 dB of the loudest near it (near `hint` s if given)."""
    e = np.sqrt(movavg(x * x, N(0.001)) + 1e-20)
    a, b = (max(0, N(hint - 0.05)), N(hint + 0.15)) if hint is not None else (0, len(e))
    pk = a + int(np.argmax(e[a:b]))
    i = pk
    while i > a and e[i] > e[pk] * 0.1:
        i -= 1
    return i


def _shares(seg):
    F = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
    fr = np.fft.rfftfreq(len(seg), 1 / SR)
    tot = F[fr >= 20].sum() + 1e-20
    return {nm: F[(fr >= lo) & (fr < hi)].sum() / tot for nm, lo, hi in BANDS}


def measure(x, hint=None):
    """A blast's numbers: band shares of its first 50, 200 and 1000 ms, its front's crest (peak over RMS, 200 ms) and
    attack (10-90% of the 5 ms level), its loudness (LUFS momentary and short-term max), peak, length (to 40 dB under
    its loudest 400 ms) and how far down it is 1 s and 3 s after the front."""
    i0 = _onset(x, hint)
    out = {}
    for ms in (50, 200, 1000):
        out[ms] = _shares(x[max(0, i0 - N(0.002)):i0 + N(ms / 1000)])
    f = x[i0:i0 + N(0.2)]
    out["crest"] = 20 * np.log10(np.abs(f).max() / (np.sqrt(np.mean(f * f)) + 1e-20))
    e = np.sqrt(movavg(x * x, N(0.005)) + 1e-20)
    w = e[i0:i0 + N(0.3)]
    out["attack"] = 1000 * (int(np.argmax(w > 0.9 * w.max())) - int(np.argmax(w > 0.1 * w.max()))) / SR
    out["peak"] = peak_db(x)
    out["lufs_m"], out["lufs_s"] = lufs_m(x, 0.4), lufs_m(x, 3.0)
    r = 10 * np.log10(movavg(x * x, N(0.4)) + 1e-20)
    above = np.where(r > r.max() - 40)[0]
    out["len"] = (above[-1] - i0) / SR
    for tt in (1.0, 3.0):
        out[f"down{tt:g}"] = r.max() - r[min(i0 + N(tt), len(r) - 1)]
    return out


def table_row(name, m):
    def s(ms):
        a = "/".join(f"{100 * m[ms][b]:.0f}" for b in ("sub", "low", "body"))
        return a + " | " + "/".join(f"{10 * np.log10(m[ms][b] + 1e-9):.0f}" for b in ("mid", "pres", "air"))
    return (f"| {name} | {s(50)} | {s(200)} | {s(1000)} | {m['crest']:.1f} | {m['attack']:.0f} | {m['lufs_m']:.1f} | "
            f"{m['lufs_s']:.1f} | {m['peak']:.1f} | {m['len']:.1f} | {m['down1']:.0f} / {m['down3']:.0f} |")


TABLE_HEAD = ("| sound | 0-50 ms sub/low/body % | 0-50 ms mid/pres/air dB | 0-200 ms % | 0-200 ms dB | 0-1 s % | 0-1 s dB | "
              "front crest dB | attack ms | LUFS-M max | LUFS-S max | peak dBFS | length s | down at 1 s / 3 s dB |\n"
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")


def table(files):
    """The measurements, as a Markdown table: the Payload's two blasts and the other lasers' ones, then every take's
    explosions (near files, from their blows)."""
    snd = ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds"
    lines = [TABLE_HEAD]
    for label, p_, h in OTHERS:
        lines.append(table_row(label, measure(load(snd / p_), h)))
    for k in takes_in(files):
        for label, base, at in blows_at(k):
            lines.append(table_row(f"take {k}: {label}", measure(files[name_of(k, base, "near")], at)))
    return "\n".join(lines)



# ============================================================================================  pictures and the page
COL = {"nether": (190, 60, 30), "aether": (200, 160, 30), "impact": (210, 0, 120), "clash": (230, 110, 20),
       "surge": (120, 70, 160), "drive": (40, 120, 160), "blast": (20, 20, 20), "sunder": (0, 150, 150),
       "after": (110, 110, 110), "quake": (60, 140, 60), "erupt": (170, 120, 60), "fire": (250, 60, 0),
       "hell": (140, 0, 0), "furnace": (255, 140, 120), "choir": (90, 170, 255), "thunder": (0, 70, 200), "win": (230, 200, 0)}


def picture(files, path, dist=150.0):
    """The level over time of the whole strike at `dist` blocks for every take (400 ms windows, LUFS-M): each layer
    thin, the sum thick."""
    from PIL import Image, ImageDraw
    opts = takes_in(files)
    H = 330
    img = Image.new("RGB", (1500, 60 + H * len(opts)), (250, 250, 248))
    d = ImageDraw.Draw(img)
    x0 = 70
    for k, c in COL.items():
        d.rectangle([x0, 14, x0 + 14, 24], fill=c)
        d.text((x0 + 18, 13), k, fill=(40, 40, 40))
        x0 += 92
    for j, o in enumerate(opts):
        f, _ = facts(files, o, dist)
        x, layers = mix(files, cues(dist, o), parts=True)
        L, TOP, R, B = 70, 60 + j * H + 20, 1480, 60 + (j + 1) * H - 30
        t0, t1, lo, hi = 0.0, 44.0, -50.0, 0.0

        def X(v):
            return L + (R - L) * (v - t0) / (t1 - t0)

        def Y(v):
            return TOP + (B - TOP) * (hi - np.clip(v, lo, hi)) / (hi - lo)
        for v in range(int(lo), int(hi) + 1, 10):
            d.line([L, Y(v), R, Y(v)], fill=(215, 215, 210))
            d.text((L - 55, Y(v) - 6), f"{v} LUFS", fill=(90, 90, 90))
        for s in range(0, 45, 2):
            d.text((X(s) - 6, B + 4), f"{s}", fill=(90, 90, 90))
        for b in (BREAK, ERUPT, MEET, *SURGES, DRAW, BLAST):
            d.line([X(b), TOP, X(b), B], fill=(255, 190, 190))

        def curve(y):
            k_ = kweight(y)
            v = -0.691 + 10 * np.log10(movavg(k_ * k_, N(0.4))[::N(0.05)] + 1e-20)
            return [(X(i * 0.05), Y(a)) for i, a in enumerate(v) if i * 0.05 <= t1]
        for kname, y in layers.items():
            d.line(curve(y), fill=COL.get(kname, (0, 0, 0)), width=1)
        d.line(curve(x), fill=(0, 0, 0), width=3)
        d.text((L, TOP - 18), f"take {o} ({NAMES.get(o, 'before')}) at {dist:.0f} blocks: blast {f['blast_lufs']:.1f} LUFS-M, loudest before it {f['pre_lufs']:.1f}; largest dip in the 2 s before the blast {f['dip2']:.1f} dB (100 ms); mix peak {f['mix_peak']:.1f} dBFS", fill=(0, 0, 0))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def spectrogram(x, path, t0, t1, title, beats=()):
    """A spectrogram (20 Hz-16 kHz, log) of x[t0:t1] with the picture's moments as red lines."""
    from PIL import Image, ImageDraw
    W, H = 1500, 420
    img = Image.new("RGB", (W, H + 60), (250, 250, 248))
    d = ImageDraw.Draw(img)
    seg = x[N(t0):N(t1)]
    f, tt, Z = signal.stft(seg, SR, nperseg=4096, noverlap=4096 - 220)
    S = 20 * np.log10(np.abs(Z) + 1e-9)
    top = np.percentile(S[(f > 20) & (f < 16000)], 99.7)
    S = np.clip((S - (top - 70)) / 70, 0, 1)
    fmin, fmax = 20.0, 16000.0
    ys = np.geomspace(fmax, fmin, H)
    fi = np.clip(np.searchsorted(f, ys), 0, len(f) - 1)
    L, R = 60, W - 20
    xs = np.linspace(0, len(tt) - 1, R - L).astype(int)
    im = (S[fi][:, xs] ** 1.4 * 255).astype(np.uint8)
    rgb = np.stack([im, (im * 0.8).astype(np.uint8), (255 - im) // 3], -1)
    img.paste(Image.fromarray(rgb, "RGB"), (L, 30))
    for fr in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
        yy = 30 + H * np.log(fmax / fr) / np.log(fmax / fmin)
        d.line([L - 6, yy, L, yy], fill=(0, 0, 0))
        d.text((4, yy - 6), f"{fr}", fill=(0, 0, 0))
    for b in beats:
        if t0 <= b <= t1:
            xx = L + (R - L) * (b - t0) / (t1 - t0)
            d.line([xx, 30, xx, 30 + H], fill=(255, 40, 40), width=2)
    s_ = np.ceil(t0)
    while s_ <= t1:
        d.text((L + (R - L) * (s_ - t0) / (t1 - t0) - 6, 34 + H), f"{s_:g}", fill=(60, 60, 60))
        s_ += 1
    d.text((L, 8), title, fill=(0, 0, 0))
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def main():
    global SRC, SRC9
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--src", help="the recordings (default: CV_SOUND_SRC)")
    ap.add_argument("--src9", help="the layers' recordings (default: CV_SOUND_SRC9)")
    ap.add_argument("--takes", default=SHIP, help="build these takes' explosions (only take SHIP's are written)")
    ap.add_argument("--picture", help="write the level over time at 150 blocks (PNG) here")
    ap.add_argument("--table", help="write the measurements against other lasers' blasts (Markdown) here")
    ap.add_argument("--dry", action="store_true", help="build and check but write no game files")
    a = ap.parse_args()
    if a.src:
        SRC = Path(a.src)
    if a.src9:
        SRC9 = Path(a.src9)
    clean = {}
    files = build(tuple(a.takes), clean_out=clean)
    snd = Path(a.out) / "assets" / "orbital" / "sounds" / TH
    if not a.dry:
        snd.mkdir(parents=True, exist_ok=True)
        ship = {shipped(nm): x for nm, x in files.items() if takes_in([nm]) in ([], [SHIP])}
        for old in snd.glob("*.ogg"):        # (files this build no longer makes)
            if old.stem not in ship:
                old.unlink()
        for nm, x in ship.items():
            write_ogg(snd / f"{nm}.ogg", x)
        path = Path(a.out) / "assets" / "orbital" / "sounds.json"
        sounds = json.loads(path.read_text()) if path.exists() else {}
        for ev in [e for e in sounds if e.startswith(f"{TH}.") and e[len(TH) + 1:] not in ship]:
            sounds.pop(ev)
        for nm in ship:
            base = event_of(nm)
            sounds[f"{TH}.{nm}"] = {"sounds": [{"name": f"orbital:{TH}/{nm}", "attenuation_distance": 256}],
                                   "subtitle": f"subtitles.orbital.{TH}.{SUBTITLE[base]}"}
        path.write_text(json.dumps(sounds, indent=2))
        print(f"{len(ship)} files in {snd}")
    checks(files, snd if not a.dry and Path(a.out).resolve() == (ROOT / "orbital-sounds").resolve() else None, clean)
    for k in takes_in(files):
        f, _ = facts(files, k)
        print(f"take {k} at 150 blocks: blast {f['blast_lufs']:.1f} LUFS-M (loudest before {f['pre_lufs']:.1f}), "
              f"400 ms margin {f['margin_st']:+.1f} dB, peaks {f['blast_peak'] - f['pre_peak']:+.1f}; impact {f['impact_st']:.1f} dB; "
              f"surges over the clash {', '.join(f'{v:+.1f}' for v in f['surge_over_bed'])} dB; last 2 s {f['last2_min']:.1f}..{f['last2_max']:.1f} "
              f"(dip {f['dip2']:.1f}); mix peak {f['mix_peak']:.2f} dBFS")
    if a.table:
        Path(a.table).write_text(table(files) + "\n")
    if a.picture:
        picture(files, a.picture)


if __name__ == "__main__":
    main()
