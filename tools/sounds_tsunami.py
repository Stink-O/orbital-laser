"""The Tsunami's sounds, all synthesised here, nothing sampled: a wall of dark, debris-laden water up to 320 blocks tall out
far, that stands up on the horizon in the first second and a half, crosses the land and goes over the player's head.
Its drama is scale: dread from the first seconds, a roar that takes the whole sky, the immersion, what goes by under the
water, the head coming out and the land's water pouring away beneath the player, the quiet it leaves.

Big water has no pitch at all, and it is not a lot of small water. It was once built here from ringing Minnaert bubbles and came
out as a stream into a can: every band's envelope three times too sparse, a hump at 1 kHz over no sub. `water` below is what
replaced it; nothing in this file rings.

Horizon decodes every sound to mono ((L+R)/2) and plays one played to the listener dead centre, 0.596 in each ear (a
positional one is panned by its direction), so every file here is mono: nothing is lost, the folder is half the size
and what is measured is what the game plays.

The schedule, `schedule(dp)` here and strike/ts_sounds.rs there, the same arithmetic (strike seconds; T_T = 9.0 the front
reaching the target; `dp` = the player's distance from the target in blocks; `tp` = when the water closes over their head,
`t_p` here; sound from the target arrives dp / 343 s after it leaves, always before the wave does):

  rupture      at 0: the seabed far off letting go; felt more than heard: a thump 1.1 s in, a long falling rumble
  rumble       at 1.5: the ground under the wave; low only; up by 8 s, out of the immersion's way by 14 s; 18 s
  roar_far     at 0.9: the wall on the horizon, its first big seas 0.75 s in, as it stands up, building; 9.5 s, gone before the
               immersion of a near player; again at 7.4, at pitch 0.94, for one the wave is far from yet
  roar_mid     at tp - 9: closer, bigger, 9 s, crossfading into roar_near over its last 3.6 s
  roar_near    at tp - 4: enormous, what it carries coming into the ear; the immersion is exactly 4.0 s into it (NEAR_PRE): a
               breath of 120 ms, then it is cut off
  roar_pass    at tp - 4 instead, for a player on a hill it never closes over: the same wall going by below; 12 s
  crash        at 9 + dp / 343 - CRASH_LEAD: the wave coming down on the target's land: water and weight, nothing single
  crash_far    the same moment, cross-faded in by distance (`far_mix`: 250 to 800 blocks, smoothstep)
  engulf       at tp: the loudest, heaviest thing there is, its slam on the first sample; 0.15 s blown white, 1.5 s of
               violent water closing down round the head, then the drop
  under        at tp + 0.2: inside the water; quiet under the engulf for a second, then a dark surging roar with what hits coming
               through it; a tree at tp + 2.5, a piece of a house at tp + 3.75, a tree at tp + 5.3; ends just after the head is out
  surface      at tp + 6.5: the head out: the burst is on its first sample, everything above 1 kHz back at once
  torrent      at tp + 6.5: the whole land's water pouring away round the player as they ride it down; 13 s, thinning
  drain        at tp + 9: running water, near and far at once; 12 s
  roar_back    at tp + 9.5: the wave going off over the far land
  rumble_after at tp + 9: the ground, low, settling
  trickle      at tp + 17, at 31 at the latest (it has dried up by the strike's end, 42 s, at any distance)
  crack1-4     positional, where a tree or a timber breaks (the front reaching the player's surroundings)
  slap1-3      positional, where water slams into stone or a wall

If the water never closes over the player, engulf, under and surface do not play. Past the wave's end (`reach`) the roars die
out and nothing pours off the land round them.

Volumes: share = clamp(0.2 + 0.001 (dp - 100), 0.2, 0.62) (the crash lies on top of the immersion for a near player)

  crash        (1 - far_mix(dp)) * share
  crash_far    far_mix(dp) * share * min(1.25 / (1 + dp / 2000), 1)
  roar_far     clamp(0.7 + 0.001 dp, 0.8, 1), 0.6 of that the second time
  roar_near    clamp(0.66 + 0.0018 (dp - 250), 0.66, 0.82)
  everything else 1 (times `reach` for what needs the wave)

How each is made (`water`, `impact`, `grit`, `groan`, `bury`: the comment at `water` says what they are):

  rupture      a small thud first (what arrives ahead through the rock), the push 1.1 s in (a ~42 Hz heave), a long rumble
               sinking from ~150 Hz to ~30 over six seconds with a shudder in it, rolls of low thunder, rock grinding.
  rumble       low swells rolling in under a sub bed, a grinding in the low mids; nothing above ~350 Hz.
  roar_far     `water` through miles of air (`FAR_SH`), surging, far seas coming down with no front to them.
  roar_mid     `water` with the air's share of the top gone (`MID_SH`), seas, the mass of what it carries (under 500 Hz, nothing small
               carries this far), steel dragging, deep.
  roar_near    `water` closing to `NEAR_SH`, seas, timber and concrete and steel coming into the ear buried in it.
  crash        a heavy blow (its attack 40 ms) and another on it, seas coming down one on another, the roar letting go; the land under
               them a dark crushing under 1.1 kHz: from hundreds of blocks off no board or pane of glass is heard.
  crash_far    the same through ~a kilometre of air (the Nuke's `far_of`): highs let down, the front smeared, a long dark tail.
  engulf       `WHITE_SH` on the first sample with a blow of everything and a cycle of pressure; seas slamming and things hitting;
               the shape closing to `UNDER_SH` by 1.8 s.
  under        `water` at `UNDER_SH`, surging hard; hits and pieces through it, sharp and short, so it stays dark between them; the two
               trees (`tree_past`: the water shoved ahead, a groan, the trunk knocking) and the house (`chunk_past`: a blow and
               everything in it going, rubble, a beam); the last second and a half the air coming.
  surface      a burst of everything on the first sample, `water` open and bright, drops.
  torrent      `water` close (`TORRENT_SH`, level to 2 kHz), ledges of it coming down, things knocking; the weight going first (`RUN_SH`,
               `RILL_SH`), its splashes coming apart.
  drain        `water` at `RILL_SH`, thin and wide, nothing in it a stream of its own, hollows letting go (`gulp`).
  roar_back    `water` far and going.
  rumble_after the ground settling: a low bed sinking away, a few far thuds.
  trickle      what is left of the water, drops (more tick than note), mud, a last timber settling twice; very quiet.
  crack1-4     a trunk snapping, a young tree's quick double snap, a house beam and planks going, a trunk wrenched out roots and all.
  slap1-3      water slamming a wall: one big, a double surge, a cascade of small ones.

    python3 tools/sounds_tsunami.py                      # writes orbital-sounds/assets/orbital/sounds/tsunami/*.ogg and the
                                                         # tsunami.* events in sounds.json (nothing else touched), in ~15 s
    python3 tools/sounds_tsunami.py --only roar_mid      # some (build crash before crash_far)
    python3 tools/sounds_tsunami.py --listen DIR         # also MP3s of each, the whole strike as heard from 200 and 600 blocks
                                                         # and the true peak of every mix, immersed or not, 100 to 720 blocks
    python3 tools/sounds_tsunami.py --plots DIR          # spectrogram pictures of each file and of those two mixes
"""
import argparse, json, subprocess, sys, wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.fft import irfft, next_fast_len
from scipy.ndimage import gaussian_filter1d
from scipy.signal import fftconvolve, resample_poly
import soundlib
from soundlib import SR, band
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P
import sounds_nuke as N
import hu_foley as F

