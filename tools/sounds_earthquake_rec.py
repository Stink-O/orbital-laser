#!/usr/bin/env python3
"""The Earthquake's earlier take (`/orbital quakesound real`; tools/sounds_earthquake.py builds the synthesized one, its
files `syn_*`, which this leaves alone). Built to the earlier timeline below; strike/eq_sounds.rs plays its files on
the present one (its `swell` no longer). What breaks (rock tearing, rock grinding on rock, the cliff letting go, boulders and scree,
trees going over, water pouring into the canyon) is shaped from CC0 recordings (`REC`; credited in NOTICE; the
recordings themselves are not in the repository): slowed, low-passed where bright, re-enveloped and layered. Synthesis
is only size and sub under them: the ground's blows, the air's pressure, the drone under the rumble bed.

New for this laser: no other laser's files, helpers or sound models (numpy and scipy only).

Every file is mono (the game sums a stereo file to mono as it loads it) and sits at a fixed level against the others
(the climax the loudest), so a cue's volume is its distance only. Events heard from more than one distance come in
tiers, `_near`, `_mid` and `_far` (`tier`), cross-faded by the player's distance from the moving land (`weights`):
near is full band and dry with the breaks' presence up to a few kHz; mid keeps the body and the sub, the top gone over
2 kHz, the breaks merged into a roll with a little ground reverb; far is the sub and a dark soft-fronted rumble. Trees,
scree, grinding and water are not heard far off (no `_far` file).

Two clocks: through the ground (the bed, the blows, the swell, the settle) late by d/1700 s; through the air
(tearing, grinding, falls, trees, water) late by d/343 s, d the player's distance from the fault in the zone (the
crack's own from where it passes them). Strike clock (seconds; strike/earthquake.rs's constants win):

  bed_X          0      the rumble bed, the whole strike: from the blow underfoot only ever climbing to the climax
                        (the swells of the ground waves 5.5-11, a step after every lurch, the strain under the build),
                        held through the thrust, falling away from rest (31), the tremors at 34.5 and 40.2; 49.4 s
  blow_X         0      the blow underfoot (its hit BLOW_AT in); 4 s
  tear_X         ~1-5   the crack racing out along the main fault, passing the player (its loudest TEAR_PASS in) and
                        running on; tearclose_X when it starts right by them (TEARCLOSE_PASS in)
  rip_X          0.8    the crack opening round the target heard from afar (mid and far only)
  branch_X       ~2     the side cracks branching off and racing out round the plates (near and mid)
  swell_X        5.5    the land swelling: low grinding as the cracks shudder, the ground waves' heaves; 4.6 s
  heaveblow_X    10     the first heave's blow through the ground (HEAVEBLOW_AT in), the air's push, the long roll
  heave_X        10     the first heave in the air: one big rip across the fault and the up side's short grind
  trees_X        10.5   trees going over near the fault (near and mid)
  grindK_X       lurch K (13.5, 17, 20.5, 24): rock grinding on rock, as long as that lurch, a hard start
                        (GRIND_AT in); the fourth runs on into the build (near and mid)
  knock_X        each lurch's body blow through the ground (KNOCK_AT in), its volume by the lurch's share
  fallK_X        rock coming off the cliff after the second and third lurches and in the build (near and mid)
  build_X        23.5   the grind rising into the climax, ending on it (BUILD_LEN in)
  climaxblow_X   27.5   the climax's blow through the ground (CLIMAXBLOW_AT in): the biggest sub, the stone's body,
                        the air's big push, the longest roll
  climax_X       27.5   the climax in the air (CLIMAX_AT in): rock tearing across the whole fault, the cliff's thrust
                        grinding on to rest and stopping dead there, a cliff face letting go, trees going over in a wave
  settle_X       31     the last settle (SETTLE_AT in)
  slideK_X       32-44  scree and boulders off the scarps, louder first, the gaps growing (near and mid)
  pour_X         33     water pouring into the canyon, its low roar only, to the end (near and mid)

X is the tier. `cues` is strike/eq_sounds.rs's schedule, mirrored for the listening mixes.

    python3 tools/sounds_earthquake_rec.py --src RECORDINGS              # the .ogg files, sounds.json and the subtitles
    python3 tools/sounds_earthquake_rec.py --src RECORDINGS --listen DIR # also the whole strike mixed as the game does
                                                                     # from 40, 250 and 800 blocks (WAV and PNG)
    python3 tools/sounds_earthquake_rec.py --src RECORDINGS --page DIR   # each event and each layer alone (WAV), LIST.txt
    python3 tools/sounds_earthquake_rec.py --src RECORDINGS --check      # the checks (hashes, levels, tiers, the dip)
"""
import argparse
import hashlib
import json
import os
import subprocess
import wave
from fractions import Fraction
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
TH = "earthquake"
ROOT = Path(__file__).resolve().parent.parent

# ---- the strike clock (strike/earthquake.rs: keep in step) --------------------------------------------------------------
CRACK = 0.8          # EQ_CRACK
CRACK_V = 110.0      # EQ_CRACK_V
CRACK_BY = 5.5       # EQ_CRACK_BY
WARP = 5.5           # EQ_WARP_START (the swells)
HEAVE = 10.0         # EQ_HEAVE
LURCH = (13.5, 17.0, 20.5, 24.0)     # EQ_BASE[1..5]
SHARE = (0.12, 0.13, 0.10, 0.05)     # EQ_SHARE[1..5]
CLIMAX = 27.5        # EQ_CLIMAX
CLIMAX_LONG = 2.2    # EQ_LONG[5]
REST = 31.0          # EQ_REST
BACK = (33.5, 38.4)  # EQ_BASE[6..8]: the plates back home, the terrain left alone
TREMORS = (34.5, 40.2)
REACH = 160.0
CAP = 0.45           # EQ_CAP
SEG = 0.75           # EQ_SEG
PAST = 60.0          # EQ_PAST
END = 50.0           # the strike's length
GROUND_V = 1700.0
AIR_V = 343.0

# ---- where each file's beat is in it, and the schedule's own numbers (strike/eq_sounds.rs: keep in step) ------------------
BLOW_AT = 0.05
TEAR_PASS = 1.6
TEARCLOSE_PASS = 0.35
HEAVEBLOW_AT = 0.25
HEAVE_AT = 0.05
GRIND_AT = 0.04
KNOCK_AT = 0.15
BUILD_LEN = 4.0
CLIMAXBLOW_AT = 0.4
CLIMAX_AT = 0.05
SETTLE_AT = 0.2
TREES_AFTER = 0.5
FALLS = ((2, 1.6), (3, 1.2))          # (after lurch K, this long after it starts)
FALL3_BEFORE = 2.2                   # the build's small fall, this long before the climax
SLIDES = ((32.3, 1.0), (35.0, 0.85), (38.6, 0.7), (43.5, 0.55))
POUR_T = 33.0
RIP_FROM = 200.0                     # the crack's opening heard from afar past this far from the target

