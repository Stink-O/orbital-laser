"""The Tsunami's sounds (a 130-block wall of dark, debris-laden water, ~2.8 km wide, crossing the land at ~100 blocks a
second: strike/tsunami.rs), all synthesised here from noise, bubbles, resonant knocks and filters, nothing sampled.
Its drama is scale: a roar that is first a rumour on the horizon, then the whole sky; a crash of timber and stone; the
immersion; then the dull pressure of being under it, the water draining off and the quiet it leaves.

Horizon decodes every sound to mono ((L+R)/2) and plays one played to the listener dead centre, 0.596 in each ear (a
positional one is panned by its direction), so every file here is mono: nothing is lost, the folder is half the size
and what is measured is what the game plays.

Timeline the files are built for, as strike/tsunami.rs plays them (strike seconds; T_T = 9.0 the front reaching the
target; `dp` = the player's distance from the target in blocks; `t_p` = 9.0 + dp / 100 + 1.07e-5 dp^2, the front
reaching the player; sound reaches the player dp / 343 s after leaving the target, so it always arrives before the
wave does):

  rupture      at 0 (global): the seabed far off letting go; sub-heavy, a thump 1.1 s in, a long falling rumble
  rumble       at 1.5 (global): the ground under the wave, growing; low only; 18 s
  roar_far     at 2.5 (global): the wave on the horizon, a rumour growing; dark; 12.5 s, fading out
  roar_mid     at t_p - 9.0 (global): closer, bigger; 9 s, ending as the front arrives (fades out over its last 2 s)
  roar_near    at t_p - 4.0 (global): enormous; the immersion is 4.0 s into it (NEAR_PRE): the roar is swallowed, muffled
               and let go over 3 s while `engulf` and `under` take over
  crash        at 9.0 + dp / 343 - CRASH_LEAD (global, or positional at the target): the wave hitting the target
  crash_far    the same moment, cross-faded in by distance (`far_mix`: 250 to 800 blocks, smoothstep)
  engulf       at t_p (global): the immersion
  under        at t_p + 0.3 (global): inside the water; 10 s, fading out for the surface
  surface      at t_p + 8.5 (global): breaking the surface
  drain        at t_p + 9.0 (global): the backwash
  roar_back    at t_p + 9.5 (global): the roar going off over the far side of the land
  rumble_after at t_p + 9.0 (global): the ground, low, settling
  trickle      at t_p + 17 (global): the quiet after
  crack1-4     positional, where a tree or a timber breaks (the front reaching the player's surroundings)
  slap1-3      positional, where water slams into stone or a wall

Volumes (`schedule`: a player the front reaches sooner hears the crash and the wave's own roar on top of each other, so
less of each there; `--listen` sweeps every distance from 100 to 720 blocks and keeps the whole mix under -1 dBTP):

  crash        (1 - far_mix(dp)) * clamp(0.6 + 0.0017 (dp - 300), 0.6, 1)
  crash_far    far_mix(dp) * clamp(0.6 + 0.0017 (dp - 300), 0.6, 1) * min(1.25 / (1 + dp / 2000), 1)
  roar_far     clamp(0.35 + 0.0013 dp, 0.6, 1)         roar_near  clamp(0.63 + 0.0022 (dp - 250), 0.63, 1)
  engulf       clamp(0.72 + 0.0028 (dp - 250), 0.72, 1)     everything else 1

How each is made:

  rupture      the sea floor breaking, far away: a small thud first (the sound that arrives first through the rock), the
               push 1.1 s in (a ~42 Hz thump sinking to 20, a heave rather than a bang: its attack is 40 ms), a long
               rumble sinking from ~150 Hz to ~30 over six seconds with a shudder (low noise chopped at 7-11 Hz) in
               its first seconds, rolls of low thunder, a grinding of rock in the low mids; the lows' harmonics so
               small speakers carry it, the sub clean.
  rumble       low swells rolling in under a sub bed that heaves and grows over 14 s, a grinding in the low mids; nothing
               above ~350 Hz.
  roar_*       one crescendo cut into three: each layer is band noise (nine octaves, each with its own grainy surges: the
               low bands slow and heavy, the top bands crackling like foam and spray) whose spectrum and level follow the
               wave's nearness (`FAR_SH` to `NEAR_SH`: dark, low-mid and distant, then full, with the spray's hiss
               and a deep pressure under it), a slow swell over all of it; `roar_mid` and `roar_near` have timber groaning
               and debris thudding in them, water slapping. Nothing sweeps, nothing rises as a tone.
  crash        the wave hits the target: a heavy whump (not a bang: its attack is 40-90 ms; ~58 Hz sinking to 33, its
               harmonics stacked on it), a slam of water, a roar of rushing water that holds a few seconds and lets
               go; hundreds of trunks snapping (cracks with a dull thud in them), planks and beams breaking in showers,
               masonry coming down in runs of knocks with a rumble under them, a faint sheet of glass far under it
               all; rolls of low thunder off the land and its dark echoes. Heard from hundreds of blocks off, so its
               top is gone and no single block is heard: a dense roaring crunch with the weight in it.
  crash_far    the same through ~a kilometre of air (the Nuke's `far_of`): highs let down, the front smeared, more low
               rolls, a long dark reverb, the mids kept so it carries.
  engulf       the front reaching the player: a sub thump, the slam of water over the head (a hard wet front, a body of
               noise 45-1400 Hz), a wash that closes from open air to muffled in half a second, a flood of bubbles, the
               pressure; handing over to `under`.
  under        inside the water: a dark churning roar (nothing above ~600 Hz), a pressure in the ears, bubbles, timber
               groaning, dull thuds of debris passing, gravel scouring; the last 2 s let the roar open up.
  surface      the head breaking out: the muffled bed opens to the roar in 0.5 s, water pouring off, splashes.
  drain        rushing water leaving the land: a broad flowing bed thinning and darkening over 12 s, gurgles and glugs
               from every hollow, streams, timber knocking and grinding along, the roar of the wave going off dark under it.
  roar_back    the roar of the wave on the far side of the land: dark, low-mid, level falling 20 dB over 12 s.
  rumble_after the ground settling: a low bed sinking away, a few far thuds.
  trickle      drips, a few trickling streams, mud sagging and glugging, a last timber settling twice; very quiet,
               with air round it.
  crack1-4     a trunk snapping (a strain, the break, a splinter run, a thud), a young tree's quick double snap, a house
               beam and planks going, a trunk wrenched out roots and all; each in white water (a wash of bubbling
               water under it); 1.5-1.9 s.
  slap1-3      water slamming a wall: a wet thump, the splash, a sheet of spray pouring down; one big, a double surge, a
               cascade of small ones.

    python3 tools/sounds_tsunami.py                      # writes orbital-sounds/assets/orbital/sounds/tsunami/*.ogg and the
                                                         # tsunami.* events in sounds.json (nothing else touched)
    python3 tools/sounds_tsunami.py --only roar_mid      # one (crash before crash_far)
    python3 tools/sounds_tsunami.py --listen DIR         # also WAVs/MP3s of each, and the whole strike as heard from
                                                         # 200 and 600 blocks (and the true peak of every mix)
    python3 tools/sounds_tsunami.py --plots DIR          # spectrogram pictures of each file and of those two mixes
"""
import argparse, json, subprocess, sys, wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.fft import irfft, next_fast_len, rfft
from scipy.signal import fftconvolve, resample_poly
import soundlib
from soundlib import SR, band
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P
import sounds_nuke as N
import hu_foley as F
import sounds_hurricane as H

TH = "tsunami"
N.TH = TH                      # (the Nuke's helpers, `decoded`, `far_of`, write to tsunami/ now)
P.TH = TH
ROOT = Path(__file__).resolve().parent.parent
NAMES = ["rupture", "rumble", "roar_far", "roar_mid", "roar_near", "roar_pass", "crash", "crash_far", "engulf", "under", "surface",
         "torrent", "drain", "roar_back", "rumble_after", "trickle", "crack1", "crack2", "crack3", "crack4", "slap1", "slap2", "slap3"]
TP_MAX = 10 ** (-1.15 / 20)     # every file's decoded true peak (4x oversampled) at most this
# The mix balance, dB added to each file's nominal level (found by `python3 tools/sounds_tsunami.py --balance`: the whole
# strike heard from every distance between 100 and 700 blocks stays under CEIL, the loudest layers let down first)
TRIM = {"rumble": -6.0}

# ---- the timeline (seconds; 0 = fired)
T_T = 9.0                       # the front crosses the target
SPEED = 343.0
CRASH_LEAD = 0.06               # the crash file's first sound is this far into it
FAR_AT = 0.9                    # roar_far: its first big seas come down as the horizon stands up (1.5 s)
FAR_AGAIN = 7.4                 # played again (lower) only if the wave is that far off yet: it must be gone before the immersion
MID_LEN = 9.0                   # roar_mid ends as the front arrives
NEAR_PRE = 4.0                  # roar_near: the immersion is this far into it
ROAR_NEAR_LEN, PASS_LEN = 7.0, 12.0
SURF_AT = 6.5                   # the head breaks the surface at tp + this (strike/tsunami.rs's carry)
DRAIN_AT, BACK_AT, SETTLE_AT = 9.0, 9.5, 9.0       # tp + these
TRICKLE_AT, TRICKLE_LAST = 17.0, 31.0              # tp + this, or this at the latest (dried up by the strike's end, 42)
NEAR_DB, ENGULF_DB = -12.0, -7.0
# what plays with what at each distance (see `schedule`)
CEIL = 10 ** (-1.0 / 20)        # the whole strike's mix, true peak, at most this (file domain, as the Rod's)


def rng():
    return soundlib.rng


def nsm(d):
    return int(round(SR * d))


def t_p(dp):
    """When the front reaches a player `dp` blocks from the target."""
    return T_T + dp / 100.0 + 1.07e-5 * dp * dp


def far_mix(dist):
    """How much of the crash is `crash_far` at `dist` blocks: none within 250, all past 800 (smoothstep)."""
    u = np.clip((dist - 250.0) / 550.0, 0, 1)
    return float(u * u * (3 - 2 * u))


def schedule(dp, immersed=True):
    """(event, file, start in strike seconds, pitch, volume) as strike/ts_sounds.rs plays them for a player `dp` blocks from
    the target; the same arithmetic. `immersed`: the wave closes over their head (it does not, on a hill above it)."""
    tp = t_p(dp)
    late = dp / SPEED
    far = far_mix(dp)
    send = min(dp + 160.0, 720.0)                                             # (the wave's end, TsGeo::send)
    u = float(np.clip((dp - send) / 400.0, 0, 1))
    reach = 1.0 - u * u * (3 - 2 * u)                                         # past it the wave only roars, and dies
    # (a player the front reaches sooner hears the crash and the wave's own roar on top of each other: less of each there;
    # the volumes are what keeps the mix of every distance under CEIL, `--listen`)
    share = float(np.clip(0.26 + 0.0016 * (dp - 100.0), 0.26, 0.72))
    near_v = float(np.clip(0.72 + 0.0022 * (dp - 250.0), 0.72, 1.0))
    far_v = float(np.clip(0.7 + 0.001 * dp, 0.8, 1.0))
    crash_v = {"crash": share * (1.0 - far), "crash_far": share * far * min(1.25 / (1.0 + dp / 2000.0), 1.0)}
    rows = [("rupture", "rupture", 0.0, 1.0, 1.0),
            ("rumble", "rumble", 1.5, 1.0, 1.0),
            ("roar_far", "roar_far", FAR_AT, 1.0, far_v),
            ("roar_mid", "roar_mid", max(tp - MID_LEN, 1.0), 1.0, reach),
            ("roar_far2", "roar_far", FAR_AGAIN, 0.94, 0.85 * far_v if tp - MID_LEN > FAR_AGAIN + 0.2 else 0.0),
            ("crash", "crash", T_T + late - CRASH_LEAD, 1.0, crash_v["crash"]),
            ("crash_far", "crash_far", T_T + late - CRASH_LEAD, 1.0, crash_v["crash_far"]),
            ("torrent", "torrent", tp + SURF_AT, 1.0, reach),
            ("drain", "drain", tp + DRAIN_AT, 1.0, reach),
            ("roar_back", "roar_back", tp + BACK_AT, 1.0, reach),
            ("rumble_after", "rumble_after", tp + SETTLE_AT, 1.0, 1.0),
            ("trickle", "trickle", min(tp + TRICKLE_AT, TRICKLE_LAST), 1.0, 1.0)]
    if immersed:
        rows += [("roar_near", "roar_near", tp - NEAR_PRE, 1.0, near_v),
                 ("engulf", "engulf", tp, 1.0, 1.0),
                 ("under", "under", tp + UNDER_AT, 1.0, 1.0),
                 ("surface", "surface", tp + SURF_AT, 1.0, 1.0)]
    else:
        rows += [("roar_pass", "roar_pass", tp - NEAR_PRE, 1.0, near_v * reach)]
    return [r for r in rows if r[4] > 0]


