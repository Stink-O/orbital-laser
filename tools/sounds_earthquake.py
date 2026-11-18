#!/usr/bin/env python3
"""The Earthquake's sounds, synthesized (the `synth` take, files `syn_*`; `/orbital quakesound synth|real`). The `real`
take is the earlier set shaped from CC0 recordings (tools/sounds_earthquake_rec.py, its files without the prefix); this
script only reads those files, for the listening mixes and the checks, and plays them on the same timeline.

Rock breaking heard in the air and the blows' stone are real: breaks cut from two CC0 recordings
(tools/sound_sources/earthquake/, `grains`, `fracture`), played as recorded, with distortion on their mids (`distort`,
`CRUNCH_*`). Every other layer is made from noise and oscillators at 44.1 kHz. Each event was measured on a
reference recording (`MEAS`: its third-octave spectrum; the numbers in each event's notes: how many breaks a second, how
they cluster, how fast a body dies, where its weight sits) and is built to those numbers; `match` pulls a layer's long
spectrum toward its reference's from 60 Hz to 2.5 kHz (at most `MATCH_DB` either way), where the references are clean.

A real break is left as made: `match` passes those layers through (`AS_MADE`). The dark rolls through the ground (`rolling`)
and wood keep the model (`fracture_model`): a short crunch (a few micro-breaks within 4-30 ms, low-passed by the size, so
no tick and no snap) through a body (`body_ir`: noise that dies faster the higher it is, so it rings low and stops,
dense enough that no one mode rings, plus two or three low modes), and for the big ones a falling sub thump. A field of
them (`field`) comes at uneven times (a rate in time, each break able to set off one or two more 25-160 ms on) with sizes
from a heavy-tailed spread with a floor (no little stones), over a low roll that follows their density (`glue`) so the
gaps never leave single pops. Grinding (`grind`) is stick-slip: slips at 25-70 a second by the slide's speed, each a
crunch, through one slab's body together, chattering at 6-10 Hz as the slab judders, over a low friction roar.

Every file is mono (the game sums stereo to mono as it loads it) and sits at a fixed level against the others (the
climax the loudest), so a cue's volume is its distance only. Tiers `_near`, `_mid`, `_far` are cross-faded by the
player's distance from the moving land (`weights`): near some tens of blocks off (its breaks' top rolled off over
3.2 kHz, a little reverb); mid the body and the sub, the top gone over
~1.8 kHz, a little ground reverb; far the sub and a dark soft-fronted rumble. Grinding, trees, scree and water have no
`_far` file. Two clocks: through the ground (the bed, the blows, the settle) late by d/1700 s; through the air the rest,
late by d/343 s.

Strike clock (strike/earthquake.rs's constants win; `cues` mirrors strike/eq_sounds.rs):

  syn_bed          0      the rumble under the whole strike: from the blow only ever climbing to the climax, held to
                          the still, falling away while rock still comes off, the tremors after rest; 49.4 s
  syn_blow         0      the blow underfoot (its hit BLOW_AT in)
  syn_tear         ~1-5   the crack racing out along the main fault, passing the player (TEAR_PASS in);
  syn_tearclose           when it starts right by them (TEARCLOSE_PASS in)
  syn_rip          0.8    the crack opening round the target heard from afar (mid and far)
  syn_branch       ~2     the side cracks racing out round the plates (near and mid)
  syn_heaveblow    6.0    the first heave's blow through the ground (HEAVEBLOW_AT in), the air's push, the roll
  syn_heave        6.0    the first heave in the air: one big rip across the fault, the up side's short grind
  syn_grindK       lurch K (8.5, 11.0, 13.5): rock grinding on rock, a hard start, stopping dead (near and mid)
  syn_knock        each lurch's blow through the ground, its volume by the lurch's share
  syn_fall1        after the second lurch; syn_fall2 in the build; syn_fall3-5 off the standing cliff 21-31
  syn_build        14.0   the grind climbing into the climax, ending on it (BUILD_LEN in)
  syn_climaxblow   18.5   the climax's blow through the ground: the biggest sub, the stone's body, the longest roll
  syn_climax       18.5   the climax in the air: rock tearing across the fault, the cliff's thrust stopping dead at the
                          thrust's end (CLIMAX_LONG in), a cliff face letting go
  syn_settle       31     the last settle
  syn_slideK       31.5-42 scree and boulders off the scarps, louder first, the gaps growing (near and mid)
  syn_pour         33     water pouring into the canyon, a low roar (near and mid); only where water runs in
  syn_tree1-3      each   one tree going over on a moving plate (terrain on; near and mid), played at its trunk as it
                          starts to fall (strike/eq_sounds.rs's `eq_tree_cues`, one of the three by its hinge's hash):
                          its trunk splitting TREE_SPLIT in, its crown hitting the land TREE_CRASH after that (the
                          picture's EQ_TREE_FALL * EQ_TREE_A), its branches breaking for half a second and a smaller
                          thud TREE_BOUNCE on (the picture's bounce); not on this timeline: a tree's own time

    python3 tools/sounds_earthquake.py                    # the syn_*.ogg files, sounds.json and the subtitles
    python3 tools/sounds_earthquake.py --listen DIR       # also both takes mixed as the game does from 40, 250 and 800
                                                          # blocks (WAV and PNG)
    python3 tools/sounds_earthquake.py --page DIR [--refs RECORDINGS]  # each event and layer alone (WAV), with the
                                                          # reference it was measured on beside it when given
    python3 tools/sounds_earthquake.py --check            # the checks (hashes, levels, tiers, the dip)
"""
import argparse
import hashlib
import json
import os
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
TH = "earthquake"
PRE = "syn_"
ROOT = Path(__file__).resolve().parent.parent

# ---- the strike clock (strike/earthquake.rs: keep in step) --------------------------------------------------------------
CRACK = 0.8          # EQ_CRACK
CRACK_V = 110.0      # EQ_CRACK_V
CRACK_BY = 5.5       # EQ_CRACK_BY
HEAVE = 6.0          # EQ_HEAVE
LURCH = (8.5, 11.0, 13.5)            # the plates working (EQ_BASE between the heave and the climax)
SHARE = (0.12, 0.10, 0.06)
CLIMAX = 18.5        # EQ_CLIMAX
CLIMAX_LONG = 1.4    # how long the climax's thrust moves the plates (EQ_LONG's)
STILL = 21.0         # EQ_STILL: every plate on its rest offset
REST = 31.0          # EQ_REST
BACK = (33.5, 38.4)  # the plates back home with the terrain left alone
TREMORS = (34.5, 40.2)
REACH = 160.0
CAP = 0.45           # EQ_CAP
SEG = 0.75           # EQ_SEG
PAST = 60.0          # EQ_PAST
END = 50.0
GROUND_V = 1700.0
RANGE = 1200         # blocks the game fades a placed sound to nothing over (sounds.json; strike/eq_sounds.rs plays most of them placed)
AIR_V = 343.0

# ---- where each file's beat is in it, and the schedule's own numbers (strike/eq_sounds.rs: keep in step) ------------------
BLOW_AT = 0.05
TEAR_PASS = 1.6
TEARCLOSE_PASS = 0.35
HEAVEBLOW_AT = 0.25
HEAVE_AT = 0.05
GRIND_AT = 0.04
KNOCK_AT = 0.15
BUILD_LEN = 4.5
CLIMAXBLOW_AT = 0.4
CLIMAX_AT = 0.05
SETTLE_AT = 0.2
TREES_AFTER = 0.5
FALL1_AFTER = 1.2                    # after the second lurch
FALL2_BEFORE = 2.2                   # in the build, before the climax
STANDS = ((3.2, 0.95), (6.4, 0.85), (9.7, 0.75))   # rock off the standing cliff: (after the climax, volume)
SLIDES = ((31.5, 1.0), (33.4, 0.85), (35.7, 0.7), (38.3, 0.55))   # while the rubble and scree come down
POUR_T = 33.0
RIP_FROM = 200.0
GRIND_LONG = (1.2, 1.1, 0.95)
# One tree going over (strike/eq_trees.rs: EQ_TREE_FALL 0.9 s, EQ_TREE_A 0.82; strike/eq_sounds.rs's TREE_SPLIT and
# TREE_CRASH: keep in step): the split this far into its file, the crash this long after the split, the second thud
# this long after the crash. The three trees: (file, size, seed).
TREE_SPLIT = 0.04
TREE_CRASH = 0.9 * 0.82
TREE_BOUNCE = 0.25
TREE_LEN = 3.0
TREE_KINDS = ((1, 0.8, 301), (2, 1.0, 302), (3, 1.2, 303))