# ---- the recordings ------------------------------------------------------------------------------------------------------
# CC0 1.0 recordings from Freesound (credited in NOTICE), read from SRC (`--src`, or the EQ_SOUND_SRC environment
# variable) under the names they were fetched with (the MP3 previews Freesound serves).
REC = {
    "R1": ("tear_rockcrack03_falcospizaetus_489905.mp3", "RockCrack03", "falcospizaetus", 489905),
    "R2": ("tear_rock_destroy_bertsz_524312.mp3", "Rock destroy", "Bertsz", 524312),
    "R3": ("tear_s41_31_misc_crashes_for_earthq_craigsmith_675846.mp3", "S41-31 Misc. crashes for earthquake; or general destruction", "craigsmith", 675846),
    "R4": ("tear_cracking_earthquake_cracking_s_uagadugu_222521.mp3", "Cracking Earthquake (cracking soil, cracking stone)", "uagadugu", 222521),
    "R5": ("thrust_stone_slab_door_grinding_heavy_nahuelmartinez_844329.mp3", "Stone Slab Door Grinding - Heavy Rock Scrape", "NahuelMartinez", 844329),
    "R6": ("thrust_stone_slab_wav_scottrex05_593489.mp3", "Stone slab.wav", "Scottrex05", 593489),
    "R7": ("thrust_rock_sliding_throndronis_799521.mp3", "Rock sliding", "Throndronis", 799521),
    "R8": ("thrust_d_placementroche_wav_davidou_88496.mp3", "DéplacementRoche.wav", "davidou", 88496),
    "R9": ("fall_s33_29_boulders_fall_down_moun_craigsmith_675733.mp3", "S33-29 Boulders fall down mountain and crash explosively", "craigsmith", 675733),
    "R10": ("fall_s33_22_boulders_crashing_down__craigsmith_675732.mp3", "S33-22 Boulders crashing down mountain (two speeds)", "craigsmith", 675732),
    "R11": ("fall_s10_20_heavy_stone_falling_ont_craigsmith_675741.mp3", "S10-20 Heavy stone falling onto stone", "craigsmith", 675741),
    "R12": ("fall_s32_12_landslide_starts_and_st_craigsmith_675735.mp3", "S32-12 Landslide starts and stops", "craigsmith", 675735),
    "R13": ("ground_g43_11_earth_quake_wav_craigsmith_438690.mp3", "G43-11-Earth Quake.wav", "craigsmith", 438690),
    "R14": ("ground_r29_03_long_rumble_for_earthqu_craigsmith_483287.mp3", "R29-03-Long Rumble for Earthquake or Explosion", "craigsmith", 483287),
    "R15": ("tree_big_tree_fall_in_forest_kinoton_494071.mp3", "Big Tree Fall in Forest", "Kinoton", 494071),
    "R16": ("tree_tall_dead_tree_splintering_the_ozymandias37_869103.mp3", "Tall dead tree splintering then falling to ground", "ozymandias37", 869103),
    "R17": ("tree_g26_24_tree_crashes_wav_craigsmith_438343.mp3", "G26-24-Tree Crashes.wav", "craigsmith", 438343),
    "R18": ("water_rushing_waterfall_colonnades_760050.mp3", "Rushing Waterfall (Aira Force)", "Colonnades", 760050),
}
SRC = Path(os.environ.get("EQ_SOUND_SRC", "earthquake-sound-src"))
_cache = {}


def rec(r):
    """Recording `r` (R1-R18) as mono float at SR."""
    if r not in _cache:
        path = SRC / REC[r][0]
        if not path.exists():
            raise SystemExit(f"no recording {path} (set EQ_SOUND_SRC or --src)")
        raw = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                             check=True, capture_output=True).stdout
        _cache[r] = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return _cache[r]


# ---- small tools ---------------------------------------------------------------------------------------------------------
def N(s):
    return int(round(s * SR))


def T(n):
    return np.arange(n) / SR


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def sos(kind, f, o):
    return signal.butter(o, f, kind, fs=SR, output="sos")


def lp(x, f, o=4):
    return signal.sosfilt(sos("lowpass", f, o), x)


def hp(x, f, o=2):
    return signal.sosfilt(sos("highpass", f, o), x)


def bp(x, lo, hi, o=2):
    return signal.sosfilt(sos("bandpass", [lo, hi], o), x)


def notch(x, lo, hi, o=2):
    return signal.sosfilt(sos("bandstop", [lo, hi], o), x)


# Steady tones some recordings carry (a ringing scrape, a tape's lines), measured against each one's median spectrum:
# notched out before anything is slowed, or slowing turns them into a low whistle.
RINGS = {"R3": ((530, 566), (812, 852)), "R5": ((1580, 1640),), "R7": ((800, 960), (1380, 1440), (1650, 2250)),
         "R12": ((985, 1040), (1400, 1700)), "R13": ((445, 480), (805, 845)), "R16": ((1690, 1760),)}


def cut(r, a, b):
    x = rec(r)[N(a):N(b)].copy()
    for lo, hi in RINGS.get(r, ()):
        x = notch(x, lo, hi, 2)
    return x


def slow(x, k):
    """Played at k times its speed (k < 1: slower and lower), as a tape slowed."""
    fr = Fraction(k).limit_denominator(60)
    return signal.resample_poly(x, fr.denominator, fr.numerator)


def fade(x, a=0.01, b=0.05):
    x = x.copy()
    na, nb = min(N(a), len(x)), min(N(b), len(x))
    if na:
        x[:na] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    if nb:
        x[len(x) - nb:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nb) / nb)
    return x


def unit(x):
    return x / (np.abs(x).max() + 1e-12)


def peak1(x):
    return x / (np.abs(x).max() + 1e-12)


def rms(x):
    return float(np.sqrt(np.mean(x * x) + 1e-20))


def curve(n, pts):
    """A level over time from (seconds, dB) points, linear in dB between them."""
    ts, vs = zip(*pts)
    return 10 ** (np.interp(T(n), ts, vs) / 20)


def wander(n, rate, seed):
    """Smooth random movement in about -1..1, `rate` changes a second."""
    g = np.random.default_rng(seed)
    k = max(int(n / SR * rate) + 3, 4)
    w = np.interp(np.arange(n), np.linspace(0, n, k), g.uniform(-1, 1, k))
    return signal.sosfiltfilt(sos("lowpass", max(rate, 0.2), 2), w) * 1.6


def place(acc, x, at, g=1.0):
    i = N(at)
    if i >= len(acc):
        return acc
    if i < 0:
        x, i = x[-i:], 0
    m = min(len(x), len(acc) - i)
    acc[i:i + m] += x[:m] * g
    return acc


def at(n, x, t, g=1.0):
    """x put `t` seconds into a silence of n samples."""
    return place(np.zeros(n), x, t, g)


def fit(x, n):
    """x cut or padded to n samples."""
    y = np.zeros(n)
    m = min(n, len(x))
    y[:m] = x[:m]
    return y


def chain(parts, n, xf=0.25):
    """Segments joined end to end with equal-power cross-fades into n samples (a long take with no loop)."""
    k = N(xf)
    up = np.sin(0.5 * np.pi * np.arange(k) / k)
    out = np.zeros(n + N(12.0))
    pos, i = 0, 0
    while pos < n:
        p = parts[i % len(parts)].copy()
        i += 1
        if i > 1:
            p[:k] *= up
        p[-k:] *= up[::-1]
        m = min(len(p), len(out) - pos)
        out[pos:pos + m] += p[:m]
        pos += len(p) - k
    return out[:n]


def ir(length, dark, seed):
    """A ground's reverb: noise falling away, darker as it goes."""
    n = N(length)
    t = T(n)
    g = np.random.default_rng(seed)
    h = lp(g.standard_normal(n), dark) * np.exp(-t / (length / 4.5)) + 0.8 * lp(g.standard_normal(n), dark * 0.35) * np.exp(-t / (length / 2.5))
    h[:N(0.012)] = 0
    return h / np.sqrt(np.sum(h * h))


def verb(x, length, dark, wet, seed=5):
    y = signal.fftconvolve(x, ir(length, dark, seed))[:len(x)]
    return (1 - wet) * x + wet * y * (rms(x) / (rms(y) + 1e-12))


def soft_front(x, ms):
    """Transients rounded: the level may climb no faster than over `ms` milliseconds (far off, everything comes in soft)."""
    h = N(0.002)
    e = np.sqrt(np.convolve(x * x, np.ones(h) / h, "same")[::h] + 1e-12)
    a = np.exp(-2.0 / ms)
    s = np.empty_like(e)
    v = e[0]
    for i, ei in enumerate(e):
        v = v + (1 - a) * (ei - v) if ei > v else ei
        s[i] = v
    g = np.minimum(1.0, s / e)
    return x * np.interp(np.arange(len(x)), np.arange(len(g)) * h, g)


# ---- synthesis: size and sub only ----------------------------------------------------------------------------------------
def sub_thump(n, t0, f0, f1, decay, attack=0.012, seed=1):
    """A sub blow: a sine falling from f0 to f1 under a quick (never clicking) attack, a little low noise round it."""
    t = T(n)
    k = np.maximum(t - t0, 0)
    f = f1 + (f0 - f1) * np.exp(-k / 0.18)
    env = smooth((t - t0) / attack) * np.exp(-k / decay)
    noise = lp(hp(np.random.default_rng(seed).standard_normal(n), 18), 70) * 3.0
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.25 * noise) * env


def push(n, t0, decay, lo=40, hi=220, attack=0.05, seed=2):
    """The air shoved: a low push of band noise, no hiss."""
    t = T(n)
    env = smooth((t - t0) / attack) * np.exp(-np.maximum(t - t0, 0) / decay)
    return unit(bp(np.random.default_rng(seed).standard_normal(n), lo, hi, 3)) * env


def swell(n, a, b, lo=30, hi=80, seed=3):
    """A soft low swell from a to b (raised cosine)."""
    u = np.clip((T(n) - a) / (b - a), 0, 1)
    return unit(bp(np.random.default_rng(seed).standard_normal(n), lo, hi, 3)) * np.sin(np.pi * u) ** 2