# =================================================================================================  small tools
def put(x, y, t0):
    F.put(x, y, t0)


def curve_db(t, pts):
    """A smooth level over `t` (seconds) through `pts` ((time, dB) pairs): linear amplitude."""
    xs, ys = zip(*pts)
    f = PchipInterpolator(xs, ys)
    return 10 ** (f(np.clip(t, xs[0], xs[-1])) / 20)


def curve(t, pts):
    """The same for a plain value."""
    xs, ys = zip(*pts)
    return PchipInterpolator(xs, ys)(np.clip(t, xs[0], xs[-1]))


def noise(n, lo, hi, order=3):
    """Unit-RMS noise in a band."""
    return T.unit(band(rng().standard_normal(n), lo, hi, order))


def grains(n, rate, taus=(0.012, 0.025, 0.05)):
    """Many little surges at random (Poisson `rate` a second, heavy-tailed sizes, each rising in 2 ms and dying over one
    of `taus`), averaging 1: the uneven boil of broken water, not a regular wobble. `n` samples."""
    out = np.zeros(n)
    for tau in taus:
        x = np.zeros(n)
        k = rng().poisson(rate * (n / SR) / len(taus))
        np.add.at(x, rng().integers(0, n, k), np.minimum(rng().pareto(2.5, k) + 0.2, 6.0))
        s = np.arange(int(tau * SR * 6)) / SR
        kern = (1 - np.exp(-s / 0.002)) * np.exp(-s / tau)
        out += fftconvolve(x, kern)[:n] / (tau * SR)
    out = np.maximum(out, 0.0)
    return out / (np.mean(out) + 1e-9)


def wander(n, lo, hi, depth_db):
    """A gain curve wandering by about `depth_db` dB, its movement between `lo` and `hi` Hz."""
    return np.exp(depth_db * PB.slow_random(n, lo, hi) / 8.686)


def sine_thump(n, t0, f0, f1, rate, rise, decay, a=1.0):
    """A heave, not a bang: a sine sinking from f0 to f1 (e-fold rate `rate`), its attack `rise` s, its decay `decay`."""
    t = np.arange(n) / SR - t0
    m = t >= 0
    u = np.maximum(t, 0)
    f = f1 + (f0 - f1) * np.exp(-u * rate)
    ph = 2 * np.pi * np.cumsum(f * m) / SR
    return np.sin(ph) * (1 - np.exp(-u / rise)) * np.exp(-u / decay) * m * a


def lows_harm(x, rel_db=-10.0, f_hi=90.0, lo=70.0, hi=320.0):
    """`x` with the harmonics of its lows added (its sub driven, the product kept to `lo`-`hi` Hz) at `rel_db` under them,
    so a laptop or a phone hears the weight; the sub itself untouched."""
    sub = band(x, None, f_hi, 3)
    c = np.percentile(np.abs(sub), 99.0) * 0.35 + 1e-9
    h = band(np.tanh(sub / c) * c, lo, hi, 2)
    h = h / (T.loudest(h) + 1e-9) * T.loudest(sub) * 10 ** (rel_db / 20)
    return x + h


def lowpass_to(x, fc, size=2048, hop=512):
    """`x` through a lowpass whose cutoff follows `fc` (Hz, one value a sample)."""
    return PB.lowpass_track(x, fc, size, hop)


def glide_fc(n, pts):
    """A cutoff track: Hz at each sample, log-interpolated through `pts` (seconds, Hz)."""
    xs, ys = zip(*pts)
    t = np.arange(n) / SR
    return np.exp(np.interp(t, xs, np.log(ys)))


def slap_event(size, wet=1.0):
    """Water slamming something solid, dry: a wet low thump, the burst of the splash, the sheet of it falling back.
    Unit peak, about 0.7 s (a big one is longer)."""
    m = nsm(0.5 + 0.5 * size)
    s = np.arange(m) / SR
    body = noise(m, 55, 220 + 260 / (1 + size), 2) * (1 - np.exp(-s / 0.004)) * np.exp(-s / (0.05 + 0.07 * size))
    punch = sine_thump(m, 0.0, 95.0 / (0.6 + 0.5 * size), 48.0 / (0.6 + 0.5 * size), 18.0, 0.003, 0.05 + 0.05 * size, 0.8)
    splash = noise(m, 500, 6500 + 2000 * wet, 2) * (1 - np.exp(-s / 0.002)) * np.exp(-s / (0.035 + 0.025 * size))
    sheet = noise(m, 1000, 7000, 2) * np.clip(grains(m, 700.0, (0.01, 0.025, 0.06)), 0, 5) ** 0.9 \
        * np.exp(-s / (0.18 + 0.2 * size)) * (1 - np.exp(-s / 0.03))
    x = body * 0.9 + punch * 0.7 + splash * 0.55 + sheet * 0.22
    return x / (np.abs(x).max() + 1e-12)


# =========================================================================================================  water
# What makes water water and not wind (McDermott & Simoncelli 2011): water's sound is "sparsely distributed, independent,
# bandpass acoustic events" about as wide as the ear's own filters; imposing only a spectrum on noise gives wind. So the
# roars are not gated noise: they are thousands of damped, slightly climbing sines (Minnaert: f = 3.26 m/s / radius; van
# den Doel 2005 for the climb) gathered in patches narrow enough for the ear to tell apart, the events of a patch louder
# when the patch is busy, over a thin bed of turbulence, with the air cavities of plunging water slamming in low. A wave
# this size is a much bigger bubble field than a beach's, so its grains run lower and slower (airborne surf peaks near 1 kHz
# for small waves and at 250-400 Hz over a metre; a waterfall's broad peak is near 100 Hz, plunging jets near 100 Hz and their air
# cylinders at 50-80 Hz in surf).
OCT = np.array([31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000])
FAR_SH = np.array([-12.0, -5.0, -1.0, 0.0, -3.0, -10.0, -22.0, -42.0, -80.0])      # through a kilometre of air
NEAR_SH = np.array([-12.0, -6.0, -1.0, 0.0, -0.5, -1.0, -5.0, -12.0, -22.0])       # surf's level 100-1600 Hz, falling over 2 kHz
UNDER_SH = np.array([-4.0, 0.0, -1.0, -4.0, -11.0, -24.0, -42.0, -62.0, -90.0])    # under the water
TORRENT_SH = np.array([-14.0, -7.0, -2.0, 0.0, 0.0, -1.0, -4.0, -9.0, -16.0])      # the land pouring away, close
RILL_SH = np.array([-44.0, -34.0, -22.0, -13.0, -6.0, 0.0, -2.0, -9.0, -20.0])     # what is left of it: rills
F_BIN = np.geomspace(36.0, 9000.0, 112)      # the resonators
ERB = 24.7 * (4.37 * F_BIN / 1000 + 1)       # the ear's filter there, Hz
BIN_W = F_BIN * (2 ** (1 / 13.4) - 1)        # a resonator's share of the spectrum, Hz
SOLO_F = 900.0                               # under this each bubble is written on its own, at a pitch of its own
FR = 1000                                    # frames a second of the rates
PATCHES = 48


def erb_num(f):
    return 21.4 * np.log10(1 + 0.00437 * f)


def bubble_q(f, q=1.0):
    """How long a bubble rings: Q ~18 in the mids; low ones are clouds ringing together, heavily damped, never a tone."""
    u = np.clip(np.log(f / 120.0) / np.log(900.0 / 120.0), 0, 1)
    return q * (3.0 + 15.0 * u * u * (3 - 2 * u))


def patch_gain(m, fc, rate, beta):
    """Where a patch of water is busy: `m` frames of a gain with mean 1: heavy-tailed clusters at Poisson `rate` a second,
    sharp to start, dying over tens of ms (slower the lower). `beta`: the share of the rate that comes in clusters."""
    tau = 0.11 * (fc / 200.0) ** -0.5
    k = rng().poisson(rate * m / FR)
    x = np.zeros(m)
    np.add.at(x, rng().integers(0, m, k), np.minimum(rng().pareto(1.5, k) + 0.15, 14.0))
    s = np.arange(int(tau * FR * 7) + 2) / FR
    y = np.convolve(x, (1 - np.exp(-s / 0.0025)) * np.exp(-s / tau))[:m]
    return (1 - beta) + beta * y / (y.mean() + 1e-9)