# ---- the measurements (third-octave spectra, dB from each one's loudest band; tools are in the team's notes) -------------
# Each from a CC0 recording's segment at the speed the earlier set played it: R3 "S41-31 Misc. crashes for earthquake",
# R2 "Rock destroy", R11 "S10-20 Heavy stone falling onto stone", R14 "R29-03 Long Rumble", R5 "Stone Slab Door
# Grinding", R6 "Stone slab", R8 "DeplacementRoche", R7 "Rock sliding", R10 "S33-22 Boulders crashing down", R9 "S33-29
# Boulders fall down mountain", R15 "Big Tree Fall in Forest", R16 "Tall dead tree splintering", R17 "G26-24 Tree
# Crashes", R12 "S32-12 Landslide starts and stops", R18 "Rushing Waterfall". Measured only: nothing of them is here.
BANDS = 25 * 2 ** (np.arange(26) / 3)
MEAS = {
    "blow": [-32.6, -29.2, -20.7, -12.2, -9.4, -4.6, 0.0, -1.0, -3.8, -7.5, -10.2, -12.5, -16.0, -18.9, -22.5, -24.9, -28.2, -31.6, -34.3, -37.7, -41.4, -45.4, -50.1, -56.2, -63.9, -70.6],
    "tear_body": [-9.9, -13.9, -16.7, -18.0, -13.6, -12.2, -12.0, -9.1, -5.5, -3.9, -1.6, 0.0, -2.0, -2.7, -5.9, -6.0, -8.3, -10.4, -10.9, -12.8, -15.3, -19.9, -28.3, -43.3, -50.2, -58.0],
    "tear_break": [0.0, -6.1, -14.1, -15.6, -19.3, -16.2, -20.3, -19.9, -20.1, -21.0, -22.8, -27.5, -29.7, -29.2, -27.8, -25.8, -27.0, -25.4, -26.5, -27.9, -33.9, -36.4, -40.1, -46.5, -48.7, -52.5],
    "rip": [-13.0, -15.5, -12.0, -7.4, -2.0, -5.6, -5.9, -2.2, -1.9, -1.5, 0.0, -2.2, -3.1, -5.1, -5.0, -7.7, -8.8, -9.5, -10.1, -10.5, -13.2, -17.4, -27.4, -42.5, -53.4, -58.8],
    "branch": [-9.9, -12.3, -15.2, -17.9, -13.8, -10.6, -9.2, -6.6, -3.5, -4.6, -2.4, 0.0, -1.5, -3.7, -2.1, -5.0, -9.3, -10.7, -11.2, -10.5, -12.9, -17.4, -22.8, -37.6, -45.9, -54.3],
    "stone_hit": [-15.7, -16.3, -14.9, -13.1, -9.3, -6.1, -5.4, -7.4, -5.1, -4.3, 0.0, -0.2, -0.6, -1.1, -1.6, -4.2, -7.6, -11.4, -16.6, -17.8, -21.2, -27.1, -33.1, -44.7, -58.4, -66.8],
    "roll": [-28.5, -24.5, -15.3, -9.7, -4.6, -0.4, 0.0, -2.8, -5.6, -9.0, -11.4, -14.1, -16.5, -19.6, -23.2, -26.6, -30.1, -33.3, -36.9, -40.8, -44.5, -49.1, -54.6, -62.9, -71.8, -75.6],
    "heave_rip": [-11.2, -14.4, -16.3, -20.5, -17.2, -15.6, -15.2, -10.4, -7.1, -3.6, -2.2, -0.1, 0.0, -4.9, -6.6, -6.7, -7.5, -11.0, -11.0, -11.9, -14.6, -17.8, -24.1, -38.3, -46.7, -55.0],
    "heave_grind": [-12.9, -8.7, -8.0, -2.9, 0.0, -3.0, -2.1, -4.7, -7.0, -10.1, -10.8, -13.2, -15.2, -17.0, -14.6, -15.9, -16.0, -24.0, -27.0, -39.9, -48.8, -59.0, -73.0, -73.6, -77.3, -87.9],
    "tree_crash": [-17.3, -13.6, -5.3, 0.0, -0.0, -4.7, -2.0, -4.5, -6.5, -9.5, -19.2, -17.8, -20.2, -20.9, -27.3, -28.0, -28.6, -24.5, -21.7, -23.8, -25.6, -28.0, -30.7, -32.8, -35.3, -36.2],
    "tree_fall": [-2.5, -0.4, 0.0, -3.3, -3.2, -3.5, -6.3, -10.5, -13.7, -21.0, -21.4, -23.8, -23.1, -20.8, -22.9, -25.0, -26.1, -24.6, -26.5, -27.5, -28.8, -30.5, -33.1, -33.6, -35.1, -37.9],
    "grind_r5": [-13.7, -9.4, -3.9, -2.3, 0.0, -2.1, -0.8, -4.0, -7.7, -11.7, -13.9, -16.4, -16.6, -17.9, -17.9, -18.7, -21.3, -25.8, -31.5, -36.1, -45.1, -56.1, -61.6, -68.0, -72.4, -85.5],
    "grind_r6": [-38.8, -37.5, -35.8, -34.5, -29.7, -23.4, -23.4, -14.9, -6.8, 0.0, -6.5, -14.9, -16.3, -15.3, -24.1, -24.8, -14.8, -24.4, -26.5, -31.9, -37.8, -34.7, -38.4, -40.7, -46.1, -52.4],
    "grind_r8": [-4.6, -4.2, -4.7, -4.8, -5.0, -3.3, -3.3, -3.7, 0.0, -1.2, -1.9, -2.7, -3.7, -2.9, -4.4, -4.5, -6.4, -9.2, -9.3, -15.0, -18.4, -18.4, -20.2, -23.0, -23.1, -28.6],
    "slide_r7": [-5.2, -3.1, -1.7, -2.3, -3.7, -6.5, -8.5, -6.6, -6.7, -8.5, -9.0, -9.7, -8.9, 0.0, -9.4, -15.2, -21.5, -17.6, -23.3, -29.2, -29.9, -34.5, -38.3, -38.7, -39.5, -46.0],
    "fall_roll": [-31.3, -25.1, -15.6, -13.9, -7.8, -2.9, -3.1, -2.6, -3.2, -1.7, 0.0, -6.9, -11.0, -15.1, -17.0, -22.9, -27.0, -30.6, -33.7, -39.5, -42.8, -49.8, -55.4, -61.2, -69.0, -75.3],
    "climax_tear": [-8.7, -12.2, -14.8, -15.2, -10.0, -11.3, -12.1, -10.6, -4.2, -1.9, -0.5, 0.0, -1.5, -0.3, -3.6, -6.5, -7.1, -9.3, -9.5, -12.7, -15.7, -21.7, -32.4, -44.6, -52.1, -57.8],
    "cliff_go": [-26.2, -20.9, -20.4, -15.3, -9.1, -6.8, -3.8, -3.6, -2.3, 0.0, -0.9, -3.6, -4.0, -8.6, -12.7, -15.3, -18.5, -19.9, -21.6, -21.6, -22.3, -24.6, -30.5, -37.7, -44.8, -55.1],
    "bed": [-1.2, 0.0, -1.4, -3.3, -4.8, -5.9, -8.7, -13.7, -18.0, -23.4, -29.4, -37.2, -46.3, -56.1, -66.4, -72.8, -75.9, -77.1, -77.7, -78.0, -78.3, -78.2, -77.5, -78.8, -78.9, -79.1],
    "slide": [-6.5, -2.9, 0.0, -1.8, -2.4, -3.9, -2.0, -1.3, -3.0, -5.9, -10.5, -12.9, -13.3, -14.3, -14.4, -14.9, -17.4, -14.8, -17.1, -21.0, -26.1, -31.6, -38.3, -45.3, -51.1, -61.5],
    "pour": [-13.6, -10.8, -9.0, -6.4, -4.7, 0.0, -2.0, -1.5, -0.7, -0.9, -1.1, -2.6, -0.5, -0.1, -2.8, -2.8, -4.4, -6.3, -7.2, -9.9, -11.6, -12.8, -15.4, -17.4, -20.7, -22.9],
}
# The reference each one was measured on (recording, start, end, the speed it was played at): for the page.
REF_SEG = {
    "blow": ("R14", 0.0, 3.4, 0.8), "tear_body": ("R3", 6.4, 14.5, 0.65), "tear_break": ("R2", 0.0, 1.35, 0.7),
    "rip": ("R3", 19.5, 26.0, 0.6), "branch": ("R3", 15.0, 18.9, 0.7), "stone_hit": ("R11", 6.6, 8.4, 0.62),
    "roll": ("R14", 3.0, 9.0, 0.7), "heave_rip": ("R3", 11.9, 13.8, 0.7), "heave_grind": ("R5", 4.98, 5.78, 0.85),
    "tree_crash": ("R16", 6.8, 8.9, 0.85), "tree_fall": ("R15", 4.3, 7.6, 0.9), "grind_r5": ("R5", 10.05, 12.1, 0.75),
    "grind_r6": ("R6", 5.65, 7.5, 0.7), "grind_r8": ("R8", 3.0, 4.95, 0.5), "slide_r7": ("R7", 9.6, 17.3, 0.6),
    "fall_roll": ("R10", 28.7, 30.4, 0.8), "climax_tear": ("R3", 6.4, 10.8, 0.6), "cliff_go": ("R9", 8.6, 13.0, 0.85),
    "bed": ("R13", 3.1, 40.0, 0.9), "slide": ("R12", 5.3, 9.0, 0.8), "pour": ("R18", 0.5, 17.0, 1.0),
}
REC_FILE = {
    "R2": "tear_rock_destroy_bertsz_524312.mp3", "R3": "tear_s41_31_misc_crashes_for_earthq_craigsmith_675846.mp3",
    "R5": "thrust_stone_slab_door_grinding_heavy_nahuelmartinez_844329.mp3", "R6": "thrust_stone_slab_wav_scottrex05_593489.mp3",
    "R7": "thrust_rock_sliding_throndronis_799521.mp3", "R8": "thrust_d_placementroche_wav_davidou_88496.mp3",
    "R9": "fall_s33_29_boulders_fall_down_moun_craigsmith_675733.mp3", "R10": "fall_s33_22_boulders_crashing_down__craigsmith_675732.mp3",
    "R11": "fall_s10_20_heavy_stone_falling_ont_craigsmith_675741.mp3", "R12": "fall_s32_12_landslide_starts_and_st_craigsmith_675735.mp3",
    "R13": "ground_g43_11_earth_quake_wav_craigsmith_438690.mp3", "R14": "ground_r29_03_long_rumble_for_earthqu_craigsmith_483287.mp3",
    "R15": "tree_big_tree_fall_in_forest_kinoton_494071.mp3", "R16": "tree_tall_dead_tree_splintering_the_ozymandias37_869103.mp3",
    "R18": "water_rushing_waterfall_colonnades_760050.mp3",
}
MATCH_DB = 6.0
# Layers of real breaks: left as made (the references they were measured on are darker than a close break).
AS_MADE = {"tear_body", "tear_break", "rip", "branch", "stone_hit", "blow", "heave_rip", "climax_tear", "cliff_go",
           "fall_roll", "slide"}


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
    return signal.sosfilt(sos("lowpass", min(f, SR * 0.45), o), x)


def hp(x, f, o=2):
    return signal.sosfilt(sos("highpass", f, o), x)


def bp(x, lo, hi, o=2):
    return signal.sosfilt(sos("bandpass", [lo, min(hi, SR * 0.45)], o), x)


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


def rms(x):
    return float(np.sqrt(np.mean(x * x) + 1e-20))


def curve(n, pts):
    """A level over time from (seconds, dB) points, linear in dB between them."""
    ts, vs = zip(*pts)
    return 10 ** (np.interp(T(n), ts, vs) / 20)


def wander(n, rate, g):
    """Smooth random movement in about -1..1, `rate` changes a second."""
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


def fit(x, n):
    y = np.zeros(n)
    m = min(n, len(x))
    y[:m] = x[:m]
    return y


def gate(n, a, b, ra=0.03, rb=0.05):
    """1 from a to b, smoothstep edges (no hard gates: they click)."""
    t = T(n)
    return smooth((t - a + ra) / ra) * (1 - smooth((t - b) / rb))


def third_octave(x):
    f, P = signal.welch(x, SR, nperseg=8192)
    out = []
    for c in BANDS:
        m = (f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))
        out.append(10 * np.log10(P[m].mean() + 1e-20))
    return np.array(out)


def match(x, ref, lo=60.0, hi=2500.0, lim=MATCH_DB):
    """x's long spectrum pulled toward the reference's (its shape, not its level) between lo and hi, at most `lim` dB
    either way, as a smooth zero-phase curve; outside, the edge's gain held (never a boost above hi)."""
    if rms(x) < 1e-9 or ref in AS_MADE:
        return x
    have = third_octave(x)
    want = np.array(MEAS[ref])
    m = (BANDS >= lo) & (BANDS <= hi)
    d = want - have
    d = d - np.median(d[m])
    d = np.clip(d, -lim, lim)
    i0, i1 = np.nonzero(m)[0][[0, -1]]
    d[:i0] = d[i0]
    d[i1 + 1:] = min(d[i1], 0.0)
    d = np.convolve(np.pad(d, 1, mode="edge"), np.ones(3) / 3, "valid")
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    g = 10 ** (np.interp(np.log(np.maximum(fr, 1.0)), np.log(BANDS), d) / 20)
    return np.fft.irfft(X * g, len(x))


# ---- the models -----------------------------------------------------------------------------------------------------------
_irs = {}


def body_ir(size, g, kind="rock"):
    """A broken body's response: noise in four bands each dying at its own rate (the low longest, the top fast), dense
    enough that no single mode rings, and two or three low modes ringing a little longer. Bigger: lower and longer."""
    s = max(size, 0.2)
    L = N(min(1.0, 0.1 + 0.2 * s))
    t = T(L)
    w = g.standard_normal(L)
    if kind == "wood":       # a trunk: higher, drier
        bands = ((60, 220, 0.06, 0.7), (220, 700, 0.035, 1.0), (700, 1800, 0.014, 0.55), (1800, 4500, 0.004, 0.12))
    elif kind == "slab":     # a slab dragged: the low longer
        bands = ((35, 150, 0.16, 1.2), (150, 450, 0.08, 1.0), (450, 1200, 0.03, 0.5), (1200, 3500, 0.007, 0.12))
    else:
        bands = ((30, 150, 0.085, 1.0), (150, 420, 0.06, 1.0), (420, 1200, 0.028, 0.6), (1200, 4500, 0.006, 0.18))
    sz = s ** 0.6
    sh = s ** -0.35          # bigger bodies: every band lower
    h = np.zeros(L)
    for lo, hi, tau, a in bands:
        h += a * bp(w, max(lo * sh, 22), max(hi * sh, lo * sh + 30), 2) * np.exp(-t / (tau * sz))
    for _ in range(g.integers(2, 4)):
        f = g.uniform(70, 260) * sh * (1 - 0.12 * smooth(t / 0.15))
        h += 0.12 * np.sin(2 * np.pi * np.cumsum(f) / SR + g.uniform(0, 6.3)) * np.exp(-t / (g.uniform(0.02, 0.045) * sz)) * smooth(t / 0.003)
    return h / np.sqrt(np.sum(h * h))


def crunch(size, g, top):
    """The break itself: a few micro-breaks bunched at the start (4-30 ms by the size), each a 0.5-1.5 ms puff of noise
    with a raised-cosine edge, low-passed at `top` (no tick, no snap)."""
    n = N(0.004 + 0.022 * size ** 0.7) + N(0.003)
    x = np.zeros(n)
    k = 1 + g.poisson(2 + 2.5 * size)
    for p in (n - N(0.003)) * g.beta(1.0, 2.5, k):
        m = N(g.uniform(0.0005, 0.0015)) + 2
        b = g.standard_normal(m) * np.hanning(m) * g.uniform(0.3, 1.0)
        place(x, b, p / SR)
    x = lp(hp(x, 30), top, 2)
    return x