# ---- tiers ---------------------------------------------------------------------------------------------------------------
# A layer's kind says what distance does to it: "sub" carries everywhere; "body" (the weight, 30-800 Hz) everywhere,
# darker and softer far off; "break" (the tearing, the blows' fronts) near and mid, far only as a soft dark low part;
# "detail" (trees, scree, grinding, water) near and mid only.
TIERS = ("near", "mid", "far")


def tier(x, which, kind):
    if which == "near":
        y = lp(hp(x, 22), 7000, 2)
        return y - 0.55 * hp(y, 3000, 2)          # (nothing bright alone above 3 kHz)
    if which == "mid":
        if kind == "sub":
            return lp(x, 400, 2)
        y = verb(lp(x, 1500 if kind == "detail" else 2000, 4), 1.1, 900, 0.3)
        return y * (0.5 if kind == "detail" else 1.0)
    if kind == "detail":
        return None
    if kind == "sub":
        return lp(x, 160, 2)
    y = verb(soft_front(lp(x, 320, 4), 60), 2.0, 300, 0.45, 9)
    return y * (0.5 if kind == "break" else 1.0)


class Event:
    """One sound event: its named layers (each a kind, the recordings it came from and a line on what it is) mixed in
    each tier it has."""

    def __init__(self, name, n, tiers=TIERS, line=""):
        self.name, self.n, self.tiers, self.line = name, n, tiers, line
        self.layers = []

    def add(self, label, kind, src, x, gain=1.0):
        self.layers.append((label, kind, src, fit(x, self.n) * gain))

    def render(self, which):
        out = np.zeros(self.n)
        parts = {}
        for label, kind, src, x in self.layers:
            y = tier(x, which, kind)
            if y is not None:
                out += y
                parts[label] = y
        return out, parts


# ---- the events ----------------------------------------------------------------------------------------------------------
def ev_blow():
    n = N(4.0)
    e = Event("blow", n, line="the blow underfoot at 0 s: a deep thud through the ground, the rumble's start")
    s = sub_thump(n, BLOW_AT, 44, 27, 1.0, seed=11) + 0.6 * swell(n, BLOW_AT, BLOW_AT + 2.2, 25, 60, seed=12)
    e.add("sub thump and pressure swell", "sub", "S", s, 0.5)
    b = lp(hp(slow(cut("R14", 0.0, 3.4), 0.8), 35), 1500)
    b = fade(b, 0.006, 0.6) * curve(len(b), [(0, 0), (0.35, 0), (2.5, -12), (4.2, -30)])
    e.add("the body: the long rumble's explosive start, slowed to 0.8, under 1.5 kHz", "body", "R14", at(n, peak1(b), BLOW_AT - 0.01), 0.35)
    return e


def tear_layers(e, n, t0, close):
    """The rip: R3's dense crashes slowed as its body, R2's whole rock breaking at the pass, R4's cracks as grain, the air
    pushed out of the fissure; loudest at `t0`, from far before it (unless close) and running away after it."""
    if close:
        lvl = [(0, -10), (t0, 0), (t0 + 0.5, -2), (t0 + 2.0, -7), (t0 + 3.6, -12), (t0 + 4.6, -22), (n / SR, -40)]
    else:
        lvl = [(0, -26), (t0 - 0.9, -12), (t0 - 0.25, -3), (t0, 0), (t0 + 0.6, -4), (t0 + 1.6, -12), (t0 + 2.8, -24), (n / SR, -40)]
    env = curve(n, lvl)
    body = hp(lp(slow(cut("R3", 6.4, 14.5), 0.65), 2700), 60)
    e.add("rock tearing: dense crashes, slowed to 0.65", "break", "R3", fade(fit(body, n), 0.05, 0.2) * env / rms(body) * 0.08)
    brk = lp(slow(cut("R2", 0.0, 1.35), 0.7), 4000)
    e.add("the heavy break as it passes: a whole rock breaking apart, slowed to 0.7", "break", "R2", at(n, peak1(fade(brk, 0.004, 0.25)), t0 - 0.12), 0.55)
    gr = lp(hp(slow(cut("R4", 2.0, 10.0), 0.75), 180, 4), 2200)
    e.add("the ground splitting: soil and stone cracks (its synth rumble cut away), slowed to 0.75", "detail", "R4", fit(gr, n) * env / rms(gr) * 0.035)
    if close:
        g1 = bp(slow(cut("R1", 0.75, 3.6), 0.6), 200, 2600, 2)
        e.add("the split forming close by: a rock crack, slowed to 0.6, 200-2600 Hz", "detail", "R1", fit(g1, n) * env / rms(g1) * 0.02)
    air = bp(np.random.default_rng(31).standard_normal(n), 60, 300, 2)
    air = 0.6 * air + 0.4 * lp(air, 140)
    e.add("air pushed out of the fissure (60-300 Hz)", "body", "S", air * env / rms(air) * 0.03)
    e.add("the ground's sub under the pass", "sub", "S", swell(n, max(t0 - 0.8, 0.0), t0 + 1.6, 28, 60, seed=32), 0.12)


def ev_tear():
    n = N(4.6)
    e = Event("tear", n, line="the crack racing out along the main fault: from far, past the player (1.6 s in), running on")
    tear_layers(e, n, TEAR_PASS, False)
    return e


def ev_tearclose():
    n = N(5.4)
    e = Event("tearclose", n, line="the crack ripping open right by the player and running away from them")
    tear_layers(e, n, TEARCLOSE_PASS, True)
    return e


def ev_rip():
    n = N(4.6)
    e = Event("rip", n, tiers=("mid", "far"), line="the crack opening round the target, heard from afar")
    env = curve(n, [(0, -30), (0.3, -4), (1.4, 0), (3.6, -3), (4.6, -30)])
    b = hp(lp(slow(cut("R3", 19.5, 26.0), 0.6), 3000), 50)
    e.add("rock tearing far off: dense crashes, slowed to 0.6", "break", "R3", fit(b, n) * env / rms(b) * 0.09)
    e.add("the ground's low tearing roll", "sub", "S", swell(n, 0.1, 4.5, 28, 70, seed=41), 0.14)
    return e


def ev_branch():
    n = N(3.8)
    e = Event("branch", n, tiers=("near", "mid"), line="the side cracks branching off and racing out round the plates")
    acc = np.zeros(n)
    for (a, b), t0, g in (((15.0, 16.5), 0.05, 1.0), ((17.3, 18.9), 1.15, 0.85), ((29.0, 30.7), 2.25, 0.7)):
        x = hp(lp(slow(cut("R3", a, b), 0.7), 2200), 60)
        x = fade(x, 0.03, 0.35) * curve(len(x), [(0, -2), (0.25, 0), (1.2, -9), (2.4, -20)])
        place(acc, x / rms(x), t0, g)
    e.add("shorter tears further out: crashes, slowed to 0.7, under 2.5 kHz", "break", "R3", acc * 0.045)
    k = hp(lp(slow(cut("R4", 5.0, 9.5), 0.75), 2500), 180, 4)
    e.add("cracks in the soil along them", "detail", "R4", fit(k, n) * curve(n, [(0, -8), (0.3, 0), (3.0, -6), (3.8, -30)]) / rms(k) * 0.02)
    return e


def r7_parts():
    """R7's slides (it stops between them), its scrape's ringing taken out (`RINGS`)."""
    out = []
    for a, b in ((9.6, 11.5), (11.8, 13.9), (14.1, 15.5), (15.8, 17.3), (19.9, 21.1), (25.4, 27.5), (29.2, 31.4), (33.9, 35.6), (38.1, 41.6)):
        out.append(fade(cut("R7", a, b), 0.08, 0.12))
    return out


def ev_swell():
    n = N(4.6)
    e = Event("swell", n, line="the land swelling (5.5-10 s): rock grinding low as the cracks shudder, the ground waves' heaves")
    t = T(n)
    g = lp(hp(chain([slow(p, 0.6) for p in r7_parts()[:5]], n, 0.3), 40), 1200)
    trains = 0.55 + 0.45 * (smooth((t - 0.3) / 0.4) * (1 - smooth((t - 1.7) / 0.4)) + smooth((t - 2.5) / 0.4))
    wave = 1 + 0.35 * np.sin(2 * np.pi * t / 0.41) ** 2 * trains
    env = curve(n, [(0, -14), (0.4, -9), (2.5, -6), (4.3, -2), (4.6, -6)]) * wave
    e.add("rock grinding on rock, low: a rock sliding, slowed to 0.6, under 1.2 kHz", "detail", "R7", g / rms(g) * env * 0.05)
    s = np.zeros(n)
    for t0, count in ((0.4, 4), (2.6, 5)):
        for k in range(count):
            a = t0 + k * 0.41
            s += swell(n, a, a + 0.62, 30, 80, seed=50 + k) * (0.6 + 0.1 * k)
    e.add("each ground wave's crest: a soft low swell (30-80 Hz)", "sub", "S", s, 0.14)
    e.add("the sub's slow heave", "sub", "S", sub_thump(n, 0.2, 32, 30, 3.0, attack=1.5, seed=51), 0.12)
    return e