def water(d, x_pts, far=FAR_SH, near=NEAR_SH, level=None, den=(0.5, 0.9), hits=(), q=1.0, bed=-14.0, chirp=0.12, couple=0.7,
          crate=0.7, beta=0.9, hit_gain=2.5):
    """`d` s of broken water, its nearness x following `x_pts` ((time, 0..1) pairs): the spectrum goes from `far` to `near`
    (dB at `OCT`, the mean of each resonator's level) and the bubbles overlapping per ear's filter at 1 kHz from `den`[0] to
    `den`[1]. `level(t)`: dB over time. `hits`: (time, size) of plunging masses: every patch bursts, the top a moment
    after the low (the spray comes down after the slam). Mono."""
    n = nsm(d)
    m = int(d * FR) + 2
    tf = np.arange(m) / FR
    xs, ys = zip(*x_pts)
    xv = np.interp(tf, xs, ys)
    lf, ln = np.interp(np.log(F_BIN), np.log(OCT), far), np.interp(np.log(F_BIN), np.log(OCT), near)
    tau = bubble_q(F_BIN, q) / (np.pi * F_BIN)
    pc = (10 ** (np.linspace(erb_num(60.0), erb_num(8500.0), PATCHES) / 21.4) - 1) / 0.00437
    G = np.array([patch_gain(m, fc, crate * (fc / 200.0) ** 0.35, beta) for fc in pc])
    if len(hits):
        for k, fc in enumerate(pc):
            lag = 0.14 * np.clip(np.log(fc / 500.0) / np.log(6000.0 / 500.0), 0, 1)
            imp = np.zeros(m)
            for th, sz in hits:
                i = int((th + lag) * FR)
                if i < m:
                    imp[i] += sz
            s = np.arange(int(1.6 * FR)) / FR
            G[k] += fftconvolve(imp, np.exp(-s / (0.3 * (fc / 200.0) ** -0.22)) * (1 - np.exp(-s / 0.006)))[:m] * hit_gain
    w = np.exp(-0.5 * ((erb_num(F_BIN)[:, None] - erb_num(pc)[None, :]) / 0.45) ** 2)
    w /= w.sum(axis=1, keepdims=True)
    y = np.zeros(n)
    size = next_fast_len(n + nsm(0.3), real=True)
    spec = np.zeros(size // 2 + 1, complex)
    for i, fc in enumerate(F_BIN):
        g = w[i] @ G
        dens = (den[0] + (den[1] - den[0]) * xv) * (fc / 1000.0) ** 0.25
        lam = dens * (BIN_W[i] / ERB[i]) / tau[i]
        cum = np.cumsum(lam * g) / FR
        k = rng().poisson(cum[-1])
        if k == 0:
            continue
        at = np.interp(rng().random(k) * cum[-1], cum, tf)
        ai = np.minimum((at * FR).astype(int), m - 1)
        lev = lf[i] + (ln[i] - lf[i]) * xv[ai]
        if level is not None:
            lev = lev + level(at)
        h = np.minimum(rng().lognormal(0.0, 0.8, k), 8.0) * g[ai] ** couple
        h = h / np.sqrt(np.mean(h ** 2) + 1e-12)
        qs = rng().uniform(0.8, 1.25, k)
        a = 10 ** (lev / 20) * h * np.sqrt(4.0 / (lam[ai] * tau[i] * qs))
        if fc < SOLO_F:
            fs = fc * 2 ** (rng().uniform(-0.5, 0.5, k) / 13.4)
            cs = chirp * rng().uniform(0.4, 1.6, k)
            ts = tau[i] * qs
            st = (at * SR).astype(int)
            mlen = (ts * 5 * SR).astype(int) + 8
            for j in range(k):
                ml = min(mlen[j], n - st[j])
                if ml < 8:
                    continue
                s = np.arange(ml) / SR
                y[st[j]:st[j] + ml] += a[j] * np.sin(2 * np.pi * fs[j] * (s + 0.5 * cs[j] * s * s / ts[j])) * np.exp(-s / ts[j]) * (1 - np.exp(-s * fs[j] * 6))
        else:
            for qm, cm in ((0.8, 0.6), (1.2, 1.4)):
                sel = rng().random(k) < 0.5
                if not sel.any():
                    continue
                imp = np.zeros(size)
                np.add.at(imp, (at[sel] * SR).astype(int), a[sel])
                ts = tau[i] * qm
                s = np.arange(int(ts * 6 * SR) + 8) / SR
                spec += rfft(imp) * rfft(np.sin(2 * np.pi * fc * (s + 0.5 * chirp * cm * s * s / ts)) * np.exp(-s / ts), size)
    y += irfft(spec, size)[:n]
    if bed is not None:
        # (the thin bed of plain turbulence, so the gaps between events are never empty)
        t = np.arange(n) / SR
        bx = np.interp(t, xs, ys)
        b = np.zeros(n)
        for j, fc in enumerate(OCT):
            b += noise(n, fc / 2 ** 0.5, min(fc * 2 ** 0.5, 15000.0), 3) * 10 ** (np.interp(bx, [0, 1], [far[j], near[j]]) / 20)
        if level is not None:
            b = b * 10 ** (level(t) / 20)
        y += b * 10 ** (bed / 20)
    return y


def plunge(size, bright=1.0):
    """A plunging mass of water coming down: the jet's slam (~100 Hz, Bolin's surf) and the air cavity under it ringing and
    closing (its pitch climbing, 40-70 Hz at this size), a crunch of broken water on it. Unit peak."""
    m = nsm(0.7 + 0.8 * size)
    s = np.arange(m) / SR
    f0 = rng().uniform(46.0, 72.0) / size ** 0.35
    f = f0 * (1 + 0.7 * s / (0.09 + 0.07 * size))
    cav = np.sin(2 * np.pi * np.cumsum(f) / SR) * (1 - np.exp(-s / 0.010)) * np.exp(-s / (0.07 + 0.05 * size))
    jet = noise(m, 70, 210, 2) * (1 - np.exp(-s / 0.005)) * np.exp(-s / (0.045 + 0.03 * size))
    crunch = noise(m, 200, 1500, 2) * (1 - np.exp(-s / 0.004)) * np.exp(-s / (0.05 + 0.05 * size)) * np.clip(grains(m, 60.0, (0.01, 0.03)), 0, 4)
    x = cav + jet * 0.8 + crunch * 0.35 * bright
    return x / (np.abs(x).max() + 1e-12)


def breakers(d, rate, lo=0.6, hi=2.2):
    """When the masses come down: (time, size) pairs, Poisson, `rate(t)` a second, sizes heavy-tailed."""
    return [(tt_, min(lo + rng().pareto(2.2) * 0.45, hi)) for tt_ in P.poisson_times(0.05, d - 0.2, rate)]


def plunges(n, hits, gain=1.0, bright=1.0, fall=0.8):
    """The low layer of `hits`. The bigger ones much the louder."""
    y = np.zeros(n)
    for th, sz in hits:
        put(y, plunge(sz, bright) * gain * sz ** 1.3 * rng().uniform(0.6, 1.0) * fall, th)
    return y


def swell(d, rate, depth_db, rise=0.35, tau=1.8):
    """A level (dB, a function of time) surging: swells that come up quickly and go away slowly, each a sea breaking."""
    m = int(d * FR) + 2
    k = rng().poisson(rate * d)
    x = np.zeros(m)
    np.add.at(x, rng().integers(0, m, k), rng().uniform(0.4, 1.0, k))
    s = np.arange(int(tau * FR * 5)) / FR
    y = fftconvolve(x, (1 - np.exp(-s / rise)) * np.exp(-s / tau))[:m]
    y = y / (y.max() + 1e-9)
    db = depth_db * (y - y.mean())
    tf = np.arange(m) / FR
    return lambda t: np.interp(t, tf, db)


def db_curve(pts):
    """A level in dB through (time, dB) pairs, a function of time."""
    xs, ys = zip(*pts)
    f = PchipInterpolator(xs, ys)
    return lambda t: f(np.clip(t, xs[0], xs[-1]))


def added(*levels):
    return lambda t: sum(f(t) for f in levels)


def bubbles(n, rate, f_lo, f_hi, q=14.0, chirp=0.4, nbins=48, skew=1.3, big=0.4):
    """Bubbles forming and bursting in broken water: Poisson events (`rate`: events a second, one value a sample), each a
    damped, slightly climbing sine at a frequency of its own between `f_lo` and `f_hi` (the lower ones commoner and
    louder), its Q and climb a little different each time, so a stream is never a handful of notes. Sparse ones are
    written event by event; dense ones summed by frequency bin (48 of them, one convolution each). Unit-ish RMS."""
    r = np.asarray(rate, float)
    if r.ndim == 0:
        r = np.full(n, float(r))
    cum = np.cumsum(r) / SR
    k = rng().poisson(cum[-1])
    if k == 0:
        return np.zeros(n)
    at = np.minimum(np.searchsorted(cum, rng().random(k) * cum[-1]), n - 1)
    u = rng().random(k) ** skew
    f = f_lo * (f_hi / f_lo) ** u
    a = rng().lognormal(0.0, 0.7, k) * (f / 1000.0) ** -big
    out = np.zeros(n)
    if k <= 6000:
        qs = q * rng().uniform(0.7, 1.3, k)
        cs = chirp * rng().uniform(0.5, 1.5, k)
        for i in range(k):
            tau = qs[i] / (np.pi * f[i])
            m = min(int(tau * SR * 6) + 8, n - at[i])
            if m < 4:
                continue
            s = np.arange(m) / SR
            out[at[i]:at[i] + m] += a[i] * np.sin(2 * np.pi * f[i] * (s + 0.5 * cs[i] * s * s / tau)) * np.exp(-s / tau) * (1 - np.exp(-s / 0.0003))
    else:
        bi = np.minimum((u * nbins).astype(int), nbins - 1)
        for b in range(nbins):
            sel = bi == b
            if not sel.any():
                continue
            imp = np.zeros(n)
            np.add.at(imp, at[sel], a[sel])
            fc = f_lo * (f_hi / f_lo) ** ((b + 0.5) / nbins)
            tau = q / (np.pi * fc)
            s = np.arange(int(tau * SR * 6) + 8) / SR
            kern = np.sin(2 * np.pi * fc * (s + 0.5 * chirp * s * s / tau)) * np.exp(-s / tau) * (1 - np.exp(-s / 0.0003))
            out += fftconvolve(imp, kern)[:n]
    return T.unit(out) if np.any(out) else out


def timber_groan(d, lvl, lo=70.0, hi=900.0, wild=0.4):
    """Wood straining under a huge weight, `d` s: stick-slip creaking through the trunk's body and a low grinding under it,
    no pitch, dry; unit-ish RMS times `lvl`."""
    n = int(SR * d)
    t = np.arange(n) / SR
    env = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 1.5
    x = H.creak(d, rng().uniform(14, 36), env, wild=wild)
    x = band(x, lo, hi, 2)
    g = H.groan(d, env)
    y = T.unit(x) * 0.8 + T.unit(g) * 0.7
    return y * env * lvl


def debris_thud(size):
    """A trunk or a beam knocking something, dull and low, no ring. Unit peak."""
    m = nsm(0.25 + 0.3 * size)
    x = T.thud(m, size)
    put(x, F.knock(0.6 + size, 0.15) * 0.6, 0.0)
    return x / (np.abs(x).max() + 1e-12)


def accents(n, d, items, fc_track=None):
    """Timber groaning, debris knocking and water slapping scattered through a bed `d` s long. `items`: (kind, count,
    level (linear, against unit), t_lo, t_hi, size lo, size hi). Returns the sum (dry); `fc_track` softens it."""
    out = np.zeros(n)
    for kind, count, lvl, t0, t1, s0, s1 in items:
        for _ in range(count):
            at = rng().uniform(t0, t1)
            size = rng().uniform(s0, s1)
            a = lvl * rng().lognormal(0.0, 0.35)
            if kind == "groan":
                put(out, timber_groan(rng().uniform(0.7, 1.6) * (0.6 + 0.5 * size), a * 0.6), at)
            elif kind == "thud":
                put(out, debris_thud(size) * a, at)
            elif kind == "slap":
                put(out, slap_event(size, 0.0) * a, at)
            elif kind == "snap":
                put(out, F.fracture(size, 0.6, dull=0.6) * a * 0.5, at)
                put(out, debris_thud(size * 0.7) * a * 0.3, at)
    if fc_track is not None:
        out = lowpass_to(out, fc_track)
    return out


# ============================================================================================================  output
def decoded_mono(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(float)


def true_peak(x):
    return float(np.abs(resample_poly(x, 4, 1)).max())


def out_path(name):
    return f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"


def decoded(name):
    """One of this set's files as the game plays it: decoded, mono. None if it is not built yet."""
    p = out_path(name) + ".ogg"
    return decoded_mono(p) if Path(p).exists() else None


def write(name, x, db=None, peak_db=None, fade_in=0.0, fade_out=0.05, lowcut=14.0, quiet=False, crest=None):
    """Write mono `x` as tsunami/`name`.ogg: DC out, band-limited to 15 kHz, a causal low cut at `lowcut` Hz (the sub
    clean, nothing ringing ahead of a hit), faded at the ends, and either its loudest 400 ms at `db` or its peak at
    `peak_db`; with `crest` the peaks above `crest` times that loudest 400 ms are soft-clipped (a noise bed's rare peaks
    rounded off, so it can be as loud as the mix's headroom allows); peaks over the ceiling are then limited (look-ahead)
    until the decoded true peak is under TP_MAX. The mix balance (`TRIM`) is added to the level."""
    x = np.asarray(x, float)
    x = x - x.mean()
    x = band(x, None, 15000.0, 4)
    x = PB.causal_lowcut(x, lowcut)
    n = len(x)
    if fade_in > 0:
        k = nsm(fade_in)
        x[:k] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, k))
    k = nsm(fade_out)
    x[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    db = db + TRIM.get(name, 0.0) if db is not None else None
    peak_db = peak_db + TRIM.get(name, 0.0) if peak_db is not None else None
    g = 10 ** (db / 20) / (T.loudest(x) + 1e-12) if db is not None else 10 ** (peak_db / 20) / (np.abs(x).max() + 1e-12)
    if crest is not None and db is not None:
        # (the soft clip takes some of the level with it: raised until the clipped file's loudest 400 ms is at `db`)
        c = crest * 10 ** (db / 20)
        for _ in range(8):
            got = T.loudest(PB.soft_clip(x * g, c, 0.7))
            err = 10 ** (db / 20) / (got + 1e-12)
            g *= err
            if abs(20 * np.log10(err)) < 0.05:
                break
        x = PB.soft_clip(x * g, c, 0.7)
    else:
        x = x * g
    c = TP_MAX * 0.97
    lim = 0.0
    y, dec, tp = x, None, 0.0
    for _ in range(8):
        if np.abs(x).max() > c:
            lim = 20 * np.log10(np.abs(x).max() / c)
            y = PB.limit(x[:, None], c)[:, 0]
        else:
            y = x.copy()
        PB.write_ogg(out_path(name), y, 1)
        dec = decoded_mono(out_path(name) + ".ogg")
        tp = true_peak(dec)
        if tp <= TP_MAX:
            break
        c *= TP_MAX / tp * 0.995
    if not quiet:
        size = Path(out_path(name) + ".ogg").stat().st_size / 1024
        warn = f"  (peaks limited by {lim:.1f} dB: lower its level)" if lim > 2.0 else ""
        print(f"wrote {TH}/{name:13s} {n / SR:5.2f}s  mono  loudest {20 * np.log10(T.loudest(dec) + 1e-12):6.1f} dB  "
              f"peak {20 * np.log10(np.abs(dec).max()):6.2f} dBFS  true peak {20 * np.log10(tp):6.2f} dBTP  {size:5.0f} KB{warn}")
    return dec


# ===============================================================================================  the far rupture
def rupture():
    d = 7.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(71001):
        # (a small thud first: what arrives ahead through the rock; then the push, a heave with a long fall to it)
        x = sine_thump(n, 0.55, 58.0, 34.0, 9.0, 0.02, 0.22, 0.28)
        x += sine_thump(n, 0.62, 31.0, 24.0, 4.0, 0.05, 0.35, 0.2)
        x += sine_thump(n, 1.10, 44.0, 20.0, 3.4, 0.045, 0.62, 1.0)
        x += sine_thump(n, 1.18, 27.0, 18.0, 2.0, 0.08, 0.9, 0.7)
        x += sine_thump(n, 1.9, 36.0, 21.0, 3.0, 0.09, 0.5, 0.28)
        # (a rumble that sinks: noise in a narrow band whose ceiling falls from ~170 Hz to ~40, swelling in over a third of
        # a second and easing over the six seconds after; a shudder through its first three seconds)
        base = noise(n, 18, 260, 2)
        fc = glide_fc(n, [(0.0, 190.0), (1.2, 150.0), (3.0, 85.0), (7.0, 38.0)])
        rum = T.unit(lowpass_to(base, fc))
        env = curve_db(t, [(0.0, -80), (0.7, -34), (1.15, -9), (1.7, -10), (3.2, -17), (5.0, -27), (7.0, -52)])
        shud = np.clip(1 + 0.85 * PB.slow_random(n, 7.0, 11.0), 0.05, None)
        shud = 1 + (shud - 1) * np.exp(-np.maximum(t - 1.1, 0) / 1.6)
        rum = rum * env * shud * wander(n, 0.15, 1.2, 3.0)
        x += rum * 1.2
        # (rolls of low thunder behind it and the rock grinding in the low mids)
        rl, rr = PB.thunder_rolls(d, 1.0, count=9, length=5.0)
        x += (rl + rr) / 2 * 0.12
        grind = noise(n, 90, 420, 2) * np.clip(grains(n, 20.0, (0.05, 0.12, 0.3)), 0, 5) ** 1.2 \
            * curve_db(t, [(0.0, -80), (0.9, -40), (1.5, -24), (3.5, -29), (6.0, -45), (7.0, -70)])
        x += grind * 0.6
        x = lows_harm(x, -11.0)
    write("rupture", x, peak_db=-5.0, fade_in=0.08, fade_out=1.8)


# ===================================================================================================  the rumble
def rumble():
    d = 18.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(71101):
        bed = noise(n, 18, 70, 3) * curve_db(t, [(0, -42), (1, -32), (3, -25), (6, -22), (11, -21), (14.0, -24), (16.0, -34), (18, -52)]) \
            * wander(n, 0.1, 0.9, 3.0)
        x = bed.copy()
        tr, k = 0.7, 0
        while tr < d - 3.5:
            near = min(tr / 7.0, 1.0) * (1.0 - 0.6 * np.clip((tr - 11.0) / 4.0, 0, 1))
            ln = rng().uniform(1.6, 3.2)
            m = nsm(ln)
            s = np.arange(m) / SR
            env = (1 - np.exp(-s / rng().uniform(0.15, 0.45))) ** 2 * np.exp(-s / rng().uniform(0.55, 1.1))
            env /= env.max() + 1e-9
            hi = 150 + 90 * near
            lvl = 10 ** ((-31.0 + 10.0 * near + rng().uniform(-2.5, 2.5)) / 20)
            sw = noise(m, 22, hi, 2) * env * np.clip(grains(m, 11.0, (0.05, 0.12, 0.3)), 0, 4) ** 0.6
            put(x, sw * lvl, tr)
            tr += rng().gamma(1.8, 0.85 - 0.3 * near)
            k += 1
        # (heavier thumps rolling through it, more of them as it grows)
        for tb in sorted(rng().uniform(2.0, 15.5) for _ in range(9)):
            a = 10 ** ((-27.0 + 6.0 * min(tb / 7.0, 1.0) - 6.0 * np.clip((tb - 11.0) / 4.0, 0, 1)) / 20) * rng().uniform(0.7, 1.3)
            put(x, sine_thump(nsm(2.6), 0.0, rng().uniform(34, 46), 22.0, 3.0, 0.12, rng().uniform(0.5, 0.9), a), tb)
        grind = noise(n, 70, 330, 2) * np.clip(grains(n, 13.0, (0.08, 0.2, 0.5)), 0, 4) ** 1.1 \
            * curve_db(t, [(0, -70), (2, -44), (6, -36), (12, -37), (16, -46), (18, -70)])
        x += grind
        rl, rr = PB.thunder_rolls(d, 0.0, count=11, length=13.0)
        x += (rl + rr) / 2 * 0.1
        x = band(x, None, 360.0, 4)
        x = lows_harm(x, -12.0, f_hi=80.0, lo=60.0, hi=240.0)
        x = band(x, None, 360.0, 4)
    write("rumble", x, db=-19.0, fade_in=1.8, fade_out=3.0, crest=2.0)


# ======================================================================================================  the roars
FAR_LEN, FAR_DB = 9.5, -15.5


def roar_far():
    # (the wall a kilometre and more off as it stands up on the horizon: at once huge, a deep rolling of water that carries;
    # the first big seas come down as the horizon rises, 0.75 s in, that is about 1.65 s into the strike)
    d = FAR_LEN
    n = nsm(d)
    with PB.seeded(72001):
        lvl = added(db_curve([(0.0, -34.0), (0.65, -2.0), (2.0, -1.5), (6.0, -0.5), (d, 0.0)]), swell(d, 0.42, 5.0, 0.25, 1.5))
        hits = [(0.75, 2.2), (1.9, 1.2), (2.6, 1.6), (3.3, 1.1), (4.3, 1.5), (5.0, 1.2)] + [h for h in breakers(d, lambda v: 1.0) if h[0] > 5.4]
        x = water(d, [(0.0, 0.14), (d, 0.42)], level=lvl, den=(0.9, 1.1), hits=hits, bed=-11.0, hit_gain=0.9)
        x = x + plunges(n, hits, np.std(x) * 1.3, bright=0.5)
        ir = T.outdoor_ir(2.2, 70, density=60.0, darken=(1800, 260), decay=0.8)
        x = x + fftconvolve(x, ir)[:n] * 0.32
        x = lowpass_to(x, glide_fc(n, [(0.0, 2400.0), (d, 3600.0)]))
        x = lows_harm(x, -11.0, f_hi=80.0, lo=60.0, hi=260.0)
    return write("roar_far", x, db=FAR_DB, fade_in=0.45, fade_out=3.0, crest=1.9)


def roar_mid():
    d = MID_LEN
    n = nsm(d)
    with PB.seeded(72101):
        lvl = added(db_curve([(0.0, -8.0), (d - 2.0, 0.0), (d, 0.0)]), swell(d, 0.55, 5.0, 0.22, 1.2))
        hits = breakers(d, lambda v: 1.1 + 0.9 * v / d, 0.6, 2.4)
        x = water(d, [(0.0, 0.36), (d, 0.85)], level=lvl, den=(0.9, 1.2), hits=hits, bed=-12.0, hit_gain=1.3)
        x = x + plunges(n, hits, np.std(x) * 1.2, bright=0.7)
        x = lows_harm(x, -12.0, f_hi=80.0, lo=60.0, hi=260.0)
    # (its last 4 s always lie under roar_near's first 4: their peaks are kept down there)
    ceil_k = 1.6 - 0.5 * np.clip((np.arange(n) / SR - (d - 4.0)) / 1.5, 0, 1)
    return write("roar_mid", x, db=-14.0, fade_in=2.2, fade_out=3.6, crest=ceil_k)


def near_signal():
    """The wall coming the last 4 s and going on past: `roar_near` cuts it at the immersion (NEAR_PRE), `roar_pass` lets
    it go by for a player it does not reach."""
    d = PASS_LEN
    n = nsm(d)
    with PB.seeded(72201):
        lvl = added(db_curve([(0.0, -5.0), (NEAR_PRE, 0.0), (NEAR_PRE + 1.0, -0.5), (d, -1.5)]), swell(d, 0.7, 6.0, 0.18, 1.0))
        hits = breakers(d, lambda v: 1.6 + 1.6 * min(v / NEAR_PRE, 1.0), 0.7, 2.6)
        x = water(d, [(0.0, 0.66), (NEAR_PRE, 1.0), (d, 1.0)], level=lvl, den=(0.9, 1.3), hits=hits, bed=-12.0)
        x = x + plunges(n, hits, np.std(x) * 1.25, bright=1.0)
        # (what the front is dragging, only in its last 60 blocks: heavy dull knocks, no single board)
        acc = accents(n, d, [("thud", 7, 1.4, 2.4, 3.9, 0.8, 2.0), ("snap", 4, 0.9, 2.8, 3.8, 0.8, 1.6)], np.full(n, 1500.0))
        x = x + acc * np.std(x) * 0.8
        return lows_harm(x, -13.0, f_hi=80.0, lo=60.0, hi=260.0)


def roar_near():
    x = near_signal()[:nsm(ROAR_NEAR_LEN)]
    n = len(x)
    t = np.arange(n) / SR
    # the immersion NEAR_PRE s in: a breath of 120 ms first (the hit lands out of it), then the air's roar is cut by
    # what the head is now in: the level drops at once, the top closes in a third of a second, the rest dies under the churn
    k = nsm(NEAR_PRE)
    u = np.maximum(t - NEAR_PRE, 0)
    fc = np.where(t < NEAR_PRE, 14000.0, 420.0 + 11000.0 * np.exp(-u / 0.12))
    y = lowpass_to(x, fc)
    g = np.where(t < NEAR_PRE, 1.0, 10 ** (-12.0 / 20) * 10 ** (-24.0 * np.minimum(u / 2.0, 1.0) ** 0.8 / 20))
    g *= 1 - (1 - 10 ** (-4.5 / 20)) * np.clip((t - (NEAR_PRE - 0.13)) / 0.1, 0, 1) * (t < NEAR_PRE)
    return write("roar_near", y * g, db=NEAR_DB, fade_in=2.2, fade_out=0.05, crest=1.35 + 0.3 * np.clip((t - 2.4) / 1.2, 0, 1))


def roar_pass():
    x = near_signal()
    n = len(x)
    t = np.arange(n) / SR
    x = x * curve_db(t, [(0.0, 0.0), (NEAR_PRE + 1.0, 0.0), (NEAR_PRE + 3.0, -5.0), (PASS_LEN, -16.0)])
    x = lowpass_to(x, glide_fc(n, [(0.0, 14000.0), (NEAR_PRE + 1.0, 14000.0), (PASS_LEN, 2400.0)]))
    return write("roar_pass", x, db=NEAR_DB, fade_in=2.2, fade_out=2.5, crest=1.35 + 0.3 * np.clip((t - 2.4) / 1.2, 0, 1))


def roar_back():
    # (the wave going off over the far land: the same water, ever further)
    d = 12.0
    n = nsm(d)
    with PB.seeded(72301):
        lvl = added(db_curve([(0.0, 0.0), (3.0, -7.0), (7.0, -15.0), (d, -28.0)]), swell(d, 0.4, 6.0, 0.3, 1.6))
        hits = breakers(d, lambda v: 0.7 * np.exp(-v / 5.0))
        x = water(d, [(0.0, 0.3), (d, 0.0)], level=lvl, den=(0.6, 0.8), hits=hits, bed=-13.0)
        x = x + plunges(n, hits, np.std(x) * 1.5, bright=0.3)
        ir = T.outdoor_ir(2.2, 70, density=60.0, darken=(1500, 220), decay=0.8)
        x = x + fftconvolve(x, ir)[:n] * 0.3
        x = lowpass_to(x, glide_fc(n, [(0.0, 1900.0), (d, 480.0)]))
        x = lows_harm(x, -14.0, f_hi=80.0, lo=60.0, hi=260.0)
    write("roar_back", x, db=-28.0, fade_in=1.5, fade_out=3.0, crest=3.2)


# ==========================================================================================================  engulf
ENGULF_FOAM = 1.5      # s of violent foam (the pass's) before the drop into the dark


def engulf():
    # The loudest, heaviest thing in the strike, on the sample of `tp`: the slam, 0.15 s blown white (everything, up to the
    # top), 1.5 s of violent foam shut in round the head, then the drop into the dark
    d = 4.0
    n = nsm(d)
    t = np.arange(n) / SR
    F_ = ENGULF_FOAM
    with PB.seeded(73001):
        low = sine_thump(n, 0.0, 62.0, 26.0, 6.0, 0.003, 0.5, 1.0) + sine_thump(n, 0.03, 34.0, 22.0, 3.0, 0.02, 0.8, 0.8) \
            + sine_thump(n, 0.34, 46.0, 24.0, 4.0, 0.03, 0.55, 0.7) + sine_thump(n, 0.82, 40.0, 24.0, 4.0, 0.04, 0.5, 0.45)
        smack = noise(n, 70, 9000, 1) * np.exp(-t / 0.016)
        hits = [(0.0, 2.8), (0.17, 1.5), (0.40, 2.2), (0.66, 1.3), (0.93, 1.9), (1.21, 1.2)]
        lvl = db_curve([(0.0, 2.0), (0.15, 2.0), (0.5, 0.0), (F_, -1.0), (F_ + 0.25, -11.0), (d, -26.0)])
        foam = water(d, [(0.0, 1.0), (d, 1.0)], near=np.array([-12.0, -5.0, -1.0, 0.0, 0.0, 0.0, -2.0, -6.0, -12.0]), level=lvl, den=(1.5, 1.5), hits=hits, bed=-9.0, crate=1.1)
        foam = lowpass_to(foam, glide_fc(n, [(0.0, 14000.0), (0.15, 11000.0), (0.5, 4200.0), (F_, 1900.0), (F_ + 0.25, 720.0), (d, 380.0)]))
        foam = T.unit(foam)
        pl = plunges(n, hits, 1.0, bright=1.0, fall=1.0)
        x = low * 1.0 + smack * 0.8 + foam * 0.62 + pl * 0.5
        x = lows_harm(x, -9.0, f_hi=90.0, lo=70.0, hi=300.0)
    write("engulf", x, db=ENGULF_DB, fade_in=0.002, fade_out=1.2, crest=1.32, lowcut=20.0)


# ============================================================================================================  under
UNDER_AT = 0.2         # tp + this
UNDER_LEN = SURF_AT - UNDER_AT + 0.3     # (it ends 0.3 s after the head is out, under the surface's own burst)
TREE_AT, CHUNK_AT = 1.3, 3.2


def uw_knock(kind, size=1.0):
    """Something solid knocking under water, heard through it: wood hollow and short, stone a harder clack. Unit peak."""
    if kind == "wood":
        f0 = rng().uniform(170.0, 400.0) / size ** 0.5
        h = P.modal_hit(nsm(0.3), f0, [1.0, rng().uniform(1.9, 2.4), rng().uniform(3.1, 3.9)], [0.05 * size, 0.022, 0.01], [1.0, 0.45, 0.2], 0.5, 1800.0)
    else:
        f0 = rng().uniform(320.0, 880.0) / size ** 0.4
        h = P.modal_hit(nsm(0.22), f0, [1.0, rng().uniform(1.5, 1.9), rng().uniform(2.4, 3.3)], [0.02, 0.012, 0.006], [1.0, 0.6, 0.3], 0.5, 2400.0)
    th = debris_thud(0.5 + 0.6 * size)
    y = np.zeros(max(len(h), len(th)))
    y[:len(h)] += h / (np.abs(h).max() + 1e-12)
    y[:len(th)] += th * 0.5
    return y / (np.abs(y).max() + 1e-12)


def bubble_cloud(d, rate, lo, hi, q=16.0):
    """A cloud of bubbles close to the ear, `rate` a second at its middle, swelling and gone in `d` s. Clear, each one heard."""
    m = nsm(d)
    s = np.arange(m) / SR
    r = rate * np.sin(np.pi * np.clip(s / d, 0, 1)) ** 2
    return bubbles(m, r, lo, hi, q=q, chirp=0.35, skew=1.0, big=0.5)


def tree_past(d=2.6):
    """A whole tree going by close: the push of the water in front of it, a long creak, its limbs knocking as it rolls, the
    air it drags streaming off it. Unit-ish. Everything under ~1 kHz."""
    m = nsm(d)
    s = np.arange(m) / SR
    bell = np.exp(-0.5 * ((s - 1.0) / 0.48) ** 2)
    x = T.unit(noise(m, 24, 110, 3)) * bell * 1.5
    x += T.unit(noise(m, 110, 420, 2) * np.clip(grains(m, 25.0, (0.03, 0.08)), 0, 4)) * bell * 0.38
    put(x, timber_groan(1.5, 0.75, 60, 520), 0.5)
    at = 0.55
    while at < 1.9:
        put(x, uw_knock("wood", rng().uniform(0.9, 1.7)) * rng().uniform(0.4, 1.0), at)
        at += rng().uniform(0.11, 0.42)
    return x


def chunk_past(d=2.8):
    """A piece of a house going over, close: the heavy blow of it, stone clattering off it, a beam groaning, the air shut in it
    getting out in big slow gulps."""
    m = nsm(d)
    x = sine_thump(m, 0.25, 54.0, 30.0, 5.0, 0.012, 0.42, 1.5)
    th = debris_thud(2.4)
    put(x, lowpass_to(th, np.full(len(th), 320.0)) * 1.1, 0.25)
    at = 0.27
    while at < 1.8:
        put(x, uw_knock("stone", rng().uniform(0.7, 1.5)) * rng().uniform(0.25, 0.9) * np.exp(-(at - 0.27) / 1.4), at)
        at += rng().uniform(0.04, 0.26)
    put(x, uw_knock("wood", 1.6) * 0.8, 0.34)
    put(x, timber_groan(1.2, 0.6, 60, 460), 0.8)
    at = 0.7
    while at < 2.4:
        put(x, glug(rng().uniform(110, 260), rng().uniform(1.0, 1.6)) * rng().uniform(0.2, 0.5), at)
        at += rng().uniform(0.09, 0.3)
    return x


def under():
    d = UNDER_LEN
    n = nsm(d)
    t = np.arange(n) / SR
    rise = d - 1.5                       # the pull up to the surface starts here
    with PB.seeded(74001):
        # the dark churn: the water itself in the bubbles' lowest grains, heavily shut in; a slow heave under it
        lvl = added(db_curve([(0.0, 0.0), (1.2, 0.5), (rise, -0.5), (d, -7.0)]), swell(d, 0.45, 7.0, 0.3, 1.1))
        hits = breakers(d, lambda v: 1.0)
        churn = water(d, [(0.0, 1.0), (d, 1.0)], near=UNDER_SH, level=lvl, den=(1.3, 1.3), hits=hits, bed=-10.0, q=0.8)
        press = noise(n, 22, 60, 3) * wander(n, 0.15, 0.8, 4.5) * 0.9
        churn = T.unit(churn)
        x = churn + press * curve_db(t, [(0.0, 0.0), (rise, 0.0), (d, -8.0)])
        x += plunges(n, hits, 0.8, bright=0.0, fall=0.7)
        # solid things going by: the two big ones, and knocks of every size, near and far
        solid = np.zeros(n)
        put(solid, tree_past() * 0.8, TREE_AT)
        put(solid, chunk_past() * 0.85, CHUNK_AT)
        for at in sorted(rng().uniform(0.2, d - 0.8) for _ in range(16)):
            put(solid, uw_knock("wood" if rng().random() < 0.55 else "stone", rng().uniform(0.6, 1.6)) * rng().uniform(0.2, 0.75), at)
        ir_n = nsm(0.5)
        s_ = np.arange(ir_n) / SR
        ir = band(rng().standard_normal(ir_n), None, 700.0, 2) * np.exp(-s_ / 0.11)
        solid = solid + fftconvolve(solid, ir / np.sqrt(np.sum(ir ** 2)))[:n] * 0.45
        x = lowpass_to(x + solid, glide_fc(n, [(0.0, 700.0), (rise, 760.0), (d - 0.3, 1000.0), (d, 1000.0)]))
        x = band(x, None, 1050.0, 3)
        # bubbles close to the ear: the only thing up here. Clouds of them streaming past, the air leaving the head at the
        # start, and rushing up with the player at the end
        bub = np.zeros(n)
        put(bub, bubble_cloud(1.3, 260.0, 500, 2400) * 0.9, 0.0)
        for at in sorted(rng().uniform(0.9, rise - 0.3) for _ in range(9)):
            put(bub, bubble_cloud(rng().uniform(0.25, 0.8), rng().uniform(60.0, 180.0), 420, rng().uniform(1300, 2400)) * rng().uniform(0.25, 0.8), at)
        put(bub, bubble_cloud(1.6, 340.0, 600, 3200) * 1.0, rise - 0.1)
        x = x + bub * np.std(x) * 0.55
        x = lows_harm(x, -11.0, f_hi=80.0, lo=60.0, hi=240.0)
        # (under the engulf's foam until it drops, ENGULF_FOAM s after tp: it comes up out of it)
        x = x * curve_db(t + UNDER_AT, [(0.0, -11.0), (ENGULF_FOAM - 0.05, -11.0), (ENGULF_FOAM + 0.35, 0.0), (10.0, 0.0)])
    write("under", x, db=-16.0, fade_in=0.3, fade_out=0.3, crest=2.6)


# ==========================================================================================================  surface
def surface():
    # The head out: on the sample of tp + SURF_AT the world opens: all the top that has been missing for six seconds, the
    # size of the air round the player, the water pouring off the head and shoulders
    d = 3.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(75001):
        burst = noise(n, 120, 9000, 1) * (1 - np.exp(-t / 0.0015)) * np.exp(-t / 0.035)
        lvl = db_curve([(0.0, 0.0), (0.25, 0.0), (1.0, -4.0), (2.0, -11.0), (d, -24.0)])
        hits = [(0.02, 1.6), (0.3, 0.9), (0.62, 0.7), (1.1, 0.6)]
        opn = water(d, [(0.0, 1.0), (d, 1.0)], near=np.array([-22.0, -13.0, -6.0, -2.0, 0.0, 0.0, -1.0, -3.0, -8.0]), level=lvl, den=(1.2, 1.2), hits=hits, bed=-9.0)
        # sheets of water off the head: fast, close and high; then runs of drops
        drops = bubbles(n, 900.0 * np.exp(-t / 0.8) + 40.0, 900, 6000, q=11.0) * curve_db(t, [(0.0, -80), (0.08, -5), (1.2, -11), (d, -26)])
        x = T.unit(opn) + burst * 0.7 + drops * 0.4 + plunges(n, hits, 0.5, bright=1.0)
        # (the air: the first thing the ear gets back is how big the outside is)
        ir = T.outdoor_ir(1.8, 30, density=120.0, darken=(6500, 900), decay=0.6)
        x = x + fftconvolve(x, ir)[:n] * 0.35
        for at, sz in ((0.1, 0.7), (0.34, 1.0), (0.7, 0.5), (1.05, 0.6), (1.5, 0.4), (1.9, 0.3)):
            put(x, slap_event(sz, 1.0) * 0.2 * (1.2 - 0.5 * at / d), at)
        x = lows_harm(x, -13.0, f_hi=80.0, lo=60.0, hi=260.0)
    write("surface", x, db=-13.5, fade_in=0.002, fade_out=0.9, crest=1.8)


# ==========================================================================================================  torrent
def torrent():
    # Riding the falling water down: the whole land's water pouring away round the player, loud at first, falls off every
    # edge; it thins, the low weight going first, the grains falling apart into separate running water
    d = 13.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(75501):
        lvl = added(db_curve([(0.0, -0.5), (2.0, 0.0), (4.0, -3.5), (7.0, -10.0), (10.0, -19.0), (d, -40.0)]), swell(d, 0.5, 5.0, 0.2, 1.0))
        hits = breakers(d, lambda v: 2.2 * np.exp(-v / 3.8), 0.5, 1.5)
        x = water(d, [(0.0, 1.0), (4.0, 0.95), (8.5, 0.45), (d, 0.0)], far=RILL_SH, near=TORRENT_SH, level=lvl, den=(0.14, 1.7), hits=hits, bed=-13.0, q=1.1)
        x = T.unit(x) + plunges(n, hits, 0.9, bright=0.8, fall=0.8)
        x = lows_harm(x, -13.0, f_hi=80.0, lo=60.0, hi=260.0)
    write("torrent", x, db=-13.5, fade_in=0.45, fade_out=2.5, crest=1.8)


# ============================================================================================================  drain
def glug(f0, size=1.0):
    """One glug of water draining from a hollow: a bubble forming and bursting, pitch rising a third, low and round."""
    m = nsm(0.12 + 0.25 * size)
    s = np.arange(m) / SR
    f = f0 * (1 + 0.38 * (1 - np.exp(-s / 0.045)))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR + rng().uniform(0, 6.28)) * (1 - np.exp(-s / 0.006)) * np.exp(-s / (0.045 + 0.06 * size))
    x += noise(m, f0 * 1.5, f0 * 6, 2) * np.exp(-s / 0.012) * 0.25
    return x / (np.abs(x).max() + 1e-12)