def fracture_model(size, g, top=None, kind="rock", sub=True):
    """One break: its crunch through its body, and for a big one a falling sub thump. Energy grows with the size."""
    if top is None:
        top = float(np.clip(4800 / size ** 0.7, 900, 5500))
    h = body_ir(size, g, kind)
    y = signal.fftconvolve(crunch(size, g, top), h)
    if sub and size > 1.2:
        n = len(y)
        t = T(n)
        f0 = g.uniform(50, 80) / size ** 0.3
        f = f0 * (0.55 + 0.45 * np.exp(-t / 0.04))
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
        thud = lp(hp(g.standard_normal(n), 25, 2), 110, 4)
        th = (0.5 * tone + 0.5 * thud / (rms(thud) + 1e-12)) * smooth(t / 0.004) * np.exp(-t / min(0.03 * size, 0.08))
        y += th * rms(y) * 2.2 * min(1.0, (size - 1.2) / 1.2)
    y = fade(y, 0.0, 0.02)
    return y / (rms(y) + 1e-12) * size ** 1.5 * 0.02


# ---- real breaks -------------------------------------------------------------------------------------------------------
BREAK_SRC = ROOT / "tools" / "sound_sources" / TH
BREAK_FILES = (("rock_destroy_524312.mp3", 0.18), ("rockcrack03_489905.mp3", 0.3))   # (file, onset threshold of its peak)
CRUNCH_DRIVE = 14.0     # dB into the clipper
CRUNCH_MIX = 0.7        # the grit's level against the break's own
CRUNCH_DENSE = False    # every break a cluster of two to four a few ms apart
_pool = []


def grains(path, thr, pre=0.004, length=0.28, gap=0.09):
    """A recording's breaks: from 4 ms before each onset (a peak of its 3 ms level over `thr` of the highest) to
    `length` on or the next break, faded out, at one RMS."""
    x = read_audio(path)
    x = x / np.abs(x).max()
    w = N(0.003)
    e = np.sqrt(np.convolve(x * x, np.ones(w) / w, "same"))
    pk, _ = signal.find_peaks(e, height=thr * e.max(), distance=N(gap))
    out = []
    for i, k in enumerate(pk):
        a = max(k - N(pre) - w, 0)
        b = min(a + N(length), len(x) if i + 1 == len(pk) else max(pk[i + 1] - N(pre) - w, a + N(0.05)))
        q = fade(x[a:b].copy(), 0.001, min(0.04, (b - a) / SR / 3))
        out.append(q / (rms(q) + 1e-12))
    return out


def rock_pool():
    if not _pool:
        for f, thr in BREAK_FILES:
            _pool.extend(grains(BREAK_SRC / f, thr))
    return _pool


def distort(y, drive_db, mix):
    """Grit on a break: its mids pushed into a clipper (a little uneven, so even harmonics too), the fizz over 7 kHz
    taken off, its tail held to the break's own (a clipper lifts tails), added over the break as recorded: the lows and
    the thud stay whole."""
    pk = np.abs(y).max() + 1e-12
    pre = hp(y, 180) + 1.2 * bp(y, 500, 3500)
    z = pre / pk * 10 ** (drive_db / 20)
    z = 0.6 * np.tanh(z) + 0.4 * np.clip(z + 0.15, -0.7, 1.0)
    z = lp(hp(z, 200), 7000, 2)
    w = N(0.003)
    e = np.sqrt(np.convolve(y * y, np.ones(w) / w, "same"))
    z *= (e / (e.max() + 1e-12)) ** 0.6
    z *= rms(y) / (rms(z) + 1e-12)
    return y + mix * z


def real_break(size, g, top, sub):
    """One real break: a grain a little lower the bigger it is (a resample, at most a third down), darker only where the
    caller asks for a low top (far off, or through the ground), and for a big one a falling sub thump."""
    p = rock_pool()
    q = p[int(g.integers(0, len(p)))]
    r = float(np.clip(2 ** ((size - 1.6) * 0.18), 0.85, 1.35)) * g.uniform(0.94, 1.06)
    y = signal.resample(q, int(len(q) * r))
    if top is not None and top < 2400:
        y = lp(y, float(np.clip(top * 3.4, 1800, 11000)), 2)
    y = np.concatenate([y, np.zeros(N(0.3))])
    if sub and size > 1.0:
        t = T(len(y))
        f0 = g.uniform(55, 85) / max(size, 0.2) ** 0.3
        f = f0 * (0.5 + 0.5 * np.exp(-t / 0.035))
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
        thud = lp(hp(g.standard_normal(len(y)), 25, 2), 100, 4)
        th = (0.6 * tone + 0.4 * thud / (rms(thud) + 1e-12)) * smooth(t / 0.004) * np.exp(-t / min(0.035 * size, 0.09))
        y += th * rms(y[:N(0.03)]) * 1.3 * min(1.0, (size - 1.0) / 1.0)
    y = fade(y, 0.0, 0.03)
    return y / (rms(y) + 1e-12) * size ** 1.5 * 0.02


def fracture(size, g, top=None, kind="rock", sub=True, real=True):
    """One break. Rock heard as rock: a real one, with its grit. A dark roll through the ground (`real` off), or wood:
    the model."""
    if kind != "rock" or not real:
        return fracture_model(size, g, top, kind, sub)
    y = real_break(size, g, top, sub)
    if CRUNCH_DENSE:
        acc = np.zeros(len(y) + N(0.08))
        acc[:len(y)] = y
        t = 0.0
        for _ in range(int(g.integers(1, 4))):
            t += g.uniform(0.007, 0.028)
            q = real_break(size * g.uniform(0.45, 0.8), g, top, False)
            place(acc, q * (rms(y) / (rms(q) + 1e-12)) * g.uniform(0.5, 0.85), t)
        y = acc
    return distort(y, CRUNCH_DRIVE, CRUNCH_MIX) if CRUNCH_MIX > 0 else y


def times_from(rate, g, follow=0.45, gap=(0.025, 0.16)):
    """Break times from a rate (breaks a second, one value every 10 ms), each able to set off one or two more 25-160 ms
    on (breaks bunch, then gaps: the references' spacing is uneven, its spread about as wide as its mean)."""
    dt = 0.01
    hits = np.nonzero(g.uniform(0, 1, len(rate)) < rate * dt)[0] * dt
    out = []
    for t0 in hits:
        t0 = t0 + g.uniform(0, dt)
        out.append((t0, 1.0))
        k = 0
        while k < 2 and g.uniform() < follow:
            t0 += g.uniform(*gap)
            out.append((t0, g.uniform(0.45, 0.9)))
            k += 1
    return sorted(out)


def sizes(k, g, lo, hi, alpha=1.5):
    """A heavy-tailed spread of sizes with a floor (many middling, a few big, none tiny)."""
    return np.clip(lo * (1 - g.uniform(0, 1, k)) ** (-1 / alpha), lo, hi)


def field(n, rate, g, lo, hi, alpha=1.5, top=None, gain=None, kind="rock", follow=0.45, real=True):
    """Breaks over n samples at `rate` (breaks a second, per 10 ms), sizes `lo`..`hi`; `top(t, size)` and `gain(t)` as
    the source comes nearer or goes."""
    acc = np.zeros(n)
    ts = times_from(rate, g, follow)
    ss = sizes(len(ts), g, lo, hi, alpha)
    for (t0, k), s in zip(ts, ss):
        s = max(lo, s * k)
        tp = top(t0, s) if top else None
        x = fracture(s, g, tp, kind, real=real)
        place(acc, x, t0, gain(t0) if gain else 1.0)
    return acc


def rate_of(n_s, pts):
    """A rate in breaks a second, every 10 ms, from (seconds, rate) points."""
    t = np.arange(int(n_s / 0.01)) * 0.01
    ts, vs = zip(*pts)
    return np.interp(t, ts, vs)


