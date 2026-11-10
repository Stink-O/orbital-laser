"""The Sky Breaks' sounds, all synthesised here and all this laser's own: nothing sampled (but the shudder's glass), nothing taken from another
laser's sound code (this file imports only `soundlib`'s filter, its sample rate and the output folder); the shudder's
glass is slices of real CC0 glass breaks (tools/sound_sources/skybreak). Round 4: a disc
of land tears free round the target and rises into the sky, sinks into it, the sky rings stiffly and bows under a hand
pressing on it from behind; the hand punches through (the crack), withdraws, an eye slides in to look through the hole;
huge panes of sky break free, come down and smash into the land; at the end the eye flares, the hand comes back down
through the hole and slams the land, its shudder knocks the last of the middle loose, and the sky heals.

The glass is built from its physics (Zheng and James, fracture sound, SIGGRAPH 2010: the sound is mostly the new
pieces ringing; Warren and Verbrugge 1984: a break is many overlapping series of knocks; a window's break a low thump,
then its pieces; glass loss factor ~0.005; brittle fragments power-law in size):
- every piece is a small plate: its partials its own plate's modes ((m^2 + (n r)^2) for its aspect r, the near-equal
  pairs split so they beat), its pitch set by its size (thickness / size^2), each mode dying in Q / (pi f), its Q about
  150-300 at 500 Hz and more over it, so a small piece rings clear for a few tens of ms and a big one dies before it
  can boom (and where pieces are heard one by one, their Q kept low: they knock rather than ping), struck by a contact
  pulse whose length sets how much of its top it gets (`shard`, `ring_shard`);
- a break is thousands of pieces, power-law in size, each its own series of knocks at shrinking intervals as it is born
  and hits its neighbours or the land: many overlapping series is what the ear hears as breaking (`cascade`);
- a crack is a few milliseconds of rupture and a stream of pieces born as it runs (`rupture`, `crack_at`);
- the sky is one pane with its own low modes (`PANE`, 31 Hz up, inharmonic): it booms as it is struck and is choked as
  the cracks cut it up, and under load it sings, its modes bowed by the strain (`pane_ring`, `pane_song`), small
  cracks ticking in it faster as it nears the break;
- the scale: the whole glass sits about two octaves under a window's, so its big pieces ring at 150-600 Hz and its
  smallest at 2-4 kHz, their decays as long as a slowed-down recording's; the smallest are the quietest, and past the
  first moment they are heard mostly through the sky (`distance`), darkened. No chime, no clink, no crinkle: the bright
  part is a dense crash at the break, then a far, dark glitter.
Under the glass, the weight: tonal booms, the land's own modes, a sub, all dry and tight. No burst of noise on the front
of a hit (a snare), no fast gain over a roar (the flicker): the roars are bands of noise each boiling slowly on its own.
Horizon plays every sound summed to mono: every file here is mono.

The schedule (strike seconds), as mod/src/strike/sb_sounds.rs plays them (the panes' own, `release` to `slam`, as
strike/skybreak.rs's sb_pane_events does); `late` = the player's distance / 343:

  tear       0         the hook: the land wrenched free (the ground's own modes in a heavy lurch, deep wrenches you can
                       count, the ground parting, the air sucked in under it, the earth pouring off it); `tear_far` by distance
  rise       0         to TOP (4.2): a deep tone climbing as it gathers speed, the air it pushes up through, a rush band
                       sweeping up, the earth streaming off it at first, a sub; more and more of it the sky's
  sink       TOP-0.3   it meets the pane: a soft heavy blow on the sky's own modes, the pane singing as it bends round it,
                       the gulp as it is taken in, the star crack snapping out where it went in (5.3), a soft deep shut
  ripple     IN-0.05   two or three tight stiff rings: the pane's modes knocked softly, each dead before the next; dead by 7
  pressure   IN        to the crack, never dipping: the pane singing under the hand's load, its modes opening and
                       climbing, a sub climbing, two heaves of the hand's weight, small cracks ticking quicker and
                       bigger; the fist drawn back (8.35), the air pulled in, rushing up into the punch
  crack      9.0       the hand punching through: one hard rupture and the fist's deep blow, the crack running over the
                       whole sky (the radials in 0.07 s, the rings by 0.25), the pane's boom choked as it is cut up,
                       then the pieces breaking away, big and small, deep and dense, and the sky giving it back
  withdraw   9.3       the arm going back up through the hole: the air rising away, the shards it
                       drags grinding on the edge, one breaking off (10.0), the pane groaning, the air sucked in behind it
  strain     9.6       the sky under load to the last impact: the pane singing low, a dark rumble, deep cracks as the
                       panes shift
  gaze       LOCK-7.6  the eye sliding in behind the sky, two deep notes a semitone apart swelling as it opens and looks
                       round, cut dead as its gaze lands on the player (LOCK) on one deep blow
  collapse   ~9.0      the middle blown down round the fist: its pieces breaking on each other, falling away; 2.4-4 s
                       later the glitter as they burst, far up, faint and dark
  void       18.25     what looks through the holes, on into the heal
  release    per pane  a pane sagging (its own modes singing, cracks running round its edge), breaking free at 1.5 s in
                       (a crack, the pieces shed off its broken edge, its body choked), the air as it drops away
  fall       per pane  the air it tears through, its glass humming in it, cut dead on the impact
  ground     per pane  its blow through the ground, first
  impact     per pane  it smashing into the land: the boom and the land's modes, the pane crashing into pieces as it goes
                       in, the pieces bouncing and settling (fewer and further off), the earth thrown; `impact_far` far off
  slam       per pane  its far end slamming down: a short heavy blow and the glass crunching under it
  rumble     2 s after the last pane before the finale, and after the slam: the land settling
  flare      35.1-4    the eye's last flare (its burst on 35.1): the sky's air pulled in to the hole, a gale building
                       (no riser, no sweep), the sky groaning under it; then a thunderclap up there, the roll of it,
                       the hot air spilling out (round 6: all of it from pressure strokes and crackle, no tones)
  descend    36+late   the fist thrown down through the hole in one blow: the air drawn up to it beyond the glass, the
                       shards round the hole cracking off as it bursts through (0.9 s in), then the roar of the air it
                       drives down and the wall of air ahead of the fist, only climbing out of the flare, cut dead on
                       the slam (1.5 s in)
  (the slam, 37.5 + late: the Payload's alternative blast, its ground_alt, blast_alt or blast_alt_far, rush and tail,
                       as strike/sb_sounds.rs plays them; this laser's own `smash` and `smash_far` are gone. Their
                       builders are kept below, unused)
  shudder    after it  the slam's shudder up through the glass: the last ring of the middle letting go piece by piece,
                       each a sheet of glass breaking (round 8: slices of real glass breaks, CC0, from
                       tools/sound_sources/skybreak, over a synthesised dull body, sub, air and sky echo), falling, and
                       bursting into glitter far up
  heal       HEAL-1    the sky drawn back whole: its pieces' rings swelling backwards into the seal, the pane singing as
                       it closes, one deep ring as it is whole (HEAL 47)

    python3 tools/sounds_skybreak.py                  # writes orbital-sounds/assets/orbital/sounds/skybreak/*.ogg and the
                                                      # skybreak.* events in sounds.json
    python3 tools/sounds_skybreak.py --only crack     # some (tear before tear_far, impact before impact_far, smash before
                                                      # smash_far)
    python3 tools/sounds_skybreak.py --only --listen DIR   # no building: MP3s of the stems, the crack in context (4 to
                                                      # 12.5 s) and the whole strike as the game mixes it from 30, 300
                                                      # and 800 blocks, spectrograms, levels
"""
import argparse, json, os, subprocess, sys, wave
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import minimum_filter1d
from scipy.signal import butter, fftconvolve, lfilter, resample_poly, sosfilt
import soundlib
from soundlib import SR, band

TH = "skybreak"
ROOT = Path(__file__).resolve().parent.parent
NAMES = ["tear", "tear_far", "rise", "sink", "ripple", "pressure", "crack", "withdraw", "strain", "collapse", "release", "release2",
         "fall", "ground", "impact", "impact2", "impact3", "impact_far", "void", "rumble", "heal", "gaze", "slam", "flare", "descend",
         "shudder"]
# (round 3's, superseded long ago: their events and files go)
GONE = ["fracture", "spread", "smash", "smash_far"]   # (and round 4's slam: the Payload's alternative blast now)
# The mix balance, dB added to a file's nominal level
TRIM = {}
TP_MAX = 10 ** (-1.15 / 20)     # every file's decoded true peak (4x oversampled) at most this

FALL_CUT = 4.6                  # (skybreak.rs's SB_FALL_SND: the fall is cut dead this far in, on the impact)
RELEASE_FREE = 1.5              # the release's crack: the pane breaks free this far into the file
IMP_LEAD = 0.02                 # the impact's blow is this far into its file
SLAM = 0.34                     # (skybreak.rs's SB_SLAM: a pane's far end slams down this long after its low end strikes)
SPEED = 343.0
GROUND_V = 5 * SPEED

# ---- the timeline (sb_sounds.rs has the same: keep them in step) -----------------------------------------------------
LEAD = 8.75                     # (SB_LEAD: round 3's beats this much later)
TOP, IN = 4.2, 5.4              # the island reaches the sky shell; the sky rings from here (sb_lift.rs's LF_TOUCH, LF_RIPPLE)
STAR = 5.3                      # (LF_STAR: the star crack snaps out where it went in)
BOW = 7.0                       # the hand, laid flat on the sky, leans on it from here (LF_PRESS)
CURL = 8.35                     # the fist drawn back off the sky, its last heave (LF_CURL)
CRACK_T = 9.0                   # the hand punches through
LET_GO = 10.0                   # (sb_hand.rs's SB_LET_GO: the first shard the arm drags falls off it)
LOCK_HIT = 10.4 + 0.45 + LEAD   # the eye's gaze lands on the player (skybreak.wgsl's SB_LOCK + 0.45, shifted)
COLLAPSE_T = CRACK_T + 0.03     # (SB_COLLAPSE: the middle round the fist blown down, a hair after the crack)
VOID_T = 9.5 + LEAD
FLARE_T, DOWN_T, SLAM_T = 35.1, 36.0, 37.5   # the eye flares; the fist is thrown down from over the hole; it slams the land
KNOCK_T = SLAM_T + 0.22         # (SB_KNOCK: its shudder knocks the middle's outer ring loose, over 0.85 s)
HEAL_T = 40.0                   # (SB_HEAL)
# where each beat is in its file
TEAR_AT = 0.03
SINK_AT = 0.3
RIPPLE_AT = 0.05
PRESS_TOP = CRACK_T - IN        # (pressure starts at IN and is at its top on the crack)
CRACK_AT = 0.02
WITHDRAW_AFTER = 0.3            # (withdraw starts this long after the crack)
GAZE_HIT = 7.6                  # (gaze starts LOCK_HIT - GAZE_HIT: the slide in from 12.0)
FLARE_AT = 4.0                  # (flare starts FLARE_AT before the flare: its gathering)
DESCEND_CUT = SLAM_T - DOWN_T   # (descend is cut dead this far in, on the slam)
DESCEND_THROUGH = 0.9           # (its knuckles burst down through the hole this far in: sb_hand.rs's slam)
SMASH_AT = 0.02
LIFT_AT, GONE_AT = 38.9 - SLAM_T, 42.6 - SLAM_T   # (smash: sb_hand.rs's SB_LIFT, SB_GONE, this far after the slam)
SHUDDER_AT = 0.1                # (shudder: the knock this far in)
COLLAPSE_AT = 0.15              # (collapse: the middle blown down this far in)
GLITTER = (2.4, 3.7)            # (skybreak.rs: a fragment of the middle bursts into glitter this long after it falls)


# =================================================================================================  small tools
_R = [np.random.default_rng(1)]


def rng():
    return _R[0]


@contextmanager
def seeded(seed):
    """This sound's randomness from its own stream, so changing one sound leaves every other one's draws as they were."""
    old = _R[0]
    _R[0] = np.random.default_rng(seed)
    try:
        yield
    finally:
        _R[0] = old


def nsm(d):
    return int(round(SR * d))


def put(x, y, t0):
    """`y` added into `x` from `t0` s (what falls outside `x` dropped)."""
    k = nsm(t0)
    if k < 0:
        y, k = y[-k:], 0
    m = min(len(y), len(x) - k)
    if m > 0:
        x[k:k + m] += y[:m]


def ss(a, b, x):
    u = np.clip((np.asarray(x, float) - a) / (b - a), 0.0, 1.0)
    return u * u * (3 - 2 * u)


def curve(t, pts):
    """A smooth level over `t` through `pts` ((s, dB) pairs), as a linear gain."""
    xs, ys = zip(*pts)
    return 10 ** (PchipInterpolator(xs, ys)(np.clip(t, xs[0], xs[-1])) / 20)