def rill(d, fc, level_db, den=0.25):
    """One run of water over stones, `d` s, its bubbles around `fc` Hz; swells and thins on its own."""
    sh = -30.0 * np.abs(np.log2(OCT / fc)) ** 1.4
    lvl = added(db_curve([(0.0, -30.0), (0.25 * d, -1.0), (0.6 * d, -3.0), (d, -30.0)]), swell(d, 0.9, 7.0, 0.1, 0.5))
    y = water(d, [(0.0, 1.0), (d, 1.0)], near=np.maximum(sh, -60.0), level=lvl, den=(den, den), bed=None, q=1.3, crate=1.0)
    return T.unit(y) * 10 ** (level_db / 20)


def drain():
    # The water running off the land, in streams now: each its own, some near; glugs from every hollow; the first stones
    # and timber settling. Quiet by the time the strike ends at any distance
    d = 12.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(76001):
        x = np.zeros(n)
        for at, ln, fc, db_ in ((0.0, 8.5, 650.0, -2.0), (0.4, 7.0, 1300.0, 0.0), (1.8, 7.5, 2100.0, -3.0), (3.6, 6.5, 950.0, -4.0), (5.5, 5.5, 1700.0, -7.0), (6.8, 4.5, 2600.0, -11.0)):
            put(x, rill(ln, fc, db_), at)
        sd = np.std(x[:nsm(5.0)])
        for tc in sorted(rng().uniform(0.3, 9.0) for _ in range(13)):
            f0 = rng().uniform(140, 420)
            for j in range(rng().integers(3, 9)):
                put(x, glug(f0 * (1 + 0.08 * rng().standard_normal()), rng().uniform(0.5, 1.4)) * sd * 0.8 * np.exp(-tc / 7.0) * rng().uniform(0.5, 1.0), tc + j * rng().uniform(0.06, 0.16))
        for _ in range(5):
            at = rng().uniform(0.3, 7.0)
            put(x, slap_event(rng().uniform(0.3, 0.7), 0.0) * sd * 0.6 * np.exp(-at / 6.0), at)
        for _ in range(7):
            at = rng().uniform(0.4, 9.0)
            put(x, debris_thud(rng().uniform(0.4, 1.2)) * sd * 0.7 * np.exp(-at / 7.0), at)
        x = x * curve_db(t, [(0.0, -12.0), (2.0, -2.0), (4.0, 0.0), (7.0, -6.0), (9.5, -18.0), (d, -46.0)])
        x = lows_harm(x, -14.0, f_hi=80.0, lo=60.0, hi=260.0)
    write("drain", x, db=-20.0, fade_in=0.5, fade_out=2.0, crest=3.4)