TH = "tsunami"
N.TH = TH                      # (the Nuke's helpers, `decoded`, `far_of`, write to tsunami/ now)
P.TH = TH
ROOT = Path(__file__).resolve().parent.parent
NAMES = ["rupture", "rumble", "roar_far", "roar_mid", "roar_near", "roar_pass", "crash", "crash_far", "engulf", "under", "surface",
         "torrent", "drain", "roar_back", "rumble_after", "trickle", "crack1", "crack2", "crack3", "crack4", "slap1", "slap2", "slap3"]
TP_MAX = 10 ** (-1.15 / 20)     # every file's decoded true peak (4x oversampled) at most this
# The mix balance, dB added to a file's nominal level
TRIM = {"rumble": -8.0}

# ---- the timeline (seconds; 0 = fired)
T_T = 9.0                       # the front crosses the target
SPEED = 343.0
CRASH_LEAD = 0.06               # the crash file's first sound is this far into it
FAR_AT = 0.9                    # roar_far: its first big seas come down as the horizon stands up (1.5 s)
FAR_AGAIN, FAR_IF = 7.4, 9.0    # played again (lower) only if roar_mid starts after FAR_IF: it must be gone before the immersion
MID_LEN = 9.0                   # roar_mid ends as the front arrives
NEAR_PRE = 4.0                  # roar_near: the immersion is this far into it
ROAR_NEAR_LEN, PASS_LEN = 4.45, 12.0
SURF_AT = 6.5                   # the head breaks the surface at tp + this (strike/tsunami.rs's carry)
DRAIN_AT, BACK_AT, SETTLE_AT = 9.0, 9.5, 9.0       # tp + these
TRICKLE_AT, TRICKLE_LAST = 17.0, 31.0              # tp + this, or this at the latest (dried up by the strike's end, 42)
NEAR_DB, ENGULF_DB = -13.0, -8.0
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
    share = float(np.clip(0.2 + 0.001 * (dp - 100.0), 0.2, 0.62))
    near_v = float(np.clip(0.66 + 0.0018 * (dp - 250.0), 0.66, 0.82))
    far_v = float(np.clip(0.7 + 0.001 * dp, 0.8, 1.0))
    crash_v = {"crash": share * (1.0 - far), "crash_far": share * far * min(1.25 / (1.0 + dp / 2000.0), 1.0)}
    rows = [("rupture", "rupture", 0.0, 1.0, 1.0),
            ("rumble", "rumble", 1.5, 1.0, 1.0),
            ("roar_far", "roar_far", FAR_AT, 1.0, far_v),
            ("roar_mid", "roar_mid", max(tp - MID_LEN, 1.0), 1.0, reach),
            ("roar_far2", "roar_far", FAR_AGAIN, 0.94, 0.6 * far_v if tp - MID_LEN > FAR_IF else 0.0),
            ("crash", "crash", T_T + late - CRASH_LEAD, 1.0, crash_v["crash"]),
            ("crash_far", "crash_far", T_T + late - CRASH_LEAD, 1.0, crash_v["crash_far"]),
            ("torrent", "torrent", tp + SURF_AT, 1.0, reach),
            ("drain", "drain", tp + DRAIN_AT, 1.0, reach),
            ("roar_back", "roar_back", tp + BACK_AT, 1.0, reach),
            ("rumble_after", "rumble_after", tp + SETTLE_AT, 1.0, reach),
            ("trickle", "trickle", min(tp + TRICKLE_AT, TRICKLE_LAST), 1.0, reach)]
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


# =========================================================================================================  water
# Big water has no pitch at all. Measured against the sequences in private reference (long-term spectra, modulation, envelope
# fine structure; numbers only, nothing of them is used here): the roar of a wall of water is close to Gaussian in every band,
# a band's envelope varying by 0.25-0.5 of its mean at 20 ms and 4-32 Hz modulation near -17 dB, under big slow surges of 3-5 dB
# that take the top with them; a body under 300 Hz as loud as anything; level from 100 Hz to 1 kHz within 6 dB. A bank of ringing
# bubbles cannot do that: thin it out and it is a stream, every event heard on its own (a stream into a can); so nothing here
# rings. `water` is 30 third-octave bands of independent noise, each under a gain that is chaos in dB:
#   eddies   a 1/f curve, slow for the big eddies down low, quicker up high, part of it shared, part smooth across the bands
#   spatter  quick and narrow, a thin heavy-tailed grain over 300 Hz
#   surges   heavy-tailed swells of a second or more (up fast, away slowly, arrivals bunched: never an LFO), one set for the low,
#            mid and high regions and one over them all, the top moving most
#   blobs    splashes in the time-frequency plane: an octave or so wide, up in 10-50 ms, gone in a few hundred, heavy-tailed sizes
#   foam     a sparse shot process carrying part of the top bands
# `impact` is the same thing as an event: a broad burst, every band up at once, each dying at its own rate, the spray late.
# Solid things in the water are `grit` (clicks of heavy-tailed size, each a wisp of noise) and `groan` (stick-slip pulses with a
# third of a period's jitter through wide bands: a body with no note), buried by `bury` (lowpassed, smeared by a short noise tail).
# (dB, third-octave band levels at SH_F)
SH_F = np.array([20, 31.5, 50, 79, 125, 198, 315, 500, 794, 1260, 2000, 3175, 5040, 8000, 12700, 16000.0])
NEAR_SH = np.array([-8.0, -1, 2, -2, -1, -1, -2, -2, -3, -4, -4, -6, -8, -10, -14, -24])          # the wall, close
MID_SH = np.array([-6.0, 0, 2, 0, 0, -1, -2, -4, -6, -8, -11, -15, -20, -26, -34, -44])            # coming, the air has some of the top
FAR_SH = np.array([-5.0, 1, 3, 2, 1, 0, -2, -5, -10, -17, -26, -37, -50, -64, -80, -90])           # miles off
UNDER_SH = np.array([-4.0, -1, 2, 1, -4, -9, -13, -17, -22, -28, -35, -43, -52, -62, -72, -80])     # under it: the hits carry the top
TORRENT_SH = np.array([-12.0, -2, 2, 0, -1, -3, -4, -5, -5, -5, -6, -8, -10, -12, -15, -26])        # in the flow: flat to 2 kHz
RUN_SH = np.array([-30.0, -22, -16, -12, -8, -6, -4, -2, -1, -1, -2, -3, -5, -8, -13, -24])        # the weight gone, wide still
RILL_SH = np.array([-50.0, -40, -30, -22, -15, -11, -8, -5, -3, -2, -2, -3, -5, -8, -13, -24])     # running water: never a hump
WHITE_SH = np.array([-2.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, -1, -2, -3, -6, -14])                    # the blow: everything at once
IMP_DARK = np.array([-6.0, 0, 1, 0, -3, -6, -9, -13, -18, -24, -31, -39, -48, -58, -70, -80])      # a blow, the top gone
IMP_WHITE = np.array([-6.0, 0, 1, 1, 0, 0, -1, -1, -2, -3, -3, -4, -6, -8, -12, -20])              # a blow, all of it
CR = 400                                                   # frames a second of the gains
FC = 20.0 * 2 ** (np.arange(30) / 3.0)                     # the bands' centres, 20 Hz to 16 kHz
NB = len(FC)
LF = np.log2(FC)
LSH = np.log2(SH_F)