def unit(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def loud(x, w=0.4, hop=0.1):
    """The loudest `w` s of `x` (RMS): how loud a sound plays."""
    n, h = nsm(w), nsm(hop)
    if len(x) <= n:
        return float(np.sqrt(np.mean(x ** 2)))
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    a = np.arange(0, len(x) - n, h)
    return float(np.sqrt(np.max(c[a + n] - c[a]) / n))


def noise(n, lo=None, hi=None, order=2):
    """Unit-RMS noise in a band."""
    return unit(band(rng().standard_normal(n), lo, hi, order))


def slow(n, lo, hi, rate=1000):
    """A random curve, unit spread, all its movement between `lo` and `hi` Hz."""
    m = int(n * rate / SR) + 4
    g = band(rng().standard_normal(m), lo * SR / rate, hi * SR / rate, 2)
    g = g / (np.std(g) + 1e-12)
    return np.interp(np.arange(n) * rate / SR, np.arange(m), g)


def causal_hp(x, f, order=2):
    """A highpass that only looks back: nothing rings ahead of a hit."""
    return sosfilt(butter(order, f, "highpass", fs=SR, output="sos"), x)


def stft_shape(x, gain_at, size=2048, hop=512):
    """`x` through a filter that changes as it goes: `gain_at(sample)` the gain over `rfftfreq(size)` for the frame
    centred there; Hann frames overlap-added."""
    n = len(x)
    win = np.hanning(size)
    xp = np.concatenate([np.zeros(size), x, np.zeros(size)])
    out = np.zeros(len(xp))
    norm = np.zeros(len(xp))
    for s in range(0, n + size, hop):
        c = min(max(s + size // 2 - size, 0), n - 1)
        fr = np.fft.irfft(np.fft.rfft(xp[s:s + size] * win) * gain_at(c), size) * win
        out[s:s + size] += fr
        norm[s:s + size] += win ** 2
    return (out / np.maximum(norm, 1e-3))[size:size + n]


FR = np.fft.rfftfreq(2048, 1 / SR)


def lowpass_track(x, fc):
    """`x` through a lowpass (12 dB an octave) whose cutoff follows `fc` (Hz, one a sample): the top let go with distance."""
    fc = np.broadcast_to(np.asarray(fc, float), (len(x),))
    return stft_shape(x, lambda c: 1 / np.sqrt(1 + (FR / fc[c]) ** 4))


def glide(n, fc, width):
    """Noise in a band `width` octaves wide whose middle follows `fc` (Hz, one a sample). Unit RMS."""
    fc = np.broadcast_to(np.asarray(fc, float), (n,))
    width = np.broadcast_to(np.asarray(width, float), (n,))
    lf = np.log2(np.maximum(FR, 1.0))
    return unit(stft_shape(rng().standard_normal(n), lambda c: np.exp(-0.5 * ((lf - np.log2(fc[c])) / (width[c] / 2.355)) ** 2)))


def sky_ir(length, t60, seed, build):
    """The open sky or the land round it giving a sound back: noise dying in `t60` (its lows, mids, highs: s to -60 dB),
    building up over `build` s (no hard first reflection out there). Unit energy."""
    g = np.random.default_rng(seed)
    n = nsm(length)
    t = np.arange(n) / SR
    b = g.standard_normal(n)
    h = band(b, None, 280, 2) * np.exp(-6.91 * t / t60[0]) + band(b, 280, 2200, 2) * np.exp(-6.91 * t / t60[1]) * 0.8 \
        + band(b, 2200, None, 2) * np.exp(-6.91 * t / t60[2]) * 0.45
    h *= 1 - np.exp(-t / build)
    return h / np.sqrt(np.sum(h ** 2))


def verb(x, length=5.0, t60=(4.0, 2.6, 0.9), seed=0, build=0.05, lo=150.0):
    """Only what the sky gives back of `x` over `lo` Hz (under it the space adds nothing: a long reverb piles a sub up
    into a second, slower blow, so the weight stays dry and tight). The same length as `x`."""
    y = band(x, lo, None, 2) if lo else x
    return fftconvolve(y, sky_ir(length, t60, seed, build))[:len(x)]


def space(x, wet=0.5, **kw):
    return x + verb(x, **kw) * wet


def weight(x, rel_db=-9.0, f_hi=90.0, lo=70.0, hi=320.0):
    """`x` with the harmonics of its lows added (its sub through a lopsided saturation, odd and even, kept to `lo`-`hi`
    Hz) at `rel_db` under them: a laptop or a phone hears the weight; the sub itself untouched."""
    sub = band(x, None, f_hi, 3)
    c = np.percentile(np.abs(sub), 99.0) * 0.35 + 1e-9
    s = np.tanh(sub / c)
    h = band(s + 0.4 * s * s, lo, hi, 2)
    return x + h / (loud(h) + 1e-12) * loud(sub) * 10 ** (rel_db / 20)


def soft_clip(x, c, knee=0.6):
    """Peaks over `knee` of `c` rounded off smoothly, nothing past `c`: the density of a blast's first instant."""
    k = knee * c
    a = np.abs(x)
    return np.where(a > k, np.sign(x) * (k + (c - k) * np.tanh((a - k) / (c - k))), x)


def tame_lows(x, f=200.0, pct=99.0, knee=0.5):
    """`x` with only its lows' peaks rounded off (under `f` Hz, over its `pct` percentile): a sub's peaks take the
    headroom the crack's front needs, and the lows driven a little are only more power."""
    lo = band(x, None, f, 2)
    return x - lo + soft_clip(lo, np.percentile(np.abs(lo), pct), knee)


def limit(x, ceiling, look=0.0015, release=0.15):
    """A look-ahead peak limiter: the gain dips in time for each peak and comes back over `release` s."""
    g = np.minimum(1.0, ceiling / np.maximum(np.abs(x), 1e-12))
    w = max(nsm(look), 2)
    g = minimum_filter1d(g, 2 * w + 1)
    k = np.exp(-1.0 / (release * SR))
    out = []
    s = 1.0
    for v in g.tolist():
        s = v if v < s else 1.0 - (1.0 - s) * k
        out.append(s)
    out = np.array(out)
    sm = np.convolve(np.pad(out, (w, w), mode="edge"), np.ones(2 * w + 1) / (2 * w + 1), mode="valid")
    return x * np.minimum(sm, g)


# ---- shapes of a blow (this laser's own) -------------------------------------------------------------------------------
def heave(n, t0, f0, f1, rate, rise, decay, a=1.0):
    """A heave, not a bang: a sine sinking from `f0` to `f1` Hz (e-fold `rate`), rising over `rise` s, dying over `decay`."""
    t = np.arange(n) / SR - t0
    on = t >= 0
    u = np.maximum(t, 0)
    f = f1 + (f0 - f1) * np.exp(-u * rate)
    return np.sin(2 * np.pi * np.cumsum(f * on) / SR) * (1 - np.exp(-u / rise)) * np.exp(-u / decay) * on * a


def knock(n, t0, f, decay, a=1.0):
    """A short hard knock of body at `f` Hz (its first cycle the strongest): weight a small speaker still hears."""
    t = np.arange(n) / SR - t0
    on = t >= 0
    u = np.maximum(t, 0)
    return np.sin(2 * np.pi * f * u * (1 - 0.12 * np.clip(u / decay, 0, 1))) * np.exp(-u / decay) * (1 - np.exp(-u / 0.0007)) * on * a


def struck(n, t0, rise, modes, a=1.0):
    """Something huge struck: its own modes (Hz, decay s, gain), rising over `rise` s, each with a phase of its own."""
    t = np.arange(n) / SR - t0
    on = t >= 0
    u = np.maximum(t, 0)
    y = np.zeros(n)
    for f, dk, g in modes:
        y += g * np.sin(2 * np.pi * f * u * (1 + 0.004 * rng().standard_normal()) + rng().uniform(0, 6.28)) * np.exp(-u / dk)
    return y * (1 - np.exp(-u / rise)) * on * a


LAND = ((27, 0.8, 1.2), (38, 0.7, 1.1), (54, 0.6, 1.0), (76, 0.45, 0.85), (108, 0.35, 0.65), (152, 0.25, 0.45), (215, 0.18, 0.3))
RUBBLE = ((118, 0.12, 1.0), (171, 0.1, 0.8), (246, 0.08, 0.6), (355, 0.06, 0.4), (512, 0.04, 0.25))


def boom(n, t0, f0, f1, decay, drive=2.6, a=1.0, low=0.6):
    """A blow's boom: a deep tone sinking from `f0` to `f1`, driven so its harmonics carry it (odd and even), with the
    low rumble of the air shoved under it (a burst of noise under 150 Hz). No noise on its front."""
    t = np.arange(n) / SR - t0
    on = t >= 0
    u = np.maximum(t, 0)
    f = f1 + (f0 - f1) * np.exp(-u / (decay * 0.35))
    s = np.sin(2 * np.pi * np.cumsum(f * on) / SR) * (1 - np.exp(-u / 0.002)) * np.exp(-u / decay) * on
    y = np.tanh(drive * s) / np.tanh(drive) + 0.25 * s * s * (1 - np.exp(-u / 0.01))
    y = y - band(y, None, 12, 2)
    lo = noise(n, 22, 150, 3) * (1 - np.exp(-u / 0.006)) * np.exp(-u / (decay * 1.3)) * on
    return (y + lo * low) * a


def shove(n, t0, dur, a=1.0):
    """The pressure shoved out by a blow (a Friedlander wave of `dur` s), what's felt more than heard (12-70 Hz)."""
    t = np.arange(n) / SR - t0
    u = np.maximum(t, 0)
    y = (1 - u / dur) * np.exp(-1.6 * u / dur) * (t >= 0)
    y = band(y, 12, 70, 2)
    return y / (np.abs(y).max() + 1e-12) * a


def drive(x, amount=3.0, db_=-5.0, lo=100.0, hi=900.0):
    """The heat of a blow: its 100-900 Hz driven hard and added under it."""
    m = band(x, lo, hi, 2)
    c = np.percentile(np.abs(m), 99.5) / amount + 1e-12
    h = band(np.tanh(m / c) * c, lo, hi * 2, 2)
    return h / (loud(h) + 1e-12) * loud(x) * 10 ** (db_ / 20)


def roar(n, bands, lvl, boil=4.0, rates=(0.3, 3.0)):
    """A roar with no pitch: bands of noise (Hz, octaves wide, gain) each boiling slowly on its own by about `boil` dB
    (nothing over `rates`[1] Hz: no flicker); `lvl` its level a sample. Unit RMS before `lvl`."""
    y = np.zeros(n)
    for fc, w, g in bands:
        # (each band overlapping its neighbours: a narrow band of noise flickers on its own, a wide one doesn't)
        w = max(w * 1.8, 1.6)
        b = noise(n, fc * 2 ** (-w / 2), fc * 2 ** (w / 2), 1)
        y += b * g * np.exp(boil * slow(n, *rates) / 8.686)
    return unit(y) * lvl


SKY = ((40, 1.0, 1.0), (75, 1.0, 1.0), (140, 1.0, 0.75), (260, 1.0, 0.45), (480, 1.0, 0.22), (900, 1.0, 0.09))      # up in the sky
AIR = ((60, 1.0, 0.8), (120, 1.0, 1.0), (240, 1.0, 0.9), (480, 1.0, 0.65), (950, 1.0, 0.4), (1900, 1.0, 0.18))    # torn air, near
EARTH = ((45, 1.0, 1.0), (90, 1.0, 1.0), (180, 1.0, 0.85), (360, 1.0, 0.55), (720, 1.0, 0.3), (1400, 1.0, 0.12))  # earth thrown
FIRE = ((95, 0.6, 1.0), (160, 0.6, 1.0), (265, 0.6, 0.85), (430, 0.6, 0.6), (700, 0.6, 0.36), (1150, 0.6, 0.16))     # a hot roar


def rolls(n, t0, count, length, lo=28.0, hi=190.0):
    """Deep swells of rumble rolling off the sky or the land after a blow, each from somewhere of its own, each its own
    band, rising over a fraction of a second and dying over one or two. Unit RMS."""
    y = np.zeros(n)
    for k in range(count):
        c = t0 + length * rng().uniform() ** 1.4
        r, f = rng().uniform(0.12, 0.5), rng().uniform(0.7, 2.4)
        a, b = c - 4 * r, c + 5 * f
        m = nsm(b - a)
        if m < 64:
            continue
        tt = np.arange(m) / SR + a - c
        env = np.where(tt < 0, np.exp(-(tt / r) ** 2), np.exp(-tt / f))
        sh = rng().uniform(0.75, 1.3)
        put(y, noise(m, lo * sh, hi * sh, 2) * env * rng().lognormal(0, 0.35) * (1 - 0.5 * k / count), a)
    return unit(y)


def pour(n, lo, hi, dark=600.0):
    """Earth pouring off something: a dark stream of noise boiling slowly, no grit in it."""
    y = noise(n, lo, hi, 2) * np.exp(5.0 * slow(n, 0.6, 6.0) / 8.686)
    return unit(lowpass_track(y, dark + 0 * y))


def note(f0, d, swell, partials=36, top=2400.0, drift=0.0012, boil=0.3):
    """A deep held note on `f0` (Hz, or one a sample), its upper partials opening only near the peaks of `swell` (0-1 a
    sample), each partial drifting a hair and its level boiling slowly on its own."""
    n = nsm(d)
    f0 = np.broadcast_to(np.asarray(f0, float), (n,))
    ph = 2 * np.pi * np.cumsum(f0 * (1 + drift * slow(n, 0.1, 0.8))) / SR
    y = np.zeros(n)
    for k in range(1, partials + 1):
        fk = float(f0.mean()) * k
        if fk > top:
            break
        body = 0.15 + np.exp(-0.5 * (np.log2(fk / 150.0) / 0.6) ** 2) + 0.45 * np.exp(-0.5 * (np.log2(fk / 380.0) / 0.45) ** 2)
        e = swell ** (1.0 + 2.5 * np.clip(np.log2(k) / 5.0, 0, 1))
        bo = 1.0 - boil + boil * (0.5 + 0.5 * slow(n, 0.3, 3.0))
        y += k ** -0.85 * body * np.sin(k * ph + rng().uniform(0, 6.3)) * e * bo
    return y


def leveled(x, t, pts, win=0.3, heard=False):
    """`x` with its own slow rise and fall taken out (its RMS over `win` s; `heard`, as a loudness meter weighs it) and
    the level `pts` put on instead: a climb that only climbs."""
    w = np.hanning(nsm(win))
    y = k_weighted(x) if heard else x
    e = np.sqrt(np.maximum(fftconvolve(y * y, w / w.sum(), mode="same"), 0.0))
    return x / np.maximum(e, e.max() * 1e-3) * curve(t, pts)


# =================================================================================================  the glass
# One glass for the whole laser. A piece of it is a plate: its partials the modes of a thin plate of its own aspect r,
# (m^2 + (n r)^2) / (1 + r^2) times its lowest, each a little off (no piece is perfectly regular), so near-equal modes
# split into pairs that beat; its lowest goes as thickness / size^2, so a piece half as big rings four times higher.
# GLASS_BIG: the lowest mode of the biggest piece (size 1); the sky's glass about two octaves under a window's.
GLASS_BIG = 135.0
GLASS_TOP = 5200.0              # (no mode over this: the brightest of it kept down)
GLASS_Q = (150.0, 300.0)        # (a piece's Q at 500 Hz, more over it and less under it: a small piece rings clear for a
                                # few tens of ms, a big one dies before it can boom, and each knock on its neighbours
                                # stops and starts it again)
MAX_MODES = 14


def plate_ratios(r, top, split=0.012, g=None):
    """A thin plate's mode ratios for aspect `r`, up to `top` times its lowest, each off by about `split`."""
    g = g if g is not None else rng()
    v = sorted((m * m + (k * r) ** 2) / (1 + r * r) for m in range(1, 12) for k in range(1, 12))
    v = np.array([u for u in v if u <= top])
    return v * (1 + split * g.standard_normal(len(v))) if len(v) else v


def contact(f, tc):
    """How much of a mode at `f` a knock lasting `tc` s gives: all of it under 1 / (2 tc), less and less over it (a
    hard knock is bright, a soft one dark)."""
    return 1 / np.sqrt(1 + (2 * np.asarray(f) * tc) ** 4)


def shard(f1, top=GLASS_TOP, q=None, qmax=700.0):
    """One piece of the glass, its lowest mode at `f1`: (its modes' Hz, their decays, how much each sounds where it is
    struck). None if it is too small to have a mode under `top`."""
    if f1 > top:
        return None
    r = rng().uniform(1.0, 2.3)
    ra = plate_ratios(r, top / f1)[:MAX_MODES]
    if len(ra) == 0:
        ra = np.array([1.0])
    f = f1 * ra
    q = rng().uniform(*GLASS_Q) if q is None else q
    qs = np.clip(q * (f / 500.0) ** 0.5 * rng().uniform(0.75, 1.25, len(f)), 30.0, qmax)
    tau = qs / (np.pi * f)
    shape = rng().uniform(0.3, 1.0, len(f)) * ra ** -0.5
    return f, tau, shape


def ring_shard(out, piece, hits):
    """`piece` (a `shard`) rung by `hits` ((s, gain, contact s) each) into `out`: each knock lands somewhere else on it,
    so each gives its modes in its own proportion. Each mode a two-pole resonator."""
    f, tau, shape = piece
    t0 = min(h[0] for h in hits)
    k0 = nsm(t0)
    if k0 >= len(out):
        return
    if k0 < 0:
        return
    span = max(h[0] for h in hits) - t0 + 6.0 * float(tau.max())
    L = min(nsm(span), len(out) - k0)
    if L <= 4:
        return
    tr = np.zeros((len(f), L))
    for t, g, tc in hits:
        i = nsm(t) - k0
        if 0 <= i < L:
            tr[:, i] += g * contact(f, tc) * shape * rng().uniform(0.45, 1.0, len(f))
    y = np.zeros(L)
    for j in range(len(f)):
        w = 2 * np.pi * f[j] / SR
        R = np.exp(-1.0 / (tau[j] * SR))
        y += lfilter([np.sin(w)], [1.0, -2 * R * np.cos(w), R * R], tr[j])
    out[k0:k0 + L] += y


_SNAPS = {}


def snaps(lo=300.0, hi=7500.0, k=48):
    """A bank of ruptures: a few milliseconds of everything at once as glass parts (the crack tip's release), each
    its own. Peak 1."""
    key = (lo, hi)
    if key not in _SNAPS:
        g = np.random.default_rng(int(lo * 7 + hi))
        out = []
        for _ in range(k):
            m = nsm(0.014)
            t = np.arange(m) / SR
            d = g.uniform(0.0005, 0.0024)
            x = band(g.standard_normal(m), lo, hi, 2) * np.exp(-t / d) * (1 - np.exp(-t / 0.00012))
            out.append(x / (np.abs(x).max() + 1e-12))
        _SNAPS[key] = out
    return _SNAPS[key]


def sizes(count, smin, smax=1.0, b=1.5):
    """`count` piece sizes (1 the biggest) drawn from a power law: many small, few big (glass fragments' N ~ size^-b)."""
    u = rng().uniform(0, 1, count)
    return smin * (1 - u * (1 - (smin / smax) ** b)) ** (-1 / b)


def by_rate(count, pts):
    """`count` times drawn so they come as thick as `pts` ((s, relative rate) pairs, linear between) says."""
    xs, ys = zip(*pts)
    t = np.linspace(xs[0], xs[-1], 4000)
    c = np.cumsum(np.interp(t, xs, ys))
    c = c / c[-1]
    return np.sort(np.interp(rng().uniform(0, 1, count), c, t))


def cascade(n, born, size, big=GLASS_BIG, top=GLASS_TOP, amp_pow=1.25, snap=0.25, knocks=(1, 4), gap=(0.05, 0.25),
            shrink=(0.45, 0.7), loss=(0.28, 0.55), tc=(0.0003, 0.0012), birth_tc=0.00025, ground=False, lo_snap=300.0, hi_snap=7500.0,
            qmax=700.0):
    """Pieces of the glass breaking away (`born` s, `size` 0-1 each): each born with a rupture and rung hard as it is
    freed, then knocking into its neighbours (or, `ground`, bouncing on the land) at shrinking intervals, softer each
    time. Many such series overlapping is what the ear hears as breaking. `qmax` caps how clear a piece rings: where
    pieces are heard one by one (a crack here and there), they knock rather than ping."""
    out = np.zeros(n)
    bank = snaps(lo_snap, hi_snap)
    for tb, s in zip(born, size):
        piece = shard(big / s ** 2, top, qmax=qmax)
        if piece is None:
            continue
        a = s ** amp_pow * rng().lognormal(0, 0.35)
        hits = [(tb, a, birth_tc * rng().uniform(0.6, 1.6))]
        k = int(rng().integers(knocks[0], knocks[1] + 1))
        dt = rng().uniform(*gap) * (0.4 + s) * (1.6 if ground else 1.0)
        t, g = tb, a
        for _ in range(k - 1):
            t += dt * (rng().uniform(0.9, 1.1) if ground else rng().uniform(0.55, 1.45))
            g *= rng().uniform(*loss)
            dt *= rng().uniform(*shrink)
            hits.append((t, g, rng().uniform(*tc)))
        ring_shard(out, piece, hits)
        if snap > 0:
            put(out, bank[int(rng().integers(len(bank)))] * a * snap, tb)
    return out


def rupture(n, t0, dur=0.0025, lo=180.0, hi=9000.0, step=0.6):
    """The instant glass gives: a few milliseconds of everything at once and the step of the pressure it lets go (a
    half-cycle in the lows). No body held after it (that would be a snare). Peak about 1."""
    t = np.arange(n) / SR - t0
    on = t >= 0
    u = np.maximum(t, 0)
    x = noise(n, lo, hi, 2) * np.exp(-u / dur) * (1 - np.exp(-u / 0.0001)) * on
    x = x / (np.abs(x).max() + 1e-12)
    p = np.sin(np.pi * np.clip(u / 0.012, 0, 1)) * on * (u < 0.012)
    p = band(p, 25, 400, 2)
    return x + p / (np.abs(p).max() + 1e-12) * step


# ---- the sky's own pane ----------------------------------------------------------------------------------------------
PANE_F, PANE_R = 31.0, 1.37
PANE_TOP = 560.0


def plate(f0, r, top, seed, split=0.015):
    """A whole pane's modes (Hz) and how much each sounds where it is struck: its own, the same every time."""
    g = np.random.default_rng(seed)
    ra = plate_ratios(r, top / f0, split, g)
    return f0 * ra, g.uniform(0.35, 1.0, len(ra)) * ra ** -0.45


PANE = plate(PANE_F, PANE_R, PANE_TOP, 5600)
# (its upper voice: the same glass's modes from the low mids up, what a small speaker hears of it singing or flexing)
PANE_HI = plate(PANE_F * 3.3, 1.21, 1500.0, 5601)


def pane_ring(n, t0, a=1.0, tc=0.01, q=45.0, choke=None, modes=PANE, bend=0.0):
    """The pane struck at `t0` by a blow lasting `tc` s: its own low modes, inharmonic, the high ones dying first (Q
    `q`); with `choke` (s, s) it is cut up as it rings, its modes stopping from the top down over that time (the pane
    is gone, its pieces take over). `bend` lowers its pitch a little as it rings (a pane bent by the blow)."""
    f, shape = modes
    t = np.arange(n) / SR - t0
    on = t >= 0
    u = np.maximum(t, 0)
    y = np.zeros(n)
    for fk, sk in zip(f, shape):
        tau = q * rng().uniform(0.8, 1.2) / (np.pi * fk)
        ph = 2 * np.pi * fk * (u - bend * 0.2 * (1 - np.exp(-u / 0.2))) + rng().uniform(0, 6.28)
        e = np.exp(-u / tau)
        if choke is not None:
            c = choke[0] + (choke[1] - choke[0]) * (f[0] / fk) ** 0.4
            e = e * (1 - ss(c * 0.6, c, u))
        y += sk * contact(fk, tc) * np.sin(ph) * e
    return y * (1 - np.exp(-u / max(tc * 0.25, 0.0004))) * on * a


def pane_song(n, load, q=60.0, bend=0.03, opens=2.5, modes=PANE, seed=None):
    """The pane singing under load (bowed glass): each of its modes driven by the strain as narrow noise round it
    (`q`), so each wavers on its own; the higher ones only near the load's peaks; the whole a little higher as the load
    stiffens it. `load` 0-1 a sample."""
    g = np.random.default_rng(seed) if seed is not None else rng()
    f, shape = modes
    rate = 400
    m = int(n * rate / SR) + 4
    y = np.zeros(n)
    for fk, sk in zip(f, shape):
        bw = max(fk / q, 0.15)
        z = band(g.standard_normal(m), None, bw * SR / rate, 2) + 1j * band(g.standard_normal(m), None, bw * SR / rate, 2)
        z = z / (np.sqrt(np.mean(np.abs(z) ** 2)) + 1e-12)
        z = np.interp(np.arange(n) * rate / SR, np.arange(m), z.real) + 1j * np.interp(np.arange(n) * rate / SR, np.arange(m), z.imag)
        ph = 2 * np.pi * np.cumsum(fk * (1 + bend * load)) / SR + g.uniform(0, 6.28)
        e = load ** (1.0 + opens * np.log2(fk / f[0]) / 4.0)
        y += sk * np.real(z * np.exp(1j * ph)) * e
    return y


def crack_at(out, t0, size=0.5, run=0.0, big=GLASS_BIG, top=GLASS_TOP, pieces=None, body=1.0, modes=PANE, snap_db=-4.0, deep=True, qmax=700.0):
    """One crack in the glass, into `out` at `t0`: its rupture, with `run` s of it running on (a stream of small pieces
    born as it goes), the pieces it frees (`pieces`, or more the bigger it is) and the pane knocked under it (`modes`,
    choked as it breaks), a sinking heave of body. All of it scales with `size` (0-1.5)."""
    n = len(out)
    a = size
    r = rupture(n, t0, 0.0012 + 0.0016 * size, 220.0, 7000.0, step=0.8)
    x = r * 10 ** (snap_db / 20)
    if run > 0:
        k = int(10 + 260 * run * size)
        born = t0 + run * rng().uniform(0, 1, k) ** 1.6
        x = x + cascade(n, born, sizes(k, 0.18, 0.5, 1.6), big, top, snap=0.5, knocks=(1, 2), qmax=qmax)
    k = pieces if pieces is not None else int(4 + 40 * size)
    born = t0 + 0.004 + 0.35 * size * rng().uniform(0, 1, k) ** 2.0
    x = x + cascade(n, born, sizes(k, 0.2, min(1.0, 0.45 + 0.4 * size), 1.4), big, top, knocks=(1, 3), qmax=qmax)
    ref = loud(x) + 1e-12
    if deep and body > 0:
        pb = pane_ring(n, t0, 1.0, 0.004 + 0.004 * (1 - min(size, 1)), 40.0, (0.08 + 0.12 * size, 0.25 + 0.3 * size), modes)
        x = x + pb / (loud(pb) + 1e-12) * ref * body
        x = x + heave(n, t0, 70.0, 28.0, 7.0, 0.003, 0.18 + 0.3 * size) * ref * body * 1.4
    out += x * a


def distance(x, t, after=0.5, keep=0.25, length=6.0, t60=(4.5, 3.2, 1.4), seed=0, dark=3200.0, lo=1200.0):
    """The bright part of `x` (over `lo` Hz) let down to `keep` past `after` s and given back by the sky instead, long
    and darkened (the glitter of it far off, never a tinkle in your ear). Returns the new whole."""
    hi = band(x, lo, None, 2)
    w = verb(hi, length, t60, seed, build=0.08, lo=None)
    w = band(w, None, dark, 2)
    dry = x - hi + hi * (keep + (1 - keep) * (1 - ss(after, after + 0.6, t)))
    return dry + w


def scrape(n, rate, lo_f=170.0, hi_f=420.0, count=3, q=70.0):
    """Shards dragged over the glass's broken edge: a rough edge (`rate` grabs a second, one a sample: thick enough that
    none is heard on its own) knocking `count` pieces of glass, each ringing in its own modes. Unit RMS."""
    rate = np.broadcast_to(np.asarray(rate, float), (n,))
    p = np.clip(rate / SR, 0, 0.5)
    hits = rng().uniform(0, 1, n) < p
    tr = hits * rng().lognormal(0, 0.6, n) * np.sqrt(np.clip(rate / (rate.max() + 1e-9), 0, 1))
    y = np.zeros(n)
    for _ in range(count):
        piece = shard(rng().uniform(lo_f, hi_f), 3500.0, q)
        f, tau, shape = piece
        for j in range(len(f)):
            w = 2 * np.pi * f[j] / SR
            R = np.exp(-1.0 / (tau[j] * SR))
            y += lfilter([np.sin(w) * shape[j] * contact(f[j], 0.0007)], [1.0, -2 * R * np.cos(w), R * R], tr * rng().uniform(0.4, 1.0, n))
    y = y + band(tr, 300, 3000, 2) * 0.15
    return unit(y)


def ticks(n, times, size0, size1, big=GLASS_BIG * 0.8, top=2400.0, run=0.0):
    """Small cracks in the pane under load, at `times`, growing from `size0` to `size1`: each its rupture, a few pieces
    freed and the pane knocked (the strain heard before the break, quicker and bigger as it nears)."""
    out = np.zeros(n)
    for k, tc in enumerate(times):
        u = k / max(len(times) - 1, 1)
        s = (size0 + (size1 - size0) * u) * rng().uniform(0.8, 1.15)
        crack_at(out, tc, s, run=run * rng().uniform(0.5, 1.0), big=big, top=top, pieces=int(3 + 10 * s), body=0.45, snap_db=-8.0, qmax=200.0)
    return out


def through_air(x, d, seed, rolls_db=0.45):
    """`x` through a long stretch of air: the top let down, the front softened, more of the low rolls, a long dark
    reverb."""
    n = nsm(d)
    y = np.zeros(n)
    y[:min(len(x), n)] = x[:n]
    tt = np.arange(n) / SR - 0.02
    soft = np.clip(tt / 0.08, 0, 1) ** 2
    lo = band(y, None, 300, 2)
    mid = band(y, 300, 1500, 2) * np.sqrt(soft)
    hi = band(y, 1500, None, 2) * soft
    y = lo * 0.8 + mid * 1.1 + band(hi, None, 3500, 2) * 0.25
    y = y + rolls(n, 0.8, 16, d - 1.0) * loud(y) * rolls_db
    y = space(y, 0.6, length=7.0, t60=(6.0, 3.6, 1.2), seed=seed, lo=100.0)
    return weight(y, -6.0)


# =================================================================================================  the file
def out_path(name):
    return f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(float)


def decoded(name):
    """One of this laser's files as the game plays it: decoded, mono. None if it is not built yet."""
    p = out_path(name) + ".ogg"
    return decode(p) if Path(p).exists() else None


def true_peak(x):
    return float(np.abs(resample_poly(x, 4, 1)).max())


def write(name, x, db=None, peak_db=None, fade_in=0.0, fade_out=0.05, lowcut=14.0, crest=None, top=15000.0):
    """Write mono `x` as skybreak/`name`.ogg: DC out, band-limited to 15 kHz, a causal low cut at `lowcut` Hz, faded at
    the ends (`top`: the band's top, 15 kHz but for the glass); its loudest 400 ms at `db` (or its peak at `peak_db`); with `crest` the peaks over `crest` times that are
    rounded off; then any peak over the ceiling limited until the decoded true peak is under TP_MAX."""
    x = np.asarray(x, float)
    x = x - x.mean()
    x = band(x, None, top, 4)
    x = causal_hp(x, lowcut, 2)
    n = len(x)
    if fade_in > 0:
        k = nsm(fade_in)
        x[:k] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, k))
    k = nsm(fade_out)
    x[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    db = db + TRIM.get(name, 0.0) if db is not None else None
    peak_db = peak_db + TRIM.get(name, 0.0) if peak_db is not None else None
    g = 10 ** (db / 20) / (loud(x) + 1e-12) if db is not None else 10 ** (peak_db / 20) / (np.abs(x).max() + 1e-12)
    if crest is not None and db is not None:
        c = crest * 10 ** (db / 20)
        for _ in range(8):
            got = loud(soft_clip(x * g, c, 0.7))
            err = 10 ** (db / 20) / (got + 1e-12)
            g *= err
            if abs(20 * np.log10(err)) < 0.05:
                break
        x = soft_clip(x * g, c, 0.7)
    else:
        x = x * g
    c = TP_MAX * 0.97
    lim = 0.0
    p = out_path(name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    dec, tp = None, 0.0
    for _ in range(8):
        if np.abs(x).max() > c:
            lim = 20 * np.log10(np.abs(x).max() / c)
            y = limit(x, c)
        else:
            y = x.copy()
        write_wav(p + ".wav", y)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", p + ".wav", "-c:a", "libvorbis", "-q:a", "7", p + ".ogg"], check=True)
        os.remove(p + ".wav")
        dec = decode(p + ".ogg")
        tp = true_peak(dec)
        if tp <= TP_MAX:
            break
        c *= TP_MAX / tp * 0.995
    size = Path(p + ".ogg").stat().st_size / 1024
    warn = f"  (peaks limited by {lim:.1f} dB: lower its level)" if lim > 2.0 else ""
    print(f"wrote {TH}/{name:10s} {n / SR:5.2f}s  loudest {20 * np.log10(loud(dec) + 1e-12):6.1f} dB  peak {20 * np.log10(np.abs(dec).max()):6.2f} dBFS  "
          f"true peak {20 * np.log10(tp):6.2f} dBTP  {size:4.0f} KB{warn}", flush=True)
    return dec


# =========================================================================================================  the lift
def tear():
    """The land wrenched free round the target, the hook: the ground's own modes in a heavy lurch with no noise on its
    front, its boom and a knock of body, the land's mass moving, six deep wrenches you can count as the last roots and
    rock let go and a lesser lurch as it comes clear, the ground parting under it (a long dark breath), the air sucked
    in under it as it lifts, the earth pouring off its underside, dark and soft and thinning as it goes."""
    d = 4.8
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = TEAR_AT
    u = np.maximum(t - t0, 0)
    on = t >= t0
    x = struck(n, t0, 0.14, LAND, 1.2)
    x = x + boom(n, t0 + 0.012, 74.0, 44.0, 0.5, 2.6, 0.5)
    x = x + struck(n, t0 + 0.004, 0.006, RUBBLE, 0.6)
    x = x + knock(n, t0, 104.0, 0.08, 0.8) + knock(n, t0 + 0.003, 215.0, 0.04, 0.4)
    ref = loud(x)
    mass = noise(n, 40, 300, 2) * (1 - np.exp(-u / 0.05)) * np.exp(-u / 0.45) * on
    x = x + mass * ref * 10 ** (-5 / 20)
    tk = t0 + 0.12
    for k in range(6):
        g = (1.0 - 0.12 * k) * rng().uniform(0.75, 1.1)
        sc = rng().uniform(0.85, 1.2)
        w = struck(n, tk, 0.02, tuple((f * sc, dk * 0.5, a) for f, dk, a in LAND[1:6]), g)
        uk = np.maximum(t - tk, 0)
        w = w + noise(n, 90, 620, 2) * (1 - np.exp(-uk / 0.006)) * np.exp(-uk / 0.07) * (t >= tk) * g * 0.6
        x = x + w * ref * 10 ** (-7 / 20)
        tk += rng().uniform(0.12, 0.26)
    x = x + struck(n, t0 + 0.62, 0.08, ((33, 0.6, 1.1), (47, 0.5, 1.0), (66, 0.4, 0.8), (94, 0.3, 0.6), (133, 0.2, 0.4)), 0.45)
    breath = noise(n, 45, 420, 2) * ss(0.05, 0.5, u) * (1 - ss(1.2, 2.6, u)) * on * np.exp(3.0 * slow(n, 0.3, 2.0) / 8.686)
    x = x + breath * ref * 10 ** (-9 / 20)
    fc = np.maximum(150.0 * 0.35 ** np.clip(u / 1.6, 0, 1), 40.0)
    suck = glide(n, fc, 0.7) * ss(0.15, 0.6, u) * (1 - ss(1.2, 2.4, u)) * on
    x = x + suck * ref * 10 ** (-9 / 20)
    x = x + pour(n, 110, 1100, 700.0) * curve(t, [(0.0, -70), (0.25, -60), (0.6, -16), (1.4, -14), (2.6, -22), (4.0, -38), (4.8, -60)]) * ref
    x = space(x, 0.35, length=3.0, t60=(2.6, 1.8, 0.7), seed=101)
    x = weight(x, -9.0)
    write("tear", x, db=-12.0, fade_out=0.5)


def tear_far():
    """`tear` from hundreds of blocks: through the air, the top gone, the front softened, the land giving it back."""
    x = decoded("tear")
    if x is None:
        raise SystemExit("tear is not built yet: build it before tear_far")
    write("tear_far", through_air(x, 6.5, 120, 0.35), db=-14.0, fade_out=1.0)


def rise():
    """The island going up, slow at first and then faster (to TOP): a deep tone climbing as it gathers speed (two notes
    a fifth apart, their upper partials opening), the dark roar of the air it pushes up through, a rush band sweeping up
    as it speeds, the earth streaming off it at first, the weight of land going up (a sub). Higher and higher: more and
    more of it is the sky giving it back. Handed to `sink` as it goes in."""
    d = TOP + 0.75
    n = nsm(d)
    t = np.arange(n) / SR
    u = np.clip(t / TOP, 0, 1)
    speed = u ** 1.3
    gone = ss(TOP - 0.1, TOP + 0.6, t)
    sw = np.clip(0.2 + 0.8 * speed ** 1.2, 0, 1) * (1 - gone)
    f = 34.0 * 2 ** (3.0 / 12 * speed ** 1.5)
    x = unit(note(f, d, sw)) + unit(note(f * 1.5, d, sw ** 1.4, drift=0.002)) * 0.35
    x = x + roar(n, SKY, curve(t, [(0.0, -24), (1.5, -17), (3.0, -9), (TOP, -2), (TOP + 0.75, -40)])) * 0.9
    fc = 220.0 * (900.0 / 220.0) ** (speed ** 1.6)
    x = x + glide(n, fc, 0.8) * curve(t, [(0.0, -40), (1.5, -30), (3.2, -16), (TOP, -10), (TOP + 0.75, -50)])
    x = x + pour(n, 120, 900, 700.0) * curve(t, [(0.0, -50), (0.4, -14), (1.2, -16), (2.2, -26), (3.2, -44), (d, -70)])
    x = x + noise(n, 22, 65, 3) * curve(t, [(0.0, -30), (1.0, -20), (3.0, -10), (TOP, -4), (TOP + 0.75, -40)]) * 0.8
    w = verb(x, 4.5, (4.0, 2.6, 1.0), 111)
    k = ss(0.5, TOP, t)
    x = x * (1 - 0.55 * k) + w * (0.25 + 0.6 * k)
    x = leveled(x, t, [(0.0, -8), (0.4, -7.5), (1.0, -6.5), (2.0, -5), (3.0, -3), (TOP, 0), (TOP + 0.25, 0), (d, -30)])
    x = weight(x, -9.0)
    write("rise", x, db=-14.5, fade_in=0.3, fade_out=0.4)


# =========================================================================================================  the pane
def sink():
    """It meets the sky (SINK_AT in, TOP) and sinks into it (by IN): a soft heavy blow on the pane, its own low modes
    knocked by a broad weight (no rupture: nothing breaks yet), a sub heave; the pane singing as it bends round it,
    sinking a little in pitch; the gulp as the sky takes it in (a dark band sinking); the star crack snapping out where
    it went in (STAR); a soft deep shut as the pane closes over it. Up in the sky."""
    d = SINK_AT + 2.6
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = SINK_AT
    u = np.maximum(t - t0, 0)
    on = t >= t0
    tin = IN - TOP
    x = pane_ring(n, t0, 1.0, 0.03, 70.0, bend=0.04)
    x = x + heave(n, t0, 46.0, 30.0, 3.0, 0.04, 0.6, 1.2) * loud(x) * 2.5
    ref = loud(x)
    load = np.clip(ss(0.0, 0.25, u) * (1 - ss(tin - 0.2, tin + 0.5, u)), 0, 1) * on
    song = pane_song(n, load * 0.9, 50.0, bend=-0.02, seed=1211)
    x = x + song / (loud(song) + 1e-12) * ref * 10 ** (-5 / 20)
    hs = pane_ring(n, t0 + 0.003, 1.0, 0.012, 40.0, modes=PANE_HI, bend=0.03) + pane_song(n, load, 100.0, bend=-0.02, opens=1.0, modes=PANE_HI, seed=1212) * 0.03
    x = x + hs / (loud(hs) + 1e-12) * ref * 10 ** (-3 / 20)
    gfc = np.maximum(140.0 * 0.32 ** np.clip(u / tin, 0, 1), 38.0)
    c = ss(0.0, 0.12, u) * (1 - ss(tin - 0.3, tin + 0.2, u)) * on
    x = x + glide(n, gfc, 0.45) * c * ref * 10 ** (-6 / 20)
    st = np.zeros(n)
    crack_at(st, t0 + (STAR - TOP), 0.45, run=0.04, big=GLASS_BIG * 0.9, top=3200.0, pieces=8, body=0.6, snap_db=-6.0, qmax=240.0)
    x = x + st / (loud(st) + 1e-12) * ref * 10 ** (-4 / 20)
    x = x + pane_ring(n, t0 + tin, 0.5, 0.05, 50.0) * 1.0 + heave(n, t0 + tin, 50.0, 30.0, 6.0, 0.03, 0.5, 1.0) * ref * 1.2
    x = space(x, 0.6, length=5.0, t60=(4.5, 3.0, 1.0), seed=121)
    x = weight(x, -9.0)
    write("sink", x, db=-12.5, fade_in=0.05, fade_out=0.6)


RINGS = ((RIPPLE_AT, 1.0), (RIPPLE_AT + 0.5, 0.62), (RIPPLE_AT + 0.95, 0.36))    # (the ripple's rings: when, how hard)


def ripple():
    """Two or three tight, stiff rings of the sky (a pane flexing, not water), dead by 7.0: each the pane's own modes
    knocked by a soft broad push, a stiff inharmonic body in the low mids, quick, nothing left ringing, a sub heave
    under it; where the island went in, two small cracks far apart (the star cracks glinting). Up in the sky."""
    d = 2.4
    n = nsm(d)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k, (tr, a) in enumerate(RINGS):
        p = pane_ring(n, tr, 1.0, 0.012 + 0.006 * k, 34.0, modes=PANE, bend=0.02)
        x = x + p / (loud(p) + 1e-12) * a
        q = pane_ring(n, tr + 0.002, 1.0, 0.004 + 0.002 * k, 26.0, modes=PANE_HI, bend=0.01)
        x = x + q / (loud(q) + 1e-12) * a * 0.75
        x = x + heave(n, tr, 50.0 - 4 * k, 30.0, 7.0, 0.025, 0.22, 1.1 * a)
    ref = loud(x)
    st = np.zeros(n)
    for tc, s in ((0.36, 0.3), (1.42, 0.24)):
        crack_at(st, tc, s, big=GLASS_BIG * 0.9, top=2800.0, pieces=6, body=0.5, snap_db=-8.0, qmax=200.0)
    x = x + st / (loud(st) + 1e-12) * ref * 10 ** (-9 / 20)
    x = x * curve(t, [(0.0, 0), (1.4, 0), (1.65, -6), (2.1, -30), (2.4, -60)])
    x = space(x, 0.55, length=3.5, t60=(3.0, 2.0, 0.8), seed=131)
    x = weight(x, -9.0)
    write("ripple", x, db=-15.5, fade_out=0.3)


def pressure():
    """The sky bowing down under the hand (from IN, hardest from BOW, its top on the crack and never dipping on the way):
    the pane singing under the load, its modes opening and climbing as the strain stiffens it; a sub climbing under it;
    two slow heaves of the hand's weight; small cracks ticking in it, quicker and bigger as it nears the break; the fist
    drawn back (CURL), the air pulled in after it; and in the last half second everything rushing up into the punch.
    Let go fast under the crack's front."""
    d = PRESS_TOP + 0.55
    n = nsm(d)
    t = np.arange(n) / SR
    top = PRESS_TOP
    bow = BOW - IN
    curl = CURL - IN
    load = curve(t, [(0.0, -6), (0.8, -4.5), (bow, -2.5), (bow + 0.8, -1.8), (bow + 1.4, -1.0), (top - 0.15, -0.3), (top, 0), (top + 0.04, -1),
                     (top + 0.2, -14), (d, -50)])
    sw = np.clip(load, 0, 1)
    song = pane_song(n, sw, 70.0, bend=0.05, opens=1.6, seed=1411)
    hi = pane_song(n, sw, 120.0, bend=0.05, opens=1.2, modes=PANE_HI, seed=1412)
    x = unit(song) + unit(hi) * 0.9
    f = 22.0 + 16.0 * ss(1.2, top, t)
    x = x + np.sin(2 * np.pi * np.cumsum(f) / SR) * sw * 0.7
    x = x + roar(n, SKY, sw * 0.35, boil=3.0)
    # (it only climbs, as it is heard: the body levelled onto the load)
    climb = [(0.0, -4.5), (0.8, -4), (bow, -3), (bow + 0.8, -2.4), (curl, -1.6), (top - 0.15, -0.3), (top, 0), (top + 0.04, -1), (top + 0.2, -14), (d, -50)]
    x = leveled(x, t, climb, 0.35, heard=True)
    for tp, a in ((bow + 0.55, 0.8), (bow + 1.35, 1.0)):
        x = x + heave(n, tp, 34.0, 26.0, 2.0, 0.22, 0.45, a * 1.4)
        h = pane_ring(n, tp, 1.0, 0.08, 40.0)
        x = x + h / (loud(h) + 1e-12) * 0.3 * a
    # (the cracks ticking: a few at first, then quicker and bigger, a run of them into the punch)
    times = [0.5, 1.15, bow - 0.1, bow + 0.45, bow + 0.8, bow + 1.05, bow + 1.25, curl - 0.2, curl - 0.06, curl + 0.1, curl + 0.2, curl + 0.28, curl + 0.34,
             top - 0.16, top - 0.11, top - 0.07, top - 0.04]
    tk = ticks(n, times, 0.18, 0.55, run=0.03)
    x = x + tk / (loud(tk) + 1e-12) * curve(t, [(0.0, -10), (bow, -7), (top - 0.6, -5), (top, -6)]) * 0.9
    # (the fist drawn back: the air pulled in after it, rising into the punch)
    pull = glide(n, 70.0 * 6.0 ** ss(curl, top, t), 0.9) * ss(curl - 0.1, top - 0.02, t) ** 1.5 * (1 - ss(top, top + 0.08, t))
    x = x + pull * 0.6
    # (and the whole, as it is heard, never dipping: from 3.5 dB under its top to it)
    x = leveled(x, t, [(0.0, -2.8), (bow, -2.2), (curl, -1.2), (top - 0.1, 0), (top, 0), (d, 0)], 0.5, heard=True)
    x = tame_lows(x, 120.0, 97.0)
    x = x * np.where(t > top, load, 1.0)
    x = space(x, 0.45, length=4.0, t60=(3.6, 2.4, 0.9), seed=141)
    x = weight(x, -9.0)
    x = soft_clip(x, np.percentile(np.abs(x), 99.95), 0.6)
    write("pressure", x, db=-11.5, fade_in=0.25, fade_out=0.15)


# =========================================================================================================  the crack
GLASS_OVER = 5.0               # (the crack's glass this many dB over its blow)


def crack_main():
    """The hand punching through the sky (CRACK_AT in): one hard rupture, the glass giving all at once, with the fist's
    deep blow and the pressure it shoves; the crack running out over the whole sky, a stream of ruptures, each a piece
    born (the radials in 0.07 s, the rings joining them by 0.25 s, a little deeper); the pane's own modes booming as the
    fist goes in and choked as the cracks cut it up; then thousands of pieces breaking away, big ones deep and few, small
    ones bright and many and quiet, each knocking into its neighbours as it goes; past the first moment its brightness
    let down and given back by the sky, darkened; the sky rolling it round."""
    d = 7.5
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = CRACK_AT
    u = np.maximum(t - t0, 0)
    # (the blow: the fist's boom, a knock of body, the pane's modes struck hard and cut up, the pressure, the sky giving
    # under it)
    blow = boom(n, t0, 112.0, 40.0, 0.32, 3.0, 1.0, 0.8)
    blow = blow + knock(n, t0, 128.0, 0.07, 0.9) + knock(n, t0 + 0.003, 255.0, 0.035, 0.45)
    blow = blow + shove(n, t0, 0.35, 0.8)
    ref = loud(blow)
    blow = blow + drive(blow, 3.0, -6.0)
    pb = pane_ring(n, t0, 1.0, 0.003, 55.0, choke=(0.12, 0.42))
    blow = blow + pb / (loud(pb) + 1e-12) * ref * 10 ** (-3 / 20)
    blow = blow + heave(n, t0 + 0.05, 52.0, 24.0, 3.0, 0.03, 0.7) * ref * 1.0
    # (the glass: the rupture; the crack running, the radials, then the rings; the pieces breaking away, big and small,
    # most in the first half second, the last of them by two and a half; a few big slabs splitting off, each its own crack)
    g = rupture(n, t0, 0.004, 200.0, 9000.0, 0.6) + rupture(n, t0 + 0.0045, 0.003, 400.0, 8000.0, 0.2) * 0.6
    born = np.concatenate([by_rate(1500, [(0.0, 3.0), (0.01, 3.0), (0.045, 2.0), (0.07, 0.6), (0.08, 0.0)]),
                           by_rate(900, [(0.06, 0.0), (0.08, 1.0), (0.16, 1.4), (0.25, 0.5), (0.3, 0.0)])]) + t0
    sz = np.concatenate([sizes(1500, 0.15, 0.4, 1.6), sizes(900, 0.18, 0.55, 1.5)])
    run = cascade(n, born, sz, top=7000.0, amp_pow=0.7, snap=0.8, knocks=(1, 2), birth_tc=0.00015)
    k = 1700
    born = t0 + 0.04 + by_rate(k, [(0.0, 0.5), (0.04, 2.5), (0.2, 2.0), (0.45, 0.6), (0.8, 0.15), (1.6, 0.03), (2.5, 0.0)])
    pcs = cascade(n, born, sizes(k, 0.18, 1.0, 1.6), amp_pow=1.0, knocks=(1, 4), gap=(0.04, 0.2))
    sl = np.zeros(n)
    for tc in t0 + 0.08 + np.sort(rng().uniform(0, 0.9, 5)):
        crack_at(sl, tc, rng().uniform(0.5, 0.9), run=0.05, pieces=18, body=0.0, deep=False)
    gr = loud(run)
    g = g * gr * 3.0 + run + pcs / (loud(pcs) + 1e-12) * gr * 10 ** (-1 / 20) + sl / (loud(sl) + 1e-12) * gr * 10 ** (-7 / 20)
    x = blow + g / (loud(g) + 1e-12) * ref * 10 ** (GLASS_OVER / 20)
    # (what follows the crack's front let down a little after it, as a real break's crash is under its crack: the crack
    # stands out of it)
    x = x * curve(t, [(0.0, 0), (t0 + 0.035, 0), (t0 + 0.09, -4), (t0 + 0.3, -4.5), (d, -4.5)])
    x = distance(x, u, after=0.45, keep=0.35, length=6.5, t60=(5.0, 3.6, 1.6), seed=151)
    x = x + verb(x, 6.0, (5.0, 3.2, 1.1), 152) * 0.4 * ss(0.03, 0.4, u)
    x = x + rolls(n, t0 + 0.6, 12, 6.0) * ref * 0.15
    x = weight(x, -9.0)
    x = tame_lows(x, 200.0, 97.0)
    x = soft_clip(x, np.percentile(np.abs(x), 99.9) * 0.9, 0.6)
    write("crack", x, db=-9.0, fade_out=0.8)


def withdraw():
    """The arm going back up through the hole (from 0.3 s after the crack): the air rising away, its top going as it
    goes; the shards it drags grinding on the hole's broken edge (pieces of the glass dragged over glass, thick enough
    that no knock is heard on its own); one breaking off it (LET_GO), a crack far up; the pane groaning as they go; the
    air sucked in behind it, falling; the mass of it leaving, a deep heave."""
    d = 4.4
    n = nsm(d)
    t = np.arange(n) / SR
    r = roar(n, SKY + ((1500, 1.0, 0.03),), curve(t, [(0.0, -34), (0.35, -10), (1.0, 0), (1.9, -3), (3.0, -12), (4.4, -40)]))
    r = lowpass_track(r, 1600.0 * 0.25 ** ss(0.6, 3.6, t))
    rate = 260.0 * curve(t, [(0.0, -30), (0.25, -4), (0.6, 0), (1.5, -2), (2.4, -10), (3.0, -30), (d, -60)])
    gr = scrape(n, rate, 150.0, 380.0, 3, 60.0) * curve(t, [(0.0, -50), (0.3, -20), (0.6, -6), (1.6, -8), (2.4, -20), (3.0, -50), (d, -80)])
    x = r + gr * 0.5
    off = np.zeros(n)
    crack_at(off, LET_GO - CRACK_T - WITHDRAW_AFTER, 0.6, run=0.04, pieces=20, body=0.5, top=3600.0, qmax=300.0)
    x = x + off / (loud(off) + 1e-12) * loud(r) * 10 ** (-6 / 20)
    song = pane_song(n, np.clip(curve(t, [(0.0, -40), (0.3, -8), (1.0, -4), (2.0, -10), (3.2, -40), (d, -60)]), 0, 1), 40.0, bend=-0.02, seed=1611)
    x = x + song / (loud(song) + 1e-12) * loud(r) * 10 ** (-7 / 20)
    sk = glide(n, 300.0 * (80.0 / 300.0) ** ss(1.2, 3.6, t), 0.6) * ss(1.0, 1.6, t) * (1 - ss(2.8, 3.9, t))
    x = x + sk * 0.45
    x = x + heave(n, 0.4, 40.0, 26.0, 2.0, 0.15, 0.9, 1.0)
    x = space(x, 0.6, length=5.0, t60=(4.5, 3.0, 1.0), seed=161)
    x = weight(x, -9.0)
    write("withdraw", x, db=-15.0, fade_in=0.15, fade_out=0.8)


def collapse():
    """The middle blown down round the fist (COLLAPSE_AT in): its pieces breaking on each other as they go, dense and
    deep, a few big ones splitting with a crack of their own, a boom under it; the roar of all of it falling away; then,
    far up and faint, the glitter as each piece bursts (GLITTER after it fell): a fine dark shimmer given back by the
    sky, never a tinkle in your ear; the sky rolling it round."""
    d = 9.0
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = COLLAPSE_AT
    u = np.maximum(t - t0, 0)
    x = np.zeros(n)
    k = 1300
    born = t0 + by_rate(k, [(0.0, 2.0), (0.15, 1.6), (0.4, 0.8), (0.75, 0.2), (1.2, 0.0)])
    pcs = cascade(n, born, sizes(k, 0.2, 1.0, 1.4), big=GLASS_BIG * 0.85, knocks=(2, 5), gap=(0.05, 0.22))
    x = x + pcs
    ref = loud(pcs)
    sl = np.zeros(n)
    for tc in t0 + np.sort(rng().uniform(0, 0.5, 4)):
        crack_at(sl, tc, rng().uniform(0.5, 0.9), run=0.04, pieces=16, body=0.6)
    x = x + sl / (loud(sl) + 1e-12) * ref * 10 ** (-3 / 20)
    x = x + heave(n, t0, 56.0, 23.0, 5.0, 0.004, 1.4) * ref * 2.0
    # (the middle's fragments bursting, each GLITTER after it fell: up there, a cloud of the smallest pieces)
    gl = np.zeros(n)
    for f in range(32):
        tf = t0 + 0.3 * (f / 31) ** 1.2 + rng().uniform(0, 0.08) + rng().uniform(*GLITTER)
        m = 60
        b = tf + 0.18 * rng().uniform(0, 1, m) ** 1.5
        gl = gl + cascade(n, b, sizes(m, 0.18, 0.36, 1.6), top=3600.0, amp_pow=1.0, snap=0.15, knocks=(1, 2), gap=(0.03, 0.08), qmax=320.0) * rng().uniform(0.5, 1.0)
    gl = band(gl, None, 3600.0, 2)
    x = distance(x, u, after=0.3, keep=0.3, length=6.0, t60=(5.0, 3.6, 1.5), seed=171)
    x = x + verb(gl, 6.0, (5.0, 4.0, 2.0), 172, build=0.1, lo=None) * ref * 10 ** (-17 / 20) / (loud(gl) + 1e-12) * 1.5
    x = x + gl / (loud(gl) + 1e-12) * ref * 10 ** (-30 / 20)
    x = x + roar(n, SKY, curve(t, [(0.0, -40), (0.6, -10), (1.8, -7), (3.5, -11), (6.0, -18), (9.0, -40)]), boil=4.0) * ref * 0.55
    x = space(x, 0.5, length=5.5, t60=(4.8, 3.2, 1.2), seed=173)
    x = x + rolls(n, 0.5, 12, 6.0) * loud(x) * 0.3
    x = weight(x, -9.0)
    write("collapse", x, db=-10.5, fade_out=0.8)


def strain():
    """The sky under load from just after the crack to the last impact (24 s): the pane singing low under the strain,
    swelling and easing as the load comes and goes; a dark rumble of the sky; deep cracks now and then as the panes
    shift, each its rupture, its pieces and the pane knocked under it."""
    d = 24.0
    n = nsm(d)
    t = np.arange(n) / SR
    load = curve(t, [(0.0, -30), (1.2, -10), (4.0, -4), (6.0, 0), (9.0, -1), (13.0, -2), (17.0, -6), (21.0, -11), (24.0, -40)])
    sw = np.clip(load, 0, 1) * (0.7 + 0.3 * (0.5 + 0.5 * slow(n, 0.08, 0.4)))
    song = pane_song(n, sw, 70.0, bend=0.02, opens=2.0, seed=1811)
    x = unit(song)
    x = x + roar(n, SKY, curve(t, [(0.0, -30), (1.5, -12), (6.0, -4), (16.0, -5), (22.0, -14), (24.0, -40)]), boil=4.0) * 0.8
    cr = np.zeros(n)
    tc = 1.2
    while tc < 21.5:
        k = float(np.interp(tc, t[::441], load[::441]))
        crack_at(cr, tc, (rng().pareto(2.4) * 0.2 + 0.3) * k, run=rng().uniform(0, 0.06), big=GLASS_BIG * 0.8, top=3000.0, body=0.9, snap_db=-8.0, qmax=220.0)
        tc += rng().gamma(1.4, 0.9)
    cr = verb(cr, 4.0, (4.0, 2.6, 0.9), 182, lo=None) * 0.8 + cr * 0.5
    x = x + cr / (loud(cr) + 1e-12) * 0.9
    x = x * load
    x = weight(x, -10.0)
    write("strain", x, db=-16.0, fade_in=0.4, fade_out=1.0)


# =========================================================================================================  the panes
def release_take(v):
    """A pane breaking free up there (RELEASE_FREE in): it sags, its own modes singing under its weight, cracks running
    round its edge, slowly then faster; then it breaks free: a crack, its pieces shed off its broken edge, its body
    knocked and choked, a heave; the second take cracks twice, its far edge last; and the air it lets go of as it drops
    away. Up in the sky."""
    d = 4.5
    n = nsm(d)
    t = np.arange(n) / SR
    modes = plate(44.0 if v == 1 else 52.0, 1.6 if v == 1 else 1.25, 620.0, 5700 + v)
    load = np.clip(curve(t, [(0.0, -24), (0.8, -10), (RELEASE_FREE, 0), (RELEASE_FREE + 0.05, -20), (d, -60)]), 0, 1)
    song = pane_song(n, load, 45.0, bend=0.03, modes=modes, seed=1900 + v)
    x = unit(song) * 0.5
    cr = np.zeros(n)
    for k in range(7):
        tc = 0.25 + (RELEASE_FREE - 0.3) * (k / 6.0) ** 0.7 + rng().uniform(-0.05, 0.05)
        crack_at(cr, tc, 0.25 + 0.15 * k / 6.0, run=0.02, pieces=6, body=0.6, modes=modes, snap_db=-8.0, top=3000.0, qmax=220.0)
    crack_at(cr, RELEASE_FREE, 1.1, run=0.1, pieces=70, body=1.2, modes=modes)
    if v == 2:
        crack_at(cr, RELEASE_FREE + 0.17, 0.8, run=0.06, pieces=40, body=1.0, modes=modes)
    x = x / (loud(x) + 1e-12) * loud(cr) * 10 ** (-8 / 20) + cr
    x = x + heave(n, RELEASE_FREE, 60.0, 24.0, 6.0, 0.003, 0.9) * loud(cr) * 1.6
    x = x + roar(n, SKY, curve(t, [(0.0, -80), (RELEASE_FREE, -60), (RELEASE_FREE + 0.3, -8), (2.9, -10), (d, -40)]), boil=4.0) * loud(cr) * 0.4
    x = distance(x, t, after=RELEASE_FREE + 0.3, keep=0.3, length=5.0, t60=(4.5, 3.2, 1.4), seed=190 + v)
    x = space(x, 0.6, length=5.0, t60=(4.5, 3.0, 1.0), seed=v * 7)
    x = weight(x, -9.0)
    write("release" if v == 1 else "release2", x, db=-12.0, fade_out=0.5)


def fall():
    """A huge pane coming down (cut dead on the impact, FALL_CUT in): the air it tears through, darker and further up at
    first, then on them; it turns as it tumbles, its roar swelling and easing with each turn, faster and faster; the
    pane's own glass humming in the wind it makes; a deep throb of the air under its face."""
    d = FALL_CUT + 0.05
    n = nsm(d)
    t = np.arange(n) / SR
    u = np.clip(t / FALL_CUT, 0, 1)
    r = roar(n, AIR, curve(t, [(0.0, -26), (FALL_CUT * 0.4, -16), (FALL_CUT * 0.75, -8), (FALL_CUT * 0.95, -1), (FALL_CUT, 0), (d, 0)]), boil=5.0, rates=(0.4, 4.0))
    r = lowpass_track(r, 500.0 * (3800.0 / 500.0) ** (u ** 1.6))
    turn = 1.0 + 0.45 * np.sin(2 * np.pi * np.cumsum(0.32 + 0.5 * u ** 2) / SR + 0.7)
    x = unit(r) * turn
    hum = pane_song(n, np.clip(0.35 + 0.65 * u ** 2, 0, 1) * (0.6 + 0.4 * turn / 1.45), 25.0, bend=0.0, modes=plate(48.0, 1.45, 520.0, 5711), seed=1951)
    x = x + hum / (loud(hum) + 1e-12) * (0.12 + 0.18 * u)
    ph = 2 * np.pi * np.cumsum(22.0 + 16.0 * u ** 2) / SR
    x = x + np.sin(ph) * (0.2 + 0.8 * u ** 2.5) * 0.9 * turn
    far = verb(x, 4.0, (4.0, 2.6, 1.0), 196, lo=None)
    x = x * (0.45 + 0.55 * u) + far * (1.0 - u) ** 1.5 * 0.7
    x = weight(x, -8.0)
    k = nsm(FALL_CUT)
    x[k:] *= np.linspace(1.0, 0.0, len(x) - k) ** 4
    write("fall", x, peak_db=-2.5, fade_out=0.01)


def ground():
    """A blow through the ground, ahead of the air: a deep heave and a short low shudder."""
    d = 3.0
    n = nsm(d)
    t = np.arange(n) / SR
    x = heave(n, 0.02, 48.0, 21.0, 4.5, 0.004, 0.55)
    x = x + noise(n, 22, 70, 3) * np.exp(-np.maximum(t - 0.03, 0) / 0.9) * (t > 0.02) * 0.45
    sh = (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(11.0 + 3.0 * slow(n, 0.5, 3.0)) / SR)) ** 2
    x = x + noise(n, 30, 160, 2) * sh * np.exp(-np.maximum(t - 0.05, 0) / 0.5) * (t > 0.03) * 0.35
    x = weight(x, -9.0)
    write("ground", x, db=-11.0, fade_out=0.4)


def impact_take(v):
    """A pane smashing into the land (IMP_LEAD in): its boom and the land's own modes, a knock of body, the pressure; the
    pane crashing into pieces as it goes in, a rupture and thousands of pieces, deeper than the crack's (they are
    bigger), each bouncing on the land and on each other at shrinking intervals; then the heap settling, pieces sliding
    and falling off it, fewer and further off, heard mostly as the land gives them back; the earth thrown; the land
    rolling it away. Take 3's far end slams down after it."""
    d = 9.0
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = IMP_LEAD
    u = np.maximum(t - t0, 0)
    deep = {1: 1.0, 2: 0.88, 3: 1.05}[v]
    x = boom(n, t0, 70.0 * deep, 30.0 * deep, 0.9, 2.6, 1.0, 0.8)
    x = x + heave(n, t0 + 0.22, 48.0 * deep, 22.0 * deep, 5.0, 0.01, 0.6, 0.6)
    x = x + struck(n, t0, 0.003, LAND, 0.9) + struck(n, t0 + 0.003, 0.002, RUBBLE, 0.5)
    x = x + knock(n, t0, 112.0 * deep, 0.08, 0.8) + knock(n, t0 + 0.003, 240.0 * deep, 0.04, 0.35)
    x = x + shove(n, t0, 0.3, 0.7)
    ref = loud(x)
    x = x + drive(x, 3.0, -7.0)
    x = x + rupture(n, t0, 0.003, 200.0, 7000.0, 0.6) * ref * 1.6
    k = 1600
    born = t0 + 0.005 + by_rate(k, [(0.0, 2.5), (0.1, 2.0), (0.35, 1.0), (0.9, 0.25), (1.4, 0.0)])
    pcs = cascade(n, born, sizes(k, 0.2, 1.0, 1.35), big=GLASS_BIG * 0.8 * deep, knocks=(2, 5), gap=(0.06, 0.3), shrink=(0.5, 0.7), ground=True)
    x = x + pcs / (loud(pcs) + 1e-12) * ref * 10 ** (5 / 20)
    m = 380
    born = t0 + 1.0 + by_rate(m, [(0.0, 1.0), (1.0, 0.5), (2.5, 0.2), (5.0, 0.03)])
    st = cascade(n, born, sizes(m, 0.2, 0.6, 1.6), big=GLASS_BIG * 0.8 * deep, top=3200.0, knocks=(1, 3), gap=(0.05, 0.2), ground=True, snap=0.1, qmax=260.0)
    x = x + st / (loud(st) + 1e-12) * ref * 10 ** (-22 / 20)
    if v == 3:
        x = x + heave(n, t0 + 0.38, 58.0, 23.0, 6.0, 0.002, 0.8) * ref * 1.4
        sl = np.zeros(n)
        crack_at(sl, t0 + 0.38, 0.9, run=0.04, pieces=60, body=0.0, deep=False)
        x = x + sl / (loud(sl) + 1e-12) * ref * 10 ** (-4 / 20)
    x = x + roar(n, EARTH, curve(t, [(0.0, -40), (t0 + 0.05, -2), (0.4, 0), (1.5, -7), (3.5, -19), (6.0, -32), (9.0, -50)]), boil=4.0) * ref * 0.5
    x = distance(x, u, after=0.6, keep=0.35, length=4.0, t60=(3.0, 2.2, 1.1), seed=200 + v, dark=3400.0)
    x = x + rolls(n, t0 + 0.5, 10, 4.0) * loud(x) * 0.2
    x = space(x, 0.35, length=3.5, t60=(3.0, 2.0, 0.8), seed=v * 11)
    x = x * curve(t, [(0.0, 0), (2.0, 0), (5.0, -6), (9.0, -20)])
    x = weight(x, -8.0)
    x = soft_clip(x, np.percentile(np.abs(x), 99.7) * 0.9, 0.6)
    write(["impact", "impact2", "impact3"][v - 1], x, db=-10.0, fade_out=0.8)


def impact_far():
    """`impact` through a kilometre of air: the top let down, the front softened, more of the low rolls, a long dark reverb."""
    x = decoded("impact")
    if x is None:
        raise SystemExit("impact is not built yet: build it before impact_far")
    d = 12.0
    n = nsm(d)
    y = np.zeros(n)
    y[:min(len(x), n)] = x[:n]
    tt = np.arange(n) / SR - IMP_LEAD
    soft = np.clip(tt / 0.08, 0, 1) ** 2
    lo = band(y, None, 300, 2)
    mid = band(y, 300, 1500, 2) * np.sqrt(soft)
    hi = band(y, 1500, None, 2) * soft
    y = lo * 0.8 + mid * 1.1 + band(hi, None, 3500, 2) * 0.25
    y = y + rolls(n, IMP_LEAD + 0.8, 16, 11.0) * loud(y) * 0.45
    y = space(y, 0.6, length=7.0, t60=(6.0, 3.6, 1.2), seed=40, lo=100.0)
    y = weight(y, -6.0)
    write("impact_far", y, db=-13.5, fade_out=1.2)


def slam():
    """A pane's far end slamming down a moment after its low end strikes: one heavy short blow, the glass under it
    crunching into pieces (a short dense crash, deep), the earth thrown."""
    d = 3.2
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = IMP_LEAD
    u = np.maximum(t - t0, 0)
    x = boom(n, t0, 64.0, 26.0, 0.6, 2.4, 1.0, 0.7)
    x = x + knock(n, t0, 118.0, 0.06, 0.8) + knock(n, t0 + 0.003, 260.0, 0.03, 0.35)
    x = x + struck(n, t0, 0.003, RUBBLE, 0.6)
    ref = loud(x)
    k = 650
    born = t0 + 0.004 + by_rate(k, [(0.0, 2.0), (0.12, 1.0), (0.4, 0.2), (0.6, 0.0)])
    pcs = cascade(n, born, sizes(k, 0.22, 1.0, 1.3), big=GLASS_BIG * 0.75, top=4600.0, knocks=(1, 3), gap=(0.05, 0.2), ground=True)
    x = x + pcs / (loud(pcs) + 1e-12) * ref * 10 ** (0 / 20)
    x = x + roar(n, EARTH, curve(t, [(0.0, -40), (0.04, -4), (0.3, -6), (1.4, -20), (d, -50)]), boil=4.0) * ref * 0.35
    x = distance(x, u, after=0.35, keep=0.35, length=3.0, t60=(2.6, 1.8, 0.9), seed=81, dark=3400.0)
    x = space(x, 0.3, length=2.5, t60=(2.0, 1.4, 0.6), seed=80)
    x = weight(x, -8.0)
    x = soft_clip(x, np.percentile(np.abs(x), 99.7) * 0.9, 0.6)
    write("slam", x, db=-12.0, fade_out=0.6)


def rumble():
    """The land settling after a blow: a low roar, rolls, a few deep heaves."""
    d = 14.0
    n = nsm(d)
    t = np.arange(n) / SR
    x = roar(n, EARTH[:4], curve(t, [(0.0, -20), (1.0, -3), (5.0, -6), (10.0, -14), (14.0, -40)]), boil=4.0, rates=(0.2, 2.0))
    x = unit(x) + rolls(n, 0.2, 10, 10.0) * 0.6
    for k in range(5):
        x += heave(n, rng().uniform(1.0, 9.0), rng().uniform(40, 55), 22.0, 4.0, 0.01, 0.5, rng().uniform(0.2, 0.45))
    write("rumble", x, db=-17.0, fade_in=0.3, fade_out=2.0)


# =======================================================================================================  what looks in
def void():
    """What looks through the holes: a vast low drone beating against itself (two notes a little apart and their fifths,
    each drifting on its own), breathing in and out twice; a wind from nowhere, dark; a held note on the drone's root."""
    d = 21.0                    # (to the flare and the slam, 7 s sooner than round 4: the eye stares less long)
    n = nsm(d)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, a in ((36.7, 1.0), (38.4, 0.85), (55.1, 0.45), (57.3, 0.3), (73.4, 0.22), (110.2, 0.08), (146.8, 0.035)):
        fr = f * (1 + 0.004 * slow(n, 0.05, 0.3))
        x += a * np.sin(2 * np.pi * np.cumsum(fr) / SR + rng().uniform(0, 6.3)) * (0.75 + 0.25 * slow(n, 0.06, 0.25))
    # (its breathing held still from ~13 s in (strike 31): a trough of it fell on 37, the stretch before the flare's
    # gathering, the strike's quietest moment from near; now the drone holds there)
    deep = 0.45 * (1 - 0.75 * ss(12.5, 16.5, t))
    breath = 1.0 - deep + deep * np.clip(np.sin(2 * np.pi * t / 11.0 - 1.2), -1, 1) ** 2
    x = x * breath
    w = roar(n, EARTH[:4], curve(t, [(0.0, -18), (4.0, -8), (12.0, -10), (16.0, -9), (21.0, -30)]), boil=4.0, rates=(0.1, 1.5))
    sw = np.clip(curve(t, [(0.0, -30), (5.0, -4), (12.0, 0), (15.0, -3), (21.0, -30)]), 0, 1)
    b = note(36.7, d, sw * breath, partials=12, top=600.0)
    x = unit(x) + unit(w) * 0.55 + unit(b) * 0.6
    x = space(x, 0.5, length=6.0, t60=(6.0, 3.6, 1.2), seed=50, lo=None)
    x = x * curve(t, [(0.0, -40), (3.0, -2), (15.0, 0), (19.0, -3), (21.0, -30)])
    x = weight(x, -9.0)
    write("void", x, db=-17.0, fade_in=1.0, fade_out=2.0)


def heal():
    """The sky drawn back whole (sealed SEAL in): its pieces' rings swelling backwards into the seal (a break played
    backwards, dark and given back by the sky), the pane singing as it closes, rising a little into it, the air pulled
    in behind it; sealed, one deep ring of the whole pane, rolling away."""
    d = 11.0
    n = nsm(d)
    t = np.arange(n) / SR
    seal = 8.6
    sw = np.clip(curve(t, [(0.0, -24), (3.0, -11), (6.5, -5), (seal, 0), (seal + 0.15, -18), (d, -60)]), 0, 1)
    song = pane_song(n, sw, 80.0, bend=0.06, opens=2.5, seed=2111)
    x = unit(song)
    m = nsm(4.5)
    k = 900
    pcs = cascade(m, 0.02 + by_rate(k, [(0.0, 2.0), (0.4, 1.0), (1.5, 0.3), (3.0, 0.0)]), sizes(k, 0.2, 1.0, 1.4), top=3800.0, knocks=(1, 3), snap=0.1)
    pcs = pcs + verb(pcs, 4.0, (4.0, 3.0, 1.6), 212, lo=None) * 0.8
    rev = pcs[::-1] * curve(np.arange(m) / SR, [(0.0, -50), (1.5, -16), (3.5, -6), (4.4, 0), (4.5, -3)])
    pr = np.zeros(n)
    put(pr, rev, seal - 4.5 + 0.01)
    x = x + pr / (loud(pr) + 1e-12) * 0.6
    x = x + roar(n, SKY, curve(t, [(0.0, -26), (4.0, -12), (seal - 0.4, -2), (seal + 0.2, -20), (d, -50)]), boil=4.0) * 0.6
    ref = loud(x)
    p = pane_ring(n, seal, 1.0, 0.012, 70.0)
    x = x + p / (loud(p) + 1e-12) * ref * 1.1 + heave(n, seal, 52.0, 24.0, 5.0, 0.006, 0.9) * ref * 1.6
    x = x + rolls(n, seal, 8, 2.0) * np.where(t > seal, 1.0, 0.0) * ref * 0.5
    x = space(x, 0.6, length=5.0, t60=(4.5, 3.0, 1.2), seed=60)
    x = weight(x, -9.0)
    write("heal", x, db=-14.0, fade_in=0.8, fade_out=1.5)


def gaze():
    """The eye: sliding in behind the sky to the hole (a vast dark rush passing, opening as it comes and darkening as it
    settles, a deep soft stop as it comes to rest there), its lids parting (a slow breath of dread: two deep notes a
    semitone apart swelling against each other), and its gaze landing on the one who looks (GAZE_HIT in): the swell
    stopping dead and one deep blow, its body in the low mids, felt more than heard, rolling off the sky."""
    d = GAZE_HIT + 7.65
    n = nsm(d)
    t = np.arange(n) / SR
    th = GAZE_HIT
    sh = th - 4.35
    r = roar(n, EARTH[:4], curve(t, [(0.0, -40), (0.5, -18), (1.2, -6), (2.0, -6), (2.6, -12), (th - 0.4, -11), (th, -14), (th + 3.0, -30), (d, -60)]), boil=4.0)
    r = lowpass_track(r, 280.0 + 900.0 * np.exp(-0.5 * ((t - 1.3) / 0.6) ** 2) + 200.0 * ss(2.0, th, t))
    stop = heave(n, 2.4, 44.0, 28.0, 4.0, 0.08, 0.6)
    sw = np.clip(curve(t, [(0.0, -40), (2.0, -36), (sh + 1.5, -24), (sh + 2.2, -12), (sh + 3.3, -6), (th - 0.25, 0), (th - 0.02, 0), (th + 0.02, -40), (d, -60)]), 0, 1)
    b = unit(note(41.2, d, sw, partials=28)) + unit(note(43.65, d, sw ** 1.2, partials=24, drift=0.002)) * 0.8
    x = b * 0.75 + unit(r) * 0.6 * ss(th - 3.0, th - 1.0, t)
    slide = unit(r) * (1 - ss(th - 3.0, th - 1.0, t)) + stop / (np.abs(stop).max() + 1e-9) * 0.45
    x[nsm(th - 0.05):nsm(th - 0.035)] *= np.linspace(1.0, 0.0, nsm(th - 0.035) - nsm(th - 0.05))
    x[nsm(th - 0.035):nsm(th)] = 0.0
    hit = boom(n, th, 96.0, 36.0, 0.6, 2.6, 1.0, 0.6)
    hit = hit + knock(n, th, 96.0, 0.11, 0.9) + knock(n, th + 0.003, 210.0, 0.05, 0.4)
    hit = hit + heave(n, th, 52.0, 21.0, 4.0, 0.003, 1.8, 2.2)
    uh = np.maximum(t - th, 0)
    hit = hit + noise(n, 40, 400, 2) * (1 - np.exp(-uh / 0.02)) * np.exp(-uh / 0.35) * (t >= th) * loud(hit) * 0.45
    hit = soft_clip(hit, np.percentile(np.abs(hit), 99.8) * 0.75, 0.5)
    x = x / (loud(x) + 1e-9) * loud(hit) * 0.33 + hit + slide / (loud(slide) + 1e-9) * loud(hit) * 0.55
    x = space(x, 0.55, length=6.0, t60=(5.0, 3.2, 1.0), seed=70)
    x = x + rolls(n, th + 0.3, 10, 6.0) * loud(x) * 0.3 * (t > th)
    x = weight(x, -8.0)
    write("gaze", x, db=-12.0, fade_in=0.2, fade_out=1.5)


# ==========================================================================================================  the finale
# ================================================================================  round 6: pressure, crackle and glass
# Kyle tagged round 5's flare (both halves), the smash's blow and the shudder SLOP: synthetic, gamey. What gave them away:
# sines (a boom that is a sinking tone, knocks that are sine bursts, a riser that is a held note), filter sweeps (a
# band of noise gliding up: a UI riser; a "whoomph" that is a swept band), steady noise under a clean envelope, and a
# pane that bongs on its few low modes. Against the approved big hits (nuke/blast, payload/blast and blast_alt,
# meteor/impact, measured, never reused) those are dense and un-tonal (their spectra 4-6 dB peak-over-median, round 5's
# smash 7.3), their body made of many overlapping pressure events, not of partials. So round 6 builds every big sound
# here from events: pressure pulses (N-waves: what a blast or a thunder stroke is at a distance; their sharp edges are
# what put a blow's weight into 100-800 Hz, with no tone), crackle (thousands of small fractures a second, each a low-Q
# ring, their amplitudes power-law: what the land breaking or the air tearing sounds like close to) and, for the glass,
# thousands of shards a second. Thunder's physics (Few 1969: a stroke is a string of N-waves from the channel's
# tortuous segments, arriving spread out by their distances: the clap the near ones, the roll the far ones, darker and
# later) is the model for the sky's sounds.
def nwave(dur, rise):
    """One N-wave of `dur` s (a blast's or a thunder stroke's pressure at a distance: a jump up, a straight fall through
    zero, a jump back), its two fronts each `rise` s (the higher frequencies it has go as 1 / rise). Peak 1."""
    m = max(nsm(dur), 8)
    tt = np.arange(m) / SR
    p = 1.0 - 2.0 * tt / dur
    r = min(max(nsm(rise), 2), m // 3)
    w = np.ones(m)
    w[:r] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, r))
    w[-r:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return p * w


def strokes(n, times, durs, amps, rise):
    """N-waves at `times` (s), each `durs` long and `amps` big (sign kept), fronts `rise` (s, or one each)."""
    y = np.zeros(n)
    rise = np.broadcast_to(np.asarray(rise, float), (len(times),))
    for t, d, a, r in zip(times, durs, amps, rise):
        put(y, nwave(d, r) * a, t)
    return y


def events(rate, t0=0.0):
    """Times (s) of a Poisson process whose rate (a second) is `rate`, one a sample."""
    k = rng().poisson(np.clip(rate, 0, None) / SR)
    idx = np.repeat(np.arange(len(k)), k)
    return idx / SR + rng().uniform(0, 1 / SR, len(idx)) + t0


def clumps(n, rate, depth_db):
    """A slow random gain (nothing over ~2 `rate` Hz) of about `depth_db` spread: events coming in clusters."""
    return np.exp(depth_db * slow(n, rate * 0.3, rate * 2.0) / 8.686)


def crackle(n, rate, lo, hi, bands=16, alpha=2.6, q_oct=1.1):
    """Thousands of small fractures (`rate` a second, one a sample): each an impulse of power-law size (Pareto `alpha`, the
    biggest held to 6 times the smallest: no lone spike)
    and random sign, rung by a low-Q band (`q_oct` octaves wide) of its own between `lo` and `hi` Hz. Dense, it is a
    crackling roar with no tone; thin, a scatter. Unit RMS."""
    y = np.zeros(n)
    edges = np.geomspace(lo, hi, bands + 1)
    for b in range(bands):
        fc = np.sqrt(edges[b] * edges[b + 1])
        k = rng().poisson(np.clip(rate, 0, None) / SR / bands)
        imp = k * np.minimum(rng().pareto(alpha, n) + 1.0, 6.0) * rng().choice((-1.0, 1.0), n)
        y += band(imp, fc * 2 ** (-q_oct / 2), min(fc * 2 ** (q_oct / 2), SR / 2 - 100), 1)
    return unit(y)


def overload(x, drive=2.0, bias=0.15):
    """A blast's recording overloaded: the sum through a lopsided soft saturation (odd and even harmonics of its lows
    land in its body), its DC taken back out. Same peak as `x`."""
    p = np.abs(x).max() + 1e-12
    u = x / p * drive
    y = np.tanh(u + bias) - np.tanh(bias)
    y = y - band(y, None, 10, 2)
    return y / (np.abs(y).max() + 1e-12) * p


def flare():
    """The eye's last flare, up in the sky over the hole (its burst FLARE_AT in, 42.1).
    The draw (0 to FLARE_AT): the air of the whole sky pulled in to the hole. No riser, no sweep: a gale building, its
    bands of turbulence each gusting on its own and each growing with the pull as wind does (the higher a band, the
    faster it grows: the spectrum opens as the pull grows, nothing glides), the sky groaning under it (deep pressure
    strokes far off, darker the farther, more and more of them), a sub of the pressure falling. Only climbing, into the
    burst with no gap.
    The burst (FLARE_AT on): a thunderclap from 600 blocks up: the near strokes first (a short ragged clap, its top
    taken by the air), the burst's own great strokes on them (long N-waves: the weight, their edges its body), then the
    roll as the far strokes arrive, each later, longer and darker, in clumps, for some 4 s; the hot air spilling out of
    the hole, a crackling roar; all of it given back by the sky and the land."""
    d = FLARE_AT + 4.6
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = FLARE_AT
    u = np.maximum(t - t0, 0)
    on = t >= t0
    # ---- the draw
    pull = np.clip(t / t0, 0, 1) ** 1.7 * (t < t0 + 0.2)
    pull = np.maximum(pull, 0.08 * (t < t0 + 0.2))
    gale = np.zeros(n)
    for k, (fc, g) in enumerate(((45, 1.0), (90, 1.0), (180, 0.85), (360, 0.6), (720, 0.38), (1440, 0.2), (2880, 0.08))):
        b = noise(n, fc / 1.6, fc * 1.6, 1) * np.exp(5.5 * slow(n, 0.15, 1.6 + 0.3 * k) / 8.686)
        gale += b * g * pull ** (0.7 + 0.45 * k)
    pull_t = t0 * 0.55
    grt = events(curve(t, [(0.0, -2), (pull_t, 6), (t0 - 0.4, 15), (t0, 18)]) * (t < t0))
    gd = rng().uniform(0.06, 0.22, len(grt))
    ga = np.minimum(rng().pareto(2.0, len(grt)) + 0.3, 3.0) * curve(grt, [(0.0, -12), (t0, 0)]) * rng().choice((-1.0, 1.0), len(grt))
    groan = strokes(n, grt, gd, ga, 0.004)
    groan = band(groan, 18, 520, 2)
    sub = noise(n, 16, 42, 3) * pull ** 1.4
    draw = unit(gale) + unit(groan) * 0.55 + unit(sub) * 0.5
    draw = space(draw, 0.55, length=5.0, t60=(4.5, 3.0, 1.0), seed=172)
    dp = [(0.0, -17), (0.8, -11.5), (1.8, -8), (2.8, -5), (3.5, -3), (t0 - 0.05, -1), (t0 + 0.1, -2), (t0 + 0.6, -30), (d, -80)]
    draw = leveled(draw, t, dp)
    # ---- the burst
    nc = 60
    ct = t0 + 0.07 * rng().uniform(0, 1, nc) ** 1.8
    clap = strokes(n, ct, rng().uniform(0.004, 0.016, nc), (rng().pareto(2.2, nc) + 1) * rng().choice((-1.0, 1.0), nc), 0.0004)
    clap = band(clap, 40, 2600, 2)
    nb = 7
    bt = t0 + 0.004 + 0.05 * rng().uniform(0, 1, nb)
    great = strokes(n, bt, rng().uniform(0.06, 0.16, nb), rng().uniform(0.6, 1.0, nb) * rng().choice((-1.0, 1.0), nb), 0.0025)
    great = band(great, 14, 1400, 2)
    rate = (220.0 * np.exp(-u / 0.8) + 45.0 * np.exp(-u / 2.4)) * clumps(n, 1.2, 6.0) * on
    rt = events(rate)
    ur = rt - t0
    far = np.clip(ur / 3.0 + rng().uniform(-0.25, 0.25, len(rt)), 0, 1)
    rd = 0.012 + 0.12 * far * rng().uniform(0.5, 1.2, len(rt))
    ra = np.minimum(rng().pareto(2.0, len(rt)) + 1, 4.0) * np.exp(-ur / 2.4) * rng().choice((-1.0, 1.0), len(rt))
    roll = np.zeros(n)
    for lo_, hi_, fc in ((0.0, 0.33, 2400.0), (0.33, 0.66, 1100.0), (0.66, 1.01, 520.0)):
        m = (far >= lo_) & (far < hi_)
        roll += band(strokes(n, rt[m], rd[m], ra[m], 0.0012), 18, fc, 2)
    gush = crackle(n, np.interp(t, [0.0, t0, t0 + 0.05, t0 + 0.5, t0 + 2.0, d], [0, 0, 5000, 9000, 3000, 400]) * on * clumps(n, 2.0, 4.0),
                   70, 1800, 14, 3.2)
    gush = gush * curve(t, [(0.0, -80), (t0, -60), (t0 + 0.06, -6), (t0 + 0.5, 0), (t0 + 1.5, -3), (t0 + 2.8, -10), (t0 + 4.2, -24), (d, -45)])
    burst = unit(great) * 1.0 + unit(clap) * 0.35 + unit(roll) * 1.0 + gush * 0.7
    burst = overload(burst, 2.2, 0.2)
    burst = burst + shove(n, t0 + 0.01, 0.45, np.abs(burst).max() * 0.35)
    burst = space(burst, 0.7, length=6.0, t60=(5.0, 3.4, 1.1), seed=173)
    burst = burst * curve(t, [(0.0, 0), (t0 + 2.5, 0), (t0 + 4.0, -10), (d, -30)])
    ref = loud(burst)
    x = burst + draw / (loud(draw) + 1e-12) * ref * 10 ** (-4.5 / 20)
    x = weight(x, -10.0)
    write("flare", x, db=-10.0, fade_in=0.05, fade_out=0.8, crest=1.9)


def descend():
    """The fist thrown down through the hole on to the land in one blow (cut dead on the slam, DESCEND_CUT in): the
    air drawn up to it as it starts beyond the glass, the pane groaning; the shards round the hole cracking off and
    grinding on it as it bursts through (DESCEND_THROUGH in); then the roar of the air it drives down, dark and high up
    at first, nearer, fuller and faster, a rush band sweeping up, the wall of air pushed ahead of a fist of flesh the
    size of a hill (a dark low push, thickening), the weight of it, a sub and a deep throb under its fist. It starts
    under the flare's roar and only climbs, out of it and on to the slam: nothing dips before the climax."""
    cut = DESCEND_CUT
    th = DESCEND_THROUGH
    d = cut + 0.02
    n = nsm(d)
    t = np.arange(n) / SR
    u = np.clip(t / cut, 0, 1)
    rate = 300.0 * curve(t, [(0.0, -40), (th - 0.25, -20), (th - 0.05, 0), (th + 0.1, -6), (th + 0.3, -30), (d, -80)])
    gr = scrape(n, rate, 160.0, 400.0, 3, 60.0) * curve(t, [(0.0, -60), (th - 0.25, -30), (th - 0.04, -6), (th + 0.1, -8), (th + 0.3, -30), (th + 0.5, -70), (d, -90)])
    push = glide(n, 70.0 + 110.0 * u ** 2, 1.4) * curve(t, [(0.0, -40), (cut * 0.35, -22), (cut * 0.7, -11), (cut, -4), (d, -4)])
    cr = np.zeros(n)
    crack_at(cr, th - 0.03, 0.5, run=0.03, pieces=14, body=0.6, top=3600.0, qmax=300.0)
    song = pane_song(n, np.clip(curve(t, [(0.0, -40), (th - 0.2, -14), (th, -6), (th + 0.15, -6), (th + 0.5, -40), (d, -80)]), 0, 1), 40.0, bend=-0.02, seed=2311)
    r = roar(n, AIR, curve(t, [(0.0, -22), (cut * 0.4, -14), (cut * 0.75, -7), (cut * 0.95, -1), (cut, 0), (d, 0)]), boil=5.0, rates=(0.4, 4.0))
    r = lowpass_track(r, 450.0 * (3600.0 / 450.0) ** (u ** 1.5))
    x = unit(r)
    fc = 240.0 * (1150.0 / 240.0) ** (u ** 1.8)
    x = x + glide(n, fc, 0.9 + 0.3 * u) * curve(t, [(0.0, -30), (cut * 0.6, -24), (cut, -14), (d, -14)])
    x = x + noise(n, 24, 70, 3) * curve(t, [(0.0, -24), (cut * 0.6, -14), (cut, -5), (d, -5)])
    ph = 2 * np.pi * np.cumsum(20.0 + 18.0 * u ** 2) / SR
    x = x + np.sin(ph) * (0.05 + 0.95 * u ** 2.5) * 0.8
    x = x + gr * 0.55 + cr / (loud(cr) + 1e-12) * 0.45 + song / (loud(song) + 1e-12) * 0.3 + push * 0.8
    far = verb(x, 4.0, (4.0, 2.6, 1.0), 181, lo=None)
    x = x * (0.45 + 0.55 * u) + far * (1.0 - u) ** 1.5 * 0.7
    x = leveled(x, t, [(0.0, -8), (cut * 0.3, -6), (cut * 0.57, -4), (cut * 0.8, -2), (cut * 0.94, -0.8), (cut, 0), (d, 0)])
    x = weight(x, -8.0)
    k = nsm(cut)
    k6 = nsm(0.006)
    x[k - k6:k] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k6))
    x[k:] = 0.0
    x = tame_lows(x, 200.0, 99.0, 0.5)
    write("descend", x, db=-10.5, fade_in=0.12, fade_out=0.002)