# ====================================================================================================  rumble_after
def rumble_after():
    d = 12.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(77001):
        x = noise(n, 18, 75, 3) * curve_db(t, [(0, -28), (2, -26), (6, -34), (10, -46), (12, -70)]) * wander(n, 0.1, 0.8, 3.5)
        tr = 0.6
        while tr < d - 3.0:
            ln = rng().uniform(1.8, 3.0)
            m = nsm(ln)
            s = np.arange(m) / SR
            env = (1 - np.exp(-s / rng().uniform(0.2, 0.5))) ** 2 * np.exp(-s / rng().uniform(0.6, 1.2))
            env /= env.max() + 1e-9
            sw = noise(m, 22, 140, 2) * env * np.clip(grains(m, 9.0, (0.06, 0.15, 0.4)), 0, 4) ** 0.6
            put(x, sw * 10 ** ((-33.0 - 8.0 * tr / d + rng().uniform(-2, 2)) / 20), tr)
            tr += rng().gamma(1.8, 1.1)
        for tb in sorted(rng().uniform(0.8, 8.5) for _ in range(4)):
            put(x, sine_thump(nsm(2.2), 0.0, rng().uniform(32, 42), 21.0, 3.0, 0.1, rng().uniform(0.4, 0.7), 10 ** ((-31.0 - 7.0 * tb / d) / 20)), tb)
        x = band(x, None, 300.0, 4)
        x = lows_harm(x, -14.0, f_hi=70.0, lo=55.0, hi=210.0)
        x = band(x, None, 300.0, 4)
    write("rumble_after", x, db=-27.0, fade_in=1.2, fade_out=3.5)