def in_bands(sh):
    return np.interp(LF, LSH, sh)


def over_f(xs, ys):
    """Per band, through (Hz, value) pairs."""
    return np.interp(LF, np.log2(xs), ys)


def band_noise(n, b):
    """Unit-RMS noise in band `b`: bands overlap power-complementary, a cosine in log frequency, a third of an octave either side."""
    m = next_fast_len(n + nsm(0.25), real=True)
    f = np.fft.rfftfreq(m, 1 / SR)
    u = (np.log2(np.maximum(f, 1.0)) - LF[b]) * 3
    H = np.where(np.abs(u) < 1, np.cos(np.pi / 2 * u), 0.0)
    if b == 0:
        H = np.where(u < 0, (f > 8.0) * 1.0, H)
    k = np.nonzero(H)[0]
    Z = np.zeros(len(f), complex)
    Z[k] = (rng().standard_normal(len(k)) + 1j * rng().standard_normal(len(k))) * H[k]
    y = irfft(Z, m)[:n]
    return y / (y.std() + 1e-15)


def one_over_f(nt, beta, fcut, fmin=0.05):
    """A unit-variance curve with a power spectrum f^-beta between `fmin` and `fcut` Hz, at CR."""
    m = next_fast_len(nt + CR // 2, real=True)
    f = np.fft.rfftfreq(m, 1 / CR)
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


def blob_field(d, rate, level, flo, fhi, width=(0.5, 1.4), rise=(0.012, 0.05), fall=(0.08, 0.55), rate_of=None):
    """The splashes, as a power gain over 1, bands by frames. `rate_of`: a curve (0-1 at CR) thinning them over time."""
    nt = int(d * CR) + 2
    H = np.zeros((NB, nt))
    for _ in range(rng().poisson(rate * d)):
        i = int(rng().uniform(0, nt - 2))
        if rate_of is not None and rng().uniform() > rate_of[i]:
            continue
        fc, w = rng().uniform(np.log2(flo), np.log2(fhi)), rng().uniform(*width)
        a = level * min(rng().pareto(1.9) + 0.25, 3.5) ** 2
        ru, fa = rng().uniform(*rise), rng().uniform(*fall) * np.clip(1.5 / 2 ** (fc - 9), 0.35, 1.6)
        u = np.arange(min(int(fa * 7 * CR), nt - i)) / CR
        H[:, i:i + len(u)] += a * np.exp(-0.5 * ((LF - fc) / w) ** 2)[:, None] * ((1 - np.exp(-u / ru)) ** 2 * np.exp(-u / fa))[None, :]
    return H


def foam_gain(n, rate=1400.0, taus=(0.0012, 0.003, 0.007)):
    """A heavy-tailed shot process, mean 1, one value a sample."""
    x = np.zeros(n)
    for tau in taus:
        y = np.zeros(n)
        k = rng().poisson(rate * n / SR / len(taus))
        np.add.at(y, rng().integers(0, n, k), np.minimum(rng().pareto(1.4, k) + 0.1, 30.0))
        s = np.arange(int(tau * SR * 7))
        x += fftconvolve(y, np.exp(-s / (tau * SR)) * (1 - np.exp(-s / 12.0)))[:n] / tau
    return np.maximum(x, 0) / (x.mean() + 1e-12)


def water(d, keys, lvl=None, surge=(0.42, 1.0), eddy=1.0, spat=1.2, blobs=(12.0, 0.6, 120.0, 5000.0), fizz=0.2, sea=None, thin=None):
    """`d` s of water. `keys`: (seconds, shape) pairs, the band levels in dB (0 dB a band of unit RMS), linear in dB between them.
    `lvl`: (seconds, dB) pairs over it all. `surge`: (a second, depth), `eddy`, `spat`, `fizz`: see above; `blobs`: (a second, level,
    from Hz, to Hz), `thin` thinning them over time; `sea`: a surge curve to share (the same `d`)."""
    n, nt = nsm(d), int(d * CR) + 2
    t = np.arange(nt) / CR
    S = np.stack([in_bands(k[1]) for k in keys])
    s = np.stack([np.interp(t, [k[0] for k in keys], S[:, b]) for b in range(NB)]) if len(keys) > 1 else np.repeat(S, nt, 0).T
    if lvl is not None:
        s = s + 20 * np.log10(curve_db(t, lvl) + 1e-9)[None, :]
    # the eddies
    fcut = over_f([20, 200, 1000, 8000], [3, 8, 14, 22])
    sd = over_f([20, 200, 1000, 8000], [3.5, 2.6, 2.4, 3.2]) * eddy
    Z = gaussian_filter1d(np.stack([one_over_f(nt, 1.2, fcut[b]) for b in range(NB)]), 2.0, axis=0, mode="nearest")
    Z /= Z.std(axis=1, keepdims=True) + 1e-12
    F = (np.sqrt(0.75) * Z + np.sqrt(0.25) * one_over_f(nt, 1.2, 8.0)) * sd[:, None]
    # the spatter
    if spat > 0:
        Z = gaussian_filter1d(np.stack([one_over_f(nt, 0.6, 45.0) for b in range(NB)]), 0.7, axis=0, mode="nearest")
        Z /= Z.std(axis=1, keepdims=True) + 1e-12
        F = F + np.sign(Z) * np.abs(Z) ** 1.25 * (spat * over_f([20, 300, 1000, 8000], [0.0, 0.4, 1.0, 1.3]))[:, None]
    # the surges
    sea = surges(d, surge[0]) if sea is None else sea
    regs = [surges(d, surge[0] * r, down=(0.7 * q, 2.8 * q)) for r, q in ((0.7, 1.3), (1.0, 1.0), (1.5, 0.7))]
    wl, wh = over_f([200, 700], [1, 0]), over_f([1000, 3000], [0, 1])
    wm = np.clip(1 - wl - wh, 0, 1)
    L = (0.6 * sea[None, :]) + 0.7 * (wl[:, None] * regs[0][None, :] + wm[:, None] * regs[1][None, :] + wh[:, None] * regs[2][None, :])
    L = np.where(L > 0, 9.0 * np.tanh(L / 9.0), L)
    s = s + F + L * (surge[1] * over_f([20, 200, 1000, 8000], [0.9, 1.0, 1.2, 1.9]))[:, None]
    G2 = 10 ** (s / 10)
    if blobs is not None and blobs[0] > 0:
        G2 = G2 * (1 + blob_field(d, blobs[0], blobs[1], blobs[2], blobs[3], rate_of=thin))
    G = np.sqrt(G2)
    sh = foam_gain(n) if fizz > 0 else None
    ts = np.arange(n) * CR / SR
    out = np.zeros(n)
    for b in range(NB):
        if G[b].max() < 2e-4:
            continue
        y = band_noise(n, b) * np.interp(ts, np.arange(nt), G[b])
        m = fizz * np.clip((LF[b] - 11.3) / 1.7, 0, 1)
        out += y * np.sqrt((1 - m) + m * sh) if m > 0 else y
    return out


def impact(size=1.0, bright=0.5, rise=0.004, fall=0.5, spray=0.03, kick=0.0):
    """A blow: every band up at once and dying at its own rate, the lows last, the spray (`spray` s) after the slam. Its first
    quarter second has an RMS of `size`. `bright` 0-1: its top. `kick`: a cycle of pressure, weight the size of it."""
    m = nsm(float(np.clip(fall * 6, 0.7, 4.0)))
    s = np.arange(m) / SR
    sp = in_bands((1 - bright) * IMP_DARK + bright * IMP_WHITE)
    fb = np.clip(fall * (FC / 120.0) ** -0.42, 0.05, fall * 2.2)
    x = np.zeros(m)
    for b in range(NB):
        if sp[b] < -60:
            continue
        u = np.maximum(s - spray * np.clip((LF[b] - 9.0) / 4.0, 0, 1), 0)
        x += band_noise(m, b) * (1 - np.exp(-u / rise)) ** 2 * np.exp(-u / fb[b]) * 10 ** (sp[b] / 20)
    k = nsm(0.25)
    x = x / (np.sqrt(np.mean(x[:k] ** 2)) + 1e-12) * size
    if kick > 0:
        x += sine_thump(m, 0.0, 62.0, 26.0, 9.0, 0.0025, 0.13, kick * size * 3.5)
    return x


def seas(x, d, rate, t0=0.3, lo=0.4, hi=1.6, **kw):
    """Big irregular hits on `x`, a run of them: bunched, heavy-tailed sizes."""
    tb = t0
    while tb < d - 0.4:
        put(x, impact(min(lo + rng().pareto(2.2) * lo, hi), **kw), tb)
        tb += rng().gamma(0.9, 1.0 / (rate * 0.9))


def grit(m, rate, tau, lo, hi, alpha=1.5):
    """Clicks at `rate` a second (a number or a curve), heavy-tailed, each a wisp of noise `tau` s long: what breaks sounds like. Unit RMS."""
    r = np.broadcast_to(rate, (m,)).astype(float)
    p = np.cumsum(r) / SR
    k = rng().poisson(max(p[-1], 1e-3))
    at = np.minimum(np.searchsorted(p, rng().uniform(0, p[-1], k)), m - 1)
    a = np.minimum(rng().pareto(alpha, k) + 0.1, 20.0) * rng().choice((-1.0, 1.0), k)
    y = np.zeros(m)
    np.add.at(y, at, a)
    return T.unit(band(grit_of(y, tau), lo, hi, 2))


def grit_of(y, tau):
    """The impulses `y` as bursts of noise `tau` s long: an envelope over a running noise, so no two are alike. (Any fixed wisp, even a
    dozen of them, is a colour the big clicks keep repeating: a resonance held for as long as the rubble falls.)"""
    h = np.arange(int(tau * SR * 6) + 1)
    return np.maximum(fftconvolve(np.abs(y), np.exp(-h / (tau * SR)))[:len(y)], 0.0) * rng().standard_normal(len(y))


def wood(size=1.0):
    """A timber breaking: a run of splinters, a split second's body under it."""
    m = nsm(0.2 + 0.2 * size)
    s = np.arange(m) / SR
    g = grit(m, 2400 * np.exp(-s / (0.025 + 0.03 * size)) + 90 * np.exp(-s / 0.14), 0.0025, 260, 6500, 2.4) * np.exp(-s / (0.05 + 0.05 * size))
    return g + noise(m, 110, 750, 1) * (1 - np.exp(-s / 0.001)) * np.exp(-s / (0.018 + 0.03 * size)) * 0.8


def knock(size=1.0):
    """A hollow beam struck, no note: a thump of body, a few splinters."""
    m = nsm(0.35)
    s = np.arange(m) / SR
    return noise(m, 80, 480, 1) * (1 - np.exp(-s / 0.0015)) * np.exp(-s / (0.035 + 0.02 * size)) + grit(m, 500 * np.exp(-s / 0.03), 0.002, 300, 3000) * np.exp(-s / 0.05) * 0.4


def stone(size=1.0):
    """Concrete going: a heavy thud and its rubble."""
    m = nsm(0.5 + 0.5 * size)
    s = np.arange(m) / SR
    x = grit(m, 420 * np.exp(-s / (0.1 + 0.15 * size)), 0.006, 130, 2800) * (1 - np.exp(-s / 0.002)) * np.exp(-s / (0.16 + 0.16 * size))
    y = impact(1.0, 0.1, 0.002, 0.14 + 0.08 * size, 0.0)
    return x * 0.8 + y[:m] * 0.9


def crunch(d, rate=380.0):
    """Things going in the water together: a rattle of pieces, none on its own."""
    m = nsm(d)
    return grit(m, rate * wander(m, 0.5, 5.0, 8.0), 0.004, 190, 3400) * np.sin(np.pi * np.arange(m) / m) ** 0.7


def groan(d, f0=46.0, regions=((170, 430), (430, 950), (950, 1900)), wild=0.3, lvl=(1.0, 0.7, 0.4)):
    """Steel or timber dragged under load: stick-slip, each period about a third out from the last and the rate wandering, through wide
    bands that come and go. A body and a strain, no note."""
    n = nsm(d)
    at, tp, f = [], 0.0, f0
    while tp < d:
        f = float(np.clip(f * np.exp(rng().normal(0, 0.05)), f0 * 0.55, f0 * 1.7))
        tp += max(1 / f * (1 + rng().normal(0, wild)), 0.003)
        at.append(tp)
    at = np.array(at)[np.array(at) < d]
    y = np.zeros(n)
    y[(at * SR).astype(int)] = rng().lognormal(0, 0.8, len(at)) * rng().choice((-1.0, 1.0), len(at))
    x = np.zeros(n)
    y = grit_of(y, 0.004)
    for (lo, hi), a in zip(regions, lvl):
        x += T.unit(band(y, lo, hi, 1)) * wander(n, 0.5, 4.0, 8.0) * a
    return x * np.sin(np.pi * np.arange(n) / n) ** 0.9 * wander(n, 0.4, 3.0, 5.0)


def bury(x, fc, tail=0.06, wet=0.8):
    """`x` in the water: its top gone over `fc`, smeared over a short tail of noise, so it is inside the roar."""
    y = band(x, None, fc, 2)
    h = np.arange(int(tail * SR * 5))
    w = fftconvolve(y, rng().standard_normal(len(h)) * np.exp(-h / (tail * SR)))
    out = w / (np.sqrt(np.sum(np.exp(-2 * h / (tail * SR)))) + 1e-9) * wet
    out[:len(y)] += y * (1 - 0.5 * wet)
    return out


def debris(d, rate, fc, gain=None, mix=(0.45, 0.35, 0.2), big=2.0):
    """A run of what the water carries, buried: `rate` things a second, `fc`: (seconds, Hz) pairs, how much of the top reaches the
    ear; `gain`: (seconds, dB) pairs; `mix`: shares of timber, concrete and things crushed. Unit-ish: a piece's RMS over its own
    length is about 1."""
    x = np.zeros(nsm(d + 1.0))
    k = rng().poisson(rate * d)
    xs, ys = zip(*fc)
    for t0 in np.sort(rng().uniform(0, d, k)):
        size = min(0.45 + rng().pareto(2.0) * 0.5, big)
        kind = rng().choice(3, p=mix)
        ev = T.unit(wood(size) if kind == 0 and rng().uniform() < 0.6 else knock(size) if kind == 0 else stone(size) if kind == 1 else crunch(rng().uniform(0.25, 0.7)))
        put(x, bury(ev, float(np.exp(np.interp(t0, xs, np.log(ys))))) * size ** 0.8 * (float(curve_db(t0, gain)) if gain else 1.0), t0)
    x = x[:nsm(d)]
    k = nsm(min(0.25, d / 4))
    x[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))           # (what is still sounding as it ends, let go)
    return x



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
FAR_LEN, FAR_DB = 9.5, -16.5
MID_DB = -15.0