def smash_r5():
    """Round 5's smash, kept for all but its first ~1.3 s (see `smash`). The hand slamming the land (SMASH_AT in): the fist's blow all at once (a deep driven boom, the land's
    own modes and its rubble, a knock of body, the pressure shoved out); a fist of flesh, not glass: the weight of the
    arm behind it landing a beat after its knuckles (a second, deeper blow), the land caving in under it (a dark crush
    of earth and rock, slow on its front: no snare); the land breaking under it (its mass moving, chunks you could
    count); the shock running out over the land (a whoomph, the air's roar boiling behind it); the earth thrown, a dark
    roar off the land, held up for the first second and a half so the climax is the loudest stretch of the strike, not
    only its loudest instant; the land rolling it round for seconds. Then (LIFT_AT in, sb_hand.rs's SB_LIFT) the fist
    pulled up out of the land: the ground letting go of it with a deep suck, the earth pouring off it and falling back,
    the air rising away with the arm into the sky, gone by GONE_AT (SB_GONE). All of it on the land: late by the
    distance with the slam."""
    d = 10.0
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = SMASH_AT
    u = np.maximum(t - t0, 0)
    on = t >= t0
    x = boom(n, t0, 120.0, 40.0, 0.6, 3.4, 4.6, 0.9)
    x = x + struck(n, t0, 0.003, LAND, 1.6) + struck(n, t0 + 0.004, 0.002, RUBBLE, 1.2)
    x = x + knock(n, t0, 108.0, 0.09, 1.4) + knock(n, t0 + 0.003, 230.0, 0.045, 0.6)
    x = x + shove(n, t0, 0.3, loud(x) * 1.8)
    ref = loud(x)
    x = x + drive(x, 3.2, -4.0)
    x = x + noise(n, 80, 700, 2) * (1 - np.exp(-u / 0.03)) * np.exp(-u / 0.4) * on * ref * 10 ** (-6 / 20)
    tk = t0 + 0.12
    while tk < t0 + 1.5:
        g = rng().uniform(0.5, 1.0) * (1 - 0.8 * ((tk - t0) / 1.5) ** 1.5)
        sc = rng().uniform(0.8, 1.3)
        w = struck(n, tk, 0.004, tuple((f * sc, dk * 0.6, a) for f, dk, a in RUBBLE), g)
        uk = np.maximum(t - tk, 0)
        w = w + noise(n, 80, 600, 2) * (1 - np.exp(-uk / 0.005)) * np.exp(-uk / 0.06) * (t >= tk) * g * 0.5
        x = x + w * ref * 10 ** (-10 / 20)
        tk += rng().gamma(2.0, 0.07)
    fw = glide(n, 170.0 + 640.0 * np.exp(-u / 0.2), 0.5) * (1 - np.exp(-u / 0.03)) ** 2 * np.exp(-u / 0.45) * on
    x = x + fw * ref * 1.0
    # (the arm's weight behind the fist, a beat after its knuckles: deeper, slower)
    arm = boom(n, t0 + 0.07, 62.0, 28.0, 0.9, 2.8, 1.0, 0.8) + struck(n, t0 + 0.07, 0.01, LAND[:4], 0.8)
    x = x + arm / (loud(arm) + 1e-12) * ref * 10 ** (-3 / 20)
    # (the land caving in under it: a dark crush of earth and rock, its front 25 ms, its body 130-900 Hz)
    uc = np.maximum(t - t0 - 0.01, 0)
    crush = noise(n, 130, 900, 2) * np.exp(3.0 * slow(n, 0.5, 3.0) / 8.686)
    crush = lowpass_track(crush, 500.0 + 900.0 * np.exp(-uc / 0.35)) * (1 - np.exp(-uc / 0.025)) ** 2 * np.exp(-uc / 0.7) * (t >= t0 + 0.01)
    x = x + crush / (loud(crush) + 1e-12) * ref * 10 ** (-7 / 20)
    after = roar(n, FIRE, curve(t, [(0.0, -60), (t0, -60), (t0 + 0.04, -14), (t0 + 0.3, -4), (t0 + 0.9, -5), (t0 + 1.8, -10), (t0 + 3.2, -20), (t0 + 5.5, -40), (d, -60)]),
                 boil=4.5) * 0.55
    after = after + roar(n, EARTH, curve(t, [(0.0, -40), (t0 + 0.05, -6), (0.5, -2), (1.8, -8), (4.0, -20), (7.0, -34), (d, -50)]), boil=4.0) * 0.35
    after = after + rolls(n, t0 + 0.6, 30, 7.0, 40.0, 420.0) * curve(t, [(0.0, -60), (t0 + 0.4, -8), (2.0, -6), (6.0, -16), (d, -30)]) * 0.5
    after = after + rolls(n, t0 + 0.8, 12, 7.0) * 0.25
    x = x + after * ref * curve(t, [(0.0, -5), (t0 + 0.06, -5), (t0 + 0.3, -6), (t0 + 0.8, -3.5), (t0 + 1.6, -4.5), (t0 + 2.5, -7), (d, -7)])
    x = space(x, 0.4, length=4.5, t60=(3.8, 2.6, 0.9), seed=191)
    x = x * curve(t, [(0.0, 0), (2.5, 0), (6.0, -7), (d, -22)])
    # (the fist pulled up out of the land, the arm rising away into the sky)
    tl = t0 + LIFT_AT
    ul = np.maximum(t - tl, 0)
    onl = t >= tl
    lift = np.sin(2 * np.pi * np.cumsum((30.0 + 16.0 * ss(0.0, 1.2, ul)) * onl) / SR) * ss(0.0, 0.3, ul) * np.exp(-ul / 0.9) * onl
    suck = glide(n, 90.0 + 160.0 * ss(0.0, 0.8, ul), 0.9) * ss(0.0, 0.25, ul) * np.exp(-ul / 0.7) * onl
    earth = pour(n, 90, 900, 650.0) * curve(t, [(0.0, -80), (tl, -80), (tl + 0.2, -10), (tl + 1.0, -9), (tl + 2.2, -20), (tl + 3.4, -50), (d, -80)])
    up = roar(n, SKY, curve(t, [(0.0, -80), (tl, -60), (tl + 0.5, -12), (tl + 1.3, -8), (t0 + GONE_AT - 1.2, -16), (t0 + GONE_AT, -45), (d, -80)]), boil=4.0)
    up = lowpass_track(up, 1400.0 * 0.3 ** ss(0.3, GONE_AT - LIFT_AT, ul))
    lx = lift * 0.9 + suck * 0.6 + earth * 0.8 + up * 0.9
    lx = space(lx, 0.6, length=5.0, t60=(4.5, 3.0, 1.0), seed=193)
    x = x + lx / (loud(lx) + 1e-12) * ref * 10 ** (-13 / 20)
    x = weight(x, -8.0)
    x = soft_clip(x, np.percentile(np.abs(x), 99.7) * 0.9, 0.6)
    return x