# ================================================================================================  crash (the target)
CRASH_D = 16.0
CRASH_LEVEL = -11.5


def wood_snap(size, dull):
    """One trunk or heavy beam going: a ragged break of fibres with a dull thud in it. Peak-ish unit."""
    m = nsm(0.5 + 0.4 * size)
    x = np.zeros(m)
    count = int(8 + 14 * size)
    for u in np.sort(rng().beta(0.8, 2.0, count)):
        big = min(rng().pareto(1.8) * 0.4 + 0.3, 2.5) * size
        put(x, F.fracture(big, 0.8, dull=dull) * (0.3 + 0.7 * rng().random()) * (1 - 0.5 * u), 0.09 * size * u)
    put(x, F.knock(1.4 * size, 0.1) * 0.7, rng().uniform(0.004, 0.02))
    put(x, T.thud(nsm(0.5 + 0.3 * size), 1.5 * size) / 5.0 * (0.6 + 0.4 * size), rng().uniform(0.01, 0.05))
    return x / (np.abs(x).max() + 1e-12)


def planks(size, dull, count):
    """Planks and boards breaking: a burst of small fractures with knocks."""
    m = nsm(0.4 + 0.4 * size)
    x = np.zeros(m)
    for u in np.sort(rng().beta(0.7, 1.6, count)):
        put(x, F.fracture(rng().uniform(0.2, 0.8) * size, 0.9, dull=dull) * rng().uniform(0.3, 1.0), 0.3 * u)
        if rng().random() < 0.25:
            put(x, F.knock(rng().uniform(0.3, 0.8) * size, 0.5) * rng().uniform(0.2, 0.5), 0.3 * u + rng().uniform(0.005, 0.03))
    return x / (np.abs(x).max() + 1e-12)


def masonry(count, size, dull):
    """Stone coming down in a run: knocks and clacks, a tumble that thins out, a rumble of it under."""
    ln = 0.5 + 0.7 * size
    m = nsm(ln + 0.3)
    s = np.arange(m) / SR
    x = np.zeros(m)
    for u in np.sort(rng().beta(0.8, 1.8, count)):
        sz = rng().uniform(0.3, 1.0) * size
        h = P.modal_hit(nsm(0.18), rng().uniform(500, 2200) / (0.6 + sz), [1.0, rng().uniform(1.45, 2.2), rng().uniform(2.4, 3.9)],
                        [rng().uniform(0.004, 0.014), 0.006, 0.003], [1.0, 0.6, 0.35], 0.5, 9000 * (1 - 0.7 * dull))
        put(x, h / (np.abs(h).max() + 1e-9) * rng().uniform(0.2, 1.0), ln * u)
        if rng().random() < 0.4:
            put(x, F.knock(rng().uniform(0.4, 1.0) * size, 0.3) * rng().uniform(0.2, 0.6), ln * u)
    x += noise(m, 70, 500, 2) * np.clip(grains(m, 60.0, (0.02, 0.05, 0.12)), 0, 5) * np.sin(np.pi * np.clip(s / ln, 0, 1)) * 0.3
    return x / (np.abs(x).max() + 1e-12)


def crush_cluster(span, count, size, dull):
    """A stretch of forest or street going under the front: a dense burst of fractures and knocks over `span` s, the
    heaviest early in it. Peak-ish unit."""
    m = nsm(span + 0.4)
    x = np.zeros(m)
    for u in np.sort(rng().beta(0.7, 1.8, count)):
        sz = min(rng().pareto(2.0) * 0.5 + 0.35, 2.4) * size
        put(x, F.fracture(sz, 0.8, dull=dull) * rng().uniform(0.25, 1.0), span * u)
        if rng().random() < 0.3:
            put(x, F.knock(sz * 1.2, 0.2) * rng().uniform(0.2, 0.6), span * u + rng().uniform(0.003, 0.02))
    return x / (np.abs(x).max() + 1e-12)


def crash():
    # The wave coming down on the land round the target, heard from hundreds of blocks: water and weight. No board, no pane of
    # glass carries that far: what the forest and the houses add is a dark crushing under the water, nothing single.
    d = CRASH_D
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = CRASH_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(78001):
        # ---- the whump: the mass of water coming down on the land (a heave, 40-90 ms in), then the main body of it
        boom = sine_thump(n, t0, 62.0, 36.0, 7.0, 0.045, 1.0, 0.8) + sine_thump(n, t0 + 0.05, 40.0, 30.0, 3.5, 0.08, 1.6, 0.7)
        boom += sine_thump(n, t0 + 0.42, 54.0, 34.0, 5.0, 0.07, 1.3, 1.0) + sine_thump(n, t0 + 0.50, 36.0, 26.0, 3.0, 0.1, 1.8, 0.7)
        boom += sine_thump(n, t0 + 1.05, 46.0, 30.0, 4.0, 0.08, 1.0, 0.5)
        benv = band(np.abs(boom), None, 10, 1)
        low = boom + noise(n, 40, 120, 3) * np.maximum(benv, 0) * 0.5
        # ---- the water: seas coming down one on another over the first seconds, then the roar of it letting go
        lvl = added(db_curve([(0.0, -40.0), (t0 + 0.04, -40.0), (t0 + 0.25, -3.0), (1.1, 0.0), (2.0, -5.0), (4.0, -10.0), (8.0, -19.0), (12.0, -28.0), (d, -40.0)]),
                    swell(d, 0.6, 5.0, 0.2, 1.1))
        hits = [(t0 + 0.02, 2.4), (t0 + 0.42, 2.2), (t0 + 0.8, 1.6), (t0 + 1.05, 2.0), (t0 + 1.5, 1.4)] + [h for h in breakers(d, lambda v: 2.2 * np.exp(-v / 3.5), 0.6, 1.8) if h[0] > 1.7]
        wat = water(d, [(0.0, 0.92), (d, 0.8)], level=lvl, den=(1.1, 1.3), hits=hits, bed=-12.0)
        wat = T.unit(wat)
        pl = plunges(n, hits, 1.0, bright=0.8, fall=1.0)
        # ---- the land under it: a dark crushing, the mass of it (nothing single: the wood and stone are the water's grit)
        crush = np.zeros(n)
        rate = lambda v: 7.0 * np.clip((v - 0.12) / 0.4, 0, 1) * np.exp(-max(v - 1.0, 0) / 1.3) + 0.4 * np.exp(-v / 6.0)
        for tt_ in P.poisson_times(t0 + 0.1, 8.0, rate):
            put(crush, crush_cluster(rng().uniform(0.12, 0.4), int(rng().integers(16, 50)), rng().uniform(0.8, 1.6), rng().uniform(0.6, 0.9)) * rng().uniform(0.3, 0.8), tt_)
        for tt_ in sorted(rng().uniform(t0 + 0.3, 3.8) for _ in range(14)):
            put(crush, masonry(int(rng().integers(12, 40)), rng().uniform(0.8, 1.6), rng().uniform(0.6, 0.9)) * rng().uniform(0.2, 0.5), tt_)
        crush = lowpass_to(crush, np.full(n, 1100.0))
        # ---- the levels: the lows' own 30-120 Hz RMS over their first second is the reference
        i0, i1 = nsm(t0), nsm(t0 + 1.0)
        lref = np.sqrt(np.mean(band(low, 30, 120, 2)[i0:i1] ** 2)) + 1e-12

        def trim(y, db_, a, b):
            return y * lref * 10 ** (db_ / 20) / (np.sqrt(np.mean(band(y, a, b, 2)[nsm(0.5):nsm(3.0)] ** 2)) + 1e-12)
        x = low + trim(wat, -3.0, 60, 3000) + trim(pl, -3.0, 30, 400) + trim(crush, -11.0, 100, 1100)
        # ---- the land's rolls and echoes
        rl, rr = PB.thunder_rolls(d, t0 + 0.6, count=12, length=11.0)
        roll = (rl + rr) / 2
        x += roll * lref * 10 ** (-9.0 / 20) / (T.loudest(roll) + 1e-9) * 0.7
        src = band(x, None, 700, 2) * 0.12
        for dt, gn, hi in ((0.5, 0.26, 1500), (1.2, 0.18, 900), (2.3, 0.12, 560), (3.8, 0.08, 340), (5.5, 0.05, 220)):
            ech = band(src, 25, hi * rng().uniform(0.85, 1.15), 2)
            ir_n = nsm(0.5)
            s_ = np.arange(ir_n) / SR
            ir = rng().standard_normal(ir_n) * np.exp(-s_ / 0.12)
            ir /= np.sqrt(np.sum(ir ** 2))
            ech = fftconvolve(ech, ir)[:n]
            put(x, ech * gn * 4.0, dt)
        ir = T.outdoor_ir(3.0, 80, density=40.0, darken=(2600, 220), decay=1.2)
        x += fftconvolve(x, ir)[:n] * 0.18
        # (what comes from hundreds of blocks off: the top let down over its length, the lows' harmonics for small speakers)
        x = lowpass_to(x, glide_fc(n, [(0.0, 5000.0), (2.0, 3800.0), (6.0, 2500.0), (d, 1300.0)]))
        x = lows_harm(x, -9.0, f_hi=90.0, lo=70.0, hi=320.0)
        x = x * on
        # (the heavy part is the first second: after it the peaks come down with the level, 2.2 dB a second, so the crash
        # never stands over what plays with it, the roar of the front and the immersion)
        ceil_k = 1.75 * 10 ** (-np.clip((t - 1.0) * 2.2, 0, 16) / 20)
    write("crash", x, db=CRASH_LEVEL, fade_in=0.0, fade_out=2.6, crest=ceil_k)