def roar_far():
    d = FAR_LEN
    with PB.seeded(72101):
        x = T.unit(water(d, [(0.0, FAR_SH), (d, FAR_SH + np.interp(SH_F, [125, 1000], [0.0, 3.0]))], [(0, -24), (0.7, -7), (1.7, -3.5), (4.0, -1.5), (8.0, 0), (d, -8)],
                         surge=(0.36, 1.25), blobs=(5.0, 0.8, 60.0, 700.0), spat=0.6, fizz=0.0))
        # (its first big seas as the horizon stands up, then more, far apart; the air and the distance have the fronts of them)
        put(x, impact(0.7, 0.05, 0.1, 0.8, 0.0), 0.75)
        put(x, impact(0.55, 0.05, 0.14, 0.9, 0.0), 2.9)
        put(x, impact(0.6, 0.05, 0.14, 0.9, 0.0), 4.1)
        seas(x, d, 0.5, 2.1, 0.35, 0.8, bright=0.05, rise=0.12, fall=0.7, spray=0.0)
    write("roar_far", x, db=FAR_DB, fade_in=0.2, fade_out=1.0, crest=2.4)


def roar_mid():
    d = MID_LEN
    with PB.seeded(72201):
        x = T.unit(water(d, [(0.0, FAR_SH * 0.6 + MID_SH * 0.4), (5.0, MID_SH), (d, MID_SH * 0.5 + NEAR_SH * 0.5)], [(0, -7), (3, -3), (5.2, 0), (7.0, -5), (d, -16)],
                         surge=(0.5, 1.9), blobs=(7.0, 0.8, 80.0, 1400.0), spat=0.8, fizz=0.05))
        seas(x, 6.5, 0.55, 0.8, 0.5, 1.5, bright=0.15, rise=0.05, fall=0.6, spray=0.02)
        # (what it carries: only the mass of it from here; nothing small carries this far)
        n = nsm(d)
        x += debris(d, 1.3, [(0, 260.0), (d, 480.0)], [(0, -22), (6.0, -14), (d, -26)], (0.1, 0.75, 0.15))
        put(x, T.unit(groan(3.0, 34.0, ((90, 240), (240, 520)), 0.25, (1.0, 0.5))) * 0.10, 2.6)
        put(x, T.unit(groan(2.6, 40.0, ((90, 240), (240, 560)), 0.25, (1.0, 0.6))) * 0.13, 5.9)
    write("roar_mid", x, db=MID_DB, fade_in=0.9, fade_out=0.7, crest=2.3)