def smash_blow(n, t):
    """Round 6's blow (the smash's first ~1.4 s), from events, no tones: the fist's knuckles and then the heel of it
    and the arm's weight hitting the land a few ms to 80 ms apart (great N-waves, long: the weight, their fronts 1.5 ms:
    the body to ~800 Hz and nothing like a crack over it); the land fracturing under it (crackle: tens of thousands of
    small breaks a second at first, their sizes power-law, 60 Hz to 2.5 kHz, thinning over a second in clumps); the air
    driven out over the land (a crackling roar swelling over 60 ms and boiling down); the ground's own heave under it
    all (a sub pressure pulse, no sine); the whole overloaded a little as a blast's recording is. Its spectrum then sits with the approved hits':
    most in the lows, a real 100-800 Hz body, a little of 0.8-3 kHz."""
    t0 = SMASH_AT
    u = np.maximum(t - t0, 0)
    on = t >= t0
    # (the blows: four knuckles, the heel, the arm's weight)
    bt = t0 + np.array([0.0, 0.004, 0.009, 0.015, 0.035, 0.075])
    bd = np.array([0.03, 0.034, 0.028, 0.038, 0.05, 0.07])
    ba = np.array([1.0, 0.8, 0.85, 0.7, 0.9, 1.0]) * rng().uniform(0.85, 1.1, 6) * np.array([1, -1, 1, 1, -1, 1])
    great = strokes(n, bt, bd, ba, 0.0015)
    # (the land's face giving under the knuckles: many shorter strokes in the first 80 ms, the body's 80-800 Hz)
    k = 48
    mt = t0 + 0.08 * rng().uniform(0, 1, k) ** 1.5
    mid = strokes(n, mt, rng().uniform(0.005, 0.022, k), (rng().pareto(2.0, k) + 1) * rng().choice((-1.0, 1.0), k), 0.0009)
    great = band(great, 12, 2400, 2) + band(mid, 50, 2400, 2) / (np.abs(band(mid, 50, 2400, 2)).max() + 1e-12) * np.abs(great).max() * 0.55
    # (the land breaking under it)
    rate = (40000.0 * np.exp(-u / 0.15) + 12000.0 * np.exp(-u / 0.9)) * clumps(n, 3.0, 5.0) * on
    land = crackle(n, rate, 55, 2600, 18, 2.4, 1.2)
    land = land * (1 - np.exp(-u / 0.004)) * on
    land = lowpass_track(land, 650.0 + 1900.0 * np.exp(-u / 0.15)) * curve(t, [(0.0, 0), (t0 + 0.3, 0), (t0 + 0.8, -2), (t0 + 1.5, -7), (2.0, -12)])
    # (the air driven out over the land)
    air = crackle(n, 30000.0 * on * clumps(n, 2.0, 3.0), 35, 1200, 14, 3.5, 1.4)
    air = air * curve(t, [(0.0, -80), (t0, -40), (t0 + 0.06, 0), (t0 + 0.35, -0.5), (t0 + 0.9, -2.5), (t0 + 1.5, -8), (2.0, -16)])
    # (the ground's heave)
    heavep = shove(n, t0 + 0.002, 0.32, 1.0) + band(strokes(n, [t0 + 0.01], [0.18], [1.0], 0.01), 10, 60, 2) * 0.6
    x = unit(great) * 1.0 + land * 0.85 + air * 0.6
    x = x + heavep * np.abs(x).max() * 0.6
    # (given back by the land round it and the crater's walls)
    # (nothing under ~22 Hz, taken out before the overload: unheard, and a highpass after it would only throw its
    # peaks back up)
    x = causal_hp(x, 22.0, 2)
    # (the overload on all but the sub: its weight kept whole and clean under the driven body)
    lows = band(x, None, 60.0, 2)
    hi_ = overload(x - lows, 4.5, 0.1)
    hi_ = hi_ - band(hi_, None, 20.0, 2)
    w0 = slice(nsm(t0), nsm(t0 + 0.3))
    x = hi_ + lows / (np.sqrt(np.mean(lows[w0] ** 2)) + 1e-12) * np.sqrt(np.mean(hi_[w0] ** 2)) * 0.8
    # (the overload's own top off its front: no click over the blow)
    x = band(x, None, 4500.0, 2)
    return space(x, 0.45, length=3.0, t60=(3.0, 2.2, 0.8), seed=194)