def crash_far():
    # (the same moment from far off: `far_of` softens its front, lets the top down, adds rolls and a long dark tail)
    x = N.decoded("crash")
    if x is None:
        raise SystemExit("crash is not built yet: build it before crash_far")
    L, R = N.far_of("crash", 78401, CRASH_D + 5.0)
    y = (L + R) / 2
    write("crash_far", y, db=-12.5, fade_in=0.0, fade_out=3.0, crest=1.9)


# =======================================================================================  cracks and slaps (positional)
def white_water(d, lvl, rise, fc_hi=5200.0, lo_cut=250.0):
    """The bubbling wash of white water round a thing breaking: band noise with foam's grain and a stream of bubbles under
    it, swelling in over `rise` s, `d` s long, unit-ish times `lvl`."""
    n = nsm(d)
    t = np.arange(n) / SR
    w = noise(n, lo_cut, fc_hi, 2) * np.clip(grains(n, 160.0, (0.01, 0.03, 0.08)), 0, 4) ** 0.8
    w += noise(n, 90, 400, 2) * wander(n, 1.0, 6.0, 5.0) * 0.7
    b = bubbles(n, 280.0, 300, 3000, q=10.0) * 0.5
    env = (1 - np.exp(-t / rise)) * np.exp(-np.maximum(t - 0.2 * d, 0) / (0.45 * d))
    return (T.unit(w) + b) * env * lvl


def crack_take(v):
    d = (1.8, 1.5, 1.6, 1.9)[v - 1]
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(79100 + 17 * v):
        x = np.zeros(n)
        if v == 1:       # a trunk snapping: the strain, the break, the splinter run, the weight going over
            tb = 0.42
            for a in (0.06, 0.16, 0.25, 0.32):
                put(x, timber_groan(rng().uniform(0.12, 0.3), rng().uniform(0.03, 0.06), 120, 1400), a)
            put(x, wood_snap(2.0, 0.15) * 1.0, tb)
            put(x, wood_snap(1.1, 0.25) * 0.4, tb + 0.17)
            for tt_ in F.PB_poisson(tb + 0.12, 1.4, lambda w: 45.0 * np.exp(-(w - tb) / 0.3)):
                put(x, F.fracture(rng().uniform(0.15, 0.6), 0.8, dull=rng().uniform(0.2, 0.6)) * rng().uniform(0.04, 0.16), tt_)
            put(x, timber_groan(0.8, 0.10, 70, 600), tb + 0.2)
            put(x, T.thud(nsm(0.6), 2.0) / 5.0, tb + 0.72)
        elif v == 2:     # a young tree: a quick double snap, a whip of branches
            put(x, wood_snap(0.8, 0.05) * 0.7, 0.15)
            put(x, wood_snap(1.3, 0.1) * 1.0, 0.33)
            for tt_ in F.PB_poisson(0.4, 1.3, lambda w: 60.0 * np.exp(-(w - 0.33) / 0.25)):
                put(x, F.fracture(rng().uniform(0.1, 0.4), 1.0, dull=rng().uniform(0.0, 0.3)) * rng().uniform(0.04, 0.18), tt_)
            put(x, F.knock(1.2, 0.2) * 0.3, 0.62)
            put(x, T.thud(nsm(0.5), 1.4) / 5.5, 0.7)
        elif v == 3:     # a house timber and planks going: a beam, then boards in a shower, the clatter
            put(x, timber_groan(0.3, 0.05, 100, 1200), 0.0)
            put(x, wood_snap(1.6, 0.2) * 1.0, 0.28)
            for k, a in enumerate((0.5, 0.62, 0.78, 0.95)):
                put(x, planks(rng().uniform(0.5, 1.2), 0.2, int(rng().integers(8, 20))) * rng().uniform(0.2, 0.5), a)
            for a in (0.55, 0.8, 1.0, 1.2):
                put(x, F.knock(rng().uniform(0.4, 1.0), 0.4) * rng().uniform(0.1, 0.3), a)
            put(x, T.thud(nsm(0.5), 1.6) / 5.0, 0.58)
        else:            # a trunk wrenched out of the ground, roots and all: a long groan, the roots, the break, the thud
            put(x, timber_groan(0.7, 0.12, 60, 700), 0.05)
            put(x, F.soil_tear(0.8, np.clip((t[:nsm(0.8)] - 0.1) / 0.2, 0, 1) * np.exp(-np.maximum(t[:nsm(0.8)] - 0.45, 0) / 0.3)) * 0.05, 0.3)
            put(x, wood_snap(1.6, 0.3) * 0.9, 0.55)
            put(x, wood_snap(0.9, 0.3) * 0.4, 0.78)
            put(x, T.thud(nsm(0.8), 2.6) / 4.0, 0.98)
        x = x + white_water(d, 1.0, 0.3) * np.abs(x).max() * 0.04
        x = band(x, 60, None, 1)
    write(f"crack{v}", x, peak_db=-3.0, fade_in=0.0, fade_out=0.35)


def slap_take(v):
    d = (1.7, 1.6, 1.6)[v - 1]
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(79200 + 19 * v):
        x = np.zeros(n)
        if v == 1:       # a big surge slammed into a wall, and the sheet of water falling back
            put(x, slap_event(2.0, 1.0), 0.10)
            put(x, slap_event(0.9, 1.0) * 0.4, 0.42)
        elif v == 2:     # a double surge against stone: a slap, the heavier one on its heels
            put(x, slap_event(1.1, 1.0) * 0.7, 0.08)
            put(x, slap_event(2.2, 1.0), 0.40)
        else:            # a cascade of small slaps along a wall
            for a, sz, g in ((0.06, 0.8, 0.8), (0.22, 0.5, 0.6), (0.37, 1.1, 1.0), (0.58, 0.4, 0.5), (0.74, 0.7, 0.55), (0.95, 0.35, 0.35)):
                put(x, slap_event(sz, 1.0) * g, a)
        rush = noise(n, 250, 4800, 2) * np.clip(grains(n, 220.0, (0.01, 0.03, 0.08)), 0, 4) ** 0.8 \
            * (1 - np.exp(-t / 0.08)) * np.exp(-np.maximum(t - 0.12, 0) / 0.5) * 0.3
        drip = bubbles(n, 120.0 * np.exp(-t / 0.7), 900, 4000, q=10.0) * np.exp(-np.maximum(t - 0.3, 0) / 0.8) * 0.18
        x = x + rush * np.abs(x).max() * 0.25 + drip * np.abs(x).max() * 0.2
        x = band(x, 55, None, 1)
    write(f"slap{v}", x, peak_db=-3.0, fade_in=0.0, fade_out=0.4)


# ==============================================================================================================  trickle
def drip(f0, size=1.0):
    """One drop falling into shallow water: a small bubble climbing a fifth, a tick of splash. Peak-ish unit."""
    m = nsm(0.18)
    s = np.arange(m) / SR
    f = f0 * (1 + 0.45 * (1 - np.exp(-s / 0.012)))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR + rng().uniform(0, 6.28)) * (1 - np.exp(-s / 0.0008)) * np.exp(-s / (0.011 + 0.006 * size))
    x += noise(m, 1800, 9000, 2) * np.exp(-s / 0.003) * 0.18
    return x / (np.abs(x).max() + 1e-12)


def trickle():
    d = 14.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(80001):
        x = np.zeros(n)
        # drops falling into the shallows, many at first, fewer as it dries
        for tt_ in P.poisson_times(0.5, d - 1.0, lambda v: 2.6 * np.exp(-v / 7.0) + 0.45):
            put(x, drip(rng().uniform(650, 2300), rng().uniform(0.5, 1.5)) * rng().uniform(0.15, 1.0) ** 1.4 * 0.5, tt_)
        # a few small streams trickling over mud and stones, each swelling in and thinning out
        for a, b, lvl, hi in ((0.0, 7.5, 1.0, 4600.0), (3.0, 10.5, 0.7, 3600.0), (6.5, 13.5, 0.5, 2900.0)):
            m = nsm(b - a)
            r = np.clip(55.0 * wander(m, 0.3, 2.0, 5.0), 8, 200)
            s_ = bubbles(m, r, 800, hi, q=9.0, chirp=0.5)
            s_ = lowpass_to(s_, np.full(m, hi * 1.2)) * np.sin(np.pi * np.arange(m) / m) ** 1.6 * 0.5 * lvl
            put(x, s_, a)
        # mud sagging and letting go of its air: low glugs and a soft settling
        for tc in sorted(rng().uniform(0.8, 12.0) for _ in range(10)):
            put(x, glug(rng().uniform(90, 260), rng().uniform(0.8, 1.6)) * 0.5 * rng().uniform(0.3, 1.0), tc)
        for tc in sorted(rng().uniform(1.0, 11.0) for _ in range(4)):
            m = nsm(1.1)
            s_ = np.arange(m) / SR
            put(x, noise(m, 60, 420, 2) * (1 - np.exp(-s_ / 0.12)) * np.exp(-s_ / 0.4) * 0.22, tc)
        # a last timber creak or two, wood shifting
        for tc, a in ((4.6, 0.9), (9.9, 0.6)):
            put(x, timber_groan(rng().uniform(0.9, 1.3), a * 0.5, 90, 800), tc)
        for tc in (2.3, 6.8, 8.2):
            put(x, debris_thud(rng().uniform(0.3, 0.6)) * 0.12, tc)
        # air: a faint breath of it round everything
        air = noise(n, 3500, 11000, 2) * wander(n, 0.1, 0.6, 4.0) * 0.012
        x = F.space(x, wet=0.35, length=1.7, darken=(5500, 500), decay=0.7, seed_shift=9) + air
        # (drying up: what is left is hardly there by ten seconds, so the strike is quiet by its end)
        x = x * curve_db(t, [(0.0, 0.0), (5.0, -1.0), (9.0, -9.0), (12.0, -20.0), (d, -30.0)])
    write("trickle", x, db=-33.0, fade_in=1.2, fade_out=3.5)


BUILD = {"rupture": rupture, "rumble": rumble, "roar_far": roar_far, "roar_mid": roar_mid, "roar_near": roar_near, "roar_pass": roar_pass,
         "crash": crash, "crash_far": crash_far, "engulf": engulf, "under": under, "surface": surface, "torrent": torrent, "drain": drain,
         "roar_back": roar_back, "rumble_after": rumble_after, "trickle": trickle,
         "crack1": lambda: crack_take(1), "crack2": lambda: crack_take(2), "crack3": lambda: crack_take(3), "crack4": lambda: crack_take(4),
         "slap1": lambda: slap_take(1), "slap2": lambda: slap_take(2), "slap3": lambda: slap_take(3)}


# ===========================================================================================================  listening
CLIPS = {}