def near_signal(d, keys, lvl, seed, bright_hits=0.45):
    """The wall arriving: the mass of it from the first moment, what it carries coming into the ear as it comes."""
    with PB.seeded(seed):
        x = T.unit(water(d, keys, lvl, surge=(0.6, 1.3), blobs=(13.0, 0.8, 110.0, 5000.0), spat=1.2, fizz=0.16))
        seas(x, min(d, 4.0), 1.2, 0.35, 0.45, 1.5, bright=bright_hits, rise=0.012, fall=0.5, spray=0.03)
        x += debris(d, 3.2, [(0, 650.0), (d, 1500.0)], [(0, -15), (d, -9)])
        put(x, T.unit(groan(2.2, 44.0)) * 0.13, 1.1)
    return x


def roar_near():
    # (the immersion is NEAR_PRE into it: a breath of 120 ms, and then it stops: the engulf has taken it)
    d = ROAR_NEAR_LEN
    x = near_signal(d, [(0.0, MID_SH), (2.0, MID_SH * 0.35 + NEAR_SH * 0.65), (3.6, NEAR_SH + 1.0), (d, NEAR_SH)], [(0, -6), (2.0, -3), (3.6, 0), (d, 0)], 72301)
    t = np.arange(len(x)) / SR
    x = x * curve_db(t, [(0, 0), (NEAR_PRE - 0.13, 0), (NEAR_PRE - 0.02, -8), (NEAR_PRE + 0.08, -26), (d, -60)])
    write("roar_near", x, db=NEAR_DB, fade_in=0.6, fade_out=0.15, crest=2.4)


def roar_pass():
    # (on a hill above it: the wall comes on as it would, goes by below, and is off over the land)
    d = PASS_LEN
    x = near_signal(d, [(0.0, MID_SH), (2.2, MID_SH * 0.35 + NEAR_SH * 0.65), (4.0, NEAR_SH), (6.0, NEAR_SH * 0.6 + MID_SH * 0.4), (9.0, MID_SH), (d, FAR_SH)],
                    [(0, -6), (2.2, -3), (4.2, 0), (6.5, -2), (9.0, -7), (d, -26)], 72401, 0.2)
    write("roar_pass", x, db=NEAR_DB, fade_in=0.6, fade_out=1.5, crest=2.4)


def roar_back():
    d = 12.0
    with PB.seeded(72501):
        x = T.unit(water(d, [(0.0, MID_SH), (4.0, FAR_SH * 0.6 + MID_SH * 0.4), (d, FAR_SH)], [(0, 0), (2.5, -2), (6.0, -7), (10.0, -18), (d, -40)],
                         surge=(0.34, 1.3), blobs=(4.0, 0.8, 60.0, 700.0), spat=0.5, fizz=0.0))
        seas(x, 8.0, 0.35, 1.0, 0.3, 1.0, bright=0.04, rise=0.12, fall=0.7, spray=0.0)
    write("roar_back", x, db=-28.0, fade_in=1.8, fade_out=3.0, crest=3.0)


# ===========================================================================================  the immersion and what follows
ENGULF_FOAM = 1.5      # s of violent foam (the pass's) before the drop into the dark
BRIGHT_SH = NEAR_SH * 0.5 + WHITE_SH * 0.5