def smash():
    """The hand slamming the land (SMASH_AT in), the climax: round 6's blow (`smash_blow`) for its first ~1.3 s, then,
    joined over 1.15-1.45 s, round 5's sound as it was, at the level it was written at (the land breaking and rolling
    it round, and from LIFT_AT the fist pulled up out of the land: Kyle passed that part)."""
    d = 10.0
    n = nsm(d)
    t = np.arange(n) / SR
    old = smash_r5()
    with seeded(SEEDS["smash"] + 6000):
        blow = smash_blow(n, t)
    db, crest = -5.5, 1.6
    c = crest * 10 ** (db / 20)

    def gain(x):
        """The gain write() will give `x` (its loudest 400 ms at `db` once its peaks are rounded off at `crest`)."""
        y = x - x.mean()
        y = causal_hp(band(y, None, 15000.0, 4), 14.0, 2)
        g = 10 ** (db / 20) / (loud(y) + 1e-12)
        for _ in range(8):
            err = 10 ** (db / 20) / (loud(soft_clip(y * g, c, 0.7)) + 1e-12)
            g *= err
            if abs(20 * np.log10(err)) < 0.05:
                break
        return g
    g5 = gain(old)
    blow = blow / (loud(blow[:nsm(1.0)]) + 1e-12) * loud(old[:nsm(1.0)])
    a, b = nsm(1.15), nsm(1.45)
    m = nsm(0.1)
    w = np.zeros(n)
    w[a:b] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, b - a))
    w[b:] = 1.0
    k = 1.0
    for _ in range(4):
        o = old * k
        g_join = np.sqrt(np.mean(o[a:a + m] ** 2)) / (np.sqrt(np.mean(blow[a:a + m] ** 2)) + 1e-12)
        bl = blow * curve(t, [(0.0, 0.0), (0.7, 0.0), (1.15, 20 * np.log10(g_join)), (d, 20 * np.log10(g_join))])
        x = bl * np.sqrt(1 - w) + o * np.sqrt(w)
        # (round 5's part as loud in the file as it was: write() levels the whole by the blow)
        k *= g5 / (gain(x) * k)
    write("smash", x, db=db, fade_out=1.2, crest=crest)