def mixdown(dp, pad=0.5, immersed=True):
    """The whole strike as heard `dp` blocks from the target, from strike second 0 (file domain, mono, as the Rod's
    `--listen`: every file at its volume, on its time, its pitch a change of speed)."""
    ev = schedule(dp, immersed)
    clips = {f: CLIPS.setdefault(f, decoded(f)) for _, f, _, _, _ in ev}
    end = max(at + len(clips[f]) / SR / pitch for _, f, at, pitch, _ in ev) + pad
    out = np.zeros(nsm(end))
    parts = {}
    for name, f, at, pitch, vol in ev:
        c = clips[f]
        if pitch != 1.0:
            m = int(len(c) / pitch)
            c = np.interp(np.arange(m) * pitch, np.arange(len(c)), c)
        k = nsm(at)
        c = c * vol
        out[k:k + len(c)] += c[:len(out) - k]
        parts[name] = (at, len(c) / SR)
    return out, parts


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def mp3(wav):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libmp3lame", "-b:a", "160k", str(Path(wav).with_suffix(".mp3"))], check=True)


def game_peak(mix):
    """The mix as Horizon plays a sound played to the listener: 0.596 in each ear (its output limiter not applied)."""
    return 20 * np.log10(np.abs(mix).max() * 0.596 + 1e-12)


def short_term(x, w=0.4, hop=0.1):
    n, h = nsm(w), nsm(hop)
    return np.array([20 * np.log10(np.sqrt(np.mean(x[i:i + n] ** 2)) + 1e-9) for i in range(0, max(len(x) - n, 1), h)])


def octave_report(x, t0, t1):
    seg = x[nsm(t0):nsm(t1)]
    out = []
    for fc in OCT:
        lo = 16.0 if fc == OCT[0] else fc / 2 ** 0.5
        hi = min(fc * 2 ** 0.5, SR * 0.47)
        out.append(20 * np.log10(np.sqrt(np.mean(band(seg, lo, hi, 3) ** 2)) + 1e-12))
    return out


def file_report(name):
    x = decoded(name)
    if x is None:
        return
    sub = band(x, None, 18.0, 2)
    e_sub = 100 * np.sum(sub ** 2) / (np.sum(x ** 2) + 1e-12)
    d = len(x) / SR
    cuts = [0.0, d * 0.5, max(d - 1.2, 0)]
    oc = [octave_report(x, c, min(c + 1.0, d)) for c in cuts]
    print(f"  {name:13s} DC {x.mean():+.5f}  <18 Hz {e_sub:5.2f}%  head |x| {np.abs(x[:20]).max():.4f}  tail |x| {np.abs(x[-20:]).max():.4f}   octave dB (31..8k)")
    for c, o in zip(cuts, oc):
        print(f"      @{c:5.1f}s " + " ".join(f"{v:6.1f}" for v in o))


def listen(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for nm in NAMES:
        x = decoded(nm)
        if x is None:
            continue
        p = out / f"tsunami_{nm}.wav"
        write_wav(p, x)
        mp3(p)
        lufs, tp, _ = N.measure(p)
        rows.append((p.name, len(x) / SR, 20 * np.log10(np.abs(x).max()), tp, lufs))
    tmp = out / "_check.wav"
    worst = -99.0
    for dp in (100, 150, 200, 250, 300, 400, 500, 600, 700):
        x, parts = mixdown(dp)
        write_wav(tmp, x)
        _, tp, _ = N.measure(tmp)
        worst = max(worst, tp)
        print(f"  the whole strike {dp:4d} blocks off (t_p {t_p(dp):5.2f} s): sample peak {20 * np.log10(np.abs(x).max()):.2f} dBFS, "
              f"true peak {tp:.2f} dBTP (as the game plays it, {game_peak(x):.2f} dBFS per ear)")
    tmp.unlink()
    print(f"  worst true peak over every distance: {worst:.2f} dBTP (the ceiling is {20 * np.log10(CEIL):.1f})")
    sweep = []
    for imm in (True, False):
        for dp in range(100, 721):
            mix_, _ = mixdown(dp, immersed=imm)
            sweep.append((20 * np.log10(np.abs(mix_).max()), dp, imm))
    pk, dpw, immw = max(sweep)
    j = int(np.abs(mixdown(dpw, immersed=immw)[0]).argmax())
    tpk = 20 * np.log10(true_peak(mixdown(dpw, immersed=immw)[0][max(j - SR, 0):j + SR]))
    print(f"  sample peak of the whole strike at every distance from 100 to 720 blocks, immersed or not: worst {pk:.2f} dBFS at "
          f"{dpw} blocks, its true peak {tpk:.2f} dBTP")
    for dp in (200, 600):
        x, _ = mixdown(dp)
        p = out / f"tsunami_full_{dp}blocks.wav"
        write_wav(p, x)
        mp3(p)
        lufs, tp, _ = N.measure(p)
        rows.append((p.name + f"  (front reaches the player at {t_p(dp):.1f} s)", len(x) / SR, 20 * np.log10(np.abs(x).max()), tp, lufs))
    print(f"\n{'file':64s} {'len':>6s} {'peak':>7s} {'TP':>7s} {'LUFS':>7s}")
    for r in rows:
        print(f"{r[0]:64s} {r[1]:6.1f} {r[2]:7.2f} {r[3]:7.2f} {r[4]:7.1f}")
    print("\nfile checks (octave levels at the start, middle and end of each; DC; the share of energy under 18 Hz; the first and last samples):")
    for nm in NAMES:
        file_report(nm)
    for dp in (200, 400, 600):
        x, parts = mixdown(dp)
        st = short_term(x)
        marks = [(0, "0"), (T_T, "t_T"), (t_p(dp), "t_p"), (t_p(dp) + 9, "t_p+9"), (t_p(dp) + 17, "t_p+17"), (42, "42")]
        print(f"\nloudness of the mix at {dp} blocks (loudest 400 ms window each second, dB): " + ", ".join(
            f"{lb} {st[min(int(tm * 10), len(st) - 1)]:.1f}" for tm, lb in marks))
        sec = [st[i * 10:i * 10 + 10].max() for i in range(len(st) // 10)]
        print("   per second: " + " ".join(f"{v:.0f}" for v in sec))


# ================================================================================================  pictures (spectrograms)
def spectrogram_png(x, path, title, fmax=16000.0, fmin=20.0, height=420, width=1400, rng_db=78.0, marks=()):
    """A log-frequency spectrogram of mono `x` and under it its short-term level, as a PNG (Pillow): to look at what
    cannot be listened to. `marks`: (seconds, label) lines drawn over it."""
    from PIL import Image, ImageDraw
    size = 4096
    hop = max(int(len(x) / width), 1)
    win = np.hanning(size)
    freqs = np.fft.rfftfreq(size, 1 / SR)
    rows = np.geomspace(fmin, fmax, height)
    cols = []
    xp = np.pad(x, (size // 2, size))
    for i in range(0, len(x), hop):
        seg = xp[i:i + size] * win
        mag = np.abs(np.fft.rfft(seg)) ** 2
        cols.append(10 * np.log10(np.interp(rows, freqs, mag) / size + 1e-12))
    S = np.array(cols).T[::-1]
    top = np.percentile(S, 99.7)
    z = np.clip((S - (top - rng_db)) / rng_db, 0, 1)
    r = np.clip(1.6 * z - 0.2, 0, 1)
    g = np.clip(2.0 * z - 0.9, 0, 1) ** 1.2
    b = np.clip(np.where(z < 0.5, 2 * z, 1.4 - 1.4 * z), 0, 1)
    img = np.stack([r, g, b], axis=-1)
    W = img.shape[1]
    lvl = short_term(x, 0.4, len(x) / SR / W)
    lh = 70
    canvas = np.zeros((height + lh + 34, W + 56, 3), dtype=np.uint8)
    canvas[:height, 56:] = (img * 255).astype(np.uint8)
    im = Image.fromarray(canvas)
    dr = ImageDraw.Draw(im)
    for f in (31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000):
        if fmin <= f <= fmax:
            y = height - 1 - int(np.log(f / fmin) / np.log(fmax / fmin) * (height - 1))
            dr.line([(52, y), (W + 56, y)], fill=(70, 70, 70))
            dr.text((2, y - 5), f"{f:g}" if f < 1000 else f"{f / 1000:g}k", fill=(220, 220, 220))
    d = len(x) / SR
    for tm in range(0, int(d) + 1, 2):
        xx = 56 + int(tm / d * (W - 1))
        dr.line([(xx, height), (xx, height + 4)], fill=(220, 220, 220))
        dr.text((xx - 6, height + 5), f"{tm}", fill=(220, 220, 220))
    for tm, lb in marks:
        if 0 <= tm <= d:
            xx = 56 + int(tm / d * (W - 1))
            dr.line([(xx, 0), (xx, height)], fill=(80, 220, 255))
            dr.text((xx + 3, 3), lb, fill=(80, 220, 255))
    top_db, bot_db = 0.0, -60.0
    pts = [(56 + i, height + 18 + lh - int(np.clip((v - bot_db) / (top_db - bot_db), 0, 1) * lh)) for i, v in enumerate(lvl[:W])]
    dr.line(pts, fill=(120, 255, 120))
    for db_ in (0, -20, -40, -60):
        yy = height + 18 + lh - int((db_ - bot_db) / (top_db - bot_db) * lh)
        dr.line([(52, yy), (W + 56, yy)], fill=(60, 60, 60))
        dr.text((8, yy - 5), f"{db_}", fill=(180, 180, 180))
    dr.text((60, height + lh + 20), f"{title}   level (dB, 400 ms)", fill=(255, 255, 255))
    im.save(path)


def plots(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for nm in NAMES:
        x = decoded(nm)
        if x is not None:
            spectrogram_png(x, out / f"{nm}.png", nm)
    for dp in (200, 600):
        x, parts = mixdown(dp)
        marks = [(0, "rupture"), (T_T, "t_T"), (t_p(dp), "t_p"), (T_T + dp / SPEED, "crash")]
        spectrogram_png(x, out / f"mix_{dp}.png", f"the whole strike {dp} blocks off", marks=marks)


# ==================================================================================================================  main
def write_events(path):
    """The tsunami.* events in sounds.json: the existing file read and written back as it was (the same JSON format), with
    only the tsunami.* entries replaced or, the first time, inserted before the Supercell's. Every other entry untouched."""
    sounds = json.loads(path.read_text())
    new = {}
    for name in NAMES:
        ev = f"{TH}.{name}"
        reach = 2048 if name in ("crash", "crash_far") else 256
        sub = name[:-1] if name[:-1] in ("crack", "slap") else name
        new[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": reach}], "subtitle": f"subtitles.orbital.{TH}.{sub}"}
    for grp, n_ in (("crack", 4), ("slap", 3)):
        new[f"{TH}.{grp}"] = {"sounds": [{"name": f"orbital:{TH}/{grp}{v}", "attenuation_distance": 256} for v in range(1, n_ + 1)],
                              "subtitle": f"subtitles.orbital.{TH}.{grp}"}
    old_keys = [k for k in sounds if k.startswith(f"{TH}.")]
    out = {}
    if old_keys:
        placed = False
        for k, v in sounds.items():
            if k.startswith(f"{TH}."):
                if not placed:
                    out.update(new)
                    placed = True
            else:
                out[k] = v
    else:
        placed = False
        for k, v in sounds.items():
            if not placed and k.startswith("supercell."):
                out.update(new)
                placed = True
            out[k] = v
        if not placed:
            out.update(new)
    path.write_text(json.dumps(out, indent=2))


def build_one(name):
    BUILD[name]()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write listening WAVs and MP3s and the full-strike mixdowns here")
    ap.add_argument("--plots", help="also write spectrogram pictures of each file and of the mixes here")
    ap.add_argument("--jobs", type=int, default=8, help="sounds built at once (each has its own seed, so the result is the same)")
    a = ap.parse_args()
    soundlib.init(a.out)
    todo = list(a.only if a.only is not None else NAMES)
    if a.jobs > 1 and len(todo) > 1:
        import multiprocessing as mp
        with mp.get_context("fork").Pool(a.jobs) as pool:
            pool.map(build_one, [nm for nm in todo if nm != "crash_far"], chunksize=1)
        if "crash_far" in todo:
            build_one("crash_far")
    else:
        for name in todo:
            build_one(name)
    if a.only is None:
        path = Path(a.out) / "assets" / "orbital" / "sounds.json"
        if path.exists():
            write_events(path)
    if a.listen:
        listen(a.listen)
    if a.plots:
        plots(a.plots)


if __name__ == "__main__":
    main()