def blow_layers(e, n, t0, size, hit, roll_from, seed):
    """A blow through the ground: the ground's lift first, the sub hit, a stone's body (R11, slowed), the air's push, the
    long roll after (R14)."""
    lead = 0.25 + 0.15 * size
    s = smooth((T(n) - (t0 - lead)) / lead) * (1 - smooth((T(n) - t0) / 0.08))
    e.add("the ground's lift before it", "sub", "S", unit(bp(np.random.default_rng(seed).standard_normal(n), 25, 90, 3)) * s, 0.12 * size)
    e.add("the sub hit", "sub", "S", sub_thump(n, t0, 52 + 8 * size, 23, 0.9 + 1.0 * size, seed=seed + 1), 0.5)
    b = fade(lp(hp(slow(cut("R11", hit - 0.05, hit + 1.75), 0.62 - 0.07 * size), 40), 2600), 0.004, 0.5)
    e.add("the stone's body: heavy stone onto stone, slowed", "break", "R11", at(n, peak1(b), t0 - 0.03), 0.6)
    e.add("the air's push", "body", "S", push(n, t0 + 0.1, 0.3 + 0.2 * size, seed=seed + 2), 0.18 + 0.08 * size)
    r = lp(hp(slow(cut("R14", roll_from, roll_from + 6.0), 0.7), 30), 600)
    r = r / rms(r) * curve(len(r), [(0, -40), (0.25, -6), (0.6, 0), (2.0, -6), (5.0, -20), (8.5, -40)])
    e.add("the long roll after: the long rumble, slowed to 0.7, under 600 Hz", "body", "R14", at(n, r, t0 + 0.05), 0.06 * size)


def ev_heaveblow():
    n = N(7.0)
    e = Event("heaveblow", n, line="the first heave's blow through the ground (10 s), the air's push, the long roll")
    blow_layers(e, n, HEAVEBLOW_AT, 1.0, 0.2, 3.0, 60)
    return e


def ev_heave():
    n = N(4.2)
    e = Event("heave", n, line="the first heave in the air: one big rip across the fault, the up side's short heavy grind")
    rip = hp(lp(slow(cut("R3", 11.9, 13.8), 0.7), 3500), 50)
    rip = fade(rip, 0.005, 0.6) * curve(len(rip), [(0, 0), (0.6, -2), (1.6, -10), (2.7, -22)])
    e.add("one big rip across the fault: crashes, slowed to 0.7", "break", "R3", at(n, peak1(rip), HEAVE_AT), 0.6)
    gr = fade(lp(hp(slow(cut("R5", 4.98, 5.78), 0.85), 40), 3000), 0.004, 0.15)
    e.add("the up side jumping: a short heavy grind (a stone slab, slowed to 0.85, 0.9 s)", "detail", "R5", at(n, peak1(gr), HEAVE_AT + 0.02), 0.5)
    cr = hp(lp(slow(cut("R3", 16.2, 17.4), 0.7), 3000), 60)
    e.add("a second crash in the rip", "break", "R3", at(n, peak1(fade(cr, 0.01, 0.4)), HEAVE_AT + 0.45), 0.3)
    return e


def ev_trees():
    n = N(4.8)
    e = Event("trees", n, tiers=("near", "mid"), line="trees going over near the fault (the split and the crash, never the creak)")
    a = lp(hp(slow(cut("R16", 2.55, 3.35), 0.85), 50), 4000)
    e.add("a trunk splitting: splintering, slowed to 0.85", "detail", "R16", at(n, peak1(fade(a, 0.004, 0.2)), 0.0), 0.35)
    b = lp(hp(slow(cut("R16", 6.8, 8.9), 0.85), 40), 3500)
    e.add("its crash onto the ground", "detail", "R16", at(n, peak1(fade(b, 0.004, 0.4)), 1.2), 0.45)
    c = lp(hp(slow(cut("R15", 4.3, 7.6), 0.9), 35), 3500)
    e.add("a big conifer's fall and its thud (the fall only)", "detail", "R15", at(n, peak1(fade(c, 0.05, 0.6)), 0.55), 0.5)
    return e


def ev_grind(k):
    long = (1.4, 1.5, 1.3, 3.4)[k - 1]
    n = N(long + 1.0)
    e = Event(f"grind{k}", n, tiers=("near", "mid"), line=f"lurch {k}: rock grinding on rock, {long:g} s, a hard start, stopping dead"
              + (" (runs on into the build)" if k == 4 else ""))
    parts = {
        1: [("R5", 10.05, 12.1, 0.75, 1.0, GRIND_AT), ("R8", 7.9, 9.0, 0.55, 0.5, GRIND_AT)],
        2: [("R6", 5.65, 7.5, 0.7, 1.0, GRIND_AT), ("R8", 1.2, 2.3, 0.55, 0.45, GRIND_AT)],
        3: [("R5", 0.9, 2.4, 0.7, 1.0, GRIND_AT), ("R6", 0.75, 1.7, 0.7, 0.6, GRIND_AT + 0.05)],
        4: [("R8", 3.0, 4.95, 0.5, 0.7, GRIND_AT), ("R6", 2.25, 3.9, 0.65, 1.0, GRIND_AT), ("R6", 6.3, 8.4, 0.7, 0.8, GRIND_AT + 1.6)],
    }[k]
    stop = GRIND_AT + long
    env = curve(n, [(0, 0), (GRIND_AT, 0), (GRIND_AT + 0.12, 2), (stop * 0.6, -1), (stop - 0.05, 0), (stop + 0.06, -34), (n / SR, -60)])
    for r, a, b, kk, g, t0 in parts:
        x = fade(lp(hp(slow(cut(r, a, b), kk), 40), 3000), 0.003, 0.05)
        e.add(f"rock grinding on rock: {REC[r][1]}, slowed to {kk:g}", "detail", r, at(n, x / rms(x), t0) * env, 0.05 * g)
    e.add("the rock's ring as it stops", "body", "S", push(n, stop - 0.05, 0.35, 50, 260, attack=0.02, seed=70 + k), 0.05)
    if k == 4:
        g = lp(chain([slow(p, 0.6) for p in r7_parts()[5:]], n, 0.3), 1200)
        e.add("the long grind under it: a rock sliding, slowed to 0.6", "detail", "R7", g / rms(g) * curve(n, [(0, -14), (long, -6), (long + 0.4, -40)]) * 0.04)
    return e


def ev_knock():
    n = N(4.0)
    e = Event("knock", n, line="a lurch's body blow through the ground (its volume by the lurch's share)")
    t = T(n)
    s = smooth((t - (KNOCK_AT - 0.15)) / 0.15) * (1 - smooth((t - KNOCK_AT) / 0.08))
    e.add("the ground's lift", "sub", "S", unit(bp(np.random.default_rng(80).standard_normal(n), 25, 90, 3)) * s, 0.08)
    e.add("the sub hit", "sub", "S", sub_thump(n, KNOCK_AT, 50, 27, 0.9, seed=81), 0.42)
    b = fade(lp(hp(slow(cut("R11", 4.5, 6.4), 0.68), 40), 2400), 0.004, 0.5)
    e.add("the stone's body: heavy stone onto stone, slowed to 0.68", "break", "R11", at(n, peak1(b), KNOCK_AT - 0.03), 0.45)
    r = lp(slow(cut("R14", 12.0, 16.0), 0.7), 500)
    e.add("a short roll", "body", "R14", at(n, r / rms(r) * curve(len(r), [(0, -40), (0.2, 0), (1.5, -8), (3.5, -30)]), KNOCK_AT), 0.035)
    return e