def engulf():
    d = 4.0
    with PB.seeded(73001):
        # (the white flash, everything at once; then seas slamming in it, closing down over the head; then the drop)
        x = T.unit(water(d, [(0.0, WHITE_SH), (0.15, WHITE_SH), (0.34, BRIGHT_SH), (ENGULF_FOAM - 0.3, NEAR_SH), (ENGULF_FOAM, NEAR_SH * 0.5 + UNDER_SH * 0.5), (ENGULF_FOAM + 0.28, UNDER_SH), (d, UNDER_SH - 6.0)],
                         [(0, 5), (0.15, 4), (0.34, 0.5), (ENGULF_FOAM, -2.5), (ENGULF_FOAM + 0.28, -9), (d, -22)],
                         surge=(1.2, 0.8), eddy=1.2, blobs=(26.0, 1.0, 140.0, 7000.0), spat=1.4, fizz=0.22))
        put(x, impact(1.5, 1.0, 0.0012, 0.55, 0.0, 0.7), 0.0)
        for tb, sz in ((0.33, 1.0), (0.58, 1.4), (0.86, 0.9), (1.17, 1.3), (1.42, 0.8)):
            put(x, impact(sz, 0.62, 0.006, 0.34, 0.025, 0.25), tb)
        y = debris(1.8, 8.0, [(0, 3400.0), (1.6, 1200.0)], [(0, -7), (1.5, -9)])
        x[:len(y)] += y
    write("engulf", x, db=ENGULF_DB, fade_out=0.3, crest=1.45)


UNDER_AT = 0.2         # tp + this
UNDER_LEN = SURF_AT - UNDER_AT + 0.3     # (it ends 0.3 s after the head is out, under the surface's own burst)
TREE_AT, CHUNK_AT, TREE2_AT = 2.5 - UNDER_AT, 3.75 - UNDER_AT, 5.3 - UNDER_AT      # (tp + 2.5, 3.75, 5.3, as the pass draws them)


def uw(x, fc=3000.0, tail=0.04):
    """A short piece in the water. (One at a time, each its own tail: a whole group through one tail is a fixed filter, its narrow
    peaks held for as long as the group lasts.)"""
    return bury(x, fc, tail, 0.9)


def tree_past(size=1.0):
    """A whole tree going by: the water it shoves ahead of it, a long groan, limbs and trunk knocking as it rolls. The trunk is
    closest 1.2 s in."""
    d = 2.6
    m = nsm(d)
    out = np.zeros(m)
    y = impact(0.9 * size, 0.1, 0.45, 0.55, 0.0)
    put(out, y[:m], 0.0)
    put(out, band(T.unit(groan(1.9, 22.0, ((120, 420), (420, 1000)), 0.4, (1.0, 0.5))), None, 3000.0, 2) * 0.5 * size, 0.3)
    for tb, a in ((0.8, 0.7), (1.05, 0.9), (1.2, 1.5), (1.36, 0.8), (1.62, 0.7), (1.95, 0.5)):
        put(out, uw(T.unit(knock(a))) * a * 0.9 * size, tb + rng().uniform(-0.03, 0.03))
    put(out, uw(T.unit(wood(1.4))) * 1.1 * size, 1.2)
    return out


def chunk_past():
    """A piece of a house: the blow, 0.35 s in, everything in it going, a beam, rubble clattering down it, the air getting out."""
    d = 2.8
    m = nsm(d)
    out = np.zeros(m)
    put(out, impact(0.9, 0.05, 0.25, 0.4, 0.0), 0.0)
    put(out, impact(2.6, 0.5, 0.002, 0.4, 0.008, 0.8), 0.35)
    put(out, band(T.unit(crunch(1.5, 520.0)), None, 7000.0, 2) * 0.8, 0.36)
    put(out, uw(T.unit(stone(1.6)), 7000.0) * 0.9, 0.42)
    put(out, uw(T.unit(wood(1.6)), 7000.0) * 0.8, 0.6)
    put(out, band(T.unit(groan(1.7, 40.0)), None, 3000.0, 2) * 0.35, 0.5)
    for tb in (0.75, 0.92, 1.1, 1.35, 1.7):
        put(out, uw(T.unit(stone(0.6)), 5000.0) * rng().uniform(0.25, 0.55), tb)
    return out


def under():
    d = UNDER_LEN
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(74001):
        # (a deep dark roar, surging hard; in a real one what hits comes through it at every frequency while the bed stays dark)
        x = T.unit(water(d, [(0.0, UNDER_SH + np.interp(SH_F, [300, 1500], [0.0, 8.0])), (0.9, UNDER_SH), (d - 1.5, UNDER_SH), (d - 0.3, UNDER_SH * 0.55 + RUN_SH * 0.45), (d, RUN_SH)],
                         [(0, -13), (1.1, -11), (1.6, -2), (d - 1.5, -2), (d - 0.3, -1), (d, -3)], surge=(0.7, 2.8), eddy=1.25, spat=0.7, blobs=(9.0, 1.5, 60.0, 900.0), fizz=0.0))
        hits = np.zeros(n + nsm(3.0))
        # (the water's own blows, low and heavy, and what it carries, in the dark)
        seas(hits, d, 1.1, 1.6, 0.5, 1.7, bright=0.3, rise=0.006, fall=0.2, spray=0.0, kick=0.35)
        y = debris(d - 2.0, 2.0, [(0, 2600.0), (d - 1.5, 3000.0)], [(0, -11), (d, -8)], (0.45, 0.4, 0.15), 2.4)
        hits[nsm(1.6):nsm(1.6) + len(y)] += y
        put(hits, T.unit(groan(3.2, 30.0, ((110, 320), (320, 800)), 0.35, (1.0, 0.5))) * 0.22, 1.0)
        # (and over all that a chaos of seconds: a real one swings by 15 dB from one breath to the next)
        heave_ = np.interp(np.arange(len(hits)) * CR / SR, np.arange(int(d * CR) + 2), surges(d, 0.9, (0.15, 0.6), (0.4, 1.4), 0.7))
        hits[:] = hits * 10 ** (np.minimum(heave_ * 1.6, 7.0) / 20)
        x = x * 10 ** (np.minimum(heave_[:n] * 1.1, 6.0) / 20)
        # (the tree, the piece of the house, the second tree: each peak on its moment)
        put(hits, tree_past(1.0) * 1.0, TREE_AT - 1.2)
        put(hits, chunk_past(), CHUNK_AT - 0.35)
        put(hits, tree_past(0.85) * 0.9, TREE2_AT - 1.2)
        x = x + hits[:n]
        # (the last second and a half: hauled up, the air coming)
        x += noise(n, 600, 5200, 2) * curve_db(t, [(0, -70), (d - 1.5, -36), (d - 0.2, -14), (d, -11)]) * wander(n, 0.8, 5.0, 5.0)
    write("under", x, db=-14.5, fade_in=0.02, fade_out=0.1, crest=3.1)


def surface():
    d = 3.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(74101):
        # (the head out: everything at once on its first sample, then the air round the player and water falling off them)
        x = T.unit(water(d, [(0.0, WHITE_SH), (0.2, BRIGHT_SH), (0.9, TORRENT_SH), (d, TORRENT_SH)], [(0, 3), (0.25, 0), (1.0, -5), (d, -24)],
                         surge=(1.5, 0.8), blobs=(26.0, 0.9, 200.0, 8000.0), spat=1.3, fizz=0.2))
        put(x, impact(1.8, 0.95, 0.0015, 0.4, 0.0), 0.0)
        x += grit(n, 900 * np.exp(-t / 0.7) + 60, 0.0018, 900, 11000) * curve_db(t, [(0, -14), (0.8, -15), (2.0, -26), (d, -44)])
    write("surface", x, db=-14.6, fade_out=0.8, crest=2.3)