def smash_far():
    """`smash` from beyond ~350 blocks: through the air, the top gone, the front softened, the land rolling it on."""
    x = decoded("smash")
    if x is None:
        raise SystemExit("smash is not built yet: build it before smash_far")
    write("smash_far", through_air(x, 12.0, 200, 0.35), db=-7.5, fade_out=1.2, crest=1.6)


# ---- the shudder's glass (round 8: real glass) -------------------------------------------------------------------------
# Synthesised glass missed three times (round 5 a bong, round 6 "sounds like plastic", round 7 "doesn't sound like
# glass"), so the shudder's glass is now real glass: slices of four CC0 recordings (tools/sound_sources/skybreak, see its
# README): a glass splash shield smashed by a hammer (full band, the best), a run of window breaks (an old library
# recording, band-limited to ~7.5 kHz but dense), a car's tempered window (bright) and a large pane (dull, its body).
# Each slice starts 4 ms before its break's onset (found from the 1 ms envelope; the 2 ms fade-in is over the room's
# floor, never over the crack) and is faded out where its dense crash ends, before the pieces start to land one by one
# (measured from the 10-20 ms envelopes: the hammer break dense for ~0.55 s, then single pieces from ~0.75 s; the
# windows dense for 0.7-1.5 s and then gone; the car's two breaks dense ~0.34 s and ~0.22 s). Seven sheets, each a
# different layering of slices, each a little different in level and delay and at most 2 semitones off (higher or
# lower; never slowed further than that: slowed glass stops being glass). Mono, as the game plays it. Nothing of the
# glass is synthesised; what is synthesised sits under it: each sheet's dull body and the sub (as round 7's, take C the
# lighter body, take D the heavier and longer), the air of the sheets falling, and the sky giving it all back, darker
# than the dry glass. The glitter far up later is real glass too: short dense slices, quiet and far.
SHUDDER_TAKE = os.environ.get("SB_SHUDDER_TAKE", "D")
SHUDDER_HEARD = -14.2           # (its loudest 400 ms, K-weighted, dB: as round 7 was heard)
GLASS_DIR = ROOT / "tools" / "sound_sources" / "skybreak"
# (each break: its file, its onset (s), how long its dense crash lasts before the pieces land one by one (s), and the
# fade over its end (s))
BREAKS = {
    "hammer": ("glass_hammer_721363.mp3", 5.7786, 0.50, 0.15),
    "win1": ("glass_windows_487138.mp3", 0.1128, 0.8, 0.25),
    "win2": ("glass_windows_487138.mp3", 3.9576, 0.8, 0.25),
    "win3": ("glass_windows_487138.mp3", 7.6627, 0.60, 0.15),
    "win4": ("glass_windows_487138.mp3", 9.3847, 0.8, 0.25),
    "car2": ("glass_car_587928.mp3", 0.5658, 0.17, 0.07),
    "pane": ("glass_pane_675853.mp3", 0.0449, 0.70, 0.25),
}
# (the seven sheets: each (break, dB, delay s, semitones) layers: a bright break leading (the hammer's or the car's,
# full band) and the windows' mass well under it (their recording is band-limited and a little tonal: more of it
# would darken the glass), the first the biggest with the pane's body too. The car's first break is not used: it
# carries rising whistles at 5-10 kHz (chirps) and a held line near 7 kHz)
SHEETS = [
    [("hammer", 0.0, 0.0, 0.0), ("win1", -9.0, 0.006, 0.0), ("pane", -10.0, 0.0, -1.0)],
    [("car2", -1.0, 0.0, -1.0), ("win2", -9.0, 0.011, 1.0)],
    [("hammer", -2.0, 0.0, 2.0), ("win3", -9.0, 0.004, -2.0)],
    [("hammer", -1.0, 0.0, 1.5), ("win4", -10.0, 0.009, -1.0)],
    [("car2", -2.0, 0.0, -2.0), ("win4", -9.0, 0.006, 1.0)],
    [("car2", -2.0, 0.0, 1.5), ("win2", -11.0, 0.002, -1.5)],
    [("hammer", -2.0, 0.0, -2.0), ("win1", -10.0, 0.007, 1.0)],
]
_SLICES = {}