def ev_fall(k):
    n = N(3.6)
    e = Event(f"fall{k}", n, tiers=("near", "mid"), line=f"rock coming off the cliff ({['after the second lurch', 'after the third lurch', 'in the build'][k - 1]}): heavy falls, not a rattle")
    hits = {1: [(6.6, 0.0, 1.0), (2.55, 0.7, 0.6)], 2: [(8.55, 0.0, 1.0), (4.5, 0.55, 0.55)], 3: [(2.55, 0.0, 0.8)]}[k]
    rolls = {1: (28.7, 30.4), 2: (4.45, 6.2), 3: (0.45, 2.2)}[k]
    acc = np.zeros(n)
    for h, t0, g in hits:
        x = fade(lp(hp(slow(cut("R11", h - 0.05, h + 1.6), 0.7), 45), 2500), 0.004, 0.5)
        place(acc, peak1(x), 0.05 + t0, g)
    e.add("each boulder's landing: heavy stone onto stone, slowed to 0.7", "detail", "R11", acc, 0.45)
    r = lp(hp(slow(cut("R10", *rolls), 0.8), 50), 2200)
    r = fade(r, 0.05, 0.5) * curve(len(r), [(0, -6), (0.3, 0), (1.5, -6), (2.4, -20)])
    e.add("the rock tumbling behind them: boulders crashing down, slowed to 0.8", "detail", "R10", at(n, r / rms(r), 0.1), 0.05)
    e.add("their weight in the ground", "sub", "S", sub_thump(n, 0.05, 40, 28, 0.6, seed=90 + k), 0.18)
    return e


def ev_build():
    n = N(BUILD_LEN + 0.2)
    e = Event("build", n, line="the build (23.5-27.5 s): the grind rising, heavier and heavier, into the climax")
    t = T(n)
    g = hp(chain([slow(p, 0.55) for p in r7_parts()[2:8]], n, 0.3), 40)
    u = smooth(t / BUILD_LEN)
    g = (1 - u) * lp(g, 700) + u * lp(g, 1500)
    env = curve(n, [(0, -14), (1.5, -9), (3.0, -4), (BUILD_LEN - 0.05, 0), (BUILD_LEN + 0.2, -30)])
    e.add("rock grinding, rising: a rock sliding, slowed to 0.55, its top opening from 700 Hz to 1.5 kHz", "detail", "R7", g / rms(g) * env * 0.06)
    m = lp(hp(slow(cut("R5", 5.2, 9.0), 0.8), 35), 2000)
    e.add("the slab's weight under it: a stone slab grinding, slowed to 0.8", "body", "R5", fit(m, n) / rms(m) * env * 0.04)
    f = fade(lp(slow(cut("R10", 12.0, 13.6), 0.8), 2200), 0.05, 0.4)
    e.add("a small cliff fall in it", "detail", "R10", at(n, f / rms(f), 1.2), 0.02)
    e.add("the ground's strain, climbing", "sub", "S", sub_thump(n, 0.0, 34, 30, 50.0, attack=BUILD_LEN, seed=95) * (1 - smooth((t - BUILD_LEN + 0.02) / 0.1)), 0.15)
    return e


def ev_climaxblow():
    n = N(9.0)
    e = Event("climaxblow", n, line="THE CLIMAX's blow through the ground (27.5 s): the biggest sub, the stone's body, the air's push, the longest roll")
    blow_layers(e, n, CLIMAXBLOW_AT, 1.6, 6.65, 5.0, 100)
    b = lp(hp(slow(cut("R14", 0.0, 2.6), 0.6), 35), 1200)
    e.add("the long rumble's explosive start under it, slowed to 0.6", "body", "R14", at(n, peak1(fade(b, 0.005, 2.2)), CLIMAXBLOW_AT - 0.02), 0.3)
    r = lp(slow(cut("R13", 10.0, 22.0), 0.8), 400)
    e.add("the ground rolling on: the earthquake rumble, slowed to 0.8", "body", "R13",
          at(n, r / rms(r) * curve(len(r), [(0, -40), (0.5, -3), (1.5, 0), (4.0, -8), (8.5, -40)]), CLIMAXBLOW_AT), 0.05)
    return e


def ev_climax():
    n = N(7.0)
    stop = CLIMAX_AT + (REST - CLIMAX)
    e = Event("climax", n, line="THE CLIMAX in the air: rock tearing across the whole fault, the cliff's thrust grinding on to rest (stopping dead 3.5 s in), a cliff face letting go, trees going over")
    tear = hp(lp(slow(cut("R3", 6.4, 10.8), 0.6), 3500), 50)
    tear = fade(tear, 0.005, 0.3) * curve(len(tear), [(0, 0), (0.8, -1), (2.2, -6), (3.5, -12), (5.5, -26), (7.3, -40)])
    e.add("rock tearing across the whole fault: crashes, slowed to 0.6", "break", "R3", at(n, tear / rms(tear[:N(1.5)]), CLIMAX_AT), 0.11)
    br = lp(slow(cut("R2", 0.0, 1.35), 0.6), 4000)
    e.add("the rock breaking open on the moment: a rock breaking apart, slowed to 0.6", "break", "R2", at(n, peak1(fade(br, 0.004, 0.3)), CLIMAX_AT - 0.01), 0.55)
    env = curve(n, [(0, -40), (CLIMAX_AT, -3), (CLIMAX_AT + 0.15, 0), (CLIMAX_AT + CLIMAX_LONG, -2), (stop - 0.05, -5), (stop + 0.04, -45), (n / SR, -70)])
    th = lp(hp(slow(cut("R5", 5.0, 8.4), 0.75), 35), 2600)
    e.add("the cliff's thrust: a stone slab grinding, slowed to 0.75", "detail", "R5", at(n, fade(th, 0.003, 0.05) / rms(th), CLIMAX_AT) * env, 0.075)
    r7 = lp(chain([slow(p, 0.6) for p in r7_parts()[::2]], n, 0.3), 1300)
    e.add("rock sliding under it, slowed to 0.6", "detail", "R7", r7 / rms(r7) * env, 0.045)
    r6 = lp(hp(slow(cut("R6", 5.65, 8.5), 0.7), 40), 2500)
    e.add("a slab dragged in it, slowed to 0.7", "detail", "R6", at(n, fade(r6, 0.003, 0.05) / rms(r6), CLIMAX_AT + 0.3) * env, 0.04)
    cf = lp(hp(slow(cut("R9", 8.6, 13.0), 0.85), 45), 3500)
    cf = fade(cf, 0.02, 0.8) * curve(len(cf), [(0, -4), (0.4, 0), (2.0, -4), (4.5, -18), (5.2, -40)])
    e.add("a cliff face letting go 0.9 s on: boulders crashing explosively, slowed to 0.85", "break", "R9", at(n, cf / rms(cf[:N(2.0)]), CLIMAX_AT + 0.9), 0.07)
    tr = lp(hp(cut("R17", 33.0, 37.2), 50), 3500)
    e.add("trees going over in a wave: a large tree's rush and crash", "detail", "R17", at(n, fade(tr, 0.3, 0.5) / rms(tr), CLIMAX_AT + 1.1), 0.035)
    t2 = lp(hp(slow(cut("R15", 4.3, 7.6), 0.9), 35), 3500)
    e.add("a big conifer's fall in it", "detail", "R15", at(n, peak1(fade(t2, 0.05, 0.6)), CLIMAX_AT + 2.0), 0.3)
    return e


def ev_settle():
    n = N(3.0)
    e = Event("settle", n, line="rest (31 s): one soft last settle through the ground")
    e.add("a soft sub thump", "sub", "S", sub_thump(n, SETTLE_AT, 36, 26, 1.0, attack=0.06, seed=110), 0.3)
    r = fit(lp(slow(cut("R13", 30.0, 32.5), 0.8), 300), n)
    e.add("the ground's last roll", "body", "R13", r / rms(r) * curve(n, [(0, -40), (SETTLE_AT + 0.1, -2), (1.0, 0), (2.8, -30), (3.0, -40)]), 0.04)
    return e