def torrent():
    d = 13.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(75001):
        # (in the flow: the whole land's water pouring away, the weight going first, thinning towards separate running water)
        x = T.unit(water(d, [(0.0, TORRENT_SH), (3.0, TORRENT_SH), (6.5, RUN_SH), (d, RILL_SH)], [(0, 0), (2.5, -1), (5.0, -4), (8.0, -9), (11.0, -16), (d, -26)],
                         surge=(0.6, 1.8), blobs=(16.0, 1.0, 170.0, 6500.0), spat=1.0, fizz=0.15))
        # (ledges of it coming down, less and less)
        seas(x, 8.0, 0.8, 0.5, 0.4, 1.2, bright=0.5, rise=0.02, fall=0.34, spray=0.03)
        y = debris(7.0, 1.8, [(0, 3800.0), (7, 2400.0)], [(0, -13), (7, -24)], (0.6, 0.3, 0.1))
        x[:len(y)] += y
    write("torrent", x, db=-14.5, fade_in=0.03, fade_out=1.5, crest=2.4)


def gulp(size=1.0):
    """A hollow letting go: two soft thumps of water, no note."""
    m = nsm(0.3)
    s = np.arange(m) / SR
    x = noise(m, 130, 620, 1) * (1 - np.exp(-s / 0.006)) * np.exp(-s / (0.03 + 0.02 * size))
    return x + np.roll(x, nsm(rng().uniform(0.05, 0.12))) * 0.6


def drain():
    d = 12.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(76001):
        # (running water, near and far at once: wide, nothing in it a stream of its own)
        thin = np.interp(np.arange(int(d * CR) + 2) / CR, [0, 5, d], [1.0, 0.7, 0.25])
        x = T.unit(water(d, [(0.0, RUN_SH), (5.0, RILL_SH), (d, RILL_SH)], [(0, -3), (2.5, 0), (6.0, -5), (9.5, -17), (d, -42)],
                         surge=(0.9, 1.1), eddy=1.15, blobs=(34.0, 1.6, 240.0, 7000.0), spat=1.5, fizz=0.2, thin=thin))
        for tc in np.sort(rng().uniform(0.5, 10.0, 16)):
            put(x, gulp(rng().uniform(0.6, 1.4)) * 0.28 * rng().uniform(0.3, 1.0) * float(np.exp(-tc / 7.0)), tc)
        for tc, a in ((1.4, 0.32), (3.9, 0.25), (6.8, 0.16)):
            put(x, bury(T.unit(knock(rng().uniform(0.5, 1.0))), 2600.0, 0.03) * a, tc)
    write("drain", x, db=-22.0, fade_in=0.8, fade_out=2.0, crest=3.4)


# ==============================================================================================================  trickle
def drip(f0, size=1.0):
    """One drop falling into shallow water: gone in a few milliseconds, more tick than note."""
    m = nsm(0.09)
    s = np.arange(m) / SR
    f = f0 * (1 + 0.5 * (1 - np.exp(-s / 0.006)))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR + rng().uniform(0, 6.28)) * (1 - np.exp(-s / 0.0008)) * np.exp(-s / (0.004 + 0.002 * size))
    x += noise(m, 1500, 9000, 1) * np.exp(-s / 0.0025) * 0.5
    return x / (np.abs(x).max() + 1e-12)


def trickle():
    d = 14.0
    n = nsm(d)
    t = np.arange(n) / SR
    with PB.seeded(80001):
        thin = np.interp(np.arange(int(d * CR) + 2) / CR, [0, 6, d], [0.8, 0.3, 0.05])
        x = T.unit(water(d, [(0.0, RILL_SH), (d, RILL_SH - 3.0)], [(0, 0), (4, -3), (8, -11), (11, -20), (d, -34)],
                         surge=(1.0, 1.2), eddy=1.2, blobs=(24.0, 3.0, 300.0, 6000.0), spat=1.6, fizz=0.15, thin=thin)) * 0.5
        # drops into the shallows, fewer as it dries, never in time
        for tt_ in P.poisson_times(0.5, d - 1.0, lambda v: 1.5 * np.exp(-v / 6.0) + 0.3):
            put(x, drip(rng().uniform(500, 1700), rng().uniform(0.5, 1.5)) * rng().uniform(0.1, 0.8) ** 1.4 * 0.5, tt_)
        # mud sagging; a last timber settling twice
        for tc in np.sort(rng().uniform(0.8, 11.0, 8)):
            put(x, gulp(rng().uniform(0.8, 1.6)) * 0.3 * rng().uniform(0.3, 1.0), tc)
        put(x, T.unit(groan(1.1, 20.0, ((140, 420), (420, 900)), 0.4, (1.0, 0.4))) * 0.22, 4.6)
        put(x, T.unit(groan(0.9, 18.0, ((140, 420), (420, 900)), 0.4, (1.0, 0.4))) * 0.14, 9.9)
        put(x, T.unit(knock(0.6)) * 0.14, 6.1)
        x = x * curve_db(t, [(0.0, 0.0), (5.0, -1.0), (9.0, -9.0), (12.0, -20.0), (d, -30.0)])
    write("trickle", x, db=-33.0, fade_in=1.2, fade_out=3.5)



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
CRASH_LEVEL = -13.0


def crash():
    d = CRASH_D
    n = nsm(d)
    with PB.seeded(78001):
        # (a mountain of water coming down on the land: weight first; from hundreds of blocks off what it crushes is only
        # a dark mass under the roar, no board or pane heard)
        x = T.unit(water(d, [(0.0, MID_SH), (1.5, MID_SH * 0.6 + NEAR_SH * 0.4), (8.0, MID_SH), (d, FAR_SH)], [(0, -60), (0.06, -30), (0.2, 0), (1.6, -1), (3.2, -6), (6.0, -12), (10.0, -24), (d, -55)],
                         surge=(0.7, 1.15), eddy=1.1, blobs=(12.0, 1.0, 90.0, 2800.0), spat=1.0, fizz=0.08))
        put(x, impact(2.4, 0.42, 0.04, 0.95, 0.03, 0.5), CRASH_LEAD)
        put(x, impact(1.5, 0.3, 0.05, 0.8, 0.03, 0.2), CRASH_LEAD + 0.55)
        tb = 1.1
        while tb < 11.0:
            put(x, impact(min(0.4 + rng().pareto(2.2) * 0.4, 1.5) * float(np.exp(-tb / 3.5)), rng().uniform(0.1, 0.32), 0.03, 0.6, 0.03), tb)
            tb += rng().gamma(0.9, 0.55 + 0.1 * tb)
        x[:nsm(d - 1.0)] += debris(d - 1.0, 2.4, [(0, 1100.0), (d, 500.0)], [(0, -13), (8, -18), (d - 1, -40)], (0.2, 0.55, 0.25), 2.4)
        put(x, T.unit(groan(3.4, 34.0, ((90, 280), (280, 800)), 0.25, (1.0, 0.5))) * 0.14, 2.3)
        x = lows_harm(x, -14.0, f_hi=80.0, lo=60.0, hi=240.0)
    write("crash", x, db=CRASH_LEVEL, fade_out=2.0, crest=2.3)