def glass_slice(name, semis=0.0):
    """One break's slice from its recording: from 4 ms before its onset to the end of its dense crash, faded there,
    its loudest 100 ms at 1 (RMS); `semis` its pitch moved by changing its speed. Mono."""
    key = (name, semis)
    if key not in _SLICES:
        f, on, dense, fade = BREAKS[name]
        x = decode(GLASS_DIR / f)
        a = nsm(on - 0.004)
        y = x[a:a + nsm(0.004 + dense + fade)].copy()
        k = nsm(0.002)
        y[:k] *= np.linspace(0, 1, k)
        m = nsm(fade)
        y[-m:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, m))
        y = y - y.mean()
        if abs(semis) > 1e-6:
            r = 2 ** (semis / 12)
            y = np.interp(np.arange(int(len(y) / r)) * r, np.arange(len(y)), y)
        w = nsm(0.1)
        c = np.concatenate([[0.0], np.cumsum(y * y)])
        y = y / (np.sqrt(np.max(c[w:] - c[:-w]) / w) + 1e-12)
        _SLICES[key] = y
    return _SLICES[key]


def cband(x, lo, hi, order=2):
    """`x` through a band that only looks back: nothing of a blow sounds ahead of it."""
    return sosfilt(butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x)


def sheet_body(n, t0, size, ref, body_db=0.0, body_len=1.0):
    """The thick sheet's dull body under its glass (synthesised, under the real glass): a long pressure stroke and a
    low crackle; the size of the break is here, not in the glass."""
    tt = np.arange(n) / SR
    uu = np.maximum(tt - t0, 0)
    bl = body_len
    body = strokes(n, [t0, t0 + 0.012 * rng().uniform()], [(0.05 + 0.03 * size) * bl, 0.04 * bl], [1.0, -0.6], 0.002)
    body = cband(body, 18, 420, 2)
    cr = crackle(n, 20000.0 * np.exp(-uu / (0.06 * bl)) * (tt >= t0), 35, 480, 10, 2.8) * np.exp(-uu / (0.14 * bl)) * (tt >= t0)
    b = unit(body) * np.exp(-uu / (0.25 * bl)) + cr * 0.6
    return b / (np.sqrt(np.mean(b[nsm(t0):nsm(t0 + 0.3)] ** 2)) + 1e-12) * ref * 0.45 * 10 ** (body_db / 20)


def shudder():
    """The slam's shudder up through the sky's glass (SHUDDER_AT in): the last ring of the middle letting go piece by
    piece, its inner edge first, over 0.85 s (skybreak.rs's SB_KNOCK), each piece of the sky a sheet of real glass
    breaking (see the notes over BREAKS), the first the biggest; under it each sheet's dull body and the sub, the air of
    the sheets falling away, the glitter far up as they burst (2.4-3.7 s later), and the sky giving it all back.
    SHUDDER_TAKE "C" or "D" (env SB_SHUDDER_TAKE): D the heavier, longer body and the bigger space."""
    d = 7.0
    n = nsm(d)
    t = np.arange(n) / SR
    t0 = SHUDDER_AT
    heavy = SHUDDER_TAKE == "D"
    gaps = rng().uniform(0.07, 0.2, 6)
    rel = t0 + np.concatenate([[0.0], np.cumsum(gaps * 0.85 / max(gaps.sum(), 0.85))])
    szs = np.concatenate([[1.0], rng().uniform(0.55, 0.85, 6)])
    glass = np.zeros(n)
    for tr, s, layers in zip(rel, szs, SHEETS):
        for name, db, dly, semis in layers:
            put(glass, glass_slice(name, semis) * s * 10 ** (db / 20), tr + dly - 0.004)
    ref = np.sqrt(np.mean(glass[nsm(t0):nsm(t0 + 0.3)] ** 2)) + 1e-12
    low = np.zeros(n)
    for tr, s in zip(rel, szs):
        low = low + sheet_body(n, tr, s, ref, body_db=0.0 if heavy else -3.0, body_len=1.8 if heavy else 1.0) * s
    sub = cband(strokes(n, [t0 + 0.005], [0.22 if heavy else 0.14], [1.0], 0.01), 14, 90, 2)
    low = low + sub / (np.abs(sub).max() + 1e-12) * ref * (1.0 if heavy else 0.6)
    # (the glitter far up: short dense slices of real glass, quiet, dark and far)
    gl = np.zeros(n)
    for k, (tr, s) in enumerate(zip(rel, szs)):
        name = ("hammer", "car2", "win3", "win4")[k % 4]
        put(gl, glass_slice(name, (-1.0, 1.0, 0.5, -0.5)[k % 4]) * s * rng().uniform(0.6, 1.0), tr + rng().uniform(*GLITTER))
    gl = band(gl, None, 5000.0, 1)
    gl = gl + verb(gl, 2.5, (1.8, 1.3, 0.7), 244, build=0.05, lo=None) * 0.8
    x = glass + low + gl / (loud(gl) + 1e-12) * loud(glass) * 10 ** (-24 / 20)
    x = x + roar(n, SKY, curve(t, [(0.0, -60), (t0 + 0.3, -18), (1.5, -13), (3.0, -22), (4.5, -40), (d, -60)]), boil=4.0) * ref * (0.45 if heavy else 0.3)
    # (the sky giving it back: darker than the dry glass, as distance makes it; it carries the tail)
    if heavy:
        x = x + band(verb(x, 5.0, (4.5, 3.0, 1.2), 245, build=0.06, lo=None), None, 6000.0, 1) * 0.5
    else:
        x = x + band(verb(x, 3.5, (3.0, 2.0, 0.9), 245, build=0.04, lo=None), None, 7000.0, 1) * 0.4
    # (levelled by what is heard, K-weighted; the sharpest peaks rounded off sample by sample, a crest of ~13 dB kept)
    x = soft_clip(x, 4.5 * loud(x), 0.6)
    x = x * 10 ** (SHUDDER_HEARD / 20) / (loud(k_weighted(x)) + 1e-12)
    # (written as it stands: its peak taken after write()'s own band and low cut, so nothing rescales it)
    y = causal_hp(band(x - x.mean(), None, 17000.0, 4), 14.0, 2)
    write("shudder", x, peak_db=20 * np.log10(np.abs(y).max()), fade_out=0.8, top=17000.0)