def ev_slide(k):
    n = N(4.2)
    e = Event(f"slide{k}", n, tiers=("near", "mid"), line=f"aftermath {k}: scree and boulders sliding off a scarp, a dense heavy mass ending with the slide")
    x = lp(hp(slow(cut("R12", *{1: (5.3, 9.0), 2: (13.0, 16.0), 3: (33.2, 36.4), 4: (48.4, 51.2)}[k]), 0.8), 45), 2200)
    ln = len(x) / SR
    x = fade(x, 0.05, 0.35) * curve(len(x), [(0, -8), (0.25, 0), (ln * 0.6, -2), (ln, -10)])
    e.add("the slide: a landslide, slowed to 0.8, under 2.2 kHz", "detail", "R12", at(n, x / rms(x), 0.05), 0.06)
    h0 = (6.6, 8.55, 4.5, 2.55)[k - 1]
    h = fade(lp(hp(slow(cut("R11", h0 - 0.05, h0 + 1.6), 0.72), 45), 2400), 0.004, 0.5)
    e.add("a boulder's landing at its foot", "detail", "R11", at(n, peak1(h), 0.4 + 0.25 * k), 0.3)
    if k <= 2:
        r = lp(slow(cut("R10", 21.5, 24.5), 0.8), 2000)
        e.add("rock tumbling down the cliff", "detail", "R10", at(n, fade(r, 0.1, 0.5) / rms(r), 0.3), 0.03)
    e.add("its weight in the ground", "sub", "S", swell(n, 0.0, 2.6, 30, 70, seed=120 + k), 0.1)
    return e


def ev_pour():
    n = N(16.5)
    e = Event("pour", n, tiers=("near", "mid"), line="water pouring into the canyon (33 s to the end): the waterfall's low roar only, never a flat wash")
    x = lp(bp(cut("R18", 0.5, 17.0), 80, 1000, 3), 900, 4)
    x = fit(x, n)
    lvl = curve(n, [(0, -30), (1.5, -8), (4.0, 0), (7.0, -3), (11.0, -7), (16.0, -9), (16.5, -40)])
    mv = 10 ** ((4.0 * wander(n, 0.3, 130) + 1.5 * wander(n, 1.1, 131)) / 20)
    e.add("the waterfall's low roar (80-1000 Hz), swelling in and falling to a steady low pour", "detail", "R18", x / rms(x) * lvl * mv, 0.04)
    return e


def ev_bed():
    n = N(49.4)
    e = Event("bed", n, line="the rumble bed under the whole strike: only ever climbing to the climax, falling away from rest")
    t = T(n)
    pts = [(0, -60), (0.05, -60), (0.3, -9), (WARP, -7.5), (HEAVE - 0.05, -6.5), (HEAVE + 0.4, -5.0)]
    lvl = -5.0
    for lt in LURCH:
        pts += [(lt + 0.1, lvl), (lt + 0.6, lvl + 0.7)]
        lvl += 0.7
    pts += [(CLIMAX - 0.05, -1.0), (CLIMAX + 0.3, 0), (REST - 0.2, -0.5), (REST + 1.0, -5), (REST + 4.0, -11), (40.0, -15), (46.0, -19), (49.4, -40)]
    level = curve(n, pts)
    # (the ground waves 5.5-11: their swells only add, never dip; the tremors after rest)
    waves = np.zeros(n)
    for t0 in (WARP + 0.65, 7.7 + 0.65):
        waves += np.sin(np.pi * np.clip((t - t0) / 1.6, 0, 1)) * np.sin(np.pi * np.maximum(t - t0, 0) / 0.41) ** 2
    for tr in TREMORS:
        waves += 1.4 * np.sin(np.pi * np.clip((t - tr) / 1.6, 0, 1)) ** 2
    level = level * (1 + 0.45 * waves)
    r = fit(lp(hp(slow(cut("R13", 3.1, 3.1 + 49.4 * 0.9 + 0.5), 0.9), 22), 520), n)
    e.add("the earthquake rumble, slowed to 0.9", "body", "R13", r / rms(r) * level * 0.07)
    # (the drone under it: the strain climbing 2.5 semitones through the build, falling back after)
    k = smooth((t - 24.0) / (CLIMAX - 24.0)) * (1 - smooth((t - REST) / 3.0))
    f = 30.0 * 2 ** (2.5 * k / 12) * (1 + 0.05 * wander(n, 0.5, 140))
    d = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR + 1.0)
    low = lp(hp(np.random.default_rng(141).standard_normal(n), 20), 60)
    e.add("the sub drone under it", "sub", "S", (d / 1.5 * 0.7 + low / rms(low) * 0.3) * level * (0.85 + 0.15 * wander(n, 1.3, 142)), 0.09)
    return e


def events():
    out = [ev_bed(), ev_blow(), ev_tear(), ev_tearclose(), ev_rip(), ev_branch(), ev_swell(), ev_heaveblow(), ev_heave(), ev_trees()]
    out += [ev_grind(k) for k in range(1, 5)] + [ev_knock()] + [ev_fall(k) for k in range(1, 4)]
    out += [ev_build(), ev_climaxblow(), ev_climax(), ev_settle()] + [ev_slide(k) for k in range(1, 5)] + [ev_pour()]
    return out


# Each file's peak (dBFS) in its first tier: the climax's the loudest. The other tiers sit 1 dB (mid) and 3 dB (far)
# under it by RMS. A trim over all of them keeps the loudest mix's peak at -1.5 dBFS.
LEVEL = {"bed": -7.0, "blow": -9.0, "tear": -6.0, "tearclose": -6.0, "rip": -12.0, "branch": -8.0, "swell": -8.0,
         "heaveblow": -6.5, "heave": -7.5, "trees": -11.0, "grind1": -9.0, "grind2": -9.0, "grind3": -9.5, "grind4": -9.0,
         "knock": -9.0, "fall1": -10.0, "fall2": -10.0, "fall3": -12.0, "build": -7.5, "climaxblow": -2.0, "climax": -3.0,
         "settle": -13.0, "slide1": -11.0, "slide2": -12.0, "slide3": -13.0, "slide4": -14.0, "pour": -15.0}
MID_DB, FAR_DB = -1.0, -3.0
# The blows rounded by a soft saturation (dB of drive): their sub's first peak no longer sets the strike's level.
SOFT = {"climaxblow": 6.0, "heaveblow": 4.0, "climax": 3.0}


def soft(x, drive_db):
    """A soft saturation, the peak kept where it was."""
    k = 10 ** (drive_db / 20) / (np.abs(x).max() + 1e-12)
    y = np.tanh(k * x)
    return y * (np.abs(x).max() / (np.abs(y).max() + 1e-12))


def build():
    """Every file (name -> samples) and the events (for the page)."""
    files, evs = {}, events()
    for e in evs:
        ref = None
        for tr in e.tiers:
            x, _ = e.render(tr)
            if ref is None:
                x = x * (10 ** (LEVEL[e.name] / 20) / (np.abs(x).max() + 1e-12))
                ref = rms(x)
            else:
                x = x * (ref * 10 ** ((MID_DB if tr == "mid" else FAR_DB) / 20) / (rms(x) + 1e-12))
            if e.name in SOFT:
                x = soft(x, SOFT[e.name])
            files[f"{e.name}_{tr}"] = fade(x, 0.005, 0.03)
    return files, evs


# ---- the cue model (strike/eq_sounds.rs: keep in step) -------------------------------------------------------------------
def weights(d):
    """(near, mid, far) at `d` blocks: near to mid over 60-160, mid to far over 350-650, equal power."""
    x = float(smooth((d - 60) / 100)) * np.pi / 2
    y = float(smooth((d - 350) / 300)) * np.pi / 2
    return {"near": np.cos(x), "mid": np.sin(x) * np.cos(y), "far": np.sin(x) * np.sin(y)}


def gain(d):
    """The whole strike's fall with distance (the tiers do the darkening)."""
    return float(np.clip(1.0 / (1.0 + max(d - 60.0, 0.0) / 500.0), 0.3, 1.0))


class Listener:
    """A player as the game places them: `dz` from the fault in the zone, `dc` from the crack where it passes them, `dt`
    from the target, the crack passing them at `tp` (the strike's `arrive`)."""

    def __init__(self, dz, dc=30.0, dt=None, u=None, terrain=True):
        self.dz, self.dc, self.terrain = dz, dc, terrain
        self.dt = dt if dt is not None else dz + (CAP + 1.0) * REACH
        u = u if u is not None else self.dt
        self.u = u
        uz = (CAP + 1.07) * REACH
        end = max(u + PAST, uz)
        v = max(CRACK_V, 2.6 * REACH / (CRACK_BY - 0.3 - CRACK))
        if u > uz:
            tz = CRACK + uz / v
            v2 = max(v, (end - uz) / (CRACK_BY - 0.3 - tz))
            self.tp = min(tz + (u - uz) / v2, CRACK_BY - 0.3)
        else:
            self.tp = CRACK + u / v