def crash_far():
    # (the same moment from far off: `far_of` softens its front, lets the top down, adds rolls and a long dark tail)
    x = N.decoded("crash")
    if x is None:
        raise SystemExit("crash is not built yet: build it before crash_far")
    L, R = N.far_of("crash", 78401, CRASH_D + 5.0)
    y = (L + R) / 2
    write("crash_far", y, db=-13.5, fade_in=0.0, fade_out=3.0, crest=1.9)


# =======================================================================================  cracks and slaps (positional)
def splash_tail(d, lvl, rise=0.05):
    """The wash round a thing that broke or a wall that was hit: a little water of its own, no bubbles."""
    t = np.arange(nsm(d)) / SR
    return T.unit(water(d, [(0.0, RUN_SH)], [(0, -3), (rise, 0), (0.3, -2), (d, -24)], surge=(2.0, 0.8), blobs=(30.0, 1.2, 250.0, 6000.0), spat=1.4, fizz=0.2)) * lvl


def crack_take(v):
    d = (1.8, 1.5, 1.6, 1.9)[v - 1]
    n = nsm(d)
    with PB.seeded(79100 + 17 * v):
        x = np.zeros(n)
        if v == 1:       # a trunk snapping: the strain, the break, the splinter run, the weight going over
            put(x, T.unit(groan(0.42, 24.0, ((180, 700), (700, 1800)), 0.4, (1.0, 0.6))) * 0.3, 0.0)
            put(x, T.unit(wood(2.0)) * 1.0, 0.42)
            put(x, T.unit(wood(1.0)) * 0.4, 0.58)
            put(x, grit(nsm(0.9), 240 * np.exp(-np.arange(nsm(0.9)) / SR / 0.3), 0.003, 280, 5200) * 0.16 * np.exp(-np.arange(nsm(0.9)) / SR / 0.35), 0.54)
            put(x, impact(0.5, 0.05, 0.004, 0.2, 0.0), 1.1)
        elif v == 2:     # a young tree: a quick double snap, a whip of branches
            put(x, T.unit(wood(0.8)) * 0.7, 0.15)
            put(x, T.unit(wood(1.3)) * 1.0, 0.33)
            put(x, grit(nsm(0.8), 300 * np.exp(-np.arange(nsm(0.8)) / SR / 0.25), 0.002, 400, 6000) * 0.14 * np.exp(-np.arange(nsm(0.8)) / SR / 0.3), 0.42)
            put(x, impact(0.35, 0.05, 0.004, 0.16, 0.0), 0.7)
        elif v == 3:     # a house timber and planks going: a beam, then boards in a shower, the clatter
            put(x, T.unit(wood(1.6)) * 1.0, 0.28)
            for a in (0.5, 0.62, 0.78, 0.95, 1.08):
                put(x, T.unit(knock(rng().uniform(0.4, 1.0))) * rng().uniform(0.2, 0.5), a)
            put(x, impact(0.5, 0.08, 0.003, 0.18, 0.0), 0.58)
        else:            # a trunk wrenched out of the ground, roots and all: a long groan, the roots, the break, the thud
            put(x, T.unit(groan(0.8, 26.0, ((110, 420), (420, 1000)), 0.35, (1.0, 0.5))) * 0.4, 0.05)
            put(x, grit(nsm(0.6), 300.0, 0.005, 120, 1800) * 0.16 * np.sin(np.pi * np.arange(nsm(0.6)) / nsm(0.6)), 0.3)
            put(x, T.unit(wood(1.6)) * 0.9, 0.55)
            put(x, T.unit(wood(0.9)) * 0.4, 0.78)
            put(x, impact(0.8, 0.06, 0.004, 0.25, 0.0), 0.98)
        x = x + splash_tail(d, 0.05)
        x = band(x, 60, None, 1)
    write(f"crack{v}", x, peak_db=-7.0, fade_in=0.0, fade_out=0.35)


def slap_event(size):
    """Water slamming something solid: the slam, the burst, the sheet of it falling back."""
    y = impact(1.0, 0.55, 0.0025, 0.1 + 0.08 * size, 0.012, 0.3)
    m = nsm(0.5 + 0.5 * size)
    s = np.arange(m) / SR
    z = np.zeros(max(m, len(y)))
    z[:len(y)] += y
    z[:m] += grit(m, 1500 * np.exp(-s / (0.1 + 0.1 * size)), 0.0015, 700, 8000) * (1 - np.exp(-s / 0.02)) * np.exp(-s / (0.1 + 0.12 * size)) * 0.5
    return z / (np.abs(z).max() + 1e-12)


def slap_take(v):
    d = (1.7, 1.6, 1.6)[v - 1]
    n = nsm(d)
    with PB.seeded(79200 + 19 * v):
        x = np.zeros(n)
        if v == 1:       # a big surge slammed into a wall, and the sheet of water falling back
            put(x, slap_event(2.0), 0.10)
            put(x, slap_event(0.9) * 0.4, 0.42)
        elif v == 2:     # a double surge against stone: a slap, the heavier one on its heels
            put(x, slap_event(1.1) * 0.7, 0.08)
            put(x, slap_event(2.2), 0.40)
        else:            # a cascade of small slaps along a wall
            for a, sz, g in ((0.06, 0.8, 0.8), (0.22, 0.5, 0.6), (0.37, 1.1, 1.0), (0.58, 0.4, 0.5), (0.74, 0.7, 0.55), (0.95, 0.35, 0.35)):
                put(x, slap_event(sz) * g, a)
        x = x + splash_tail(d, 0.06, 0.1)
        x = band(x, 55, None, 1)
    write(f"slap{v}", x, peak_db=-7.0, fade_in=0.0, fade_out=0.4)



BUILD = {"rupture": rupture, "rumble": rumble, "roar_far": roar_far, "roar_mid": roar_mid, "roar_near": roar_near, "roar_pass": roar_pass,
         "crash": crash, "crash_far": crash_far, "engulf": engulf, "under": under, "surface": surface, "torrent": torrent, "drain": drain,
         "roar_back": roar_back, "rumble_after": rumble_after, "trickle": trickle,
         "crack1": lambda: crack_take(1), "crack2": lambda: crack_take(2), "crack3": lambda: crack_take(3), "crack4": lambda: crack_take(4),
         "slap1": lambda: slap_take(1), "slap2": lambda: slap_take(2), "slap3": lambda: slap_take(3)}


# ===========================================================================================================  listening
CLIPS = {}
OCT = np.array([31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000])


def mixdown(dp, pad=0.5, immersed=True):
    """The whole strike as heard `dp` blocks from the target, from strike second 0 (file domain, mono, as the Rod's
    `--listen`: every file at its volume, on its time, its pitch a change of speed)."""
    ev = schedule(dp, immersed)
    for _, f, _, _, _ in ev:
        if f not in CLIPS:
            CLIPS[f] = decoded(f)
    clips = CLIPS
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