def glue(x, lo=50, hi=450, k=0.3, g=None, win=0.15):
    """The mass under the breaks: low noise following their density (smoothed over `win`), `k` of their level, so the
    gaps never leave single pops."""
    g = g or np.random.default_rng(7)
    w = N(win)
    c = np.concatenate([[0.0], np.cumsum(np.pad(x * x, (w // 2, w - w // 2)))])
    e = np.sqrt(np.maximum((c[w:] - c[:-w])[:len(x)] / w, 0))
    z = bp(g.standard_normal(len(x)), lo, hi, 2)
    z = 0.6 * z + 0.4 * lp(z, lo * 2.2, 2)
    return z / rms(z) * e * k


def sub_thump(n, t0, f0, f1, decay, attack=0.012):
    """A sub blow: a sine falling from f0 to f1 under a quick (never clicking) attack."""
    t = T(n)
    k = np.maximum(t - t0, 0)
    f = f1 + (f0 - f1) * np.exp(-k / 0.16)
    env = smooth((t - t0) / attack) * np.exp(-k / decay)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env


def low_noise(n, lo, hi, g, o=3):
    return unit(bp(g.standard_normal(n), lo, hi, o))


def push(n, t0, decay, g, lo=40, hi=220, attack=0.05):
    """The air shoved: a low push of band noise, no hiss."""
    t = T(n)
    return low_noise(n, lo, hi, g) * smooth((t - t0) / attack) * np.exp(-np.maximum(t - t0, 0) / decay)


def swell(n, a, b, g, lo=30, hi=80):
    u = np.clip((T(n) - a) / (b - a), 0, 1)
    return low_noise(n, lo, hi, g) * np.sin(np.pi * u) ** 2


def rumble(n, g, lo=22, hi=110, rate=0.6):
    """A deep moving rumble: low noise whose level and colour wander (never a flat floor)."""
    a = lp(hp(g.standard_normal(n), lo, 2), hi, 4)
    b = bp(g.standard_normal(n), hi * 0.8, hi * 2.6, 2)
    m = 0.5 + 0.5 * np.tanh(wander(n, rate * 0.7, g))
    y = a / rms(a) + 0.45 * m * b / rms(b)
    return y * 10 ** (2.5 * wander(n, rate, g) / 20)


def rolling(n, g, rate_hz, lo_s=1.6, hi_s=2.8, top=500):
    """The ground rolling: big breaks heard through the ground only (dark), at an uneven `rate_hz`."""
    r = np.full(int(n / SR / 0.01) + 1, rate_hz)
    return field(n, r, g, lo_s, hi_s, top=lambda t, s: top, follow=0.25, real=False)


def grind(n, v, g, slab=1.0, chatter=8.0, top=1800, rate=(25, 70), seed_ir=None):
    """Rock grinding on rock as stick-slip: `v` (0..1+, per sample) is how fast it slides. Slips come at rate[0]..rate[1]
    a second by the speed, each a crunch, all through one slab's body; the slab judders at about `chatter` Hz (a
    jittered beat, deeper the faster it slides); under it a low friction roar by the speed."""
    gi = np.random.default_rng(seed_ir) if seed_ir is not None else g
    h = body_ir(1.6 * slab, gi, "slab")
    exc = np.zeros(n)
    t = 0.0
    T_end = n / SR
    while t < T_end:
        vi = float(v[min(N(t), n - 1)])
        r = rate[0] + (rate[1] - rate[0]) * min(max(vi, 0), 1.2)
        t += g.exponential(1.0 / r) * 0.5 + 0.5 / r
        if vi > 0.02:
            c = crunch(g.uniform(0.35, 0.9) * slab, g, top)
            place(exc, c * (0.5 + 0.7 * g.uniform()) * vi, t)
    # (the judder: a jittered beat)
    ph = np.cumsum(chatter * np.maximum(1 + 0.45 * wander(n, chatter * 0.6, g), 0.3) / SR)
    beat = 0.5 + 0.5 * np.cos(2 * np.pi * ph)
    jud = 1 - 0.4 * np.clip(v, 0, 1) * (1 - beat ** 2)
    # (the stick letting go: bigger slips at uneven times, ~4-8 a second as the references' onsets)
    sticks = np.zeros(n)
    t = g.exponential(0.12)
    while t < T_end:
        vi = float(v[min(N(t), n - 1)])
        if vi > 0.1:
            place(sticks, crunch(g.uniform(0.9, 1.8) * slab, g, top * 0.9) * vi * g.uniform(0.6, 1.4), t)
        t += g.uniform(0.06, 0.3)
    exc += sticks * 1.6
    body = signal.fftconvolve(exc, h)[:n]
    roar = bp(g.standard_normal(n), 45 / slab ** 0.3, 650 / slab ** 0.3, 2)
    roar = lp(roar, 900, 2)
    y = body / (rms(body) + 1e-12) + 0.35 * roar / rms(roar) * np.clip(v, 0, 1.3)
    return y * jud


def slide_speed(n, a, b, stop_dead=True, over=1.25):
    """A lurch's slide: from rest to full in 40 ms past it (overshooting), settling, stopping dead at b."""
    t = T(n)
    u = np.maximum(t - a, 0)
    v = smooth(u / 0.04) * (1 + (over - 1) * np.exp(-u / 0.18))
    if stop_dead:
        v *= 1 - smooth((t - b) / 0.05)
    return v


# ---- tiers ---------------------------------------------------------------------------------------------------------------
TIERS = ("near", "mid", "far")
NEAR_TOP = 3200.0     # Hz: the near tier's breaks and grinds roll off above this
NEAR_WET = 0.2        # and this much of them is the ground's reverb


def ir_room(length, dark, g):
    n = N(length)
    t = T(n)
    h = lp(g.standard_normal(n), dark) * np.exp(-t / (length / 4.5)) + 0.8 * lp(g.standard_normal(n), dark * 0.35) * np.exp(-t / (length / 2.5))
    h[:N(0.012)] = 0
    return h / np.sqrt(np.sum(h * h))


def verb(x, length, dark, wet, seed=5):
    y = signal.fftconvolve(x, ir_room(length, dark, np.random.default_rng(seed)))[:len(x)]
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
    gg = np.minimum(1.0, s / e)
    return x * np.interp(np.arange(len(x)), np.arange(len(gg)) * h, gg)


def tier(x, which, kind):
    """What distance does to a layer. sub: carried everywhere; body: everywhere, darker and softer far off; break: near
    and mid, far only as its low part; detail: near and mid only."""
    if which == "near":
        # (near is the fault some tens of blocks off, never at the ear: what breaks and grinds loses its top over
        # NEAR_TOP and stands in a little of the ground's reverb; the sub and the body's low noise as they are)
        if kind in ("break", "detail"):
            return verb(lp(hp(x, 22), NEAR_TOP, 2), 0.7, 2000, NEAR_WET, 3)
        return lp(hp(x, 22), 9000, 2)
    if which == "mid":
        if kind == "sub":
            return lp(x, 400, 2)
        y = verb(lp(x, 1400 if kind == "detail" else 1800, 4), 1.1, 900, 0.3)
        return y * (0.55 if kind == "detail" else 1.0)
    if kind == "detail":
        return None
    if kind == "sub":
        return lp(x, 160, 2)
    y = verb(soft_front(lp(x, 320, 4), 60), 2.0, 300, 0.45, 9)
    return y * (0.5 if kind == "break" else 1.0)


class Event:
    """One sound event: its named layers (each a kind, the reference it was measured on and a line on how it is made)
    mixed in each tier it has."""

    def __init__(self, name, n, tiers=TIERS, line=""):
        self.name, self.n, self.tiers, self.line = name, n, tiers, line
        self.layers = []

    def add(self, label, kind, ref, x, gain=1.0):
        self.layers.append((label, kind, ref, fit(x, self.n) * gain))

    def render(self, which):
        out = np.zeros(self.n)
        parts = {}
        for label, kind, ref, x in self.layers:
            y = tier(x, which, kind)
            if y is not None:
                out += y
                parts[label] = y
        return out, parts


def R(seed):
    return np.random.default_rng(seed)


# ---- the events ----------------------------------------------------------------------------------------------------------
def roll_layer(n, t0, length, g, size=1.0, rate=8.0):
    """The long roll after a blow: a deep rumble and big breaks heard through the ground (measured on R14's roll: some
    8 a second, its weight 60-160 Hz), falling away over `length`."""
    r = rumble(n, g, 24, 120, 0.8)
    k = rolling(n, g, rate * 1.1, 1.5, 3.0, 450)
    y = r / rms(r) + 0.8 * k / (rms(k) + 1e-12)
    env = curve(n, [(0, -60), (t0, -60), (t0 + 0.25, -4), (t0 + 0.6, 0), (t0 + length * 0.35, -6), (t0 + length, -40), (n / SR + 1, -60)])
    return match(y * env, "roll") * size


def blow_layers(e, n, t0, size, seed):
    """A blow through the ground: the ground's lift first, the sub hit, the stone's body (a cluster of big breaks within
    60-120 ms, as the stone hits measured: a main break, followers 40-400 ms on, bodies dying in 120-220 ms), the air's
    push, the long roll."""
    g = R(seed)
    lead = 0.25 + 0.15 * size
    lift = smooth((T(n) - (t0 - lead)) / lead) * (1 - smooth((T(n) - t0) / 0.08))
    e.add("the ground's lift before it: low noise 25-90 Hz swelling", "sub", "", low_noise(n, 25, 90, g) * lift, 0.12 * size)
    e.add("the sub hit: a sine falling from 60 to 23 Hz", "sub", "", sub_thump(n, t0, 52 + 8 * size, 23, 0.9 + 1.0 * size), 0.5)
    acc = np.zeros(n)
    for dt, s in ((0.0, 2.6 + 0.6 * size), (g.uniform(0.03, 0.06), 2.0 + 0.4 * size), (g.uniform(0.08, 0.13), 1.6 + 0.5 * size),
                  (g.uniform(0.25, 0.45), 1.4 + 0.3 * size)):
        place(acc, fracture(s, g, top=1800), t0 - 0.004 + dt)
    acc = match(acc, "stone_hit")
    e.add("the stone's body: four big breaks in 0.45 s, low-passed at 1.8 kHz", "break", "stone_hit", unit(acc), 0.65)
    e.add("the air's push: low noise 40-220 Hz", "body", "", push(n, t0 + 0.1, 0.3 + 0.2 * size, g), 0.18 + 0.08 * size)
    e.add("the long roll after: a deep rumble and big dark breaks through the ground", "body", "roll",
          roll_layer(n, t0 + 0.05, 3.5 + 2.5 * size, g), 0.12 * size)


def ev_blow():
    n = N(4.0)
    e = Event("blow", n, line="the blow underfoot at 0 s: a deep thud through the ground, the rumble starting")
    g = R(11)
    s = sub_thump(n, BLOW_AT, 46, 26, 1.0) + 0.6 * swell(n, BLOW_AT, BLOW_AT + 2.2, g, 25, 60)
    e.add("sub thump and pressure swell", "sub", "", s, 0.5)
    acc = np.zeros(n)
    for dt, sz in ((0.0, 3.2), (0.025, 2.8), (0.05, 2.4), (0.08, 2.2)):
        place(acc, fracture(sz, g, top=1300), BLOW_AT - 0.005 + dt)
    acc = match(acc, "blow")
    e.add("the body: four big breaks in 80 ms, under 1.3 kHz (measured on R14's start: its weight 60-160 Hz)", "body", "blow", unit(acc), 0.4)
    e.add("the rumble rolling on from it", "body", "roll", roll_layer(n, BLOW_AT + 0.15, 3.5, g, 1.0, 7.3), 0.1)
    return e


def tear_layers(e, n, t0, close, seed):
    """The rip: breaks coming faster and bigger as the crack nears (measured on R3: about 4.5 a second, bunched, the
    spacing's spread as wide as its mean, bodies dying in ~140 ms; at the pass twice that), duller far off; a whole rock
    breaking open at the pass (R2: five breaks 65-135 ms apart); the mass under them; the air pushed out of the fissure."""
    g = R(seed)
    L = n / SR
    if close:
        lvl = [(0, -10), (t0, 0), (t0 + 0.5, -2), (t0 + 2.0, -7), (t0 + 3.6, -12), (t0 + 4.6, -22), (L, -40)]
    else:
        lvl = [(0, -26), (t0 - 0.9, -12), (t0 - 0.25, -3), (t0, 0), (t0 + 0.6, -4), (t0 + 1.6, -12), (t0 + 2.8, -24), (L, -40)]
    env = curve(n, lvl)
    near = lambda t: float(np.interp(t, [p[0] for p in lvl], [p[1] for p in lvl]))   # dB
    rate = rate_of(L, [(0, 3.0 if not close else 7.0), (max(t0 - 0.6, 0), 6.0), (t0, 9.0), (t0 + 1.0, 6.0), (L, 3.0)])
    brk = field(n, rate, g, 0.8, 3.2, 1.4, top=lambda t, s: float(np.clip(3200 / s ** 0.6 * 10 ** (near(t) / 40), 500, 3500)),
                gain=lambda t: 10 ** (near(t) / 20))
    brk = match(brk, "tear_body", 150)
    e.add("rock tearing: breaks of every size bunched at uneven times, nearer and brighter as the crack passes", "break", "tear_body", brk / rms(brk), 0.10)
    acc = np.zeros(n)
    tt = t0 - 0.1
    for s in (3.4, 2.8, 3.0, 2.2, 1.8):
        place(acc, fracture(s, g, top=2800), tt)
        tt += g.uniform(0.065, 0.135)
    acc = match(acc, "tear_break", 100)
    e.add("a whole rock breaking open as it passes: five big breaks 65-135 ms apart", "break", "tear_break", unit(acc), 0.6)
    e.add("the mass under the breaks: low noise following them", "body", "tear_body", glue(brk, 50, 450, 0.35, g) / rms(brk), 0.10)
    air = low_noise(n, 60, 300, g, 2)
    e.add("air pushed out of the fissure: low noise 60-300 Hz", "body", "", air * env, 0.06)
    e.add("the ground's sub under the pass", "sub", "", swell(n, max(t0 - 0.8, 0.0), t0 + 1.6, g, 28, 60), 0.12)


def ev_tear():
    n = N(4.6)
    e = Event("tear", n, line="the crack racing out along the main fault: from far, past the player (1.6 s in), running on")
    tear_layers(e, n, TEAR_PASS, False, 21)
    return e


def ev_tearclose():
    n = N(5.4)
    e = Event("tearclose", n, line="the crack ripping open right by the player and running away from them")
    tear_layers(e, n, TEARCLOSE_PASS, True, 22)
    return e


def ev_rip():
    n = N(4.6)
    e = Event("rip", n, tiers=("mid", "far"), line="the crack opening round the target, heard from afar")
    g = R(41)
    env = curve(n, [(0, -30), (0.3, -4), (1.4, 0), (3.6, -3), (4.6, -30)])
    rate = rate_of(4.6, [(0, 3), (0.4, 7), (2.0, 6), (4.6, 3)])
    b = field(n, rate, g, 1.0, 3.2, 1.4, top=lambda t, s: 1600)
    b = match(b * env, "rip", 80)
    e.add("rock tearing far off: breaks merging into a roll, under 1.6 kHz", "break", "rip", b / rms(b), 0.09)
    e.add("the mass under them", "body", "rip", glue(b, 40, 300, 0.4, g) / rms(b), 0.09)
    e.add("the ground's low tearing roll", "sub", "", swell(n, 0.1, 4.5, g, 28, 70), 0.14)
    return e


def ev_branch():
    n = N(3.8)
    e = Event("branch", n, tiers=("near", "mid"), line="the side cracks branching off and racing out round the plates")
    g = R(45)
    # (the side cracks race out in full view, more and more of them, until the heave: denser and louder to its end,
    # never falling away before it)
    rate = rate_of(3.8, [(0, 0), (0.05, 7), (1.2, 8), (2.4, 11), (3.4, 14), (3.7, 6), (3.8, 0)])
    acc = field(n, rate, g, 0.8, 2.8, 1.5, top=lambda t, s: 2200) * curve(n, [(0, -6), (1.5, -3), (3.4, 0), (3.8, -8)])
    acc = match(acc, "branch", 120)
    e.add("shorter tears further out, more and more of them until the heave", "break", "branch", acc / rms(acc), 0.07)
    e.add("the mass under them", "body", "branch", glue(acc, 50, 400, 0.3, g) / rms(acc), 0.07)
    return e


def ev_heaveblow():
    n = N(7.0)
    e = Event("heaveblow", n, line="the first heave's blow through the ground (6 s), the air's push, the long roll")
    blow_layers(e, n, HEAVEBLOW_AT, 1.0, 60)
    return e


def ev_heave():
    n = N(4.2)
    e = Event("heave", n, line="the first heave in the air: one big rip across the fault, the up side's short heavy grind")
    g = R(65)
    rate = rate_of(4.2, [(0, 0), (HEAVE_AT, 0), (HEAVE_AT + 0.02, 15), (0.6, 9), (1.5, 3), (2.5, 0), (4.2, 0)])
    rip = field(n, rate, g, 1.1, 3.4, 1.3, top=lambda t, s: 3000 / s ** 0.5)
    first = fracture(3.6, g, top=2800)
    place(rip, first, HEAVE_AT - 0.004, 2.0)
    rip = match(rip, "heave_rip", 120)
    e.add("one big rip across the fault: a burst of big breaks (measured on R3: ~115 ms apart, dying in ~210 ms)", "break", "heave_rip", unit(rip), 0.6)
    e.add("the mass under it", "body", "heave_rip", glue(rip, 45, 400, 0.35, g) / (np.abs(rip).max() + 1e-12), 0.6)
    v = slide_speed(n, HEAVE_AT + 0.02, HEAVE_AT + 0.92)
    gr = grind(n, v, g, slab=1.3, chatter=8.0, top=1400, seed_ir=66)
    gr = match(gr, "heave_grind")
    e.add("the up side jumping: 0.9 s of stick-slip grinding, a hard start, stopping dead (R5: weight 60-250 Hz, judder 8 Hz)", "detail", "heave_grind", unit(gr), 0.45)
    return e


def tree(n, t0, g, big=1.0, fall=None):
    """A tree going over: its trunk splitting (a few big breaks through a trunk's drier body, no creak), the air of its
    fall, its crash `fall` after the split (by default by its size): a thud with a sub and its branches breaking
    (measured on R16 and R15: the crash's weight 40-100 Hz, its breaks ~70 ms apart for half a second)."""
    acc = np.zeros(n)
    for k in range(3):
        place(acc, fracture(1.6 * big, g, top=2600, kind="wood"), t0 + k * g.uniform(0.02, 0.05))
    if fall is None:
        fall = 1.1 + 0.4 * big
    air = low_noise(n, 90, 420, g, 2) * curve(n, [(0, -60), (t0 + 0.1, -60), (t0 + fall * 0.8, -6), (t0 + fall, 0), (t0 + fall + 0.15, -40), (n / SR + 1, -60)])
    crash = np.zeros(n)
    place(crash, fracture(3.0 * big, g, top=1500), t0 + fall)
    rate = rate_of(n / SR, [(0, 0), (t0 + fall, 0), (t0 + fall + 0.02, 14), (t0 + fall + 0.6, 3), (t0 + fall + 1.0, 0), (n / SR, 0)])
    crash += field(n, rate * 0.5, g, 1.0, 2.0, 1.6, top=lambda t, s: 1800, kind="wood", follow=0.2) * 0.5
    # (the crown hitting the ground: a short low rush of leaves and branches, under 1.6 kHz, dying in half a second)
    rush = lp(bp(g.standard_normal(n), 120, 1600, 2), 1600, 4) * smooth((T(n) - t0 - fall + 0.01) / 0.01) * np.exp(-np.maximum(T(n) - t0 - fall, 0) / 0.35)
    crash += rush / (rms(rush) + 1e-12) * rms(crash) * 0.8
    crash += sub_thump(n, t0 + fall, 60, 32, 0.25) * rms(crash) * 3
    return acc, air, crash


def ev_trees():
    n = N(4.8)
    e = Event("trees", n, tiers=("near", "mid"), line="trees going over near the fault (the split and the crash, never a creak)")
    g = R(70)
    sp, air, cr = tree(n, 0.0, g, 1.0)
    sp2, air2, cr2 = tree(n, 0.55, g, 0.8)
    e.add("trunks splitting: big breaks through a drier body", "detail", "tree_crash", unit(match(sp + 0.7 * sp2, "tree_crash", 80)), 0.3)
    e.add("the air of their fall: low noise 90-420 Hz", "detail", "tree_fall", unit(air + 0.8 * air2), 0.12)
    e.add("their crash: a thud and the branches breaking for half a second", "detail", "tree_crash", unit(match(cr + 0.8 * cr2, "tree_crash", 60)), 0.5)
    return e


def ev_tree(k, big, seed):
    """One tree going over on a moving plate, timed to the picture: the split TREE_SPLIT in, the crown on the land
    TREE_CRASH after it (the fall slow, then fast), the branches breaking for half a second, and a smaller thud
    TREE_BOUNCE on as it bounces and settles (a wood break through the trunk's body and a short low sub)."""
    n = N(TREE_LEN)
    e = Event(f"tree{k}", n, tiers=("near", "mid"), line=f"one tree going over (size {big}): the split, the fall's air, the crash, a second thud")
    g = R(seed)
    sp, air, cr = tree(n, TREE_SPLIT, g, big, TREE_CRASH)
    t1 = TREE_SPLIT + TREE_CRASH + TREE_BOUNCE * g.uniform(0.92, 1.08)
    bounce = np.zeros(n)
    place(bounce, fracture(1.9 * big, g, top=1200, kind="wood"), t1)
    bounce += sub_thump(n, t1, 52, 30, 0.14) * rms(bounce) * 2.5
    e.add("its trunk splitting: big breaks through a drier body", "detail", "tree_crash", unit(match(sp, "tree_crash", 80)), 0.3)
    e.add("the air of its fall: low noise 90-420 Hz", "detail", "tree_fall", unit(air), 0.12)
    e.add("its crash: a thud and the branches breaking for half a second", "detail", "tree_crash", unit(match(cr, "tree_crash", 60)), 0.5)
    e.add("the bounce: a smaller thud as it settles", "detail", "tree_crash", unit(match(bounce, "tree_crash", 60)), 0.2)
    return e


GRIND_REF = {1: "grind_r5", 2: "grind_r6", 3: "grind_r8"}


def ev_grind(k):
    long = GRIND_LONG[k - 1]
    n = N(long + 1.0)
    e = Event(f"grind{k}", n, tiers=("near", "mid"), line=f"lurch {k}: rock grinding on rock, {long:g} s, a hard start, stopping dead")
    g = R(80 + k)
    stop = GRIND_AT + long
    v = slide_speed(n, GRIND_AT, stop, over=1.3)
    gr = grind(n, v, g, slab=(1.3, 1.1, 1.0)[k - 1], chatter=(2.6, 5.0, 9.0)[k - 1], top=(1300, 1700, 2000)[k - 1], seed_ir=90 + k)
    gr = match(gr, GRIND_REF[k])
    e.add(f"stick-slip grinding through one slab's body, judder about {(2.6, 5.0, 9.0)[k - 1]:g} Hz (as measured)", "detail", GRIND_REF[k], unit(gr), 0.5)
    last = np.zeros(n)
    place(last, fracture(2.0, g, top=1500), stop - 0.03)
    e.add("the slab catching as it stops: one big break", "detail", "stone_hit", unit(match(last, "stone_hit")), 0.35)
    e.add("the rock's ring as it stops: a low push", "body", "", push(n, stop - 0.05, 0.35, g, 50, 260, attack=0.02), 0.05)
    return e


def ev_knock():
    n = N(4.0)
    e = Event("knock", n, line="a lurch's body blow through the ground (its volume by the lurch's share)")
    g = R(100)
    t = T(n)
    s = smooth((t - (KNOCK_AT - 0.15)) / 0.15) * (1 - smooth((t - KNOCK_AT) / 0.08))
    e.add("the ground's lift", "sub", "", low_noise(n, 25, 90, g) * s, 0.08)
    e.add("the sub hit", "sub", "", sub_thump(n, KNOCK_AT, 50, 27, 0.9), 0.42)
    acc = np.zeros(n)
    for dt, sz in ((0.0, 2.6), (0.04, 2.0), (0.21, 1.6)):
        place(acc, fracture(sz, g, top=1600), KNOCK_AT - 0.004 + dt)
    e.add("the stone's body: three big breaks", "break", "stone_hit", unit(match(acc, "stone_hit")), 0.45)
    e.add("a short roll", "body", "roll", roll_layer(n, KNOCK_AT, 2.5, g), 0.06)
    return e


def fall_event(name, seed, line, big=1.0):
    n = N(3.6)
    e = Event(name, n, tiers=("near", "mid"), line=line)
    g = R(seed)
    acc = np.zeros(n)
    hits = [(0.05, 2.9 * big), (0.05 + g.uniform(0.5, 0.8), 2.1 * big)]
    if big > 0.95:
        hits.append((hits[1][0] + g.uniform(0.3, 0.6), 1.7))
    for t0, s in hits:
        place(acc, fracture(s, g, top=2200), t0)
        place(acc, sub_thump(N(0.8), 0.0, 55, 30, 0.12) * 0.015 * s ** 1.5, t0)
    e.add("each boulder's landing: one big break and its thud (R11: bodies dying in 120-220 ms)", "detail", "stone_hit", unit(match(acc, "stone_hit")), 0.5)
    rate = rate_of(3.6, [(0, 0), (0.1, 0), (0.15, 7), (1.2, 6), (2.0, 2), (2.4, 0), (3.6, 0)])
    tum = field(n, rate, g, 0.9, 2.0, 1.7, top=lambda t, s: 1500, follow=0.3)
    tum = match(tum, "fall_roll")
    e.add("the rock tumbling behind them: dark breaks ~6 a second (R10: weight 100-300 Hz)", "detail", "fall_roll", tum / (rms(tum) + 1e-12), 0.05)
    e.add("their weight in the ground", "sub", "", sub_thump(n, 0.05, 40, 28, 0.6), 0.18)
    return e


def ev_build():
    n = N(BUILD_LEN + 0.2)
    e = Event("build", n, line="the build (14-18.5 s): the grind rising, heavier and heavier, into the climax")
    g = R(120)
    t = T(n)
    u = smooth(t / BUILD_LEN)
    v = (0.35 + 0.75 * u) * (1 - smooth((t - BUILD_LEN + 0.02) / 0.06))
    gr = grind(n, v, g, slab=1.5, chatter=6.0, top=1800, rate=(20, 75), seed_ir=121)
    gr = match(gr, "slide_r7")
    g2 = (1 - u) * lp(gr, 800) + u * gr
    env = curve(n, [(0, -9), (1.5, -6), (3.0, -3), (BUILD_LEN - 0.05, 0), (BUILD_LEN + 0.2, -30)])
    e.add("rock grinding, rising: stick-slip faster and faster, its top opening from 800 Hz (R7: weight 60-800 Hz)", "detail", "slide_r7", g2 / rms(g2) * env, 0.06)
    w = grind(n, v, g, slab=2.4, chatter=3.0, top=900, rate=(15, 40), seed_ir=122)
    e.add("the slab's weight under it: a bigger, slower slab", "body", "grind_r5", match(w, "grind_r5") / rms(w) * env, 0.04)
    f = np.zeros(n)
    for t0, s in ((1.4, 2.2), (3.1, 2.5)):
        place(f, fracture(s, g, top=1800), t0)
    e.add("small cliff falls in it", "detail", "stone_hit", f / (np.abs(f).max() + 1e-12), 0.25)
    strain = bp(g.standard_normal(n), 26, 44, 4)
    f0 = 30 * 2 ** (2.5 * u / 12)
    d = np.sin(2 * np.pi * np.cumsum(f0) / SR)
    e.add("the ground's strain, climbing: a low tone and narrow noise, 2.5 semitones up", "sub", "",
          (0.6 * d + 0.4 * strain / rms(strain) / 1.4) * curve(n, [(0, -10), (BUILD_LEN, 0), (BUILD_LEN + 0.1, -40)]), 0.15)
    return e


def ev_climaxblow():
    n = N(9.0)
    e = Event("climaxblow", n, line="THE CLIMAX's blow through the ground (18.5 s): the biggest sub, the stone's body, the air's push, the longest roll")
    blow_layers(e, n, CLIMAXBLOW_AT, 1.6, 140)
    g = R(141)
    acc = np.zeros(n)
    for dt, sz in ((0.0, 3.8), (0.03, 3.4), (0.07, 3.0), (0.12, 2.8)):
        place(acc, fracture(sz, g, top=1100), CLIMAXBLOW_AT - 0.01 + dt)
    e.add("the ground bursting under it: four huge breaks, under 1.1 kHz", "body", "blow", unit(match(acc, "blow")), 0.3)
    return e


def ev_climax():
    n = N(7.0)
    stop = CLIMAX_AT + CLIMAX_LONG
    e = Event("climax", n, line="THE CLIMAX in the air: rock tearing across the whole fault, the cliff's thrust grinding while it moves (stopping dead 1.4 s in), a cliff face letting go")
    g = R(150)
    rate = rate_of(7.0, [(0, 0), (CLIMAX_AT, 0), (CLIMAX_AT + 0.02, 16), (0.8, 12), (2.0, 7), (3.2, 3), (5.0, 1), (7.0, 0)])
    tear = field(n, rate, g, 1.1, 3.6, 1.3, top=lambda t, s: 3200 / s ** 0.5)
    tear = match(tear, "climax_tear", 120)
    e.add("rock tearing across the whole fault: a long burst of big breaks", "break", "climax_tear", tear / rms(tear[:N(1.5)]), 0.11)
    e.add("the mass under it", "body", "climax_tear", glue(tear, 45, 450, 0.4, g) / rms(tear[:N(1.5)]), 0.11)
    acc = np.zeros(n)
    tt = CLIMAX_AT - 0.008
    for s in (3.8, 3.2, 3.5, 2.8, 2.4):
        place(acc, fracture(s, g, top=2800), tt)
        tt += g.uniform(0.02, 0.05)
    e.add("the rock breaking open on the moment: five huge breaks in 150 ms", "break", "tear_break", unit(match(acc, "tear_break", 100)), 0.55)
    v = slide_speed(n, CLIMAX_AT, stop, over=1.35)
    th = grind(n, v, g, slab=1.8, chatter=5.0, top=1600, rate=(25, 80), seed_ir=151)
    th = match(th, "grind_r5")
    e.add("the cliff's thrust: the biggest slab grinding, stopping dead as the cliff does", "detail", "grind_r5", th / rms(th[N(CLIMAX_AT):N(stop)]), 0.075)
    rate2 = rate_of(7.0, [(0, 0), (0.9, 0), (1.0, 11), (2.6, 12), (4.5, 5), (5.6, 0), (7.0, 0)])
    cf = field(n, rate2, g, 1.6, 3.6, 1.4, top=lambda t, s: 2000)
    cf = match(cf, "cliff_go", 80)
    e.add("the mass of the cliff coming down", "body", "cliff_go", glue(cf, 40, 400, 0.6, g, 0.2) / rms(cf[N(0.9):N(3.0)]), 0.07)
    e.add("a cliff face letting go 0.9 s on: boulders crashing down (R9: ~5.6 a second, bodies ringing ~0.5 s)", "break", "cliff_go", cf / rms(cf[N(0.9):N(3.0)]), 0.07)
    return e


def ev_settle():
    n = N(3.0)
    e = Event("settle", n, line="rest (31 s): one soft last settle through the ground")
    g = R(160)
    e.add("a soft sub thump", "sub", "", sub_thump(n, SETTLE_AT, 36, 26, 1.0, attack=0.06), 0.3)
    e.add("the ground's last roll", "body", "roll", roll_layer(n, SETTLE_AT + 0.05, 2.5, g, 1.0, 5.0), 0.08)
    return e


def ev_slide(k):
    n = N(4.2)
    ln = (3.6, 3.1, 2.8, 2.4)[k - 1]
    e = Event(f"slide{k}", n, tiers=("near", "mid"), line=f"aftermath {k}: scree and boulders sliding off a scarp, a dense heavy mass ending with the slide")
    g = R(170 + k)
    rate = rate_of(4.2, [(0, 0), (0.05, 8), (0.35, 30), (ln * 0.6, 26), (ln - 0.2, 14), (ln, 0), (4.2, 0)])
    x = field(n, rate, g, 0.9, 2.4, 1.8, top=lambda t, s: 1700, follow=0.35)
    x = match(x, "slide")
    e.add("the slide: a dense run of middling-to-big breaks (R12: fused, weight 30-300 Hz), under 2 kHz", "detail", "slide", x / rms(x), 0.06)
    e.add("the mass of it: low noise following the breaks", "body", "slide", glue(x, 40, 350, 0.9, g, 0.25) / rms(x), 0.06)
    h = np.zeros(n)
    place(h, fracture(2.8, g, top=1800), 0.4 + 0.25 * k)
    place(h, fracture(2.2, g, top=1800), ln - 0.15)
    e.add("boulders landing at its foot", "detail", "stone_hit", unit(match(h, "stone_hit")), 0.3)
    e.add("its weight in the ground", "sub", "", swell(n, 0.0, ln, g, 30, 70), 0.1)
    return e


def ev_pour():
    n = N(16.5)
    e = Event("pour", n, tiers=("near", "mid"), line="water pouring into the canyon (33 s to the end): a low roar, never a flat wash, no drops")
    g = R(180)
    y = np.zeros(n)
    for k, c in enumerate((150, 210, 290, 400, 560, 780)):
        # (fixed bands whose levels wander slowly and apart: the roar's colour keeps moving, nothing switches)
        b = bp(g.standard_normal(n), c * 0.8, c * 1.25, 2)
        y += b / rms(b) * 10 ** (5.0 * wander(n, 0.35 + 0.1 * k, g) / 20) * (1.0 - 0.07 * k)
    base = lp(bp(g.standard_normal(n), 80, 1000, 3), 1000, 4)
    y = y + 0.8 * base / rms(base)
    y = lp(y, 1100, 4)
    lvl = curve(n, [(0, -30), (1.5, -8), (4.0, 0), (7.0, -3), (11.0, -7), (16.0, -9), (16.5, -40)])
    mv = 10 ** ((4.0 * wander(n, 0.3, g) + 2.0 * wander(n, 2.0, g)) / 20)
    y = match(y * lvl * mv, "pour", 80, 1200)
    e.add("the water's low roar: noise through six bands whose levels wander apart and a 80 Hz-1 kHz bed, its level always moving (R18: weight 80-900 Hz, level moving ~2 Hz)", "detail", "pour", y / rms(y), 0.04)
    return e


def ev_bed():
    n = N(49.4)
    e = Event("bed", n, line="the rumble under the whole strike: only ever climbing to the climax, held to the still, falling away")
    g = R(190)
    t = T(n)
    pts = [(0, -60), (0.05, -60), (0.3, -10), (CRACK_BY, -7.5), (HEAVE - 0.05, -7.0), (HEAVE + 0.4, -5.0)]
    lvl = -5.0
    for lt in LURCH:
        pts += [(lt + 0.1, lvl), (lt + 0.6, lvl + 0.7)]
        lvl += 0.7
    pts += [(LURCH[-1] + 0.6, lvl), (CLIMAX - 0.05, -1.0), (CLIMAX + 0.3, 0), (STILL, -0.5), (STILL + 2.0, -4), (REST - 0.2, -7),
            (REST + 1.0, -9), (REST + 4.0, -13), (40.0, -16), (46.0, -20), (49.4, -40)]
    level = curve(n, pts)
    bumps = np.zeros(n)
    for tr in TREMORS:
        bumps += 1.4 * np.sin(np.pi * np.clip((t - tr) / 1.6, 0, 1)) ** 2
    level = level * (1 + 0.45 * bumps)
    # (the rumble alone: this plays in the player's ears, and rock breaking is heard from where it breaks)
    r = rumble(n, g, 20, 95, 0.5)
    y = match(r / rms(r), "bed", 25, 300)
    e.add("the ground rumbling: deep moving noise (R13: its weight 20-80 Hz)", "body", "bed", y / rms(y) * level, 0.07)
    kk = smooth((t - 14.0) / (CLIMAX - 14.0)) * (1 - smooth((t - STILL) / 3.0))
    f = 30.0 * 2 ** (2.5 * kk / 12) * (1 + 0.05 * wander(n, 0.5, g))
    d = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR + 1.0)
    low = lp(hp(g.standard_normal(n), 20), 60)
    e.add("the sub under it: a low tone and narrow noise, the strain climbing 2.5 semitones through the build", "sub", "",
          (d / 1.5 * 0.7 + low / rms(low) * 0.3) * level * (0.85 + 0.15 * wander(n, 1.3, g)), 0.09)
    return e


def events():
    out = [ev_bed(), ev_blow(), ev_tear(), ev_tearclose(), ev_rip(), ev_branch(), ev_heaveblow(), ev_heave()]
    out += [ev_grind(k) for k in (1, 2, 3)] + [ev_knock()]
    out += [fall_event("fall1", 200, "rock coming off the cliff after the second lurch: heavy falls, not a rattle"),
            fall_event("fall2", 201, "rock coming off the cliff in the build", 0.85)]
    out += [fall_event(f"fall{k}", 199 + k, "rock still coming off the standing cliff (21-31 s)", (1.0, 0.9, 0.8)[k - 3]) for k in (3, 4, 5)]
    out += [ev_build(), ev_climaxblow(), ev_climax(), ev_settle()] + [ev_slide(k) for k in range(1, 5)] + [ev_pour()]
    out += [ev_tree(k, big, seed) for k, big, seed in TREE_KINDS]
    return out


# Each file's peak (dBFS) in its first tier: the climax's the loudest. The other tiers sit 1 dB (mid) and 3 dB (far)
# under it by RMS. A trim over all of them keeps the loudest mix's peak at -1.5 dBFS.
LEVEL = {"bed": -7.0, "blow": -8.0, "tear": -3.0, "tearclose": -3.0, "rip": -12.0, "branch": -6.0, "heaveblow": -5.5,
         "heave": -6.5, "trees": -11.0, "grind1": -8.5, "grind2": -9.0, "grind3": -9.5, "knock": -8.5, "fall1": -10.0,
         "fall2": -11.0, "fall3": -10.5, "fall4": -11.5, "fall5": -12.5, "build": -5.0, "climaxblow": -1.5, "climax": -1.0,
         "settle": -13.0, "slide1": -11.0, "slide2": -12.0, "slide3": -13.0, "slide4": -14.0, "pour": -15.0,
         "tree1": -5.0, "tree2": -5.0, "tree3": -5.0}
MID_DB, FAR_DB = -1.0, -3.0
SOFT = {"climaxblow": 6.0, "heaveblow": 4.0, "climax": 3.0, "tear": 5.0, "tearclose": 5.0}


def soft(x, drive_db):
    k = 10 ** (drive_db / 20) / (np.abs(x).max() + 1e-12)
    y = np.tanh(k * x)
    return y * (np.abs(x).max() / (np.abs(y).max() + 1e-12))


def build():
    """Every synth file (name without the prefix -> samples) and the events (for the page)."""
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
    x = float(smooth((d - 60) / 100)) * np.pi / 2
    y = float(smooth((d - 350) / 300)) * np.pi / 2
    return {"near": np.cos(x), "mid": np.sin(x) * np.cos(y), "far": np.sin(x) * np.sin(y)}


def gain(d):
    return float(np.clip(1.0 / (1.0 + max(d - 60.0, 0.0) / 500.0), 0.3, 1.0))


class Listener:
    """A player as the game places them: `dz` from the fault in the zone, `dc` from the crack where it passes them, `dt`
    from the target, the crack passing them at `tp` (the strike's `arrive`)."""

    def __init__(self, dz, dc=30.0, dt=None, u=None, terrain=True, water=False):
        self.dz, self.dc, self.terrain, self.water = dz, dc, terrain, water
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


# The tiers each event has (strike/eq_sounds.rs's EQ_SYN_EVENTS and EQ_REAL_EVENTS).
NM = ("near", "mid")
HAS_SYN = {"rip": ("mid", "far"), "branch": NM, "grind1": NM, "grind2": NM, "grind3": NM, "fall1": NM,
           "fall2": NM, "fall3": NM, "fall4": NM, "fall5": NM, "slide1": NM, "slide2": NM, "slide3": NM, "slide4": NM, "pour": NM,
           "tree1": NM, "tree2": NM, "tree3": NM}
HAS_REAL = {"rip": ("mid", "far"), "branch": NM, "trees": NM, "grind1": NM, "grind2": NM, "grind3": NM, "grind4": NM,
            "fall1": NM, "fall2": NM, "fall3": NM, "slide1": NM, "slide2": NM, "slide3": NM, "slide4": NM, "pour": NM}
REAL_BUILD_LEN = 4.0     # the earlier set's build file ends on the climax this far in
REAL_FALLS = ((2, 1.6), (3, 1.2))


def cues(L, take="synth", files=None):
    """(start on the strike clock, file, volume) as eq_sounds plays them for listener L, take `synth` or `real`."""
    out = []
    pre = PRE if take == "synth" else ""
    has = HAS_SYN if take == "synth" else HAS_REAL
    gl, al = L.dz / GROUND_V, L.dz / AIR_V
    wz, gz = weights(L.dz), gain(L.dz)
    wc, gc = weights(L.dc), gain(L.dc)
    wt, gt = weights(L.dt), gain(L.dt)

    def play(t, base, vol, w, g):
        for tr in TIERS:
            v = vol * w[tr] * g
            f = f"{pre}{base}_{tr}"
            if v > 0.002 and tr in has.get(base, TIERS) and (files is None or f in files):
                out.append((max(t, 0.0), f, min(v, 1.0)))
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
    play(HEAVE - HEAVEBLOW_AT + gl, "heaveblow", 1.0, wz, gz)
    play(HEAVE - HEAVE_AT + al, "heave", 1.0, wz, gz)
    if take != "synth":     # (no tree is seen to fall: they ride their plates)
        play(HEAVE + TREES_AFTER + al, "trees", 1.0, wz, gz)
    for k, (lt, sh) in enumerate(zip(LURCH, SHARE), 1):
        gk = k if take == "synth" or k < len(LURCH) else 4      # (the earlier set: its long fourth grind runs into the build)
        play(lt - GRIND_AT + al, f"grind{gk}", 1.0, wz, gz)
        play(lt - KNOCK_AT + gl, "knock", 0.55 + 3.0 * sh, wz, gz)
    if take == "synth":
        play(LURCH[1] + FALL1_AFTER + al, "fall1", 1.0, wz, gz)
        play(CLIMAX - FALL2_BEFORE + al, "fall2", 0.8, wz, gz)
        play(CLIMAX - BUILD_LEN + al, "build", 1.0, wz, gz)
    else:
        for i, (k, after) in enumerate(REAL_FALLS, 1):
            play(LURCH[k - 1] + after + al, f"fall{i}", 1.0, wz, gz)
        play(CLIMAX - FALL2_BEFORE + al, "fall3", 0.8, wz, gz)
        play(CLIMAX - REAL_BUILD_LEN + al, "build", 1.0, wz, gz)
    play(CLIMAX - CLIMAXBLOW_AT + gl, "climaxblow", 1.0, wz, gz)
    play(CLIMAX - CLIMAX_AT + al, "climax", 1.0, wz, gz)
    if take == "synth" and L.terrain:
        for k, (after, vol) in enumerate(STANDS, 3):
            play(CLIMAX + after + al, f"fall{k}", vol, wz, gz)
    play(REST - SETTLE_AT + gl, "settle", 1.0, wz, gz)
    for k, (t, v) in enumerate(SLIDES if L.terrain else SLIDES[:2], 1):
        play(t + al, f"slide{k}", v, wz, gz)
    if L.terrain:
        if L.water:         # (only where the land finds water set flowing: eq_land's `afterwards`)
            play(POUR_T + al, "pour", 1.0, wz, gz)
    else:
        for k, t in zip((2, 3), BACK):
            play(t - GRIND_AT + al, f"grind{k}", 0.7, wz, gz)
    return sorted(out)


# ---- the trees' cues (strike/eq_sounds.rs's eq_tree_cues and tree_file: keep in step) ----------------------------------
TREE_HASH = 0x7EE5


def _u32(x):
    return x & 0xFFFFFFFF


def eq_hash(x):
    h = _u32(x)
    h ^= h >> 16
    h = _u32(h * 0x7FEB352D)
    h ^= h >> 15
    h = _u32(h * 0x846CA68B)
    h ^= h >> 16
    return h


def eq_h(seed, a, b):
    return eq_hash(eq_hash(_u32(_u32(seed * 0x9E3779B1) + a)) ^ _u32(_u32(b * 0x85EBCA77) + 0x165667B1))


def tree_file(h):
    """Which of the three trees a hinge (x, y, z) plays: 1, 2 or 3."""
    return eq_h(TREE_HASH, _u32(h[0]), _u32(h[2]) ^ _u32(_u32(h[1]) * 0x27D4EB2F)) % 3 + 1


def tree_cues(trees, me):
    """(start on the strike clock, file, volume) for trees ((hinge, t0), ...) heard by a player at `me`: each at its
    trunk, late by the air, its tiers by the distance (each band's weight, the game's own fade over RANGE)."""
    out = []
    for h, t0 in trees:
        at = (h[0] + 0.5, h[1] + 1.5, h[2] + 0.5)
        d = float(np.sqrt(sum((a - b) ** 2 for a, b in zip(at, me))))
        w, fade_d = weights(d), max(1.0 - d / RANGE, 0.0)
        for tr in NM:
            v = w[tr] * fade_d
            if v > 0.002:
                out.append((max(t0 + d / AIR_V - TREE_SPLIT, 0.0), f"{PRE}tree{tree_file(h)}_{tr}", v))
    return sorted(out)


def env_db(x, win=0.01, hop=0.002):
    w, h = N(win), N(hop)
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    p = ((c[w:] - c[:-w]) / w)[::h]
    return np.arange(len(p)) * hop + win / 2, 10 * np.log10(p + 1e-14)


def tree_beats(x):
    """Where a tree's file splits (the first 10 ms window within 12 dB of its first 0.4 s's loudest) and where it
    crashes (the steepest 10 ms rise from 0.3 s before the crash is due to 0.06 s after: a branch breaking after it can
    rise as steeply)."""
    ts, db = env_db(x)
    m = ts < 0.4
    split = float(ts[np.nonzero(m & (db >= db[m].max() - 12))[0][0]])
    k = 5
    rise = db[k:] - db[:-k]
    tt = ts[k:]
    w = (tt > TREE_SPLIT + TREE_CRASH - 0.3) & (tt < TREE_SPLIT + TREE_CRASH + 0.06)
    crash = float(tt[w][np.argmax(rise[w])]) - 0.005
    return split, crash


LISTENERS = {"plate_40": Listener(40.0, dc=17.0, dt=60.0, u=50.0), "blocks_250": Listener(250.0), "blocks_800": Listener(800.0)}


def mix(files, cl, length=END + 3.0, parts=False):
    acc = np.zeros(N(length))
    layers = {}
    for t0, f, v in cl:
        place(acc, files[f] * v, t0)
        if parts:
            place(layers.setdefault(f.removeprefix(PRE).rsplit("_", 1)[0].rstrip("12345"), np.zeros(len(acc))), files[f] * v, t0)
    return (acc, layers) if parts else acc


def short_term(x, win=0.4, hop=0.05):
    w, h = N(win), N(hop)
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    p = ((c[w:] - c[:-w]) / w)[::h]
    return np.arange(len(p)) * hop + win / 2, 10 * np.log10(p + 1e-12)


def facts(files, L, take):
    x = mix(files, cues(L, take, files))
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


def write_ogg(path, x, q=7):
    tmp = str(path) + ".tmp.wav"
    write_wav(tmp, x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q),
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)], check=True)
    os.remove(tmp)


def read_audio(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def real_files(snd):
    """The earlier set's files as they ship (decoded), for its listening mixes and checks."""
    return {p.stem: read_audio(p) for p in sorted(snd.glob("*.ogg")) if not p.stem.startswith(PRE)}


COL = {"bed": (110, 110, 110), "blow": (40, 40, 40), "tear": (190, 90, 30), "tearclose": (190, 90, 30), "rip": (200, 140, 60),
       "branch": (160, 120, 60), "heaveblow": (120, 0, 0), "heave": (220, 40, 40), "trees": (30, 150, 30),
       "grind": (80, 80, 160), "knock": (140, 40, 140), "fall": (150, 150, 60), "build": (40, 120, 200),
       "climaxblow": (255, 0, 120), "climax": (255, 90, 0), "settle": (90, 90, 90), "slide": (130, 100, 70), "pour": (30, 120, 220), "tree": (20, 110, 20)}


def picture(files, L, name, take, path):
    from PIL import Image, ImageDraw
    f, x = facts(files, L, take)
    _, layers = mix(files, cues(L, take, files), parts=True)
    img = Image.new("RGB", (1600, 640), (250, 250, 248))
    d = ImageDraw.Draw(img)
    L0, TOP, Rr, B, t1, lo, hi = 70, 80, 1580, 590, END + 2.0, -60.0, 0.0

    def X(v):
        return L0 + (Rr - L0) * v / t1

    def Y(v):
        return TOP + (B - TOP) * (hi - np.clip(v, lo, hi)) / (hi - lo)
    beats = [(0, CRACK, "blow"), (CRACK, HEAVE, "crack"), (HEAVE, LURCH[-1] + 0.5, "heave, lurches"), (LURCH[-1] + 0.5, CLIMAX, "build"),
             (CLIMAX, STILL, "CLIMAX"), (STILL, REST, "standing"), (REST, END, "aftermath")]
    for i, (a, b, nm) in enumerate(beats):
        d.rectangle([X(a), TOP, X(b), B], fill=(240, 238, 232) if i % 2 else (246, 245, 240))
        d.text((X(a) + 4, TOP + 4), nm, fill=(90, 90, 90))
    for v in range(int(lo), int(hi) + 1, 10):
        d.line([L0, Y(v), Rr, Y(v)], fill=(215, 215, 210))
        d.text((L0 - 50, Y(v) - 6), f"{v} dB", fill=(90, 90, 90))
    for s in range(0, int(t1) + 1, 2):
        d.text((X(s) - 6, B + 4), f"{s}", fill=(90, 90, 90))
    for k, y in layers.items():
        tt, dd = short_term(y)
        d.line([(X(a), Y(b)) for a, b in zip(tt, dd) if a <= t1], fill=COL.get(k, (0, 0, 200)), width=1)
    ts, db = short_term(x)
    d.line([(X(a), Y(b)) for a, b in zip(ts, db) if a <= t1], fill=(0, 0, 0), width=3)
    d.text((L0, 12), f"{take} take, {name}: the whole strike as the game mixes it (400 ms windows; black the mix). Climax {f['climax_st']:.1f} dB; "
                     f"loudest before it {f['before_st']:.1f} dB; largest dip in the 2 s before it {f['dip_2s']:.1f} dB; mix peak {f['peak']:.2f} dBFS.", fill=(0, 0, 0))
    x0 = L0
    for k, c in COL.items():
        d.rectangle([x0, 34, x0 + 14, 44], fill=c)
        d.text((x0 + 18, 33), k, fill=(40, 40, 40))
        x0 += 78
    img.save(path)


def checks(files, evs, snd, real):
    ok = True
    print("== checks (synth take)")
    others = {hashlib.sha256(p.read_bytes()).hexdigest(): p for p in (ROOT / "orbital-sounds").rglob("*.ogg") if f"/sounds/{TH}/{PRE}" not in str(p)}
    shared = [nm for nm in files if hashlib.sha256((snd / f"{nm}.ogg").read_bytes()).hexdigest() in others]
    print(f"{'OK  ' if not shared else 'FAIL'} no file shared with another laser or the earlier take (sha256 against {len(others)} files){'' if not shared else ': ' + str(shared)}")
    ok &= not shared
    hot = [(nm, round(20 * np.log10(np.abs(x).max()), 2)) for nm, x in files.items() if np.abs(x).max() > 10 ** (-1 / 20)]
    print(f"{'OK  ' if not hot else 'FAIL'} every file's peak under -1 dBFS (the highest {max(20 * np.log10(np.abs(x).max()) for x in files.values()):.2f}){'' if not hot else ': ' + str(hot)}")
    ok &= not hot
    for take, fs in (("synth", files), ("real", real)):
        for name, L in LISTENERS.items():
            for terrain in (True, False):
                L.terrain = terrain
                f, _ = facts(fs, L, take)
                good = (f["climax_st"] >= f["before_st"] and CLIMAX - 0.2 <= f["loudest_at"] <= CLIMAX + 4.0 + L.dz / AIR_V
                        and f["dip_2s"] <= 10.0 and f["peak"] < -1.0)
                tag = ("OK  " if good else "FAIL") if take == "synth" else ("ok  " if good else "warn")
                print(f"{tag} {take} {name} terrain {'on ' if terrain else 'off'}: climax {f['climax_st']:.1f} dB, loudest before it "
                      f"{f['before_st']:.1f} dB, loudest window at {f['loudest_at']:.2f} s; largest dip in the 2 s before it {f['dip_2s']:.1f} dB "
                      f"(lowest {f['last2_min']:.1f}); mix peak {f['peak']:.2f} dBFS")
                if take == "synth":
                    ok &= good
            L.terrain = True
    spread = [((x, 64 + (x * 7 + z) % 9, z), 18.9) for x in range(-110, 111, 13) for z in range(-110, 111, 17)]
    for e in evs:
        heard = set()
        if e.name.startswith("tree"):
            for me in [(d, 66.0, 0.0) for d in (20, 100, 250, 500, 800, 1200)]:
                for _, f, _ in tree_cues(spread, me):
                    if f.removeprefix(PRE).rsplit("_", 1)[0] == e.name:
                        heard.add(f.rsplit("_", 1)[1])
        for L in [Listener(d, water=True) for d in (20, 100, 250, 500, 800, 1200)] + list(LISTENERS.values()):
            for _, f, _ in cues(L, "synth", files):
                if f.removeprefix(PRE).rsplit("_", 1)[0] == e.name:
                    heard.add(f.rsplit("_", 1)[1])
        missing = [tr for tr in TIERS if tr not in e.tiers]
        good = heard <= set(e.tiers) and set(e.tiers) == set(HAS_SYN.get(e.name, TIERS)) and heard
        ok &= bool(good)
        print(f"{'OK  ' if good else 'FAIL'} tiers {e.name}: files {', '.join(e.tiers)}; cued {', '.join(sorted(heard))}"
              + (f" (no {', '.join(missing)}: not heard there, by design)" if missing else ""))
    # (the trees: each file's crash on the picture's, all three played, heard through a grind, well under the climax)
    for k, _, _ in TREE_KINDS:
        for tr in NM:
            sp, cr = tree_beats(files[f"{PRE}tree{k}_{tr}"])
            good = abs(sp - TREE_SPLIT) < 0.02 and abs(cr - sp - TREE_CRASH) < 0.03
            ok &= good
            print(f"{'OK  ' if good else 'FAIL'} tree{k}_{tr}: split at {sp:.3f} s (due {TREE_SPLIT}), crash {cr - sp:.3f} s after it (due {TREE_CRASH:.3f}); "
                  f"{len(files[f'{PRE}tree{k}_{tr}']) / SR:.2f} s long")
    used = {}
    for h, _ in spread:
        used[tree_file(h)] = used.get(tree_file(h), 0) + 1
    good = set(used) == {1, 2, 3} and min(used.values()) > len(spread) / 6
    ok &= good
    print(f"{'OK  ' if good else 'FAIL'} the three trees all played over {len(spread)} hinges: {dict(sorted(used.items()))}")
    L = LISTENERS["plate_40"]
    f, x = facts(files, L, "synth")
    ts, db = short_term(x)
    al = L.dz / AIR_V
    grind_st = max(float(db[(ts >= lt + al) & (ts < lt + al + 1.0)].max()) for lt in LURCH)
    for d in (15.0, 60.0):
        w = weights(d)
        y = sum(files[f"{PRE}tree2_{tr}"] * w[tr] for tr in NM) * (1 - d / RANGE)
        tt, td = short_term(y)
        top = float(td.max())
        good = top >= grind_st - 4.0 and top <= f["climax_st"] - 6.0
        ok &= good
        print(f"{'OK  ' if good else 'FAIL'} a tree from {d:.0f} blocks: its loudest {top:.1f} dB (400 ms windows), a lurch's grind from "
              f"{L.dz:.0f} {grind_st:.1f} dB, the climax {f['climax_st']:.1f} dB (wanted: within 4 dB of the grind or over it, 6 under the climax)")
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


def spectro(x, w=700, h=180):
    """A small log-frequency spectrogram (20 Hz-10 kHz), dark loud, as an image."""
    from PIL import Image
    f, t, Z = signal.stft(x, SR, nperseg=2048, noverlap=2048 - 441)
    P = 10 * np.log10(np.abs(Z) ** 2 + 1e-14)
    P = np.clip((P - (P.max() - 80)) / 80, 0, 1)
    fl = np.geomspace(20, 10000, h)
    img = np.array([np.interp(fl, f, P[:, i]) for i in range(P.shape[1])]).T[::-1]
    return Image.fromarray((255 * (1 - img)).astype(np.uint8)).resize((w, h))


def page(files, evs, out, refs):
    """Each event and each layer alone, beside the reference it was measured on (same RMS), with their spectrograms."""
    from PIL import Image, ImageDraw
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for old in list(out.glob("*.wav")) + list(out.glob("*.png")):
        old.unlink()
    rows = ["The Earthquake's synth take (its rock breaks real, the rest synthesized), each beside the recording segment it was measured on.",
            "Pairs (layer_* and ref_*) are at the same RMS; every other clip's peak is at -1 dBFS. Mono, 44.1 kHz.", ""]
    cache = {}

    def put(name, x, line, peak=True):
        y = x * (10 ** (-1 / 20) / (np.abs(x).max() + 1e-12)) if peak else x
        write_wav(out / f"{name}.wav", y)
        rows.append(f"{name}.wav: {line}")

    def ref_audio(key):
        if refs is None or key not in REF_SEG:
            return None
        r, a, b, k = REF_SEG[key]
        if r not in cache:
            cache[r] = read_audio(Path(refs) / REC_FILE[r])
        from fractions import Fraction
        fr = Fraction(k).limit_denominator(60)
        return signal.resample_poly(cache[r][N(a):N(b)], fr.denominator, fr.numerator)
    for name, L in LISTENERS.items():
        put(f"whole_synth_{name}", mix(files, cues(L, "synth", files)), f"the whole strike, synth take, {name.replace('_', ' ')}")
    x = mix(files, cues(LISTENERS["plate_40"], "synth", files))
    put("moment_crack_0_to_6s_plate_40", x[:N(7.5)], "0-7.5 s on the plate: the blow underfoot, the crack ripping out, the first heave")
    put("moment_climax_13_to_23s_plate_40", x[N(13.0):N(23.0)], "13-23 s on the plate: the last lurch, the build, the climax, the still")
    rows.append("")
    for e in evs:
        for tr in e.tiers:
            put(f"event_{e.name}_{tr}", files[f"{e.name}_{tr}"], f"{e.line} ({tr})")
    rows.append("")
    sheets = []
    for e in evs:
        _, parts = e.render(e.tiers[0])
        for i, (label, kind, refk, _) in enumerate(e.layers, 1):
            if label not in parts or np.abs(parts[label]).max() <= 0:
                continue
            y = parts[label]
            nz = np.nonzero(np.abs(y) > np.abs(y).max() * 1e-3)[0]
            y = y[max(nz[0] - N(0.05), 0):nz[-1] + N(0.05)] if len(nz) else y
            ref = ref_audio(refk)
            act = lambda z: rms(z[np.abs(z) > np.abs(z).max() * 0.01]) if len(z) else 1.0
            if ref is not None:
                ref = ref[:N(min(len(ref) / SR, max(len(y) / SR, 2.0) + 0.5))]
                k = 10 ** (-1 / 20) / max(np.abs(y).max() / act(y), np.abs(ref).max() / act(ref))
                ya, ra = y / act(y) * k, ref / act(ref) * k
                put(f"layer_{e.name}_{i}", ya, f"{e.name}, layer {i} ({kind}): {label}", False)
                r, a, b, sp = REF_SEG[refk]
                put(f"ref_{e.name}_{i}", ra, f"   its reference: {r} {a}-{b} s at {sp}x ({refk})", False)
                sheets.append((f"{e.name} {i}: {label[:70]}", ya, f"reference {refk}: {r} {a}-{b} s at {sp}x", ra))
            else:
                put(f"layer_{e.name}_{i}", y, f"{e.name}, layer {i} ({kind}): {label}")
    # (the pairs' spectrograms: synth above, its reference below)
    for j in range(0, len(sheets), 6):
        part = sheets[j:j + 6]
        img = Image.new("L", (1440, len(part) * 220), 255)
        d = ImageDraw.Draw(img)
        for i, (a, ya, b, ra) in enumerate(part):
            img.paste(spectro(ya), (0, i * 220 + 18))
            img.paste(spectro(ra), (720, i * 220 + 18))
            d.text((4, i * 220 + 3), "SYNTH " + a, fill=0)
            d.text((724, i * 220 + 3), b, fill=0)
        img.save(out / f"spectra_{j // 6 + 1:02d}.png")
    (out / "LIST.txt").write_text("\n".join(rows) + "\n")


SUBTITLE = {"bed": "The ground rumbles", "blow": "The ground jolts", "tear": "The ground tears open", "tearclose": "The ground tears open",
            "rip": "The ground tears open", "branch": "The ground cracks", "swell": "The ground heaves", "heaveblow": "The ground lurches",
            "heave": "Rock tears", "trees": "Trees fall", "grind": "Rock grinds", "knock": "The ground jolts", "fall": "Rock falls",
            "build": "Rock grinds", "climaxblow": "The ground heaves", "climax": "The cliff thrusts up", "settle": "The ground settles",
            "slide": "Rock slides", "pour": "Water pours", "tree": "Tree falls"}


def base_of(nm):
    return nm.removeprefix(PRE).rsplit("_", 1)[0].rstrip("12345")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="both takes mixed as the game does from 40, 250 and 800 blocks here (WAV, PNG)")
    ap.add_argument("--page", help="each event and each layer alone (WAV), spectrograms and LIST.txt here")
    ap.add_argument("--refs", help="the reference recordings, for the page's pairs (read only)")
    ap.add_argument("--check", action="store_true", help="run the checks")
    a = ap.parse_args()
    files, evs = build()
    files = {PRE + k: v for k, v in files.items()}
    snd = Path(a.out) / "assets" / "orbital" / "sounds" / TH
    real = {k: v for k, v in real_files(snd).items()}
    worst = -200.0
    for L in LISTENERS.values():
        for terrain in (True, False):
            L.terrain = terrain
            worst = max(worst, 20 * np.log10(np.abs(mix(files, cues(L, "synth", files))).max()))
        L.terrain = True
    trim = min(0.0, -1.5 - worst)
    files = {k: v * 10 ** (trim / 20) for k, v in files.items()}
    print(f"{len(files)} files; trim {trim:+.2f} dB (the loudest mix's peak to -1.5 dBFS)")
    snd.mkdir(parents=True, exist_ok=True)
    for old in snd.glob(f"{PRE}*.ogg"):
        if old.stem not in files:
            old.unlink()
    for nm, x in files.items():
        write_ogg(snd / f"{nm}.ogg", x)
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    text = path.read_text()
    sounds = json.loads(text)
    for k in [k for k in sounds if k.startswith(f"{TH}.{PRE}")]:
        del sounds[k]
    for nm in sorted(files):
        sounds[f"{TH}.{nm}"] = {"sounds": [{"name": f"orbital:{TH}/{nm}", "attenuation_distance": RANGE}], "subtitle": f"subtitles.orbital.{TH}.{base_of(nm)}"}
    path.write_text(json.dumps(sounds, indent=2) + ("\n" if text.endswith("\n") else ""))
    lang = ROOT / "orbital-laser-mod" / "assets" / "orbital" / "lang" / "en_us.json"
    names = json.loads(lang.read_text())
    for base, s in SUBTITLE.items():
        names[f"subtitles.orbital.{TH}.{base}"] = s
    lang.write_text(json.dumps(names, indent=2, ensure_ascii=False) + "\n")
    allf = dict(real)
    allf.update(files)
    if a.listen:
        out = Path(a.listen)
        out.mkdir(parents=True, exist_ok=True)
        for take in ("synth", "real"):
            for name, L in LISTENERS.items():
                write_wav(out / f"earthquake_{take}_{name}.wav", mix(allf, cues(L, take, allf)))
                picture(allf, L, name, take, out / f"earthquake_{take}_{name}.png")
        print(f"listening mixes and pictures in {out}")
    if a.page:
        page({k.removeprefix(PRE): v for k, v in files.items()}, evs, a.page, a.refs)
        print(f"page in {a.page}")
    if a.check:
        checks(files, evs, snd, real)


if __name__ == "__main__":
    main()