BUILD = {"tear": tear, "tear_far": tear_far, "rise": rise, "sink": sink, "ripple": ripple, "pressure": pressure, "crack": crack_main,
         "withdraw": withdraw, "strain": strain, "collapse": collapse, "release": lambda: release_take(1), "release2": lambda: release_take(2),
         "fall": fall, "ground": ground, "impact": lambda: impact_take(1), "impact2": lambda: impact_take(2), "impact3": lambda: impact_take(3),
         "impact_far": impact_far, "void": void, "rumble": rumble, "heal": heal, "gaze": gaze, "slam": slam, "flare": flare, "descend": descend,
         "shudder": shudder}
SEEDS = {name: 7600 + i for i, name in enumerate(NAMES)}
# (built from another's file: after it)
AFTER = {"tear_far": "tear", "impact_far": "impact"}


def build_one(name):
    with seeded(SEEDS[name]):
        BUILD[name]()


# ===========================================================================================================  listening
def far_mix(dist):
    u = np.clip((dist - 350.0) / 650.0, 0, 1)
    return float(u * u * (3 - 2 * u))


# (seed 37's panes for a player `dp` blocks south of the target (0.5 65 0.5), as strike/skybreak.rs lays them out (its
# ignored `sb_write_table` prints them): when each breaks free and lands in round 3's time (LEAD later now), where)
PANES = {
    30: [(8.01, 13.33, (-163.0, -164.0)), (9.34, 15.00, (247.0, 3.0)), (11.02, 16.56, (-198.0, 171.0)), (12.22, 17.74, (123.0, -177.0)), (13.83, 19.59, (-43.0, -192.0))],
    300: [(8.01, 13.33, (-43.0, -192.0)), (9.34, 15.00, (123.0, -177.0)), (11.02, 16.56, (-163.0, -164.0)), (12.22, 17.74, (-99.0, -55.0)),
          (13.83, 19.59, (185.0, 61.0)), (15.15, 20.72, (-122.0, 101.0)), (16.58, 21.90, (30.0, 97.0))],
    800: [(8.01, 13.33, (-43.0, -192.0)), (9.34, 15.00, (123.0, -177.0)), (11.02, 16.56, (-163.0, -164.0)), (12.22, 17.74, (-99.0, -55.0)),
          (13.83, 19.59, (185.0, 61.0)), (15.15, 20.72, (-122.0, 101.0)), (16.58, 21.90, (46.0, 168.0))],
}


def pane_schedule(dp):
    """The panes' own sounds (skybreak.rs's sb_pane_events), round 3's times LEAD later, for a player `dp` blocks south."""
    me = (0.0, float(dp))
    sky_late = min(np.hypot(560.0, dp) / SPEED, 1.2)
    ev = []
    for i, (tr, hit, (x, z)) in enumerate(PANES[dp]):
        tr, hit = tr + LEAD, hit + LEAD
        dist = float(np.hypot(x - me[0], z - me[1]))
        late = dist / SPEED
        pitch = 0.92 + 0.16 * ((i * 0.37) % 1.0)
        ev.append(("release" if i % 2 == 0 else "release2", tr - 1.3 - 0.2 + sky_late * 0.4, pitch, 1.0))
        ev.append(("fall", hit - FALL_CUT, 1.0, 0.55 + 0.45 * min(1.0 / (1.0 + dist / 500.0), 1.0)))
        tg = hit + dist / GROUND_V
        gap = hit + late - tg
        gv = float(np.clip(1.0 / (1.0 + dist / 900.0), 0.3, 1.0) * np.clip((gap - 0.05) / 0.9, 0.25, 1.0) ** 1.5)
        ev.append(("ground", tg - 0.02, 1.0, gv))
        far = far_mix(dist)
        ev.append((["impact", "impact2", "impact3"][i % 3], hit + late - 0.02, pitch, 1.0 - far))
        ev.append(("impact_far", hit + late - 0.02, pitch, far))
        ev.append(("slam", hit + SLAM + late - 0.01, pitch, 0.6 * (1.0 - 0.6 * far)))
    return ev


def cue_schedule(dp, tl_dir):
    """The strike's own cues as sb_sounds.rs plays them for a player `dp` blocks south (its ignored `sb_write_cues`), the
    panes' hits given in round 4's time (the rumble follows the last before the flare)."""
    hits = ",".join(f"{h + LEAD:.3f}" for _, h, _ in PANES[dp])
    out = Path(tl_dir) / f"cues_{dp}.txt"
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "sb_write_cues", "--", "--ignored"], cwd=ROOT / "mod",
                   env=dict(os.environ, SB_ME=str(dp), SB_HITS=hits, SB_OUT=str(out.resolve())), check=True, capture_output=True)
    ev = []
    for line in out.read_text().splitlines():
        t, event, vol, pitch = line.split()
        laser, name = event.split(":", 1)[1].split(".", 1)
        # (another laser's file, as the slam plays the Payload's: its path from this laser's folder)
        ev.append((name if laser == TH else f"../{laser}/{name}", float(t), float(pitch), float(vol)))
    return ev


def schedule(dp, tl_dir):
    return [e for e in cue_schedule(dp, tl_dir) + pane_schedule(dp) if e[3] > 0.001]


def game_limiter(mix, block=512, release=0.2):
    """The game's output limiter (its audio callback): a block whose peak is over 1 is scaled down, the gain coming
    back over `release` s. In place; returns the seconds held down."""
    lp, rel = 1.0, np.exp(-1 / (release * SR))
    held = 0
    for s0 in range(0, len(mix), block):
        blk = mix[s0:s0 + block]
        pk = max(1.0, float(np.abs(blk).max()))
        held += pk > 1.0
        lp = max(lp, pk)
        k = np.arange(len(blk))
        blk *= 1 / np.maximum(lp * rel ** k, pk)
        lp = max(lp * rel ** len(blk), pk)
    return held * block / SR


def game_mix(ev, end=60.0):
    """`ev` (file, start, pitch, volume) mixed as the game does: each file summed to mono, 0.596 to the listener, its pitch a
    change of speed, on its tick; then the output limiter. (the mix, its peak before the limiter, seconds held down)."""
    clips = {}
    out = np.zeros(nsm(end))
    tick = lambda t: np.ceil(float(t) * 20 - 1e-6) / 20
    for f, at, p, v in ev:
        if f not in clips:
            clips[f] = decoded(f)
        c = clips[f]
        if abs(p - 1.0) > 1e-4:
            m = int(len(c) / p)
            c = np.interp(np.arange(m) * p, np.arange(len(c)), c)
        k = nsm(tick(at))
        m = min(len(c), len(out) - k)
        if m > 0:
            out[k:k + m] += c[:m] * min(v, 1.0) * 0.596
    pre = 20 * np.log10(np.abs(out).max() + 1e-12)
    held = game_limiter(out)
    return out, pre, held


def mp3(x, path):
    wav = str(path) + ".wav"
    write_wav(wav, x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-b:a", "192k", str(path) + ".mp3"], check=True)
    return wav


def spectrogram(wav, png, w=1800):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-lavfi",
                    f"aformat=channel_layouts=mono,showspectrumpic=s={w}x520:legend=1:fscale=log:scale=log:start=15:stop=12000:drange=90:color=magma",
                    str(png)], check=True)


def measure(path):
    """(integrated LUFS, true peak dBTP) by ffmpeg's ebur128."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    tail = r[r.rfind("Summary:"):]

    def grab(key):
        i = tail.find(key)
        return float(tail[i:].split(":")[1].split()[0]) if i >= 0 else float("nan")
    return grab("I:"), grab("Peak:")


def k_weighted(x):
    """`x` through BS.1770's K-weighting: what loudness meters hear, so a sub doesn't read as loud as the body it carries."""
    b1, a1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585]
    b2, a2 = [1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]
    return lfilter(b2, a2, lfilter(b1, a1, x))


def rms_db(x, w=0.1, hop=0.05):
    w_, h = nsm(w), nsm(hop)
    c = np.concatenate([[0.0], np.cumsum(x ** 2)])
    a = np.arange(0, max(len(x) - w_, 1), h)
    return 10 * np.log10((c[a + w_] - c[a]) / w_ + 1e-14)


def shares(x):
    """How the energy of `x` lies: under 80 Hz, 100-800 Hz, over 1.5 kHz."""
    p = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return tuple(float(p[w].sum() / p.sum()) for w in (f < 80, (f >= 100) & (f < 800), f >= 1500))


def flicker(x, lo=150.0, hi=2000.0):
    """The banned fast gain as a number: how much the level of `x`'s mids moves at 18-70 Hz, against its level (a grainy
    roar reads about 0.4, a smooth boiling one about 0.25)."""
    e = band(np.abs(band(x, lo, hi, 3)), None, 160.0, 2)[::SR // 800]
    m = sosfilt(butter(3, [18.0, 70.0], "band", fs=SR / (SR // 800), output="sos"), e)
    return float(np.std(m) / (np.mean(e) + 1e-12))


def snare(x, at=0.0):
    """What the front of a hit at `at` s has of a snare: how long its 150-1000 Hz stays within 12 dB of its top (s; a
    snare's is under 0.1), and the share of its first 40 ms over 1.5 kHz."""
    i = nsm(at)
    m = band(x[i:i + nsm(2.0)], 150.0, 1000.0, 3)
    w = nsm(0.02)
    r = np.array([np.sqrt(np.mean(m[k:k + w] ** 2)) for k in range(0, len(m) - w, w)])
    top = int(np.argmax(r))
    below = np.nonzero(r[top:] < r[top] * 10 ** (-12 / 20))[0]
    return float((below[0] if len(below) else len(r) - top) * 0.02), shares(x[i:i + nsm(0.04)])[2]


def stem_report(name, x, hit=None):
    sh = shares(x)
    s = f"{name:10s} {len(x) / SR:5.2f}s  loudest400 {20 * np.log10(loud(x) + 1e-12):6.1f}  peak {20 * np.log10(np.abs(x).max() + 1e-12):6.1f}  " \
        f"<80 {sh[0] * 100:4.1f}%  100-800 {sh[1] * 100:4.1f}%  >1.5k {sh[2] * 100:4.1f}%  flicker {flicker(x):.2f}"
    if hit is not None:
        sn, top = snare(x, hit)
        s += f"  hit at {hit:.2f}: 150-1000 held {sn:.2f}s, >1.5k in 40 ms {top * 100:.1f}%"
    return s


# (where each stem's blow is, for the snare check)
HITS = {"tear": TEAR_AT, "sink": SINK_AT, "ripple": RIPPLE_AT, "crack": CRACK_AT, "gaze": GAZE_HIT, "flare": FLARE_AT, "smash": SMASH_AT,
        "collapse": COLLAPSE_AT, "release": RELEASE_FREE, "release2": RELEASE_FREE, "impact": IMP_LEAD, "impact2": IMP_LEAD, "impact3": IMP_LEAD,
        "slam": IMP_LEAD, "shudder": SHUDDER_AT}
# (the moments to read the mixes at)
MOMENTS = [("tear", 0.0, 1.0), ("rise", 1.0, 4.2), ("sink", 4.2, 5.4), ("ripple", 5.4, 7.0), ("bow", 7.0, 9.0), ("crack", 9.0, 10.0),
           ("withdraw", 10.0, 12.0), ("slide", 12.0, 14.5), ("open", 14.5, 19.5), ("lock", 19.5, 21.0), ("panes", 21.0, 31.5),
           ("lull", 31.5, 40.1), ("gather", 40.1, 42.1), ("flare", 42.1, 43.0), ("down", 43.0, 44.5), ("slam", 44.5, 47.0),
           ("after", 47.0, 53.0), ("heal", 53.0, 57.5)]


def listen(out):
    d = Path(out)
    d.mkdir(parents=True, exist_ok=True)
    lines = []

    def say(s):
        print(s, flush=True)
        lines.append(s)
    say("== the stems (each file as the game decodes it, before its 0.596)")
    for name in NAMES:
        x = decoded(name)
        if x is None:
            continue
        wav = mp3(x, d / name)
        spectrogram(wav, d / f"spec_{name}.png", 1200)
        os.remove(wav)
        say(stem_report(name, x, HITS.get(name)))
    for dp in (30, 300, 800):
        ev = schedule(dp, d)
        m, pre, held = game_mix(ev)
        wav = mp3(m, d / f"mix_{dp}")
        spectrogram(wav, d / f"spec_mix_{dp}.png")
        lufs, tp = measure(wav)
        os.remove(wav)
        if dp in (30, 300):
            c = m[nsm(4.0):nsm(12.5)]
            wc = mp3(c, d / f"crack_in_context_{dp}")
            spectrogram(wc, d / f"spec_crack_in_context_{dp}.png", 1400)
            os.remove(wc)
        r = rms_db(m)
        k = rms_db(k_weighted(m), 0.4, 0.05) - 0.691 + 3.01     # (momentary loudness, LUFS, of the mono sum as both ears)
        say(f"\n== the whole strike from {dp} blocks (mix_{dp}.mp3): {lufs:.1f} LUFS, true peak {tp:.1f} dBTP, peak before the game's limiter "
            f"{pre:.1f} dBFS ({held:.1f} s held down)")
        say("   loudest 100 ms each second, dBFS: " + " ".join(f"{r[int(s * 20):int((s + 1) * 20)].max():.0f}" for s in range(0, 58)))
        say("   momentary loudness each second, LUFS (loudest 400 ms): " + " ".join(f"{k[int(s * 20):int((s + 1) * 20)].max():.0f}" for s in range(0, 58)))
        for nm, a, b in MOMENTS:
            seg, sk = r[int(a * 20):int(b * 20)], k[int(a * 20):int(b * 20)]
            say(f"   {nm:9s} {a:5.1f}-{b:5.1f}  loudest {seg.max():6.1f}  quietest {seg.min():6.1f} dB;  {sk.max():6.1f} to {sk.min():6.1f} LUFS")
        fall = lambda y: float(np.max(np.maximum.accumulate(y) - y))
        b0, kb = r[int(5.4 * 20):int(9.0 * 20)], k[int(5.4 * 20):int(8.6 * 20)]
        say(f"   5.4-9.0 (into the crack): biggest fall from the loudest so far {fall(b0):.1f} dB ({fall(kb):.1f} LU); the last 400 ms "
            f"{k[int(8.6 * 20)]:.1f} LUFS, the crack's first {k[int(9.0 * 20)]:.1f}")
        q0 = k[0:int(9.0 * 20)]
        say(f"   0-9.0: quietest momentary loudness {q0.min():.1f} LUFS at {q0.argmin() * 0.05:.2f} s (never quiet before the crack)")
        s4 = k[int(4.0 * 20):int(12.5 * 20)]
        say(f"   4.0-12.5: loudest {s4.max():.1f} LUFS at {4.0 + s4.argmax() * 0.05:.2f} s (the crack's stretch); loudest 100 ms "
            f"{r[int(4.0 * 20):int(12.5 * 20)].max():.1f} dB at {4.0 + r[int(4.0 * 20):int(12.5 * 20)].argmax() * 0.05:.2f} s")
        a0, ka = r[int(40.1 * 20):int(42.1 * 20)], k[int(40.1 * 20):int(41.7 * 20)]
        say(f"   40.1-42.1 (into the flare): biggest fall {fall(a0):.1f} dB ({fall(ka):.1f} LU)")
        sl = SLAM_T + dp / SPEED
        say(f"   the smash arrives {sl:.2f} s: the 400 ms before it {k[int((sl - 0.4) * 20)]:.1f} LUFS, its first {k[int(sl * 20)]:.1f}; the loudest moment "
            f"of the strike {k.max():.1f} LUFS at {k.argmax() * 0.05:.1f} s")
    (d / "levels.txt").write_text("\n".join(lines) + "\n")


def write_events(path):
    """The skybreak.* events in sounds.json: the existing file read and written back as it was, with only the skybreak.*
    entries replaced or, the first time, added at its end. Every other entry untouched."""
    sounds = json.loads(path.read_text())
    new = {}
    for name in NAMES:
        new[f"{TH}.{name}"] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{TH}.{name}"}
    out = {}
    placed = False
    for k, v in sounds.items():
        if k.startswith(f"{TH}."):
            if not placed:
                out.update(new)
                placed = True
        else:
            out[k] = v
    if not placed:
        out.update(new)
    path.write_text(json.dumps(out, indent=2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also MP3s of the stems, the crack in context and the whole strike as the game mixes it from 30, 300 and 800 "
                                     "blocks here, with spectrograms and levels.txt")
    ap.add_argument("--jobs", type=int, default=6, help="sounds built at once (each has its own seed: the result is the same)")
    a = ap.parse_args()
    soundlib.init(a.out)
    todo = list(a.only if a.only is not None else NAMES)
    first = [nm for nm in todo if nm not in AFTER]
    if a.jobs > 1 and len(first) > 1:
        import multiprocessing as mp
        with mp.get_context("fork").Pool(a.jobs) as pool:
            pool.map(build_one, first, chunksize=1)
    else:
        for name in first:
            build_one(name)
    for name in todo:
        if name in AFTER:
            build_one(name)
    if a.only is None:
        path = Path(a.out) / "assets" / "orbital" / "sounds.json"
        if path.exists():
            write_events(path)
        for name in GONE:
            f = Path(a.out) / "assets" / "orbital" / "sounds" / TH / f"{name}.ogg"
            if f.exists():
                f.unlink()
    if a.listen:
        listen(a.listen)


if __name__ == "__main__":
    main()