def cues(L, files=None):
    """(start on the strike clock, file, volume) as eq_sounds plays them for listener L."""
    out = []
    gl, al = L.dz / GROUND_V, L.dz / AIR_V
    wz, gz = weights(L.dz), gain(L.dz)
    wc, gc = weights(L.dc), gain(L.dc)
    wt, gt = weights(L.dt), gain(L.dt)

    def play(t, base, vol, w, g):
        for tr in TIERS:
            v = vol * w[tr] * g
            if v > 0.002 and (files is None or f"{base}_{tr}" in files) and (files is not None or tr in HAS.get(base, TIERS)):
                out.append((max(t, 0.0), f"{base}_{tr}", min(v, 1.0)))
    play(gl, "bed", 1.0, wz, gz)
    play(gl, "blow", 1.0, wz, gz)
    heard = L.tp + L.dc / AIR_V
    tv = max(1.0 / (1.0 + max(L.u - (CAP + 1.07) * REACH, 0.0) / 250.0), 0.35)
    if heard - TEAR_PASS >= CRACK - 0.1:
        play(heard - TEAR_PASS, "tear", tv, wc, gc)
    else:
        play(max(heard - TEARCLOSE_PASS, CRACK - 0.05), "tearclose", tv, wc, gc)
    if L.dt > RIP_FROM:
        play(CRACK + L.dt / AIR_V, "rip", 0.8, wt, gt)
    play(CRACK + SEG * REACH / CRACK_V + al, "branch", 0.9, wz, gz)
    play(WARP + gl, "swell", 1.0, wz, gz)
    play(HEAVE - HEAVEBLOW_AT + gl, "heaveblow", 1.0, wz, gz)
    play(HEAVE - HEAVE_AT + al, "heave", 1.0, wz, gz)
    play(HEAVE + TREES_AFTER + al, "trees", 1.0, wz, gz)
    for k, (lt, sh) in enumerate(zip(LURCH, SHARE), 1):
        play(lt - GRIND_AT + al, f"grind{k}", 1.0, wz, gz)
        play(lt - KNOCK_AT + gl, "knock", 0.55 + 3.0 * sh, wz, gz)
    for i, (k, after) in enumerate(FALLS, 1):
        play(LURCH[k - 1] + after + al, f"fall{i}", 1.0, wz, gz)
    play(CLIMAX - FALL3_BEFORE + al, "fall3", 0.8, wz, gz)
    play(CLIMAX - BUILD_LEN + al, "build", 1.0, wz, gz)
    play(CLIMAX - CLIMAXBLOW_AT + gl, "climaxblow", 1.0, wz, gz)
    play(CLIMAX - CLIMAX_AT + al, "climax", 1.0, wz, gz)
    play(REST - SETTLE_AT + gl, "settle", 1.0, wz, gz)
    for k, (t, v) in enumerate(SLIDES if L.terrain else SLIDES[:2], 1):
        play(t + al, f"slide{k}", v, wz, gz)
    if L.terrain:
        play(POUR_T + al, "pour", 1.0, wz, gz)
    else:
        for k, t in zip((2, 3), BACK):
            play(t - GRIND_AT + al, f"grind{k}", 0.7, wz, gz)
    return sorted(out)


# The tiers each event has (strike/eq_sounds.rs's `tiers`).
NM = ("near", "mid")
HAS = {"rip": ("mid", "far"), "branch": NM, "trees": NM, "grind1": NM, "grind2": NM, "grind3": NM, "grind4": NM,
       "fall1": NM, "fall2": NM, "fall3": NM, "slide1": NM, "slide2": NM, "slide3": NM, "slide4": NM, "pour": NM}
LISTENERS = {"plate_40": Listener(40.0, dc=17.0, dt=60.0, u=50.0), "blocks_250": Listener(250.0), "blocks_800": Listener(800.0)}


def mix(files, cl, length=END + 3.0, parts=False):
    acc = np.zeros(N(length))
    layers = {}
    for t0, f, v in cl:
        place(acc, files[f] * v, t0)
        if parts:
            place(layers.setdefault(f.rsplit("_", 1)[0].rstrip("1234"), np.zeros(len(acc))), files[f] * v, t0)
    return (acc, layers) if parts else acc


def short_term(x, win=0.4, hop=0.05):
    w, h = N(win), N(hop)
    p = np.convolve(x * x, np.ones(w) / w, "valid")[::h]
    return np.arange(len(p)) * hop + win / 2, 10 * np.log10(p + 1e-12)


def facts(files, L):
    """The numbers the checks hold the mix to, for listener L."""
    x = mix(files, cues(L, files))
    ts, db = short_term(x)
    hit = CLIMAX + L.dz / GROUND_V
    pre = (ts >= hit - 2.0) & (ts < hit - 0.2)
    run = np.maximum.accumulate(np.where(pre, db, -200))
    win = (ts >= hit - 0.1) & (ts < hit + 3.5)
    top = int(np.argmax(db))
    return {"climax_st": float(db[win].max()), "loudest_at": float(ts[top]), "before_st": float(db[ts < hit - 0.2].max()),
            "dip_2s": float(np.max((run - db)[pre])), "last2_min": float(db[pre].min()),
            "peak": float(20 * np.log10(np.abs(x).max() + 1e-12)), "hit": hit}, x


# ---- output --------------------------------------------------------------------------------------------------------------
def write_wav(path, x):
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


COL = {"bed": (110, 110, 110), "blow": (40, 40, 40), "tear": (190, 90, 30), "tearclose": (190, 90, 30), "rip": (200, 140, 60),
       "branch": (160, 120, 60), "swell": (60, 140, 60), "heaveblow": (120, 0, 0), "heave": (220, 40, 40), "trees": (30, 150, 30),
       "grind": (80, 80, 160), "knock": (140, 40, 140), "fall": (150, 150, 60), "build": (40, 120, 200),
       "climaxblow": (255, 0, 120), "climax": (255, 90, 0), "settle": (90, 90, 90), "slide": (130, 100, 70), "pour": (30, 120, 220)}


def picture(files, L, name, path):
    from PIL import Image, ImageDraw
    f, x = facts(files, L)
    _, layers = mix(files, cues(L, files), parts=True)
    img = Image.new("RGB", (1600, 640), (250, 250, 248))
    d = ImageDraw.Draw(img)
    L0, TOP, R, B, t1, lo, hi = 70, 80, 1580, 590, END + 2.0, -60.0, 0.0

    def X(v):
        return L0 + (R - L0) * v / t1

    def Y(v):
        return TOP + (B - TOP) * (hi - np.clip(v, lo, hi)) / (hi - lo)
    beats = [(0, CRACK, "blow"), (CRACK, WARP, "crack"), (WARP, HEAVE, "swell"), (HEAVE, LURCH[3], "heave, lurches"),
             (LURCH[3], CLIMAX, "build"), (CLIMAX, REST, "CLIMAX"), (REST, END, "aftermath")]
    for i, (a, b, nm) in enumerate(beats):
        d.rectangle([X(a), TOP, X(b), B], fill=(240, 238, 232) if i % 2 else (246, 245, 240))
        d.text((X(a) + 4, TOP + 4), nm, fill=(90, 90, 90))
    for v in range(int(lo), int(hi) + 1, 10):
        d.line([L0, Y(v), R, Y(v)], fill=(215, 215, 210))
        d.text((L0 - 50, Y(v) - 6), f"{v} dB", fill=(90, 90, 90))
    for s in range(0, int(t1) + 1, 2):
        d.text((X(s) - 6, B + 4), f"{s}", fill=(90, 90, 90))
    for k, y in layers.items():
        tt, dd = short_term(y)
        d.line([(X(a), Y(b)) for a, b in zip(tt, dd) if a <= t1], fill=COL.get(k, (0, 0, 200)), width=1)
    ts, db = short_term(x)
    d.line([(X(a), Y(b)) for a, b in zip(ts, db) if a <= t1], fill=(0, 0, 0), width=3)
    d.text((L0, 12), f"{name}: the whole strike as the game mixes it (400 ms windows; black the mix). Climax {f['climax_st']:.1f} dB; "
                     f"loudest before it {f['before_st']:.1f} dB; largest dip in the 2 s before it {f['dip_2s']:.1f} dB; mix peak {f['peak']:.2f} dBFS.", fill=(0, 0, 0))
    x0 = L0
    for k, c in COL.items():
        d.rectangle([x0, 34, x0 + 14, 44], fill=c)
        d.text((x0 + 18, 33), k, fill=(40, 40, 40))
        x0 += 78
    img.save(path)


def checks(files, evs, out_dir):
    ok = True
    print("== checks")
    others = {hashlib.sha256(p.read_bytes()).hexdigest(): p for p in (ROOT / "orbital-sounds").rglob("*.ogg") if f"/sounds/{TH}/" not in str(p)}
    shared = [nm for nm in files if hashlib.sha256((out_dir / f"{nm}.ogg").read_bytes()).hexdigest() in others]
    print(f"{'OK  ' if not shared else 'FAIL'} no file shared with another laser (sha256 against {len(others)} files){'' if not shared else ': ' + str(shared)}")
    ok &= not shared
    hot = [(nm, round(20 * np.log10(np.abs(x).max()), 2)) for nm, x in files.items() if np.abs(x).max() > 10 ** (-1 / 20)]
    print(f"{'OK  ' if not hot else 'FAIL'} every file's peak under -1 dBFS (the highest {max(20 * np.log10(np.abs(x).max()) for x in files.values()):.2f}){'' if not hot else ': ' + str(hot)}")
    ok &= not hot
    for name, L in LISTENERS.items():
        for terrain in (True, False):
            L.terrain = terrain
            f, _ = facts(files, L)
            good = (f["climax_st"] >= f["before_st"] and CLIMAX - 0.2 <= f["loudest_at"] <= CLIMAX + 4.0 + L.dz / AIR_V
                    and f["dip_2s"] <= 10.0 and f["peak"] < -1.0)
            print(f"{'OK  ' if good else 'FAIL'} {name} terrain {'on ' if terrain else 'off'}: climax {f['climax_st']:.1f} dB, loudest before it "
                  f"{f['before_st']:.1f} dB, loudest window at {f['loudest_at']:.2f} s; largest dip in the 2 s before it {f['dip_2s']:.1f} dB "
                  f"(lowest {f['last2_min']:.1f}); mix peak {f['peak']:.2f} dBFS")
            ok &= good
        L.terrain = True
    for e in evs:
        heard = set()
        for d in (20, 100, 250, 500, 800, 1200):
            for _, f, _ in cues(Listener(d), files):
                if f.rsplit("_", 1)[0] == e.name:
                    heard.add(f.rsplit("_", 1)[1])
        missing = [tr for tr in TIERS if tr not in e.tiers]
        good = heard <= set(e.tiers) and set(e.tiers) == set(HAS.get(e.name, TIERS))
        ok &= good
        print(f"{'OK  ' if good else 'FAIL'} tiers {e.name}: files {', '.join(e.tiers)}; cued {', '.join(sorted(heard))}"
              + (f" (no {', '.join(missing)}: not heard there, by design)" if missing else ""))
    hs = []
    for nm, x in files.items():
        if nm.endswith("_near"):
            F = np.abs(np.fft.rfft(x)) ** 2
            fr = np.fft.rfftfreq(len(x), 1 / SR)
            hs.append((float(F[fr > 2000].sum() / (F.sum() + 1e-12)), nm))
    hs.sort(reverse=True)
    print("energy above 2 kHz, near files (a warning past 0.3%: listen first): " + ", ".join(f"{nm} {100 * s:.2f}%" for s, nm in hs[:10]))
    print("== " + ("all checks OK" if ok else "SOME CHECKS FAILED"))
    return ok


def layer_table(evs):
    rows = []
    for e in evs:
        for label, kind, src, _ in e.layers:
            who = "synthesized" if src == "S" else f"{src} \"{REC[src][1]}\" by {REC[src][2]} (https://freesound.org/s/{REC[src][3]}/)"
            rows.append(f"{e.name:11s} {kind:6s} {label}: {who}")
    return rows


def page(files, evs, out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.wav"):
        old.unlink()
    rows = ["Each clip's peak is at -1 dBFS for listening (the levels within a clip are as in the game). Mono, 44.1 kHz.", ""]

    def put(name, x, line):
        write_wav(out / f"{name}.wav", x * (10 ** (-1 / 20) / (np.abs(x).max() + 1e-12)))
        rows.append(f"{name}.wav: {line}")
    for name, L in LISTENERS.items():
        put(f"whole_{name}", mix(files, cues(L, files)), f"the whole strike as the game mixes it, {name.replace('_', ' ')}")
    x = mix(files, cues(LISTENERS["plate_40"], files))
    put("moment_crack_0_to_6s_plate_40", x[:N(6.0)], "0-6 s on the plate: the blow underfoot, the crack ripping out")
    put("moment_climax_24_to_33s_plate_40", x[N(24.0):N(33.0)], "24-33 s on the plate: the build, the climax, rest")
    rows.append("")
    for e in evs:
        for tr in e.tiers:
            put(f"event_{e.name}_{tr}", files[f"{e.name}_{tr}"], f"{e.line} ({tr})")
    rows.append("")
    for e in evs:
        _, parts = e.render(e.tiers[0])
        for i, (label, kind, src, _) in enumerate(e.layers, 1):
            if label in parts and np.abs(parts[label]).max() > 0:
                put(f"layer_{e.name}_{i}", parts[label], f"{e.name}, layer {i} ({src}): {label}")
    rows += ["", "Which recording each layer comes from:"] + layer_table(evs)
    (out / "LIST.txt").write_text("\n".join(rows) + "\n")


SUBTITLE = {"bed": "The ground rumbles", "blow": "The ground jolts", "tear": "The ground tears open", "tearclose": "The ground tears open",
            "rip": "The ground tears open", "branch": "The ground cracks", "swell": "The ground heaves", "heaveblow": "The ground lurches",
            "heave": "Rock tears", "trees": "Trees fall", "grind": "Rock grinds", "knock": "The ground jolts", "fall": "Rock falls",
            "build": "Rock grinds", "climaxblow": "The ground heaves", "climax": "The cliff thrusts up", "settle": "The ground settles",
            "slide": "Rock slides", "pour": "Water pours"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--src", help="the recordings (default: EQ_SOUND_SRC)")
    ap.add_argument("--listen", help="write the whole strike mixed as the game does from 40, 250 and 800 blocks here (WAV, PNG)")
    ap.add_argument("--page", help="write each event and each layer alone (WAV) and LIST.txt here")
    ap.add_argument("--check", action="store_true", help="run the checks")
    a = ap.parse_args()
    global SRC
    if a.src:
        SRC = Path(a.src)
    files, evs = build()
    worst = -200.0
    for L in LISTENERS.values():
        for terrain in (True, False):
            L.terrain = terrain
            worst = max(worst, 20 * np.log10(np.abs(mix(files, cues(L, files))).max()))
        L.terrain = True
    trim = min(0.0, -1.5 - worst)
    files = {k: v * 10 ** (trim / 20) for k, v in files.items()}
    print(f"{len(files)} files; trim {trim:+.2f} dB (the loudest mix's peak to -1.5 dBFS)")
    snd = Path(a.out) / "assets" / "orbital" / "sounds" / TH
    snd.mkdir(parents=True, exist_ok=True)
    for old in snd.glob("*.ogg"):
        if old.stem not in files and not old.stem.startswith("syn_"):
            old.unlink()
    for nm, x in files.items():
        write_ogg(snd / f"{nm}.ogg", x)
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    text = path.read_text()
    sounds = json.loads(text)
    for k in [k for k in sounds if k.startswith(f"{TH}.") and not k.startswith(f"{TH}.syn_")]:
        del sounds[k]
    for nm in sorted(files):
        base = nm.rsplit("_", 1)[0].rstrip("1234")
        sounds[f"{TH}.{nm}"] = {"sounds": [{"name": f"orbital:{TH}/{nm}", "attenuation_distance": 1200}], "subtitle": f"subtitles.orbital.{TH}.{base}"}
    path.write_text(json.dumps(sounds, indent=2) + ("\n" if text.endswith("\n") else ""))
    lang = ROOT / "orbital-laser-mod" / "assets" / "orbital" / "lang" / "en_us.json"
    names = json.loads(lang.read_text())
    for base, s in SUBTITLE.items():
        names[f"subtitles.orbital.{TH}.{base}"] = s
    lang.write_text(json.dumps(names, indent=2, ensure_ascii=False) + "\n")
    if a.listen:
        out = Path(a.listen)
        out.mkdir(parents=True, exist_ok=True)
        for name, L in LISTENERS.items():
            write_wav(out / f"earthquake_{name}.wav", mix(files, cues(L, files)))
            picture(files, L, name, out / f"earthquake_{name}.png")
        print(f"listening mixes and pictures in {out}")
    if a.page:
        page(files, evs, a.page)
        print(f"page in {a.page}")
    if a.check:
        checks(files, evs, snd)


if __name__ == "__main__":
    main()
