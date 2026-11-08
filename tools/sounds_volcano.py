"""The Supervolcano's sounds, synthesised here from noise, pulses and filters, but for the eruption's `boom` (the Nuke's
and the Payload's ALT blasts, slowed), the trees' (the Hurricane's breaks) and the lightning's (the Hurricane's thunder
files made louder). Every file is mono: Horizon sums each sound file to mono anyway, so a stereo tail would only cost
size.

Timeline, as mod/src/strike/vc_sound.rs plays them (strike seconds; `late` = the player's distance from the vent / 343,
2.9 s at the 1,000 blocks that is the least it fires at, 5 s at 1,700):

  sat_sky     0        the satellite, 7,000 up and ~70 degrees over the player, on the strike's clock: it comes down into
                       view (0-3.4), the targeting beam comes on (3.3) and locks (4), the shot (4.5), the cut (7.1), it
                       lifts away (8.6), gone by 12. The sky sings: a vast low horn (G1) falling into its pitch as it
                       comes, a second voice beating slowly beside it from the aim and pulled into one at the lock; the
                       shot the braam (the octave under, the fifth and the octave over, driven until it growls, a sub blow
                       under it), held as it burns, sagging a whole tone at the cut (Inception's horns; the Fold's swell)
  sat_land    4.5+late the shot's blow on the land at the vent (when it's over by 17 s): a blow and the note coming back off
                       the land
  tremor      4.5      the mount (4.5-17 s): under hearing, then the ground rolling, a heavy groan of rock under load rising
                       with it, the land's lurches baked in where the picture has them (`mount_height`, late by what the
                       ground takes to carry them), each bigger and sooner than the last; 12.5 s long and it stops dead on
                       the file's last sample, at 17 s, as the picture does: played on the strike's clock, not late
  crack1-4    6-14.5   a crack deep in the land, come through the ground: it runs, a few dull blows, then the ground
                       ringing on, long and dark; nothing of the air in it but crack4's slight snap at its start
  creak1-4    6-14     rock under strain under the player (only within ~900 blocks of the vent): a deep grinding pressure,
                       the stone crazing in dense dark crunches as the load climbs, a heavy dull lurch where it gives
  rockfall1-3 8.5-16.9 rock coming off the mount's flanks, a long way off: dark, sliding, no clatter
  fountain    7        the lava fountains, as far as they carry: a low chugging roar; stops dead at 17 s
  steam       6        the cracks' steam: a hiss (only within ~900 blocks); stops dead at 17 s
                       (every file above ends by 17 s, whatever the distance: the mount stops dead with the picture)
  hush        17       on the strike's clock, on the tremor's last sample: the busy rolling gone at once, in its place a
                       deep pressure swelling (a sub climbing, the rock's groan drawn on up, the ground straining) to its
                       height as the ground's answer comes, then easing back a little under it and the front; never
                       silent, nothing quick in it; cut by the report (a stopsound), long enough for one from 3,000 blocks
  seism       18 + d/1715 the burst through the ground, the Payload's `ground` made far heavier: a deep hard thump under
                       the feet with a punch in the low mids, the shear's bigger heave 0.4 s on with the ground shuddering,
                       the air all round shaken with it (a dark boom rolling off round the land), then the surface waves
                       rolling on under the feet in slow swells; cut by the report with the hush
  front1-4    ending on the report, from no sooner than the seism (the longest of 1.6, 2.3, 3.2, 4.5 s that fits): the
                       blast's front coming over the land, heard before it, all the land between booming up as the ground
                       carries the burst out: a deep roll rising, the pressure's sub climbing, a dark roar opening up from
                       the 400s to over a kilohertz and a half, the air ahead of the front rushing in its last half second,
                       its top drawn in for the last tenth under the sub, and the report slams in; the longer takes darker
  report      18 + late one enormous report, the Payload's blasts' big brother: its front a blow that slams (`impact`,
                       `slam`, the air sucked back after it: `gapped`), a deep boom falling from the 80s into the 20s
                       and lasting, the vent heaving behind it, a heavy roar holding for seconds, all of it overloading
                       the microphone (`overload`, `crunch`: the boom growls and breaks up); then the land rolling it
                       back for 20 s
  report_far  the same moment, cross-faded in by distance: darker, the growl kept in the low mids
  boom(_far)  the same moment, under the report: its weight, the Nuke's ALT blast slowed to 0.74 and the Payload's ALT
                       blast's front, holding loud some ten seconds (sampled from the mod's own files)
  report_sub  the same moment: the push alone, under it, the report's boom's fall and then a deep pressure holding for
                       seconds and fading slowly, 9 s (and at pitch 0.8 with the land dropping, in the collapse)
  plate_sub   a big plate coming down (vc_lodge.rs, pitched by its size): a short push of the sub
  column      18 + late behind the report the rolling wall of fire and the land going up (for 19-27 s), handing over to
                       the Plinian column (`plinian`): an enormous turbulent roar in uneven surges, each opening upward,
                       torn by its own waves steepened into shocks (`steepen`), the rock going up rattling in it; it
                       falters and drops at 32 s into the file, the collapse
  column_far  the same moment, cross-faded in by distance: the same column and its surges, darker, the tearing dull, the
                       rock a dark rattle, thunder-like rolls off the land after its big surges and at the falter
  whistle1-3  a bomb coming down close: a deep roaring rush climbing as it comes, the wake tearing ragged over it, the
                       rock's tumble slow and uneven, the air it shoves swelling under it; its distance sets its level, its
                       top, its Doppler and the comb off the ground; cut on its landing
  thud1-4     a bomb landing close (positional): a small explosion of earth on the ground's blow, its front slammed
  spatter1-3  the rock and earth it threw coming down round it, within ~120 blocks of the player (positional)
  thud_far1-3 a bomb landing off on the land: a dull thump, late by the distance
  lt_crack1-4, lt_clap1-4, lt_roll1-4, lt_rumble1-4  the lightning's thunder (vc_sound.rs's `thunder`): the Hurricane's
                       approved thunder files made louder, so they carry over the column from kilometres off
  collapse    50 + late a colossal deep groan of the ground going, the land mass dropping (a blow of the ground 3 s in,
                       `ground_blow`),
                       then the land going down in four waves, slabs landing in a rolling slide of rock (`falling`)
  collapse_far the same moment, cross-faded in by distance
  flow_rise1-3 ending on the flow's arrival: the ground first, a low roar, the rush, the wind ahead of it and last the
                       hiss, each take the same run to the hit, the longer ones only starting further back
  flow_far    the flow heard from beyond where it stops: a dark rush swelling and ebbing, no hit
  splinter1-3 trees going, the Hurricane's breaks in the flow's air, heard only with the front within ~140 blocks (positional)
  grind1-2    rock grinding along the front, the same
  flow_hit    the front reaching the player: a slammed blow, then a wall of wind and rock (an octave table, gusting),
                       low shoves, the top shutting down to nothing above a few hundred Hz
  flow_in1-3  inside the flow (14, 9 and 5 s): a dense muffled roar for 4 s, opening to the murk by 8.5 s (the pass's
                       near-black), ash hiss and embers; the shorter takes the same squeezed, for a wall that comes late
  after       66.3     a long fading rumble, far thunder in it, the wind thinning to a low empty moan, gone by 87.8 s
  patter      70.3     ash and small rock on blocks, a soft dry wash with grains tapping in it, thinning to nothing by 87.8 s

    python3 tools/sounds_volcano.py                 # writes orbital-sounds/assets/orbital/sounds/supervolcano/*.ogg and
                                                    # adds the events to sounds.json, every other sound left as it is
    python3 tools/sounds_volcano.py --only column   # one (report before report_far, collapse before collapse_far:
                                                    # each pair is built together)
    python3 tools/sounds_volcano.py --listen DIR    # and the whole strike heard from 1,000, 1,400 and 2,000 blocks and
                                                    # flown in to 800, as the game mixes it, with a spectrogram and levels of
                                                    # each, the hush's among them (`--only sat_sky` builds the
                                                    # satellite's two files)
"""
import argparse, json, os, subprocess, sys, wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, white, band
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P
import sounds_nuke as N
import sounds_storm as S
import sounds_sinkhole as H
import hu_foley as F

TH = "supervolcano"
ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {"lt_crack": 4, "lt_clap": 4, "lt_roll": 4, "lt_rumble": 4, "creak": 4, "crack": 4, "rockfall": 3, "whistle": 3, "thud": 4, "spatter": 3, "thud_far": 3, "front": 4,
            "flow_rise": 3, "flow_in": 3, "splinter": 3, "grind": 2}
SAT = ["sat_sky", "sat_land"]
SINGLE = SAT + ["tremor", "fountain", "steam", "hush", "seism", "report", "report_far", "boom", "boom_far", "report_sub", "plate_sub", "column", "column_far",
          "collapse", "collapse_far", "flow_far", "flow_hit", "after", "patter"]
NAMES = SINGLE + list(VARIANTS)
# (the plan's old events, taken out of sounds.json and their files deleted when it's rebuilt: the old opening's, the
# satellite's other takes, and the lightning's own bolts before it took the Hurricane's thunder)
GONE = ["tick", "beam", "fire"] + [f"sat{k}_{part}" for k in (1, 2, 3) for part in ("sky", "land")] + [f"bolt{v}" for v in range(1, 5)] + [f"bolt_far{v}" for v in range(1, 5)]
# Each file's loudest 400 ms (dB, as the game plays it before its 0.596). The report and the collapse the loudest moments
# by a long way; the column under them, so the climax has headroom.
LEVEL = {"lt_crack": -9.0, "lt_clap": -10.5, "lt_roll": -12.5, "lt_rumble": -12.5, "sat_sky": -8.0, "sat_land": -15.0, "tremor": -12.0, "fountain": -27.0, "rockfall": -22.0, "creak": -21.0, "crack": -17.0, "steam": -28.0,
         "hush": -15.5, "seism": -9.0, "front": -8.5, "report": -5.0, "report_far": -5.0, "boom": -4.5, "boom_far": -5.5, "report_sub": -10.0, "column": -13.0, "column_far": -12.0,
         "whistle": -16.0, "thud": -9.5, "spatter": -20.0, "thud_far": -18.0,
         "collapse": -7.0, "collapse_far": -7.5, "flow_rise": -12.0, "flow_far": -19.0, "flow_hit": -8.5, "flow_in": -13.0,
         "splinter": -19.0, "grind": -20.0, "after": -18.5, "patter": -28.0}
LEAD = 0.02                # (the report's and the hit's silence at the start of their files)
REPORT_SLAM = 2.0          # (the report's front laid on over its drive, dB against its loudest 400 ms: `slam`)
COLLAPSE_GIVE = 1.0        # (how far the collapse's groan comes down to make room for the drop's blow, dB)
SWELL, HUSH = 7.0, 17.0    # (volcano.rs's VC_SWELL, VC_HUSH: the mount starts to rise; it stops)
TREMOR_D = HUSH - 4.5      # (`tremor`, which starts at 4.5 s, ends on the hush: vc_sound.rs's plays it on the strike's clock)
GROUND_LAG = 0.6           # (the land's lurches, late by what the ground takes to bring them 1,000 blocks: GROUND_V)
FALTER = 32.0              # (the collapse, into `column`, which starts at 18 s: keep vc_sound.rs's beats in step)
DROP = 3.0                 # (the land mass dropping, into `collapse`)
COLUMN_D = 40.0
VC_CRACK_D = 2.2           # (crack's length: vc_sound.rs's VC_CRACK_LEN)
RISES = (6.0, 11.0, 17.0)  # (flow_rise's lengths: vc_sound.rs's VC_RISES)
INS = (14.0, 9.0, 5.0)     # (flow_in's lengths: vc_sound.rs's VC_INS)
ROCKFALLS = (3.2, 4.0, 4.8)  # (rockfall's lengths: vc_sound.rs's VC_ROCKFALLS)
AFTER_D, PATTER_D = 21.5, 17.5  # (`after`'s and `patter`'s lengths: each ends at 87.8 s, vc_sound.rs's VC_AFTER_AT, VC_PATTER_AT)
HUSH_D, SEISM_D = 12.0, 10.0    # (`hush`'s and `seism`'s lengths: both cut by the report, vc_sound.rs's VC_HUSH_LEN, VC_SEISM_LEN)
FRONTS = (1.6, 2.3, 3.2, 4.5)   # (front1-4's runs to the report: vc_sound.rs's VC_FRONTS)
FRONT_TAIL = 0.1                # (and what's left of each after it, going under the report's front: VC_FRONT_TAIL)
REPORT_SUB_D = 9.0         # (`report_sub`'s length: nothing cuts it, here or at the collapse, where it's played at 0.8)


def rng():
    return soundlib.rng


def n_of(d):
    return int(SR * d)


def times(d):
    return np.arange(n_of(d)) / SR


def db_curve(t, pts):
    """A gain over time from (time, dB) points, straight in dB."""
    return 10 ** (np.interp(t, [p[0] for p in pts], [p[1] for p in pts]) / 20)


def boil(n, lo, hi, db):
    return np.exp(db * PB.slow_random(n, lo, hi) / 8.686)


def db_of(x):
    return 10 ** (x / 20)


def ease(x, sec):
    """`x` smoothed over `sec` seconds, so a curve of straight lines has no corners."""
    w = max(n_of(sec), 1)
    c = np.concatenate([[0.0], np.cumsum(np.pad(x, (w, w), mode="edge"))])
    return ((c[w:] - c[:-w]) / w)[w // 2:w // 2 + len(x)]


def lows_heard(x, fc=70.0, hi=420.0, db=-5.0):
    """`x` with its lows' own harmonics (a driven copy of them, band-passed `fc`-`hi`) so a laptop implies the weight."""
    lo = band(x, None, fc * 1.2, 3)
    c = np.percentile(np.abs(lo), 99.0) * 0.35 + 1e-9
    h = band(np.tanh(lo / c) * c, fc, hi, 2)
    return x + h / (T.loudest(h) + 1e-9) * T.loudest(lo) * 10 ** (db / 20)


def conv(x, ir):
    m = len(x) + len(ir)
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)]


def land(x, length=4.0, wet=0.5, darken=(1800, 180), decay=1.6, density=35.0, seed=0):
    """`x` off the land round it: clumps of echoes, each later one duller."""
    return x + conv(x, T.outdoor_ir(length, seed, density=density, darken=darken, decay=decay)) * wet


def steepen(x, k):
    """`x` as it comes out of a jet: each point of the wave late by its own pressure (k seconds per unit, one value or a
    curve), the high-pressure parts running ahead of the low until the fronts stand up into shocks (Burgers' equation,
    the waveform kept single-valued, as a shock does). This is what supersonic jet noise's crackle is: the wave's own
    peaks turned into sudden jumps, the pressure rising at once and easing away, which is why it tears rather than
    hisses, and comes and goes with the turbulence."""
    t = np.arange(len(x)) / SR
    arrive = np.maximum.accumulate(t - k * x)
    return np.interp(t, arrive, x)


def skew_dt(x):
    """The skewness of a sound's rate of change: over ~0.4 is what's called crackle (Ffowcs Williams 1975)."""
    d = np.diff(x)
    return float(np.mean(d ** 3) / (np.mean(d ** 2) ** 1.5 + 1e-30))


def pulse_train(d, mean, spread, t0=0.0):
    """Times of uneven pulses `mean` s apart on average, `spread` the share of it that varies."""
    out = []
    t = t0
    k = 1 / spread ** 2
    while t < d:
        out.append(t)
        t += rng().gamma(k, mean / k)
    return np.array(out)


def write(name, x, knee=None, kind=None):
    S.write(name, x, LEVEL[kind or name], knee=knee)


# ======================================================================================  what the rebuilt sounds are made of
# Three things kept out of everything here, each of which is what made the first takes sound cheap:
#  - bare high ticks. Short bursts over 1.5 kHz with nothing under them, at random, heavy-tailed: that is what tin foil
#    crinkling is. A rock's blow has its body under it; what's fine enough to be a hiss is a hiss, dense, never countable.
#  - zero-phase filters on anything struck: `band` rings ahead of the hit, and nothing in nature does (`F.cband` looks back).
#  - one envelope on one band of noise. A real roar's level moves differently at every pitch (`eddies`).
def boiled(n, lo, hi, db, cap=1.6):
    """`boil`, its rare freak swell rounded off at `cap` times `db`: a roar has no one moment that stands out of it."""
    return np.exp(db * cap * np.tanh(PB.slow_random(n, lo, hi) / cap) / 8.686)


def eddies(d, f0, f1, per_oct=2.5, slope=-4.0, turns=14.0, depth=4.0, drive=None, lift=0.0, pivot=None):
    """Turbulence, unit RMS: bands of noise (`per_oct` an octave) from `f0` to `f1`, each boiling on its own at a rate that
    goes with its pitch, as eddies do (an eddy that makes a pitch lives about `turns` cycles of it): a slow heave at the
    bottom, a fine tearing at the top, so the sound is alive at every scale and no one envelope runs through it. `slope` dB
    an octave; `depth` dB of boil at `f0`, a third of it by `f1`, so the top never breaks up into ticks. `drive`, a curve
    round 1 (a surge), brightens as it swells: `lift` dB an octave round `pivot` for each 1 over."""
    n = n_of(d)
    k = max(int(np.log2(f1 / f0) * per_oct) + 1, 2)
    wide = 2 ** (0.62 / per_oct)
    y = np.zeros(n)
    for i in range(k):
        u = i / (k - 1)
        fc = f0 * (f1 / f0) ** u
        r = min(fc / turns, 420.0)
        g = boiled(n, r * 0.22, r, depth * (1 - 0.66 * u))
        b = T.unit(band(white(d), fc / wide, fc * wide, 2)) * g * 10 ** (slope * np.log2(fc / f0) / 20)
        if drive is not None and lift:
            b = b * 10 ** (lift * np.log2(fc / (pivot or np.sqrt(f0 * f1))) * (drive - 1) / 20)
        y += b
    return T.unit(y)


def rocks(d, rate, lo, hi, sizes=(0.25, 0.6, 1.3), share=(0.62, 0.3, 0.08), tail=1.9):
    """Rocks landing, unit RMS and dry: at `rate` a second (one value a sample, wandering as it likes), each a dull blow of
    earth and rock in `lo`-`hi` Hz with its body under it (`T.thud`, a handful of takes of each size), their strengths
    heavy-tailed. However thick they come it's a rattle of blows, nothing fine or bright on top."""
    n = n_of(d)
    at = np.nonzero(rng().random(n) < np.asarray(rate) / SR)[0]
    y = np.zeros(n)
    which = rng().choice(len(sizes), len(at), p=share)
    amp = np.minimum(rng().pareto(tail, len(at)) * 0.5 + 0.3, 5.0) * rng().choice([-1.0, 1.0], len(at))
    from scipy.signal import fftconvolve
    for c, size in enumerate(sizes):
        pick = at[which == c]
        take = rng().integers(0, 5, len(pick))
        a = amp[which == c]
        for k in range(5):
            train = np.zeros(n)
            np.add.at(train, pick[take == k], a[take == k])
            y += fftconvolve(train, T.thud(n_of(0.12 + 0.3 * size), size))[:n] * (0.55 + 0.45 * size)
    return T.unit(F.cband(y, lo, hi, 2))


def heaves(d, mean, spread, rise, fall, tail=0.55, t0=0.3):
    """Uneven surges: `pulse_train`'s times, strengths heavy-tailed, each swelling over `rise` and dying over `fall`, the
    curve averaging about 1 and never quite nothing."""
    n = n_of(d)
    at = pulse_train(d, mean, spread, t0)
    train = np.zeros(n)
    np.add.at(train, np.minimum((at * SR).astype(int), n - 1), np.minimum(np.exp(rng().normal(0, tail, len(at))), 4.0))
    s = np.arange(n_of(fall * 6)) / SR
    y = conv(train, (1 - np.exp(-s / rise)) * np.exp(-s / fall))
    return ease(y / (np.mean(y) + 1e-9), 0.03)


def earth_ring(x, length=2.0, wet=0.8, darken=(620, 60), decay=0.55, seed=0):
    """`x` as it comes on through the ground from a blow in rock: the blow, then the ground's own long dark ringing, thick
    with scattered arrivals, the top going first."""
    return x + conv(x, T.outdoor_ir(length, seed, density=160.0, darken=darken, decay=decay)) * wet


def impact(n, t0, sub=(72.0, 40.0, 30.0), drop=0.07, body=(45.0, 230.0), body_fall=0.07, crack=(350.0, 2400.0),
           crack_fall=0.012, mix=(1.0, 0.9, 0.3)):
    """The front of a big hit, what makes it slap: a sub blow falling in pitch (`sub` Hz: from, to in `drop` s, on to),
    rising in 2 ms, with its harmonics so a laptop hears its weight; a low-mid punch of noise (`body`, its decay
    `body_fall`), the chest's part of it; and a short crack of rock and air (`crack`, `crack_fall`), its top set by how
    far it has come. `mix` the three's levels. Causal, so nothing rings ahead of the hit."""
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    on = t >= t0
    k = S.blow(n, t0, sub[0], sub[1], sub[2], drop, 0.002, ((0.65, 0.09), (0.35, 0.3)), drive=2.5, octv=0.3, h3=0.12, harm=0.5)
    k = k / (np.abs(k).max() + 1e-9)
    b = T.unit(F.cband(rng().standard_normal(n), body[0], body[1], 2)) * (1 - np.exp(-u / 0.0015)) * np.exp(-u / body_fall) * on
    c = T.unit(F.cband(rng().standard_normal(n), crack[0], crack[1], 2)) * (1 - np.exp(-u / 0.0004)) * np.exp(-u / crack_fall) * on
    return k * mix[0] + b * 0.33 * mix[1] + c * 0.33 * mix[2]


def slam(x, t0, hit, db=1.0, duck=-4.0, gap=(0.05, 0.3, 0.7)):
    """`x` with `hit` (`impact`'s) laid on at `t0`, `db` against `x`'s loudest 400 ms, and `x` itself let down by `duck`
    dB just after the front (from `gap[0]`, deepest by `gap[1]`, back by `gap[2]` s), as a big blast's mids drop away
    after its crack: the front stands out of what follows, so it's a blow, not a loud noise starting."""
    t = np.arange(len(x)) / SR - t0
    g = db_curve(t, [(-1.0, 0.0), (gap[0], 0.0), (gap[1], duck), (gap[2], 0.0), (1e9, 0.0)])
    return x * g + hit / (T.loudest(hit) + 1e-12) * T.loudest(x) * 10 ** (db / 20)


def bare_blow(size, lo=26.0, hi=120.0, rise=0.012, fall=0.11):
    """A blow with no pitch in it (a sine is a kick drum): low noise rising in `rise`, dying over `fall` times `size`."""
    m = n_of(fall * size * 7 + 0.05)
    s = np.arange(m) / SR
    return T.unit(F.cband(rng().standard_normal(m), lo, hi, 2)) * (1 - np.exp(-s / rise)) * np.exp(-s / (fall * size))


# =====================================================================================================  sampled files
SOUNDS = ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds"
BOOM_D = 24.0              # (`boom`'s length: vc_sound.rs's VC_BOOM_LEN)
BOOM_SPEED = 0.74          # (the Nuke's ALT blast slowed to this: a fourth deeper and a third longer)
BOOM_FRONT_SPEED = 0.6     # (the Payload's ALT blast, for the front, slowed further)


def sampled(rel, speed=1.0):
    """One of the mod's own files (`rel` under its sounds), as the game plays it (summed to mono), at `speed` (the game's
    pitch: a change of speed)."""
    y = decoded_ogg(SOUNDS / rel)
    if abs(speed - 1) > 1e-4:
        pos = np.arange(0, len(y) - 1, speed)
        i0 = pos.astype(int)
        y = y[i0] * (1 - (pos - i0)) + y[i0 + 1] * (pos - i0)
    return y


# =========================================================================================================  the satellite
# The opening, as an orbital laser 7,000 up and 70 degrees over the player: it comes down into view (0-3.4), the red
# targeting beam comes on (3.3) and its spot locks (4.0), the shot (4.5) melts the hole, the beam is cut (7.1), the hole
# glows and the satellite lifts away (8.6), gone by 12. Two files: `sat_sky`, on the strike's clock from 0 (a sound from
# orbit can't be late by the distance and still be on its picture: films play it on the picture too), and `sat_land`, the
# shot's blow on the land at the vent come to the player late by the distance (by the air, 343 a second).
# What makes it read as high in the sky and not at the ear (the Payload's fall is the model): no top over a few kHz
# (7 km of air takes it), nothing quick (every level and colour moves slowly, bands on their own: no shared flutter), soft
# fronts (a blow's onset in milliseconds, never a burst of noise: that's a snare), and the land answering it, late,
# dark and long (`sky_echo`). The weight comes with the shot: a sub blow and the 100-800 Hz body with it, so the low end
# is heard on a laptop too (`lows_heard`). Nothing beeps, rings or chimes; the aim and the lock are changes in what is
# already sounding.
SAT_SKY_D = 12.5           # (`sat_sky`'s length: vc_sound.rs's SAT_SKY_LEN)
SAT_LAND_D = 6.0           # (`sat_land`'s: SAT_LAND_LEN)
SAT_AIM, SAT_LOCK, SAT_HIT, SAT_CUT, SAT_GONE = 3.3, 4.0, 4.5, 7.1, 12.0


def ss(a, b, x):
    u = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return u * u * (3 - 2 * u)


def sky_echo(x, length=6.0, wet=0.55, darken=(1500, 140), decay=2.2, pre=0.18, seed=0):
    """`x` as the land round the player answers a sound high overhead: nothing for `pre` s (the nearest land is that far
    off), then clumps of dark echoes off hills and trees for seconds, each later one duller."""
    ir = T.outdoor_ir(length, seed, density=28.0, darken=darken, decay=decay)
    ir = np.concatenate([np.zeros(n_of(pre)), ir])
    # (the echo `wet` of the sound itself, whatever its colour: an IR this dark, scaled to unit energy, would otherwise
    # carry the lows several times over and smear every blow into the next)
    e = conv(x, ir)
    return x + e * wet * np.sqrt(np.mean(x ** 2) / (np.mean(e ** 2) + 1e-20))


def blow_at(n, t0, f_hi, f_lo, f_end, drop, rise, decs, drive=3.0):
    """S.blow, peak 1."""
    b = S.blow(n, t0, f_hi, f_lo, f_end, drop, rise, decs, drive=drive, octv=0.3, h3=0.15, harm=0.5)
    return b / (np.abs(b).max() + 1e-9)


def soft_body(n, t0, lo, hi, rise, fall):
    """A short body of low noise, its front rising over `rise` s (no burst on it), dying over `fall`; unit RMS before its
    envelope."""
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    return T.unit(F.cband(rng().standard_normal(n), lo, hi, 2)) * (1 - np.exp(-u / rise)) * np.exp(-u / fall) * (t >= t0)


def sat_write(name, x, d):
    x = PB.causal_lowcut(x, 20.0) * T.fade(n_of(d), 0.002, 0.6)
    land_ = name.endswith("_land")
    # (the sky's blows rounded off a little rather than limited, so the shot keeps its weight under the true-peak cap)
    write(name, x[:n_of(d)], knee=None if land_ else 0.8, kind="sat_land" if land_ else "sat_sky")


# ---- the satellite: the sky sings (Inception's horns, "massive low-end musical tones, sounding like distant horns"; the Fold's
# approved `swell`, one huge bowed note)
SAT_ROOT = 49.0           # G1: the note the satellite is


def horn(t, f0, fm, width, nh=48, jitter=0.0015):
    """A brass-like voice: harmonics of `f0` (Hz, a curve) under a formant centred at `fm` Hz (a curve) `width` octaves
    wide, each partial a little off and swelling slowly on its own (`boiled`), nothing above 3.5 kHz. Unit RMS."""
    n = len(t)
    ph = 2 * np.pi * np.cumsum(f0 * (1 + jitter * PB.slow_random(n, 0.1, 0.8))) / SR
    lfm = np.log2(np.maximum(fm, 20.0))
    y = np.zeros(n)
    for k in range(1, nh + 1):
        if np.min(f0) * k > 3500:
            break
        lf = np.log2(f0 * k)
        w = 0.08 + np.exp(-0.5 * ((lf - lfm) / (width / 2.355)) ** 2) + 0.25 * (lf < lfm)
        y += k ** -0.7 * w * np.sin(k * ph * (1 + 0.0004 * (k - 1)) + rng().uniform(0, 6.3)) * boiled(n, 0.15, 0.9, 1.6)
    return T.unit(y)


def build_sat():
    """The satellite is a note. It comes into view as a vast low horn far up (G1, its overtones closed), falling into its
    pitch as it settles on its orbit; the targeting beam a second voice beside it, a little off, the two beating slowly and
    unevenly as the spot wanders; the lock the two pulling into one (the beating stops, the note firms and opens a
    little). It swells to the shot, which is the braam: the octave under it, the fifth and the octave over come in at once,
    the formant thrown open, driven until it growls, a sub blow and a deep body under its front; it holds while the beam
    burns, slowly closing, and at the cut it sags a whole tone and closes to its bottom, ringing off the land until it is
    gone."""
    d = SAT_SKY_D
    n, t = n_of(d), times(d)
    with PB.seeded(61201):
        f = SAT_ROOT * 2 ** ((0.4 * np.exp(-t / 0.55) - 2.0 * ss(SAT_CUT, SAT_CUT + 2.2, t)) / 12)
        # (its colour: closed as it comes, opening a little at the lock, thrown open on the shot, closing as it burns)
        fm = np.interp(t, [0, 3.9, SAT_LOCK, SAT_LOCK + 0.2, SAT_HIT - 0.02, SAT_HIT + 0.07, 5.7, SAT_CUT, SAT_CUT + 1.5, d],
                       [150, 210, 230, 330, 470, 1050, 900, 720, 260, 160])
        fm = ease(fm, 0.04)
        a = horn(t, f, fm, 1.4)
        # (the second voice: on at the aim, its pitch off by a wandering few tenths of a percent, pulled in at the lock)
        off = (0.0045 + 0.0035 * PB.slow_random(n, 0.2, 0.9)) * (1 - ss(SAT_LOCK - 0.25, SAT_LOCK + 0.05, t))
        # (its overtones only up to the 16th, so the two beat slowly, never a flutter up top)
        b = horn(t, f * (1 + off), fm * 0.95, 1.3, nh=16) * ss(SAT_AIM, SAT_AIM + 0.5, t)
        lead = (a + 0.85 * b) * db_curve(t, [(0, -75), (0.5, -40), (2.5, -30), (SAT_LOCK, -27), (SAT_LOCK + 0.2, -24.5),
                                             (SAT_HIT - 0.05, -18), (SAT_HIT + 0.08, -16), (5.1, -20), (SAT_CUT, -21),
                                             (SAT_CUT + 0.4, -21), (9.0, -28), (SAT_GONE, -48), (d, -80)])
        # ---- the braam: the octave under, the fifth and the octave over, in at once, driven till it growls
        on = ss(SAT_HIT - 0.01, SAT_HIT + 0.06, t)
        held = db_curve(t, [(0, 5.0), (SAT_HIT + 0.15, 5.0), (5.3, 0), (5.9, -1.0), (SAT_CUT, -2.0), (SAT_CUT + 0.35, -8), (9.0, -19), (SAT_GONE, -45), (d, -80)])
        under = horn(t, f / 2, fm * 0.8, 1.6, nh=60)
        fifth = horn(t, f * 1.4983, fm, 1.3)
        over = horn(t, f * 2.0, fm * 1.05, 1.2)
        braam = (under * 1.0 + fifth * 0.55 + over * 0.45 + a * 0.6) * on
        drive = 2.6 * on * (1 - 0.5 * ss(SAT_CUT, SAT_CUT + 1.0, t)) + 0.3
        braam = np.tanh(braam * drive) / np.tanh(drive)
        braam = F.cband(braam * held, None, 3000, 2) * db_of(-12)
        # (a sub under the root, the note an octave lower again, there only with the braam)
        sub = np.sin(2 * np.pi * np.cumsum(f / 2) / SR) * on * held * db_of(-13)
        # (the front's weight: a sub blow and a deep body, rising in milliseconds)
        hit = blow_at(n, SAT_HIT, 66.0, 32.0, 24.5, 0.1, 0.004, ((0.6, 0.3), (0.4, 1.1)), drive=3.0) * db_of(-6)
        hit += soft_body(n, SAT_HIT, 40, 360, 0.008, 0.45) * db_of(-16)
        x = lead + braam + sub + hit
        x = sky_echo(x, 6.5, 0.5, (1600, 140), 2.4, 0.2, seed=121)
        x = lows_heard(x, 60, 360, -9.0)
        x = F.cband(x, None, 4000, 2)
    sat_write("sat_sky", x, d)
    # the land's answer: the shot's blow at the vent, and the note coming back off the land with it, dark
    d = SAT_LAND_D
    n, t = n_of(d), times(d)
    with PB.seeded(61202):
        u = np.maximum(t - LEAD, 0)
        x = blow_at(n, LEAD, 56.0, 29.0, 24.5, 0.2, 0.025, ((0.6, 0.4), (0.4, 1.5)), drive=2.2)
        x += soft_body(n, LEAD, 30, 240, 0.03, 0.8) * 0.4
        note = horn(t, SAT_ROOT * 2 ** (-2.0 * ss(0.0, 2.5, t) / 12) / 2, np.interp(t, [0, 0.1, 2.5, d], [180, 380, 180, 120]), 1.4)
        x += note * (1 - np.exp(-u / 0.06)) * np.exp(-u / 1.3) * 0.5
        x = land(x, 4.0, 0.55, (800, 100), 2.2, 30.0, seed=122)
        x = lows_heard(x, 55, 300, -8.0)
    sat_write("sat_land", x, d)


# The lightning's thunder: the Hurricane's approved thunder, its files as they are but louder, so a volcano's lightning
# carries over the column from kilometres off (vc_sound.rs's `thunder`): crack (`thunder`), clap (`thunder_mid`), roll
# (`thunder_far`), rumble (a flash in the cloud).
LIGHTNING = {"lt_crack": "thunder", "lt_clap": "thunder_mid", "lt_roll": "thunder_far", "lt_rumble": "rumble"}


def build_lightning(name):
    for v in range(1, VARIANTS[name] + 1):
        write(f"{name}{v}", sampled(f"hurricane/{LIGHTNING[name]}{v}.ogg"), knee=0.8, kind=name)


def build_boom():
    """The eruption's weight, under the report: the Nuke's ALT blast (approved) slowed to BOOM_SPEED, deeper and holding
    loud for some ten seconds, the Payload's ALT blast slowed further for its front, both on the report's front (LEAD);
    faded out from 12 s under the column. boom_far the same from their far files."""
    for name, a, b in (("boom", "nuke/blast_alt.ogg", "payload/blast_alt.ogg"),
                       ("boom_far", "nuke/blast_alt_far.ogg", "payload/blast_alt_far.ogg")):
        x = np.zeros(n_of(BOOM_D))
        y = sampled(a, BOOM_SPEED)
        z = sampled(b, BOOM_FRONT_SPEED)
        on = np.argmax(np.abs(z) > 0.25 * np.abs(z).max())
        z = z[max(on - n_of(0.004), 0):]
        for v, g in ((y, 1.0), (z, 0.7)):
            m = min(len(v), len(x) - n_of(LEAD))
            x[n_of(LEAD):n_of(LEAD) + m] += v[:m] * g
        x = x * db_curve(np.arange(len(x)) / SR, [(0, 0), (12.0, 0), (18.0, -8), (BOOM_D - 0.5, -40), (BOOM_D, -90)])
        write(name, x, knee=0.8)


def mount_height(t, ph=0.0):
    """How high the mount stands at strike time `t` (volcano_mount.wgsl's vm_hgt): slow, then frightening, in lurches."""
    s = np.clip(t - SWELL, 0.0, HUSH - SWELL)
    a = 2 * np.pi * (0.55 * s + 0.045 * s * s) + ph
    da = 2 * np.pi * (0.55 + 0.09 * s)
    st = s - 0.8 * np.sin(a) / da + 0.8 * np.sin(ph) / (2 * np.pi * 0.55)
    u = np.clip(st / 10.0, 0.0, 1.0)
    return 150.0 * (0.12 * u + 0.3 * u ** 2 + 0.58 * u ** 4) * np.clip(s / 0.8, 0, 1) ** 2 * (3 - 2 * np.clip(s / 0.8, 0, 1))


def lurch_times():
    """When each of the mount's lurches is at its fastest (strike seconds): vm_hgt's `a` at pi, ten of them."""
    return [SWELL + (-0.55 + np.sqrt(0.55 ** 2 + 4 * 0.045 * (0.5 + k))) / (2 * 0.045) for k in range(10)]


def lurch(size):
    """One step of the land rising, heard through the ground: a slow shove with no edge, the rock's body round it, plates
    grating over each other for a moment. Bigger is longer and more of the grating."""
    d = 1.3 + 0.5 * size
    n = n_of(d)
    s = times(d)
    f = 19.0 + 15.0 * np.exp(-s / 0.3)
    shove = np.sin(2 * np.pi * np.cumsum(f) / SR) * (1 - np.exp(-s / 0.045)) * np.exp(-s / (0.26 + 0.14 * size))
    body = T.unit(band(white(d), 36, 150, 2)) * (1 - np.exp(-s / 0.03)) * np.exp(-s / (0.16 + 0.1 * size)) * boil(n, 6.0, 20.0, 3.0)
    grate = T.stick_slip(d, 19.0 + 12.0 * size, 100, 560, 0.9, 3.5)
    grate = T.unit(grate) * (1 - np.exp(-s / 0.07)) * np.exp(-s / (0.2 + 0.16 * size))
    return (shove + body * 0.5 * size ** 0.5 + grate * 0.15 * size) * T.fade(n, 0.001, 0.25)


def dull_crack(d, size):
    """A crack deep in the land, come a long way through the rock: the snap gone, a dull knock and a thump under the feet."""
    x = band(H.rock_crack(d, size, 0.7), 22, 620, 2)
    return x + soundlib.thump(n_of(d), 0.02, 64, 26, 0.18, 9.0) * 0.8


def build_tremor():
    """The mount, heard from a long way off: 4.5 to 17 s, the longest build in the strike. What keeps it moving is that it
    is the land's own rise: the bed swells with how fast the mount climbs (so with its lurches), the lurches come ever
    sooner and heavier, a groan of rock under load climbs slowly through it and the sound widens upward as it goes,
    rather than only getting louder. At 17 s it stops dead, the last lurch unfinished: the file ends there."""
    d = TREMOR_D
    n = n_of(d)
    t = times(d)
    # (its build was drawn over 15 s: `kt` fits it to the file's length; the lurches and the last cracks are on the strike's clock)
    kt = d / 15.0
    with PB.seeded(61101):
        h = mount_height(t + (HUSH - TREMOR_D) - GROUND_LAG)
        rate = np.clip(np.gradient(h) * SR, 0.0, None)
        rate = ease(rate / rate.max(), 0.14)
        rise = np.interp(t / kt, [0, 5, 15], [0.35, 0.5, 1.0]) * rate ** 0.45 + 0.4         # (0.4 to 1.4: the bed breathing with it)
        roll = np.clip(0.45 + 0.42 * PB.slow_random(n, 0.18, 1.1), 0.0, None) ** 1.4    # (the rolling: swells that come and go)
        shudder = np.clip(1 + (0.25 + 0.6 * np.clip((t / kt - 3) / 7, 0, 1)) * PB.slow_random(n, 7.0, 13.0), 0.05, None)
        deep = T.unit(band(white(d), 11, 32, 3)) * boil(n, 0.2, 1.0, 3.0)
        rolling = T.unit(band(white(d), 26, 72, 2)) * roll * shudder * rise
        body = T.unit(band(white(d), 65, 210, 2)) * roll ** 1.3 * boil(n, 2.0, 9.0, 3.0) * rise
        grind = T.stick_slip(d, 6.0, 70, 340, 0.9, 4.0) * np.clip(0.4 + 0.5 * PB.slow_random(n, 0.3, 1.5), 0, None)
        # (and over it, late on, the dark slide of the rock coming off the flanks, which the takes can't ring on into the hush)
        wide = T.unit(band(white(d), 200, 520, 2)) * np.clip(N.grains(d, 9.0, (0.05, 0.12, 0.3)), 0, 6) ** 0.7 * rate ** 0.5
        # (the groan: narrow bands of noise, no pitch to ring, climbing a fourth as the load comes on)
        res = sum(T.glide_noise(d, f, f * 1.36, w, curve=0.9) * a for f, w, a in ((43.0, 0.24, 1.0), (69.0, 0.27, 0.7), (104.0, 0.3, 0.5), (151.0, 0.34, 0.3)))
        groan = T.unit(res) * np.clip(0.7 + 0.4 * PB.slow_random(n, 0.25, 1.2), 0.1, None) * rise
        x = (deep * db_curve(t / kt, [(0, -60), (3, -41), (6, -31), (10, -25), (15, -19)])
             + rolling * db_curve(t / kt, [(0, -84), (2.5, -56), (5, -41), (9, -30), (12, -24), (15, -16)])
             + body * db_curve(t / kt, [(0, -100), (4.5, -62), (8, -43), (11, -34), (15, -23)])
             + T.unit(grind) * db_curve(t / kt, [(0, -100), (5, -72), (7, -52), (11, -38), (15, -28)])
             + groan * db_curve(t / kt, [(0, -100), (3.5, -62), (5, -47), (9, -35), (12, -28), (15, -21)])
             + wide * db_curve(t / kt, [(0, -100), (8, -66), (11, -46), (13, -37), (15, -29)]))
        # (the lurches, as the picture has them, each bigger; the last is cut short by the hush)
        ts = lurch_times()
        for k, tk in enumerate(ts):
            u = k / (len(ts) - 1)
            tl = tk + GROUND_LAG - (HUSH - TREMOR_D) if k < len(ts) - 1 else d - 0.17
            P.put(x, lurch(0.6 + 1.0 * u) * 10 ** ((-36.0 + 22.0 * u ** 0.8) / 20), tl)
        # (and the land's last cracks, which the separate takes would ring on past the hush)
        for j, (tc, size) in enumerate(((15.15, 1.0), (15.9, 1.2), (16.35, 0.9), (16.62, 1.4))):
            P.put(x, dull_crack(0.9, size) * T.fade(n_of(0.9), 0.001, 0.3) * 10 ** ((-33.0 + j) / 20), tc - (HUSH - TREMOR_D))
        # (the last two seconds the most of it: it must still be climbing when it stops)
        x *= db_curve(t, [(0, 0), (d - 2.2, 0), (d - 0.4, 3.5), (d, 3.5)])
        x = lows_heard(x, 60, 280, -9.0)
        x = PB.causal_lowcut(x * T.fade(n, 0.5, 0.001), 12.0)
        # (it stops dead: no tail of any kind)
        x *= np.clip((d - t) / 0.025, 0, 1) ** 0.5
    write("tremor", x)


# When the rock under the player gives in each take of `creak` (s) and how much: the load climbs to each slip and eases
# a little after it.
CREAKS = {1: ((0.45, 0.8), (1.0, 1.0)), 2: ((0.55, 0.6), (1.2, 1.1), (1.85, 0.55)), 3: ((0.5, 1.0),), 4: ((0.35, 0.5), (0.85, 0.75), (1.4, 1.0))}


def build_creak(v):
    """Rock under strain right under the player. Not a creak (a creak is a squeak, stick and slip at a steady rate: a
    wooden door, a toy), but the stone giving as the load climbs: a deep grinding pressure low down, the rock crazing in
    dense dark crunches that thicken as the stress builds (thousands of tiny fractures, too many to count, nothing over
    800 Hz), and where it gives, a heavy dull lurch with a burst of crushing in it; close and dry, in the rock."""
    d = [1.5, 2.4, 1.1, 2.0][v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(61200 + v):
        slips = CREAKS[v]
        stress = np.full(n, 0.12)
        for ts, size in slips:
            stress += size * np.where(t < ts, np.clip((t - ts + 0.55) / 0.55, 0, 1) ** 2, 0.25 + 0.75 * np.exp(-(t - ts) / 0.15))
        stress = ease(stress, 0.04) * np.clip(1 + 0.25 * PB.slow_random(n, 1.5, 6.0), 0.3, None)
        # (the crazing: a dense crunch of tiny fractures, as thick and as strong as the stress)
        craze = rocks(d, 150.0 + 1100.0 * stress ** 1.5, 60, 560, (0.06, 0.14, 0.35), (0.6, 0.32, 0.08), 2.2) * stress ** 1.2
        # (the grinding: the pressure deep in it, turbulence at every scale low down)
        grind = eddies(d, 26, 320, 2.5, -2.0, 6.0, 7.0) * stress
        # (the slips: a heavy dull lurch, a burst of crushing round it)
        slip = np.zeros(n)
        for ts, size in slips:
            P.put(slip, bare_blow(0.8 + 0.8 * size, 22, 110, 0.012, 0.09) * size, ts)
            m = n_of(0.6)
            q = np.arange(m) / SR
            crush = rocks(0.6, 2600.0 * np.exp(-q / 0.07) + 1e-3, 80, 700, (0.1, 0.25, 0.6), (0.55, 0.35, 0.1), 2.0)
            P.put(slip, crush * (1 - np.exp(-q / 0.004)) * np.exp(-q / 0.12) * size * 0.45, ts + 0.004)
        x = grind * 0.8 + craze * 0.7 + slip / (T.loudest(slip) + 1e-9) * 1.0
        x = F.cband(x, 24, 800, 2)
        # (in the rock: a short thick dark ringing, no air)
        x = earth_ring(x, 0.7, 0.35, (500, 80), 0.18, seed=200 + v)
        x = lows_heard(x, 50, 260, -8.0)
    write(f"creak{v}", PB.causal_lowcut(x, 20.0) * T.fade(n, 0.03, 0.3), kind="creak")


# When each sub-event of a crack goes (s) and how big: a crack in rock runs, it's never one blow.
CRACKS = {1: ((0.02, 1.0), (0.05, 0.45), (0.13, 0.3)),
          2: ((0.02, 0.7), (0.07, 0.3), (0.36, 1.1), (0.41, 0.5), (0.6, 0.3)),
          3: ((0.02, 0.5), (0.12, 0.6), (0.21, 0.55), (0.28, 0.8), (0.37, 0.7), (0.44, 1.0), (0.5, 0.6), (0.63, 0.4), (0.8, 0.25)),
          4: ((0.05, 1.35), (0.18, 0.7), (0.3, 0.4))}
CRACK_SNAP = 0.014         # (crack4's snap, ahead of its run)


def build_crack(v):
    """A crack deep in the land, a kilometre of rock away: no snap, no pitch. It runs: a few blows close together (each
    the ground's dull shove with a crunch of rock at its front, nothing over 700 Hz left), a grating as the faces slide,
    then the ground itself ringing on after it for a second and more, long and dark, which is what makes it huge and far
    down. Each take runs differently: a single hard one, two a moment apart, one tearing along, one big and low."""
    d = VC_CRACK_D
    n = n_of(d)
    with PB.seeded(61310 + v):
        x = np.zeros(n)
        run = CRACKS[v]
        for tc, size in run:
            P.put(x, bare_blow(size * rng().uniform(0.85, 1.2), 24, 95 + 40 * rng().random(), 0.007, 0.075) * size, tc)
            m = n_of(0.16)
            q = np.arange(m) / SR
            crunch = T.unit(F.cband(rng().standard_normal(m), rng().uniform(110, 170), rng().uniform(420, 680), 2))
            crunch *= (1 - np.exp(-q / 0.0012)) * np.exp(-q / rng().uniform(0.014, 0.03)) * np.clip(1 + 0.5 * PB.slow_random(m, 40.0, 140.0), 0.1, None)
            P.put(x, crunch * size ** 0.8 * 0.55, tc + rng().uniform(0.0, 0.003))
        # (the faces grating as they slide, through the run)
        end = run[-1][0] + 0.2
        t = times(d)
        slip = np.clip(N.grains(d, 60.0, (0.012, 0.03)), 0, 6) ** 1.2 * np.clip((end - t) / 0.2, 0, 1) * (t > 0.02)
        x += T.unit(F.cband(white(d), 90, 360, 2)) * slip * 0.1
        if v == 4:
            # (the big one opens with a slight snap: the rock's first face letting go, small and sharp, a moment before the
            # deep crack runs; dry, its top short of a snare's, a little body under it and one splinter after)
            with PB.seeded(61319):
                m = n_of(0.08)
                q = np.arange(m) / SR
                snap = (T.unit(F.cband(rng().standard_normal(m), 900, 4800, 2)) * (1 - np.exp(-q / 0.0002)) * np.exp(-q / 0.0022)
                        + T.unit(F.cband(rng().standard_normal(m), 220, 1100, 2)) * (1 - np.exp(-q / 0.0004)) * np.exp(-q / 0.011) * 0.75)
                P.put(snap, snap[:n_of(0.02)] * 0.35, 0.0065)
                P.put(x, snap / (np.abs(snap).max() + 1e-9) * np.abs(x).max() * 0.6, CRACK_SNAP)
        x = earth_ring(x, 2.0, 0.75 + 0.2 * rng().random(), (640, 55), 0.42 + 0.12 * rng().random(), seed=120 + v)
        x = lows_heard(x, 60, 300, -7.0)
    write(f"crack{v}", PB.causal_lowcut(x, 17.0) * T.fade(n, 0.0005, 0.7), kind="crack")


def build_rockfall(v):
    """Rock coming off the mount's flanks, a long way off: a dark slide of many blows run together, swelling and thinning.
    Nothing small: at this range a fall of rock is a rumble, its clatter long lost to the air."""
    d = ROCKFALLS[v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(61350 + v):
        env = np.clip(t / (0.3 * d), 0, 1) ** 1.3 * np.clip((d - t) / (0.55 * d), 0, 1) ** 1.2
        hits = np.zeros(n)
        tc = 0.05
        while tc < d - 0.6:
            P.put(hits, T.thud(n_of(0.5), min(rng().pareto(2.0) * 0.7 + 1.0, 3.0)) * rng().uniform(0.4, 1.0) * env[n_of(tc)], tc)
            tc += rng().exponential(0.07)
        hits = band(hits, 28, 360, 2)
        slide = T.unit(band(white(d), 60, 420, 2)) * np.clip(N.grains(d, 8.0, (0.05, 0.12, 0.3)), 0, 6) ** 0.7 * env
        x = T.unit(hits) + slide * 0.55
        x = land(band(x, 24, 480, 2), 2.4, 0.5, (520, 130), 1.0, seed=100 + v)
    write(f"rockfall{v}", PB.causal_lowcut(x, 22.0) * T.fade(n, 0.1, 0.7), kind="rockfall")


def build_steam():
    """The cracks venting, out on the land, for one who has flown close: a hiss in uneven jets, its top taken off by the
    distance, growing to the hush, where it stops dead with everything else."""
    d = HUSH - 6.0
    n = n_of(d)
    t = times(d)
    with PB.seeded(61401):
        jets = np.clip(0.7 + 0.5 * PB.slow_random(n, 0.4, 2.0), 0.05, None) * boil(n, 6.0, 30.0, 2.0)
        x = T.unit(band(white(d), 1400, 6500, 2)) * jets + T.unit(band(white(d), 500, 1800, 2)) * 0.35 * jets
        x *= db_curve(t, [(0, -50), (1.8, -14), (6, -7), (d, 0)])
        x = land(x, 2.0, 0.3, (3500, 800), 0.8, seed=11)
        x *= np.clip((d - t) / 0.025, 0, 1) ** 0.5
    write("steam", x * T.fade(n, 0.2, 0.001))


def build_fountain():
    """The mount's lava fountains, as far as they carry: gas pushing rock out in uneven heaves, a low chugging roar like
    surf a long way off, the top gone. Grows with them from the swell; stops dead on the hush."""
    d = HUSH - SWELL
    n = n_of(d)
    t = times(d)
    with PB.seeded(61451):
        chug = np.clip(N.grains(d, 4.5, (0.09, 0.18, 0.35)), 0, 6) ** 0.8
        roar = T.unit(band(white(d), 130, 900, 1.5)) * boil(n, 1.0, 6.0, 4.0) * chug
        low = T.unit(band(white(d), 55, 200, 2)) * boil(n, 0.5, 3.0, 3.0) * chug
        spit = T.unit(band(white(d), 900, 2400, 2)) * np.clip(N.grains(d, 40.0, (0.01, 0.03, 0.06)), 0, 7) * chug
        x = (roar + low * 0.8 + spit * 0.06) * db_curve(t, [(0, -44), (3, -24), (7, -9), (d, 0)])
        x = land(x, 2.2, 0.4, (900, 220), 1.0, seed=13)
        x *= np.clip((d - t) / 0.025, 0, 1) ** 0.5
    write("fountain", PB.causal_lowcut(x, 30.0) * T.fade(n, 0.6, 0.001))


def held(y, sec=0.4):
    """A narrow band of noise with its own beating taken out (its level over `sec` divided away), unit RMS: a drone held
    steady, its tone and its slow wander kept, none of the deep dips a narrow band of noise falls into now and then."""
    return T.unit(y / (np.sqrt(ease(y ** 2, sec)) + 1e-9 * np.sqrt(np.mean(y ** 2))))


def build_hush():
    """The hush (17 s, on the strike's clock, the moment the tremor stops dead, until the report, which cuts it: vc_sound.rs's
    stopsound): the land's rolling, its lurches and its cracks gone at once, and in their place a deep pressure held under
    everything and swelling to the ground's answer (1.5-2.6 s in, as the seism comes from 800 to 1,500 blocks), then easing
    back a few dB under it and the blast's front (`front`), which take the climb on, so the wait is tension and never
    silence. A sub climbing slowly, the rock's groan under load
    drawn on up past where the tremor left it, the ground straining under it. Every movement in it slow: nothing grainy,
    nothing quick, no hiss. It starts well under where the tremor stopped (the cut-off still reads), and long enough for a
    report heard from 3,000 blocks."""
    d = HUSH_D
    n = n_of(d)
    t = times(d)
    with PB.seeded(61481):
        # (the sub climbing, and its octave, so a laptop hears it rise)
        sub = held(T.glide_noise(d, 23.0, 44.0, 0.32, curve=0.75)) * np.clip(1 + 0.18 * PB.slow_random(n, 0.1, 0.5), 0.5, None)
        sub2 = held(T.glide_noise(d, 46.0, 88.0, 0.28, curve=0.75)) * np.clip(1 + 0.3 * PB.slow_random(n, 0.15, 0.7), 0.3, None)
        press = T.unit(band(white(d), 14, 38, 3)) * boiled(n, 0.08, 0.5, 1.5)
        # (the groan: the tremor's (43, 69, 104 and 151 Hz, there climbed a fourth) climbing on, narrower as the load comes on)
        res = sum(held(T.glide_noise(d, f * 1.36, f * 1.75, w, curve=0.8)) * a for f, w, a in ((43.0, 0.2, 1.0), (69.0, 0.22, 0.85), (104.0, 0.25, 0.7), (151.0, 0.3, 0.45)))
        groan = T.unit(res) * np.clip(0.8 + 0.35 * PB.slow_random(n, 0.15, 0.7), 0.25, None)
        strain = T.unit(band(white(d), 28, 105, 2)) * boiled(n, 0.2, 1.2, 1.5)
        x = (sub * db_curve(t, [(0, -7), (0.5, -5), (2.5, -2.5), (5, 0), (d, 1)])
             + sub2 * db_curve(t, [(0, -18), (0.8, -13), (3, -9), (6, -7), (d, -6)])
             + press * db_curve(t, [(0, -10), (1.5, -8), (5, -6), (d, -5)])
             + groan * db_curve(t, [(0, -9), (0.4, -5), (2.0, -1), (4.0, 1.5), (7, 2.5), (d, 3)])
             + strain * db_curve(t, [(0, -18), (0.8, -13), (3, -9), (6, -7), (d, -6)]))
        # (a held pressure: its level over time set outright (a slow leveller over its noise's lumps), so no one swell of its
        # own stands out; at its height as the seism comes, then let back 2-3 dB so the front's swell is the climb heard)
        lvl = np.sqrt(ease(x ** 2, 0.7))
        x = x / (lvl + 1e-9 * lvl.max()) * db_curve(t, [(0, -1.5), (0.6, -1), (1.5, 0), (2.6, 0), (4.0, -2), (7.0, -3), (d, -3)])
        x = lows_heard(x, 50, 260, -7.0)
        x = PB.causal_lowcut(x, 13.0) * T.fade(n, 0.03, 2.5)
    write("hush", x)


def lowpass_by(x, fc_of):
    """`x` through a lowpass whose cutoff at each moment is `fc_of(seconds)` Hz (frame by frame, overlap-added)."""
    n = len(x)
    size, hop = 4096, 1024
    win = np.hanning(size)
    out = np.zeros(n + size)
    norm = np.zeros(n + size)
    xp = np.concatenate([x, np.zeros(size)])
    freqs = np.fft.rfftfreq(size, 1 / SR)
    for start in range(0, n, hop):
        g = 1 / (1 + (freqs / fc_of((start + size / 2) / SR)) ** 4)
        out[start:start + size] += np.fft.irfft(np.fft.rfft(xp[start:start + size] * win) * g, size) * win
        norm[start:start + size] += win ** 2
    return out[:n] / np.maximum(norm[:n], 1e-3)


def driven(x, db):
    """`x` driven `db` dB into a soft clip and brought back to its own loudness: its peaks rounded, its harmonics up, so
    a blow is heavy on any speaker. Light: a little grit for power, never fuzz."""
    c = np.percentile(np.abs(x), 99.5) + 1e-12
    y = np.tanh(x / c * 10 ** (db / 20)) * c
    return y * (T.loudest(x) / (T.loudest(y) + 1e-12))


def build_seism():
    """The burst, through the ground: it gets here before the air does (18 s + d / 1715), and it is a supervolcano going
    off under the land. The Payload's `ground` (its thump through the earth, felt more than heard, with a jolt) made far
    heavier and longer, with a body: the first wave a deep hard thump under the feet (a falling low tone and a burst of
    low noise rising in 20 ms, its 30 Hz as heavy as its 60, a punch at 80-400 Hz for the chest and a dull blow of the
    ground's face over it, all of it driven a little, so its weight is heard on any speaker); the second wave (the
    shear, 0.42 s on) a bigger heave, the ground lurching, a low-mid shudder rattling through it; then the surface
    waves rolling under the feet in slow swells, each crest shuddering, rolling on and on. With it the air all round
    shaken by the land: a broad dark boom coming up out of the ground and rolling off round the land, long, low rolls in
    it. The roll holds on under the hush and the blast's front (`front`) until the report cuts it (vc_sound.rs's
    stopsound), never falling away. Long enough for a report heard from 3,000 blocks."""
    d = SEISM_D
    n = n_of(d)
    t = times(d)
    t0 = LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(61473):
        # ---- the first wave: the thump (a falling low tone dying in a few swings, low noise on it, the sub under it), the
        # punch of it in the chest and the ground's face struck, dull, over it
        th = soundlib.thump(n, t0, 60.0, 24.0, 0.3, 4.5) * (1 - np.exp(-u / 0.02)) * on
        th += T.unit(F.cband(white(d), 20, 100, 2)) * (1 - np.exp(-u / 0.018)) * np.exp(-u / 0.2) * on * 0.6
        th += T.unit(F.cband(white(d), 16, 42, 2)) * (1 - np.exp(-u / 0.016)) * np.exp(-u / 0.4) * on * 0.7
        punch = T.unit(F.cband(white(d), 80, 400, 2)) * (1 - np.exp(-u / 0.006)) * np.exp(-u / 0.11) * on
        face = T.unit(F.cband(white(d), 300, 950, 2)) * (1 - np.exp(-u / 0.004)) * np.exp(-u / 0.05) * on
        first = th + punch * 0.55 + face * 0.12
        # ---- the second wave, the shear: a bigger heave, the ground lurching, rattling with a low-mid shudder
        t2 = t0 + 0.42
        u2 = np.maximum(t - t2, 0)
        on2 = t >= t2
        hv = soundlib.thump(n, t2, 48.0, 21.0, 0.45, 3.5) * (1 - np.exp(-u2 / 0.04)) * on2
        hv += T.unit(F.cband(white(d), 18, 90, 2)) * (1 - np.exp(-u2 / 0.035)) * np.exp(-u2 / 0.42) * on2 * 0.75
        hv += T.unit(F.cband(white(d), 70, 320, 2)) * (1 - np.exp(-u2 / 0.02)) * np.exp(-u2 / 0.22) * on2 * 0.4
        flut = np.clip(1 + 0.75 * PB.slow_random(n, 8.0, 20.0), 0.1, None)
        shud = T.unit(F.cband(white(d), 80, 700, 2)) * flut * np.exp(-0.5 * ((t - t2 - 0.12) / 0.14) ** 2) * 0.32
        second = hv * 1.15 + shud
        ground = driven(first + second, 5.0)
        ref = T.loudest(ground)
        # ---- the surface waves: the land rolling under the feet in slow swells (a little under a second apart, uneven),
        # each crest shuddering in the low mids, from 0.6 s on and holding, rolling on under the wait
        sw = heaves(d, 0.85, 0.35, 0.18, 0.5, tail=0.35, t0=t0 + 0.65)
        swell = np.clip(sw / (np.percentile(sw, 95) + 1e-9), 0, 1.6)
        roll = T.unit(F.cband(white(d), 18, 75, 2)) * (0.6 + 0.7 * swell) * boiled(n, 0.3, 1.5, 2.0)
        body = eddies(d, 60.0, 420.0, per_oct=2.0, slope=-3.0, turns=30.0, depth=2.5) * (0.4 + 0.8 * swell)
        crest = T.unit(F.cband(white(d), 90, 650, 2)) * np.clip(1 + 0.7 * PB.slow_random(n, 7.0, 18.0), 0.1, None) * swell ** 2
        rolling = (roll + body * 0.55 + crest * 0.18) * np.clip((u - 0.5) / 0.6, 0, 1) * on
        rolling = rolling / (np.sqrt(np.mean(rolling[n_of(1.5):n_of(4.0)] ** 2)) + 1e-12) * ref * db_curve(t, [(0, -7.5), (1.5, -7.5), (4.0, -7), (d, -6.5)])
        # ---- in the air: the land shaking the air all round, a broad dark boom coming up out of the ground and rolling
        # off round the land
        src = (T.unit(F.cband(white(d), 40, 1100, 2)) * (1 - np.exp(-u / 0.03)) * np.exp(-u / 0.2) * on
               + F.cband(th + hv, None, 160, 2) / (np.abs(th + hv).max() + 1e-9) * 0.9)
        air_ = conv(src, T.outdoor_ir(4.5, 47, density=30.0, darken=(1400, 130), decay=1.1))
        air_ = air_ * (1 - np.exp(-u / 0.1))
        rl, rr = PB.thunder_rolls(d, t0 + 0.25, count=10, length=5.0)
        rolls = (rl + rr) / 2
        boom = air_ / (np.sqrt(np.mean(air_[n_of(t0):n_of(t0 + 1.0)] ** 2)) + 1e-12) * ref * db_of(-4.0)
        boom += rolls / (T.loudest(rolls) + 1e-12) * ref * db_of(-14.0)
        x = ground + boom + rolling
        x = lows_heard(x, 45, 260, -5.0)
        # (nothing of the air's top in it: the ground's answer is all under a couple of kilohertz)
        x = F.cband(x, None, 2200, 4)
    write("seism", PB.causal_lowcut(x * T.fade(n, 0.0005, 2.0), 14.0), knee=0.55)


def build_front(v):
    """The blast's front coming over the land, heard before it (vc_sound.rs plays it to end on the report, from no sooner
    than the seism): what comes between the ground's answer and the air's. The ground has carried the burst out ahead of
    the air, and all the land between the player and the vent is shaking and booming up into the air; what is heard of
    it comes from ever nearer the vent, where the ground heaves hardest, so the roar swells and opens up until the
    report itself is on it. A deep roll of the land rising; the pressure coming, a sub climbing; a dark roar opening up
    from the 200s to a kilohertz and more; the air ahead of the front rushing in its last half second; and for the last
    tenth the roar's top drawn in under the sub, the breath before the blow, which the report slams in on. Every take
    the same run to the report, counted back from it, the longer ones (for a player further off) only starting further
    back and darker, as the air takes the top first. It fades in from nothing under the seism and goes under the
    report's front in a few hundredths. Smooth: no grain, no flicker, nothing countable."""
    L = FRONTS[v - 1]
    d = L + FRONT_TAIL
    n = n_of(d)
    t = times(d)
    w = L - t                                   # (seconds before the report)
    back = lambda pts: db_curve(-w, [(-a, b) for a, b in pts] + [(FRONT_TAIL, pts[-1][1])])
    dark = (v - 1) / (len(FRONTS) - 1)          # (0 the nearest take, 1 the furthest)
    with PB.seeded(61490 + v):
        ground = T.unit(F.cband(white(d), 18, 70, 2)) * boiled(n, 0.3, 1.6, 2.5)
        sub = held(T.glide_noise(d, 26.0 * 2 ** (-L / 6), 40.0, 0.3, curve=2.2))
        roar = eddies(d, 45.0, 1400.0, per_oct=2.0, slope=-2.0, turns=32.0, depth=2.5)
        rush = eddies(d, 160.0, 3200.0, per_oct=2.0, slope=-2.0, turns=40.0, depth=2.0)
        # (the roar opening up as it nears: its top from the 400s to over a kilohertz and a half in its last two and a half
        # seconds; the rush's from 800 Hz to nearly 3 kHz in its last second; both a little darker in the furthest takes)
        top = lambda a, b, span: (lambda s: a * (b / a) ** np.clip(1 - (L - s) / span, 0, 1) ** 1.2)
        roar = lowpass_by(roar, top(420.0, 1600.0 * (1 - 0.3 * dark), 2.5))
        rush = lowpass_by(rush, top(800.0, 2800.0 * (1 - 0.35 * dark), 1.2))
        x = (ground * back([(4.5, -19), (2.5, -20), (1.0, -17), (0.3, -12), (0, -10)])
             + sub * back([(4.5, -27), (2.0, -25), (1.0, -19), (0.4, -11), (0.1, -7), (0, -6)])
             + roar * back([(4.5, -21), (2.5, -21), (1.5, -18), (1.0, -14), (0.5, -6), (0.25, -1), (0.1, -2), (0, -5)])
             + rush * back([(4.5, -58), (1.5, -34), (0.6, -15), (0.15, -3), (0.06, -6), (0, -11)]))
        x = land(x, 2.4, 0.18, (1200, 160), 0.9, seed=190 + v)
        x = lows_heard(x, 45, 280, -6.0)
        # (from nothing, under the seism; gone under the report's front)
        x *= np.clip(t / min(0.35, 0.25 * L), 0, 1) ** 2
        x *= np.clip(1 - (t - L) / 0.06, 0, 1) ** 2
        x = PB.causal_lowcut(x, 14.0)
    write(f"front{v}", x * T.fade(n, 0.01, 0.002), knee=0.6, kind="front")


# ===========================================================================================================  the report
def far_of(x, d, lo_gain=0.9, seed=0, soften=0.05):
    """What a blast's `x` is past a kilometre of air: the top nearly gone, the front smeared, a long dark reverb."""
    n = len(x)
    u = np.arange(n) / SR - LEAD
    soft_on = np.clip(u / soften, 0, 1) ** 2
    lo = band(x, None, 300, 2)
    mid = band(x, 300, 1200, 2)
    hi = band(x, 1200, None, 2)
    y = lo * lo_gain + mid * np.sqrt(soft_on) * 0.8 + P.air(hi, 3000) * soft_on * 0.14
    y = land(y, 7.0, 0.5, (1000, 140), 3.0, 30.0, seed=seed)
    return lows_heard(y, 70, 420, -6.0)


# The report, in the Payload's blasts' family (sounds_payload.py's `blast`, `blast_alt`), scaled up past them: what makes
# those hit, measured on their files, is a front that is broad and dense (its 63 Hz-1 kHz all within a few dB of each
# other in the first 50 ms, driven into a soft clip: the overloaded microphone), the mids dropping away after it while
# the sub swells on, a boom round 50-70 Hz falling to the 30s, and a roar that holds near its loudest for seconds with
# its 100-800 Hz as strong as its sub (the body's own harmonics: it is heard on any speaker). This is bigger: a deeper
# boom falling further and lasting longer, the vent heaving behind it, and the overload made a part of the sound, not
# hidden in it: the body driven hard and a fuzzed copy of the lows laid under it, so the boom growls and breaks up the
# way a recording of something too big for the microphone does.
REPORT_DRIVE = 16.0        # (the body's drive at its strongest, dB: held REPORT_HOLD s, then easing off over REPORT_EASE)
REPORT_HOLD, REPORT_EASE = 0.9, 2.6
REPORT_CRUNCH = -1.0       # (the fuzzed copy of the lows, dB against the 100-800 Hz the drive leaves while the boom peaks)
REPORT_FRONT_CLIP = 7.5    # (its first 0.3 s soft-clipped this far over the boom after it, dB: dense, the microphone overloaded)
REPORT_REST_CLIP = 4.0     # (and the roar after it, to 6 s, this far over it: its own peaks never reach the front's)


def overload(x, t0, drive_db, hold, ease, split=(70.0, 600.0), bias=0.22, makeup=0.55):
    """`x` driven as a blast far too big for the microphone: split at `split` (zero-phase, the bands summing back); the
    sub under it left clean; the body driven into a lopsided tanh (odd and even harmonics: crunch in the low mids, the boom
    heard on small speakers), its output kept to 30-2600 Hz so nothing new lands in the sub or as fizz; the top through a
    gentler tanh at half the drive, its grit. The drive `drive_db` from `t0` for `hold` s, then its dB easing away over
    `ease`; small signals pass at unity, so it thickens the loud part only, made up by `makeup` of the drive."""
    n = len(x)
    u = np.maximum(np.arange(n) / SR - t0, 0)
    gdb = drive_db * np.where(u < hold, 1.0, np.exp(-np.maximum(u - hold, 0) / ease))
    g = 10 ** (gdb / 20)
    sub = band(x, None, split[0], 2)
    rest = x - sub
    body = band(rest, None, split[1], 2)
    top = rest - body
    ref = np.percentile(np.abs(body), 99.9) + 1e-12
    z = g * body / ref
    sat = (np.tanh(z + bias) - np.tanh(bias)) / (1 - np.tanh(bias) ** 2)
    body_d = band(sat * ref / g, 30, 2600, 2)
    gt = np.sqrt(g)
    tref = np.percentile(np.abs(top), 99.9) + 1e-12
    top_d = np.tanh(gt * top / tref) * tref / gt
    return sub + body_d * g ** makeup + top_d * gt ** 0.5


def crunch(x, t0, lo=22.0, hi=150.0, out=(80.0, 1500.0), bias=0.3, hold=1.5, ease=2.5):
    """The lows of `x` fuzzed: hard-clipped nearly square (a little lopsided), only what the clip made new kept (`out`
    Hz: their 3rd, 5th, 7th..., and the even ones from the lopsidedness), at the lows' own level moment to moment, so it
    growls with the boom's pitch and falls with it, and is gone where they are quiet. Unit level over its loudest 400 ms
    times how much of it there is: full for `hold` s from `t0`, easing off over `ease` (the overload goes with the blow)."""
    n = len(x)
    u = np.maximum(np.arange(n) / SR - t0, 0)
    lb = band(x, lo, hi, 3)
    lev = np.sqrt(np.maximum(band(lb ** 2, None, 40.0, 2), 0)) + 1e-12
    v = lb / lev
    y = np.clip(v * 4.0 + bias, -1.0, 1.0) - np.clip(bias, -1.0, 1.0)
    y = F.cband(y * lev, out[0], out[1], 3)
    y = y * np.where(u < hold, 1.0, np.exp(-np.maximum(u - hold, 0) / ease)) * (u > 0)
    return y / (T.loudest(y) + 1e-12)


def report_body():
    """The report (see the module's notes and REPORT_DRIVE's): the front a blow that slams (the pressure jump, a sub
    falling in pitch, the chest's punch and a broad dull crack of the air), the mids dropping out after it while a deep
    boom swells on under them, falling from the 80s into the 20s and lasting; the vent's next heaves and the land's far
    side behind it; a heavy roar rolling in over it and holding for seconds; all of it driven into the overloaded
    microphone and growling with it; then the land giving it back for twenty seconds."""
    d = 26.0
    n = n_of(d)
    t = times(d)
    t0 = LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(61501):
        # ---- the push and the boom: one long pressure pulse, a deep boom falling on it, and three more blows of the vent
        # and of the land's far side (800 blocks across: its blow comes in seconds after the near side's)
        push = band(T.friedlander(n, t0, 0.34, 1.4), 13, 150, 2)
        push = push / (np.abs(push).max() + 1e-9)
        boom = S.blow(n, t0, 84.0, 36.0, 25.0, 0.13, 0.004, ((0.5, 0.3), (0.34, 1.1), (0.16, 3.2)), drive=4.0, octv=0.38, h3=0.24, harm=0.6)
        boom2 = S.blow(n, t0 + 0.38, 56.0, 32.0, 24.0, 0.12, 0.014, ((0.6, 0.3), (0.4, 1.0)), drive=3.5) * 0.62
        boom3 = S.blow(n, t0 + 1.06, 46.0, 29.0, 23.0, 0.12, 0.03, ((0.6, 0.34), (0.4, 1.2)), drive=3.0) * 0.46
        boom4 = S.blow(n, t0 + 1.8, 40.0, 27.0, 22.0, 0.14, 0.06, ((0.6, 0.4), (0.4, 1.4)), drive=3.0) * 0.32
        low = push * 1.4 + boom + boom2 + boom3 + boom4
        # (a body of low noise riding the booms, so they are a blast's and not a synth's: no clean sine left in it)
        benv = np.maximum(band(np.abs(low), None, 10, 1), 0)
        body = (T.unit(band(white(d), 30, 90, 3)) * 0.5 + T.unit(band(white(d), 80, 240, 2)) * 0.45) * benv * boil(n, 2.0, 12.0, 2.0)
        ref = np.sqrt(np.mean(low[n_of(t0):n_of(t0 + 0.4)] ** 2))
        # ---- the front: `impact`'s blow (a sub falling from 90 Hz, a punch of 45-300 Hz, a broad crack of 220 Hz-2.6 kHz,
        # its top as a kilometre of air leaves it), on the pressure jump
        with PB.seeded(61504):
            hit = impact(n, t0, (92.0, 44.0, 31.0), 0.06, (45.0, 300.0), 0.08, (220.0, 2600.0), 0.022, (1.0, 1.35, 1.0))
        hit = hit / (T.loudest(hit) + 1e-12) * ref * 0.8
        # ---- the roar: turbulence at every scale (`eddies`), low and broad, rolling in after the gap a little over itself
        # and holding near the top for two seconds, then going down under the column
        surge = heaves(d, 0.9, 0.5, 0.06, 0.45, 0.5, 0.1)
        roar = eddies(d, 40, 2200, 2.5, -2.2, 10.0, 5.0, surge, 1.2, 250.0)
        renv = db_curve(t, [(0, -80), (t0 + 0.05, -40), (t0 + 0.12, -6), (t0 + 0.2, 1.0), (t0 + 0.4, 0.0), (t0 + 2.0, -1.0),
                            (t0 + 3.2, -3.5), (t0 + 5.0, -8.0), (t0 + 8.0, -14.0), (t0 + 12.0, -21.0), (t0 + 18.0, -30.0), (d, -48.0)])
        roar = roar * renv * (0.8 + 0.2 * surge) * ref * 0.5 * on
        # (the gap: what is over 350 Hz of everything but the front dropping away 25-110 ms in, as a blast's mids do after
        # its crack, while the sub swells on: the front stands out of what follows)
        rest = low + body + roar
        gap = db_curve(u, [(0, 0), (0.025, 0), (0.045, -12), (0.09, -12), (0.13, 1.5), (0.2, 0), (1e9, 0)])
        hi_ = band(rest, 350, None, 2)
        x = (rest - hi_ + hi_ * gap + hit) * on
        # ---- the overload: the body driven hard, and the lows' fuzz laid under it, following the boom
        clean = x
        x = overload(x, t0, REPORT_DRIVE, REPORT_HOLD, REPORT_EASE) * on
        fz = crunch(x, t0)
        w0, w1 = n_of(t0 + 0.05), n_of(t0 + 0.6)
        have = np.sqrt(np.mean(band(x, 100, 800, 2)[w0:w1] ** 2))
        got = np.sqrt(np.mean(band(fz, 100, 800, 2)[w0:w1] ** 2)) + 1e-12
        x = x + fz * have / got * 10 ** (REPORT_CRUNCH / 20)
        # (how much of what is heard is the overload: its 100-800 Hz against the clean sound's, each against its 25-90 Hz)
        mid_lo = lambda y, a, b: 20 * np.log10(np.sqrt(np.mean(band(y, 100, 800, 2)[n_of(t0 + a):n_of(t0 + b)] ** 2))
                                               / np.sqrt(np.mean(band(y, 25, 90, 2)[n_of(t0 + a):n_of(t0 + b)] ** 2)))
        print("report: the overload's 100-800 Hz against the lows, clean -> driven: "
              + ", ".join(f"{a}-{b} s {mid_lo(clean, a, b):+.1f} -> {mid_lo(x, a, b):+.1f} dB" for a, b in ((0.05, 0.6), (0.6, 2.0), (2.0, 5.0))))
        # (and the front laid on again over the drive, so the blow stands out of the roar it starts: a fresh `impact`,
        # what follows let down just after it; the front clip later rounds it into the overloaded microphone)
        with PB.seeded(61505):
            hit2 = impact(n, t0, (90.0, 42.0, 30.0), 0.06, (45.0, 320.0), 0.09, (220.0, 2400.0), 0.02, (1.0, 1.3, 0.9))
        x = slam(x, t0, hit2, REPORT_SLAM, -6.5, (0.045, 0.12, 0.38))
        # ---- the land giving it back: echoes darker each time, rolls, a heaving sub bed
        src = band(x, None, 700, 2)
        for dt, g, hi in ((1.35, 0.3, 900), (2.6, 0.24, 640), (4.1, 0.19, 450), (6.2, 0.15, 320), (8.9, 0.12, 230), (12.4, 0.08, 170), (16.3, 0.05, 130)):
            e = band(src, 22, hi, 2)
            ir = rng().standard_normal(n_of(0.5)) * np.exp(-np.arange(n_of(0.5)) / (0.14 * SR))
            P.put(x, conv(e, ir / np.sqrt(np.sum(ir ** 2))) * g, dt)
        rl, rr = PB.thunder_rolls(d, t0 + 0.9, count=22, length=17.0)
        rolls = (rl + rr) / 2
        x += rolls / (T.loudest(rolls) + 1e-9) * ref * 0.34
        bed = T.unit(band(white(d), 17, 62, 3)) * boil(n, 0.1, 0.9, 3.0) * db_curve(t, [(0, -60), (0.8, -21), (3, -20), (8, -24), (15, -32), (22, -44), (26, -70)])
        x += bed * ref * 3.2
        x = land(x, 3.0, 0.16, (2200, 200), 1.2, seed=3)
        L, R = N.glue(x, x, 2.0, 0.01, 0.4, 6.0)
        x = PB.causal_lowcut((L + R) / 2 * on * T.fade(n, 0.0005, 3.5), 15.0)
    return x


def build_plate_sub():
    """One of the big plates coming down (vc_sound.rs's plate_down, pitched down by its size): a short push of the sub,
    a blow falling from the 50s into the 20s, clean. (Until the report's sub was made to hold, this was it.)"""
    d = 2.6
    n = n_of(d)
    with PB.seeded(61503):
        x = S.blow(n, LEAD, 52.0, 31.0, 24.0, 0.11, 0.005, ((0.62, 0.24), (0.38, 0.8)), drive=1.0, octv=0.0, h3=0.0, harm=0.0)
        push = band(T.friedlander(n, LEAD, 0.34, 1.4), 13, 90, 2)
        x = x + push / (np.abs(push).max() + 1e-9) * 0.75
    S.write("plate_sub", PB.causal_lowcut(band(x, None, 110, 2) * T.fade(n, 0.0005, 0.9), 14.0), -8.5, knee=0.6)


def build_report_sub():
    """The push under the report, played with it and again with the land's drop (pitched to 0.8): only the sub, the part
    that's felt. On the front the report's own boom's fall (84 Hz to 36 in a tenth of a second, on down to 25), clean,
    and the blast's pressure; then not a decay but a pressure that holds, a deep steady rumble (its beating taken out:
    no lumps, no pulse) settling a little lower in pitch and level and holding for seconds, then fading slowly. A file
    of its own, so together they go past what one file can."""
    d = REPORT_SUB_D
    n = n_of(d)
    t = times(d)
    t0 = LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(61506):
        boom = S.blow(n, t0, 84.0, 36.0, 25.0, 0.13, 0.004, ((0.45, 0.3), (0.35, 1.2), (0.2, 3.0)), drive=1.0, octv=0.0, h3=0.0, harm=0.0)
        boom = boom / (np.abs(boom).max() + 1e-9)
        push = band(T.friedlander(n, t0, 0.34, 1.4), 13, 90, 2)
        push = push / (np.abs(push).max() + 1e-9)
        # (the held pressure: two narrow bands of noise, held steady, sinking slowly from the boom's end to the low 20s)
        hold = (held(T.glide_noise(d, 31.0, 23.0, 0.45, curve=0.5), 0.5) * 1.0
                + held(T.glide_noise(d, 46.0, 36.0, 0.4, curve=0.5), 0.5) * 0.45)
        hold = held(hold, 0.35) * np.clip(1 + 0.08 * PB.slow_random(n, 0.1, 0.4), 0.5, None)
        henv = db_curve(u, [(0, -40), (0.04, -14), (0.25, -6), (0.6, -4.5), (2.5, -5.0), (4.5, -6.5), (6.5, -10), (8.0, -15), (d, -26)]) * on
        x = boom * 0.6 + push * 0.45 + hold * henv * 0.7
    write("report_sub", PB.causal_lowcut(band(x, None, 110, 2) * T.fade(n, 0.0005, 1.2), 14.0), knee=0.6)


def report_far_of(x, seed=31):
    """The report from further off: the same blast, its lows and its growl kept (the overload's crunch is in the low mids,
    and they carry), what is over 700 Hz going and its front smeared a little, all of it in the land's long dark reverb."""
    n = len(x)
    u = np.arange(n) / SR - LEAD
    soft_on = np.clip(u / 0.014, 0, 1) ** 2
    lo = band(x, None, 160, 2)
    mid = band(x, 160, 700, 2)
    up = band(x, 700, 1600, 2)
    hi = band(x, 1600, None, 2)
    y = lo * 0.95 + mid * np.sqrt(soft_on) * 0.85 + up * soft_on * 0.38 + P.air(hi, 2600) * soft_on * 0.06
    y = land(y, 7.0, 0.5, (1000, 140), 3.0, 30.0, seed=seed)
    return lows_heard(y, 60, 420, -6.0)


def front_clip(x, db, rest_db=REPORT_REST_CLIP):
    """The first 0.3 s of `x` soft-clipped `db` over the level of the boom after it (0.15-1 s in): dense, as the start of
    a recording of a blast too big for the microphone is; what follows rounded off lower, `rest_db` over it (the overload
    going on through the roar), so the front is what reaches the file's peak, standing out of what follows, and the
    game's limiter has nothing left to ride."""
    u = np.arange(len(x)) / SR - LEAD
    ref = np.sqrt(np.mean(x[n_of(LEAD + 0.15):n_of(LEAD + 1.0)] ** 2))
    over = 10 ** (np.interp(u, [0.0, 0.3, 0.45, 6.0, 8.0], [db, db, rest_db, rest_db, rest_db + 30.0]) / 20)
    knee = np.interp(u, [0.0, 0.3, 0.45], [0.4, 0.4, 0.6])
    return PB.soft_clip(x, ref * over, knee)


def gapped(x, deep=-10.0, sub=-6.0):
    """`x` with the instant after its front let down (`deep` dB, its lows under 80 Hz only `sub`) 40-125 ms in, coming
    back a little over itself by 0.19 s: a blast's negative phase, the air sucked back after the blow, so the front
    stands out of the roar it starts (the Payload's blasts drop 6-20 dB there)."""
    u = np.arange(len(x)) / SR - LEAD
    g_hi = db_curve(u, [(-1.0, 0.0), (0.04, 0.0), (0.06, deep), (0.125, deep), (0.19, 0.8), (0.28, 0.0), (1e9, 0.0)])
    g_lo = db_curve(u, [(-1.0, 0.0), (0.04, 0.0), (0.06, sub), (0.125, sub), (0.19, 0.0), (1e9, 0.0)])
    lo = band(x, None, 80, 3)
    return lo * g_lo + (x - lo) * g_hi


def build_report():
    x = report_body()
    # (the lows rounded a little over their loudest: this is what is felt, and a thump needs density, not peaks)
    lo = band(x, None, 130, 3)
    c = T.loudest(lo) * 10 ** (3.0 / 20)
    x = x - lo + PB.soft_clip(lo[:, None], c, 0.5)[:, 0]
    # (the blow at the top, the boom and the roar it starts 3 dB under it so it slams, what rolls off after it under them)
    x = x * db_curve(np.arange(len(x)) / SR - LEAD, [(-1, 0), (0.12, 0), (0.3, -3.0), (2.4, -3.0), (4.0, -4.0), (7, -5.5), (26, -5.5)])
    write("report", front_clip(gapped(x), REPORT_FRONT_CLIP), knee=0.8)
    with PB.seeded(61502):
        y = report_far_of(x, seed=31)
        # (from further off its front is a darker blow, laid on again so the land's long echo doesn't blunt it)
        hit = impact(len(y), LEAD, (80.0, 40.0, 29.0), 0.08, (40.0, 220.0), 0.09, (180.0, 1000.0), 0.024, (1.0, 1.0, 0.45))
        y = slam(y, LEAD, hit, REPORT_SLAM - 1.0, -6.0, (0.06, 0.16, 0.5))
    write("report_far", front_clip(gapped(y, -8.0, -4.5), REPORT_FRONT_CLIP) * T.fade(len(y), 0.0005, 3.0), knee=0.8)


# ===========================================================================================================  the column
def column_flow():
    """The mass flow through time: rising out of the fire, full by 18 s into the file, faltering and dropping in lurches
    at the collapse."""
    d = COLUMN_D
    t = times(d)
    F0 = FALTER
    flow = np.interp(t, [0, 2.5, 6, 11, 18, F0], [0, 0.06, 0.4, 0.82, 1.0, 1.0])
    flow = ease(flow, 0.6)
    lurch = np.interp(t, [F0, F0 + 0.5, F0 + 1.0, F0 + 1.6, F0 + 2.4, F0 + 3.2, F0 + 4.2, F0 + 6.0, d],
                      [1, 0.60, 0.72, 0.34, 0.44, 0.16, 0.09, 0.02, 0.0])
    return flow * ease(lurch, 0.12)


def plinian():
    """The Plinian column near: a thing far louder than any engine, heard a kilometre off. Its roar is turbulence at every
    scale at once (`eddies`), low and broad, and never steady: it comes in surges, big uneven ones the vent's own and quick
    ones in between, and each surge doesn't only get louder, it opens upward. What tears is the roar's own waves steepened
    into shocks (`steepen`) on the way out of the jet, kept with the lows that make them, so each rip has its weight
    under it. In it the rock going up: a rattle of blows thick as the surges (`rocks`), and all of it off the land round
    about. The fire before it is the same stuff, its own heaves running through it."""
    d = COLUMN_D
    n = n_of(d)
    t = times(d)
    F0 = FALTER
    with PB.seeded(61611):
        f = column_flow()
        big = heaves(d, 3.2, 0.75, 0.45, 1.5, 0.6, 0.8)
        quick = heaves(d, 0.75, 0.5, 0.05, 0.3, 0.6, 0.4)
        # (its surges rounded over the top: it's a density, and the report and the collapse have to stay over it)
        surge = 0.2 + 2.6 * np.tanh(np.maximum(0.55 * big + 0.45 * quick - 0.2, 0) / 2.6)
        # (the rips: the same few moments right across the sound, as a shock is, in flurries with the surges)
        burst = np.clip(N.grains(d, 15.0, (0.025, 0.07, 0.18)), 0, 6) ** 0.7
        gust = boiled(n, 1.0, 9.0, 5.0)
        sub = T.unit(band(white(d), 15, 46, 3)) * boil(n, 0.1, 0.8, 3.0) * (0.8 + 0.3 * big) * f ** 0.6
        rum = eddies(d, 30, 170, 2.5, -1.0, 9.0, 6.0, surge, 1.0) * (0.75 + 0.35 * surge) * f ** 0.8
        roar = eddies(d, 120, 3400, 3.0, -2.3, 12.0, 6.5, surge, 3.2, 300.0) * (0.5 + 0.55 * surge) * f * gust ** 0.8 * burst ** 0.45
        # (the tear: the wave's own fronts stand up where it's strongest, so the rips come with the surges)
        src = eddies(d, 90, 1800, 3.0, -2.0, 12.0, 5.0, surge, 2.0, 300.0) * gust * burst ** 0.5
        tear = steepen(T.unit(src), 3.2e-4 * np.clip(f * surge, 0, 2.2) ** 0.9 * burst ** 0.5)
        print(f"column: crackle (skewness of dp/dt) {skew_dt(tear[n_of(14):n_of(30)]):.2f}")
        tear = T.unit(F.cband(tear, 200, 7500, 2)) * f ** 1.2 * (0.55 + 0.5 * surge)
        rate = (35.0 + 240.0 * np.clip(surge - 0.3, 0, 3) ** 1.2) * f ** 1.4 + 1e-3
        rattle = rocks(d, rate, 170, 1300, (0.2, 0.45, 1.0), (0.6, 0.32, 0.08)) * f ** 0.6
        top = eddies(d, 3000, 7500, 2.0, -5.0, 16.0, 2.5, surge, 2.5) * f ** 1.4 * (0.45 + 0.55 * surge) * burst ** 0.5
        # (the fire: the same stuff, wider and rougher, its own slow heaves, the land coming down in it)
        heave = heaves(d, 0.95, 0.42, 0.24, 1.0, 0.5, 0.0)
        heave = heave / np.percentile(heave, 99)
        fl = eddies(d, 30, 160, 2.5, -1.0, 8.0, 6.0, heave + 0.6, 1.0) * (0.55 + 0.8 * heave)
        fm = eddies(d, 130, 1100, 3.0, -3.5, 11.0, 6.0, heave + 0.6, 1.6) * (0.45 + 0.9 * heave)
        ft = eddies(d, 900, 3600, 2.5, -4.0, 13.0, 4.0, heave + 0.6, 1.6) * (0.3 + 0.9 * heave)
        falls = rocks(d, np.full(n, 13.0), 26, 420, (0.8, 1.6, 2.6), (0.6, 0.3, 0.1), 1.9)
        fire_env = db_curve(t, [(0, -70), (0.7, -34), (1.8, -11), (3.0, -3), (4.0, 0), (9.0, 0), (12.0, -5), (18, -13), (26, -22), (F0, -26), (F0 + 2, -60), (d, -90)])
        lo_on = db_curve(t, [(0, -60), (1.2, -26), (2.6, -5), (3.6, 0), (d, 0)])
        parts = dict(sub=sub, rum=rum, roar=roar, tear=tear, rattle=rattle, fl=fl, fm=fm, ft=ft, falls=falls,
                     fire_env=fire_env, lo_on=lo_on, f=f, surge=surge, big=big)
        x = (sub * 0.9 + rum * 0.85 + roar * 1.1 + tear * 0.85 + rattle * 0.34 + top * 0.08
             + (fl * 1.0 + fm * 0.95 + ft * 0.3) * fire_env + falls * fire_env * lo_on * 0.7)
        x = land(x, 3.5, 0.3, (1500, 190), 1.6, 40.0, seed=22)
        x = lows_heard(x, 70, 300, -9.0)
        return (lambda g: (g[0] + g[1]) / 2)(N.glue(x, x, 1.5, 0.03, 0.5, 8.0)), parts


def far_rolls(d, f, big, falter):
    """Thunder-like rolls of the column off the land round about, heard from far off: deep swells (28-240 Hz, no edge),
    each arriving on its own after a big surge of the vent (`big`'s peaks) and a darker echo of it a moment later, as
    many as the flow `f` drives, and the biggest with the collapse's lurches from `falter` on. Unit level at the top."""
    n = n_of(d)
    t = times(d)
    base = T.unit(F.cband(white(d), 28, 240, 2))
    dark = T.unit(F.cband(white(d), 24, 140, 2))
    at = list(pulse_train(d - 3.0, 2.3, 0.6, 2.2))
    amp = [float(np.minimum(np.exp(rng().normal(0, 0.45)), 2.4) * f[min(n_of(c), n - 1)] ** 0.8 * (0.6 + 0.25 * big[min(n_of(c), n - 1)])) for c in at]
    for c, a in ((falter + 0.1, 1.5), (falter + 1.05, 1.2), (falter + 1.7, 1.0), (falter + 2.5, 0.7), (falter + 3.4, 0.45)):
        at.append(c)
        amp.append(a)
    y = np.zeros(n)
    for c, a in zip(at, amp):
        w = rng().uniform(0.5, 1.5)
        k0, k1 = max(n_of(c - 0.4), 0), min(n_of(c + w * 6), n)
        u = t[k0:k1] - c
        sh = np.where(u < 0, np.exp(-0.5 * (u / (0.09 + 0.06 * w)) ** 2), np.exp(-u / w))
        y[k0:k1] += base[k0:k1] * sh * a
        e = c + rng().uniform(0.5, 1.2)
        k0, k1 = max(n_of(e - 0.5), 0), min(n_of(e + w * 7), n)
        u = t[k0:k1] - e
        sh = np.where(u < 0, np.exp(-0.5 * (u / 0.2) ** 2), np.exp(-u / (w * 1.3)))
        y[k0:k1] += dark[k0:k1] * sh * a * 0.5
    return y / (T.loudest(y) + 1e-12)


def column_far(parts):
    """The column from further off, with all the life the near one has, darker: the same surges and the same column (the
    vent's big heaves and the quick ones between, its flow rising out of the fire and faltering at the collapse), what
    carries of it kept and made to carry them: its sub and its rumble, the roar's low mids following the surges harder,
    the tearing gone dull, the rock going up a dark rattle in it, the fire's roar before it, and thunder-like rolls of it
    off the land round about after its big surges and with the collapse's lurches; all in the land's long dark reverb."""
    p = parts
    d = COLUMN_D
    with PB.seeded(61602):
        sw = p["surge"]
        roar = F.cband(p["roar"], None, 1100, 2) * (0.35 + 0.65 * sw) ** 1.3
        tear = P.air(F.cband(p["tear"], 150, None, 2), 1900)
        rattle = F.cband(p["rattle"], None, 950, 2)
        fire = ((p["fl"] * 1.0 + F.cband(p["fm"], None, 900, 2) * 0.95 + P.air(p["ft"], 1400) * 0.25) * p["fire_env"]
                + p["falls"] * p["fire_env"] * p["lo_on"] * 0.75)
        x = p["sub"] * 1.15 * (0.75 + 0.25 * p["big"]) + p["rum"] * 1.1 * (0.6 + 0.4 * sw) + roar * 0.85 + tear * 0.95 + rattle * 0.5 + fire
        rolls = far_rolls(d, p["f"], p["big"], FALTER)
        x = x + rolls * T.loudest(x) * db_of(0.0)
        x = land(x, 6.5, 0.5, (900, 140), 2.6, 30.0, seed=23)
        x = lows_heard(x, 70, 300, -8.0)
        return (lambda g: (g[0] + g[1]) / 2)(N.glue(x, x, 1.5, 0.03, 0.5, 8.0))


def build_column():
    """Near, the column (`plinian`). Far: the same column further off (`column_far`)."""
    near, parts = plinian()
    far = column_far(parts)
    n = n_of(COLUMN_D)
    # (the lows' lumps rounded over the top: the fire is a density, and the two files stack, so no blow of its own may reach
    # as high as the report's)
    def rounded(x):
        lo = band(x, None, 220, 3)
        x = x - lo + PB.soft_clip(lo[:, None], T.loudest(lo) * 10 ** (6.0 / 20), 0.5)[:, 0]
        return PB.soft_clip(x[:, None], T.loudest(x) * 10 ** (8.5 / 20), 0.7)[:, 0]
    write("column", PB.causal_lowcut(rounded(near) * T.fade(n, 0.4, 1.6), 14.0), knee=0.6)
    write("column_far", PB.causal_lowcut(rounded(far) * T.fade(n, 0.4, 1.6), 14.0), knee=0.6)


# =============================================================================================================  the bombs
def build_whistle(v):
    """A lava bomb coming down close by: a lump of rock the size of a car tearing through the air at you, not a cartoon's
    bomb, no whistle in it. A deep roaring rush with the weight of the thing in it, its middle climbing as it comes on;
    over it the wake tearing, ragged where the turning rock bites the air; the tumble slow and uneven, every turn its own
    (a flat face catching now and then, the rush lurching), never a steady beat; the air it shoves ahead of it swelling
    under it as it closes. Where it is sets everything, as it does for a real one: its level is its distance, so nothing
    for a long time and then all at once; the air takes the top till it's close; the Doppler lifts the whole sound while
    it's coming on; the sound off the ground, a moment behind, makes a comb that closes as it comes down. Cut on its
    landing."""
    d = [3.2, 4.2, 2.6][v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(61710 + v):
        speed, past = [150.0, 130.0, 175.0][v - 1], [34.0, 46.0, 28.0][v - 1]
        w = d - t
        r = np.hypot(speed * w, past)
        near = past / r
        doppler = 1 / (1 - (speed / 343.0) * speed * w / r)
        # (the tumble: a lopsided lump turning over slowly at a rate that wanders a lot, every turn its own: how hard it
        # catches the air (heavy-tailed: now and then a flat face bites and the rush lurches), where in the turn, how wide;
        # never a steady beat, which is what made the last take a propeller)
        turn = [2.6, 2.1, 3.3][v - 1] * np.clip(1 + 0.4 * PB.slow_random(n, 0.3, 1.6), 0.35, None) * doppler ** 0.5
        tp = np.cumsum(turn) / SR
        k = tp.astype(int)
        frac = tp - k
        kk = int(k.max()) + 2
        bite = np.minimum(np.exp(rng().normal(0, 0.5, kk)), 3.2)
        at = rng().uniform(0.25, 0.75, kk)
        wide = rng().uniform(0.08, 0.2, kk)
        face = bite[k] * np.exp(-0.5 * ((frac - at[k]) / wide[k]) ** 2) + 0.45 * bite[k] ** 0.5 * np.exp(-0.5 * ((frac - (at[k] + 0.5) % 1) / 0.12) ** 2)
        lob = ease(face, 0.012)
        lob = lob / (np.mean(lob) + 1e-9) - 1.0
        # (the air it tears through: the rush noise laid out faster than it's heard, for the Doppler to read back)
        m = int(np.sum(doppler)) + 16
        rd = lambda y: np.interp(np.cumsum(doppler) - doppler[0], np.arange(len(y)), y)
        # its body: a deep roaring rush whose middle climbs as it comes on (110 Hz to over 300), the weight of the thing
        body = rd(T.glide_noise(m / SR, 110.0, 320.0, 1.6, curve=2.2))
        # its tear: the wake at every scale, its fronts steepened into a ragged rip where the turn bites
        wake = eddies(m / SR, 300, 6500, 3.0, -2.4, 9.0, 7.0)
        tear = rd(F.cband(steepen(T.unit(wake), 1.6e-4), 280, None, 2))
        x = (body * db_of(lob * 3.5) * 1.0 + F.cband(tear, None, 1600, 2) * db_of(lob * 6.0) * 0.8
             + F.cband(tear, 1600, None, 2) * db_of(lob * 9.0) * 0.55)
        # (the air's share of its top: 25 blocks in every 1,000 Hz, near enough)
        fc = np.clip(16000.0 * near, 1200.0, 8500.0)
        x = T.lowpass_glide(x, fc[0], fc[-1], 1.1)
        x = T.flange(x, 2 * past * past / (speed * d) / 343.0 * 3.0, 0.0006, 0.42, 0.75)
        # (the air it shoves ahead of it, felt as it closes: a low push lurching with the tumble, swelling into a pressure
        # in the last instants)
        shove = T.unit(F.cband(white(d), 26, 160, 2)) * db_of(lob * 4.0) * np.clip(1 + 0.35 * PB.slow_random(n, 2.0, 9.0), 0.2, None)
        x = T.unit(x) + shove * (0.15 + 0.7 * np.clip(past * 2.5 / r, 0, 1) ** 1.2)
        x = lows_heard(x, 60, 280, -9.0)
        x = x * near ** 0.95
        x = PB.soft_clip(x[:, None], T.loudest(x) * 10 ** (8.0 / 20), 0.6)[:, 0]
        x *= np.clip((d - t) / 0.006, 0, 1)
    write(f"whistle{v}", PB.causal_lowcut(x * T.fade(n, 0.15, 0.001), 24.0), kind="whistle")


def build_thud(v):
    """A bomb landing close: tonnes of rock at a couple of hundred blocks a second, the ground going up round it. It's an
    explosion, small and of earth, so it's built as the strike's approved blasts are (`PB.explosion_live`, on the table
    of a real one, quick and with the top taken off by the distance), on a blow of the ground that's felt, with the
    earth it throws slumping back and the land round about giving it back."""
    d = 3.4
    n = n_of(d)
    t = times(d)
    with PB.seeded(61810 + v):
        size = [1.1, 0.8, 1.4, 1.0][v - 1]
        t0 = LEAD
        u = np.maximum(t - t0, 0)
        L, R = PB.explosion_live(d, t0, stretch=0.16 + 0.05 * size, debris=0.0, whump=1.6, live=1.0)
        x = F.cband((L + R) / 2, None, 4800, 2) * np.exp(-u / (0.4 + 0.22 * size))
        ref = T.loudest(x)
        # (the ground's blow: noise and a few swings of a falling pitch, as the Payload's land answers)
        g = soundlib.thump(n, t0, rng().uniform(58, 66), 27.0, 0.13 + 0.05 * size, 6.0) * (1 - np.exp(-u / 0.012))
        g += T.unit(F.cband(white(d), 22, 130, 2)) * (1 - np.exp(-u / 0.012)) * np.exp(-u / (0.13 + 0.06 * size)) * 0.8
        # (the earth thrown up, slumping back: a dull heavy rush of blows)
        fall = (1 - np.exp(-np.maximum(u - 0.1, 0) / 0.12)) * np.exp(-u / 0.55) * (u > 0.1)
        earth = rocks(d, 90.0 * fall + 1e-3, 80, 900, (0.5, 1.0, 1.8), (0.55, 0.35, 0.1))
        x = x + g * ref * 1.5 + earth * fall * ref * 0.22
        x = land(x, 2.4, 0.3, (2000, 170), 0.9, seed=140 + v)
        x = lows_heard(x, 70, 320, -6.0)
        L, R = N.overdrive(x, x, t0)
        # (its front a blow you feel: the sub falling in pitch, the chest's punch, the rock's crack, what follows let down
        # just after it; the bigger, the deeper)
        f0 = 76.0 - 10.0 * size
        hit = impact(n, t0, (f0, f0 * 0.56, f0 * 0.45), 0.05 + 0.02 * size, (48.0, 300.0), 0.05 + 0.02 * size,
                     (450.0, 3800.0), 0.009, (1.0, 1.0, 0.55))
        x = slam((L + R) / 2, t0, hit, 0.0, -4.5, (0.05, 0.25, 0.6))
    write(f"thud{v}", PB.causal_lowcut(x, 20.0) * T.fade(n, 0.0005, 0.9), kind="thud", knee=0.6)


def build_spatter(v):
    """What a bomb throws up, coming back down round where it hit, a hundred blocks off and less: the way the Payload's and
    the Nuke's debris comes down. A few big stones thrown hard, then the bulk of it, thinning: clods thudding, stones
    knocking on the land, each with its body under it and its top taken off by the distance it's come; the further ones
    dull and in the land's echo. Under them the dirt raining down is a soft dense wash, nothing that can be counted."""
    d = [3.8, 4.6, 3.4][v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(61860 + v):
        near_bus = np.zeros(n)
        far_bus = np.zeros(n)
        rate = lambda s: 15.0 * np.clip((s - 0.25) / 0.7, 0, 1) * np.exp(-max(s - 1.0, 0) / 0.95) + 2.2 * np.exp(-s / 1.2)
        for tc in P.poisson_times(0.18, d - 0.6, rate):
            near = rng().random() ** 1.4
            kind = rng().random()
            if kind < 0.5:                      # (a clod of earth)
                size = min(rng().pareto(2.0) * 0.3 + 0.25, 1.6)
                y = T.thud(n_of(0.2 + 0.3 * size), size) * (0.25 + 0.75 * size)
            elif kind < 0.9:                    # (a stone: a short dull knock in the mids, on a clod's thud)
                size = rng().uniform(0.25, 0.9)
                m = n_of(0.18)
                q = np.arange(m) / SR
                lo, hi = rng().uniform(260, 460), rng().uniform(1100, 2600)
                y = T.unit(F.cband(rng().standard_normal(m), lo, hi, 2)) * (1 - np.exp(-q / 0.0006)) * np.exp(-q / rng().uniform(0.006, 0.02))
                y = y * 0.8 * size + T.thud(m, 0.3 * size) * 0.12 * size
                if rng().random() < 0.3:
                    h = P.modal_hit(m, rng().uniform(420, 1100), [1.0, rng().uniform(1.5, 2.2), rng().uniform(2.6, 3.8)],
                                    [rng().uniform(0.005, 0.016), 0.005, 0.003], [1.0, 0.6, 0.3], 0.25, 3800)
                    y = y + h / (np.abs(h).max() + 1e-9) * 0.5 * size
                if rng().random() < 0.3:
                    P.put(y, y * rng().uniform(0.25, 0.5), rng().uniform(0.06, 0.16))
            else:                               # (a slab, landing off)
                y = T.thud(n_of(0.7), rng().uniform(1.5, 2.4)) * 0.9
                near *= 0.4
            y = F.cband(y, None, 1800 + 4200 * near, 2)
            P.put(near_bus, y * (0.3 + 0.7 * near), tc)
            P.put(far_bus, y * (1 - near), tc)
        wet = conv(far_bus, T.outdoor_ir(1.8, 150 + v, density=40.0, darken=(1800, 260), decay=0.6))
        fall = db_curve(t, [(0, -60), (0.5, -36), (1.3, -27), (2.3, -31), (d, -60)])
        wash = T.unit(F.cband(white(d), 320, 3000, 1)) * boil(n, 1.0, 7.0, 3.0) * fall * 0.9
        x = near_bus + far_bus * 0.5 + wet * 0.6 + wash
    write(f"spatter{v}", F.cband(x, 95, None, 1) * T.fade(n, 0.02, 0.7), kind="spatter")


def build_thud_far(v):
    """A bomb landing off on the land: a dull thump and its echo. Nothing of the rock breaking carries this far."""
    d = 3.0
    n = n_of(d)
    with PB.seeded(61900 + v):
        x = soundlib.thump(n, 0.03, [58, 50, 66][v - 1], 26, 0.26, 7.0)
        x += T.unit(band(white(d), 40, 170, 2)) * (1 - np.exp(-times(d) / 0.02)) * np.exp(-times(d) / 0.12) * 0.25
        x = land(band(x, None, 300, 2), 2.4, 0.5, (500, 120), 1.0, seed=50 + v)
        x = lows_heard(x, 60, 240, -6.0)
    write(f"thud_far{v}", PB.causal_lowcut(x, 20.0) * T.fade(n, 0.005, 0.8), kind="thud_far")


# ==========================================================================================================  the collapse
def collapse_body(falling=None):
    """A colossal groan of the ground going (rock sliding on rock, down through the audible floor, cracks going off in
    it); the land mass dropping, a slow enormous blow with no edge; then the sustained thunder of it falling: big
    impacts overlapping into one long roll, a grinding roar over it, thinning over twelve seconds. `falling(d, Td, ref)`,
    if given, is what falls after the drop instead."""
    d = 24.0
    n = n_of(d)
    t = times(d)
    Td = DROP
    with PB.seeded(62201):
        # ---- the groan
        g_d = Td + 1.6
        gn = n_of(g_d)
        gt = np.arange(gn) / SR
        swell = np.clip(gt / (Td * 0.9), 0, 1) ** 1.3 * (0.75 + 0.25 * np.clip(0.5 + 0.5 * PB.slow_random(gn, 0.8, 3.0), 0, 1))
        res = np.zeros(gn)
        for k, (w, a) in enumerate(((0.3, 1.0), (0.4, 0.55), (0.5, 0.32), (0.6, 0.2))):
            res += T.glide_noise(g_d, 62.0 * 1.62 ** k, 24.0 * 1.62 ** k, w, curve=0.8) * a
        groan = T.unit(res) * swell
        grind = T.stick_slip(g_d, 8.0, 60, 420, 0.9, 5.0)
        groan = groan + T.unit(grind) * swell ** 1.6 * 0.5
        groan *= np.clip((g_d - gt) / 1.1, 0, 1) ** 1.5
        x = np.zeros(n)
        P.put(x, groan, 0.0)
        for _ in range(7):
            tc = rng().uniform(0.5, Td - 0.3)
            P.put(x, band(H.rock_crack(1.4, rng().uniform(0.8, 1.6), 0.6), None, 1400, 2) * rng().uniform(0.2, 0.5), tc)
        # ---- the drop: slow, enormous, no edge
        boom = S.blow(n, Td, 46.0, 28.0, 22.0, 0.32, 0.07, ((0.5, 0.6), (0.33, 1.7), (0.17, 4.5)), drive=3.0, octv=0.34, h3=0.2, harm=0.5)
        boom2 = S.blow(n, Td + 0.9, 38.0, 26.0, 21.0, 0.25, 0.09, ((0.6, 0.7), (0.4, 2.0)), drive=2.5) * 0.6
        press = band(T.friedlander(n, Td, 0.7, 1.2), 13, 100, 2)
        press = press / (np.abs(press).max() + 1e-9)
        low = boom + boom2 + press * 1.2
        ref = np.sqrt(np.mean(low[n_of(Td + 0.1):n_of(Td + 0.5)] ** 2))
        x = x * ref * 0.45 + low
        if falling is not None:
            x = x + falling(d, Td, ref)
            x = land(x, 3.5, 0.16, (1500, 180), 1.5, seed=7)
            x = lows_heard(x, 70, 420, -4.0)
            L, R = N.glue(x, x)
            L, R = N.overdrive(L, R, Td)
            return PB.causal_lowcut((L + R) / 2 * T.fade(n, 0.6, 3.5), 15.0)
        # ---- the land falling: impacts on impacts
        rate = lambda s: 3.0 + 13.0 * np.exp(-s / 5.0)
        fall = np.zeros(n)
        tc = Td + 0.15
        while tc < d - 3.0:
            s = tc - Td
            size = min(rng().pareto(2.0) * 0.6 + 0.8, 3.5)
            m = n_of(0.5 + 0.35 * size)
            P.put(fall, T.thud(m, size * 1.2) * rng().uniform(0.5, 1.0) * np.exp(-s / 7.5), tc)
            tc += rng().exponential(1.0 / rate(s))
        fall = fall / (T.loudest(fall) + 1e-9) * ref * 0.6
        x += band(fall, 26, 420, 2)
        heave = boil(n, 0.2, 1.2, 3.5)
        rum = T.unit(band(white(d), 24, 95, 2)) * heave * db_curve(t, [(0, -70), (Td, -40), (Td + 0.7, -9), (Td + 3, -8), (Td + 8, -13), (Td + 14, -24), (d, -70)])
        clump = np.clip(N.grains(d, 7.0, (0.05, 0.12, 0.3)), 0, 7) ** 0.7
        roll = T.unit(band(white(d), 90, 300, 2)) * clump * db_curve(t, [(0, -70), (Td, -40), (Td + 0.9, -15), (Td + 4, -15), (Td + 9, -23), (Td + 14, -36), (d, -70)])
        slide = T.unit(band(white(d), 280, 1000, 1.5)) * boil(n, 2.0, 12.0, 4.0) * db_curve(t, [(0, -80), (Td + 0.2, -50), (Td + 1.2, -24), (Td + 5, -25), (Td + 10, -35), (Td + 15, -52), (d, -80)])
        x += (rum + roll + slide) * ref
        x = land(x, 3.5, 0.16, (1500, 180), 1.5, seed=7)
        x = lows_heard(x, 70, 420, -4.0)
        L, R = N.glue(x, x)
        L, R = N.overdrive(L, R, Td)
        x = PB.causal_lowcut((L + R) / 2 * T.fade(n, 0.6, 3.5), 15.0)
    return x


# When the land's slabs go, after the drop (s), and how big: it doesn't fall all at once, it goes in waves, each a great
# piece of it coming down and what it brings with it.
SLABS = ((1.7, 1.0), (2.5, 0.75), (2.9, 0.5), (4.6, 1.15), (5.7, 0.7), (6.5, 0.45), (8.4, 0.95), (9.6, 0.6), (11.6, 0.65), (13.7, 0.45), (15.8, 0.3))
WAVES = (1.2, 4.5, 8.3, 11.6)


def falling(d, Td, ref):
    """The land going down, after the blow of the drop: not a noise that fades but things happening, in four waves. Great
    slabs of it landing (a slow heavy blow, no edge, the rock of it breaking, each off the land's far side a moment
    later), the slide of the rock between them boiling at every scale and opening up with each wave (`eddies`), a rattle of
    rock through it thick as the wave, the land's rolling answers and the ground heaving under all of it, each wave lower
    and further off than the last."""
    n = n_of(d)
    t = times(d)
    s_ = t - Td
    with PB.seeded(62211):
        wave = np.zeros(n)
        for k, w0 in enumerate(WAVES):
            u = s_ - w0
            wave += (1 - np.exp(-np.maximum(u, 0) / 0.4)) * np.exp(-np.maximum(u, 0) / (1.25 + 0.25 * k)) * (u > 0) * 0.88 ** k
        wave = ease(wave, 0.15) + 0.04
        wave *= boil(n, 0.4, 2.0, 2.0)
        fade = db_curve(t, [(0, -80), (Td + 0.6, -60), (Td + 1.3, -3), (Td + 3, 0), (Td + 9, -4), (Td + 14, -12), (Td + 18, -26), (d, -80)])
        slide = eddies(d, 55, 1900, 3.0, -5.2, 11.0, 6.0, np.clip(wave * 1.3, 0.2, 2.5), 1.7, 280.0)
        slide = slide * (0.12 + 1.15 * wave) * fade
        rate = (40.0 + 300.0 * np.clip(wave, 0, 2) ** 1.2) * db_curve(t, [(0, -60), (Td + 0.8, -30), (Td + 1.4, 0), (Td + 8, -5), (Td + 16, -18), (d, -40)]) + 1e-3
        rattle = rocks(d, rate, 130, 1100, (0.3, 0.7, 1.4), (0.55, 0.33, 0.12)) * fade ** 0.6 * (0.15 + 0.95 * wave)
        x = slide * 0.34 + rattle * 0.16
        for dt, size in SLABS:
            k = n_of(5.0)
            y = S.blow(k, 0.0, 52.0 - 6 * size, 29.0, 22.0, 0.16, 0.008, ((0.6, 0.4 + 0.35 * size), (0.4, 1.2 + 0.8 * size)), drive=2.5) * 0.8
            P.put(y, bare_blow(2.2 + size, 24, 150, 0.006, 0.2) * 1.3, 0.0)
            q = np.arange(k) / SR
            # (the rock of it breaking: a burst of blows, no edge of its own)
            y = y + rocks(5.0, 420.0 * (1 - np.exp(-q / 0.05)) * np.exp(-q / (0.16 + 0.22 * size)) + 1e-3, 90, 620, (0.5, 1.0, 1.8), (0.5, 0.36, 0.14)) * (1 - np.exp(-q / 0.05)) * np.exp(-q / (0.3 + 0.3 * size)) * 0.55
            P.put(x, y * size * 0.75 * (0.82 ** (dt / 4.0)) * rng().uniform(0.85, 1.1), Td + dt)
            P.put(x, F.cband(y, None, 420, 2) * size * 0.2, Td + dt + rng().uniform(0.7, 1.5))
        rl, rr = PB.thunder_rolls(d, Td + 0.8, count=26, length=17.0)
        rolls = (rl + rr) / 2
        x = x + rolls / (T.loudest(rolls) + 1e-9) * 0.24
        bed = T.unit(band(white(d), 17, 62, 3)) * boil(n, 0.1, 0.9, 3.5) * (0.5 + 0.5 * np.clip(wave, 0, 1.5)) * fade
        return (x + bed * 0.26) * ref * 0.86


def build_collapse():
    # (its opening kept exactly as it was: the groan, the cracks and the blow of the drop are the first take, and from a moment
    # after the blow it hands over to the land falling, on the same groan and the same blow, so nothing joins that shows)
    first = collapse_body()
    x = collapse_body(falling)
    t = times(24.0)
    a, b = DROP + 0.9, DROP + 1.7
    m = (t >= a - 0.7) & (t < a)
    x = x * (np.sqrt(np.mean(first[m] ** 2)) / (np.sqrt(np.mean(x[m] ** 2)) + 1e-12))
    u = np.clip((t - a) / (b - a), 0, 1)
    x = first * np.cos(u * np.pi / 2) + x * np.sin(u * np.pi / 2)
    # (the blow stays the loudest thing in it, so the file's level, and so its opening, stay exactly where they were)
    for _ in range(3):
        x = x * (1 - (1 - min(T.loudest(first) / T.loudest(x), 1.0)) * np.clip((t - a + 0.1) / 0.5, 0, 1))
    # (the drop made a blow: the land mass landing (`ground_blow`: no clean sine, no click, a body of rock hitting rock
    # and arriving over a few hundred ms by many paths), what follows let down a moment, so it stands well out of the
    # groan before it. The groan itself kept where it was: the file's level is raised by what the blow adds, less
    # COLLAPSE_GIVE dB)
    with PB.seeded(62204):
        hit = ground_blow(len(x), DROP, 1.0, 0.0)
    y = slam(x, DROP, hit, 1.0, -4.0, (0.1, 0.5, 1.2))
    keep = 20 * np.log10(T.loudest(y) / T.loudest(x)) - COLLAPSE_GIVE
    S.write("collapse", y, LEVEL["collapse"] + keep, knee=0.5)
    with PB.seeded(62202):
        z = far_of(x, 24.0, lo_gain=0.9, seed=33, soften=0.0001)
    with PB.seeded(62205):
        hit = ground_blow(len(z), DROP, 1.15, 1.0)
        z = slam(z, DROP, hit, 2.0, -4.0, (0.12, 0.55, 1.3))
    S.write("collapse_far", z * T.fade(len(z), 0.6, 3.0), LEVEL["collapse_far"] + keep, knee=0.5)


def ground_blow(n, t0, size=1.0, far=0.0):
    """A land mass landing, as a blow of the ground: what `impact`'s clean falling sine and its short crack made cheap (a
    kick drum's thump, a tock) left out. Its pressure a slow heave (no edge sharper than 20 ms); its sub low noise, not a
    tone; its body many arrivals over a third of a second (the blow coming by every path through the land, each later one
    duller), the chest's 60-400 Hz; the rock of it breaking, a dense crunch dying with it; and the ground ringing on after
    it, long and dark. `far` 0 to 1: the top and the crunch going, the front smeared further, more of the ring."""
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    on = t >= t0
    d = n / SR
    press = F.cband(T.friedlander(n, t0, 0.18 * size, 1.5), 13, 75, 2)
    press = press / (np.abs(press).max() + 1e-9) * (1 - np.exp(-u / (0.012 + 0.02 * far)))
    sub = T.unit(F.cband(rng().standard_normal(n), 20, 62, 2)) * (1 - np.exp(-u / (0.025 + 0.02 * far))) * np.exp(-u / (0.22 * size)) * on
    body = np.zeros(n)
    for dt, g, hi in ((0.0, 1.0, 480), (0.03, 0.5, 420), (0.075, 0.38, 340), (0.14, 0.28, 270), (0.23, 0.2, 210), (0.36, 0.13, 170)):
        ud = np.maximum(t - t0 - dt * (1 + 0.3 * far), 0)
        b = T.unit(F.cband(rng().standard_normal(n), 38, hi * (1 - 0.35 * far), 2))
        body += b * (1 - np.exp(-ud / (0.008 + 0.012 * far))) * np.exp(-ud / ((0.07 if dt == 0 else 0.13) * size)) * (ud > 0) * g
    crunch = (T.unit(F.cband(rng().standard_normal(n), 140, 900 * (1 - 0.5 * far), 2)) * np.clip(N.grains(d, 220.0, (0.006, 0.015, 0.04)), 0, 6) ** 0.6
              * (1 - np.exp(-u / 0.006)) * np.exp(-u / (0.16 * size)) * on)
    x = press * 0.45 + sub * 0.35 + body * 0.5 + crunch * 0.12 * (1 - 0.6 * far)
    x = earth_ring(x, 2.2, 0.25 + 0.2 * far, (560 - 200 * far, 50), 0.4 + 0.15 * far, seed=77 + int(far))
    return lows_heard(x, 55, 300, -6.0)


# ==============================================================================================================  the flow
def build_flow_rise(v):
    """The front closing, on what comes first: the ground, through which it reaches the player soonest, then a low roar,
    the rush opening up, the wind it pushes ahead of it and last of all the hiss, which the air takes longest to give up.
    Every take the same run to its end, its curves counted back from the hit, the longer ones only starting further
    back. It stops on the hit (under `flow_hit`), and fades in from nothing."""
    d = RISES[v - 1]
    n = n_of(d)
    t = times(d)
    w = d - t
    back = lambda pts: db_curve(-w, [(-a, b) for a, b in pts])
    with PB.seeded(62300 + v):
        grain = np.clip(N.grains(d, 40.0, (0.01, 0.03, 0.07)), 0, 7) ** 0.7
        ground = T.unit(band(white(d), 18, 72, 3)) * boil(n, 0.3, 2.0, 3.5)
        roar = T.unit(band(white(d), 40, 230, 2)) * grain ** 0.6 * boil(n, 0.5, 3.0, 3.0)
        rush = T.unit(band(white(d), 150, 1500, 1.5)) * boil(n, 2.0, 12.0, 5.0)
        gust = T.unit(band(white(d), 220, 1300, 1.5)) * boil(n, 3.0, 14.0, 6.0)
        hiss = T.unit(band(white(d), 700, 4200, 1.5)) * boil(n, 1.0, 7.0, 3.0)
        rush = T.lowpass_glide(rush, 420.0 if d > 12 else 700.0, 3600.0, 1.6)
        x = (ground * back([(17, -46), (11, -29), (6, -18), (2.5, -9), (0, -5)])
             + roar * back([(17, -52), (11, -33), (6, -19), (2.5, -8), (0, -1)])
             + rush * back([(17, -64), (11, -42), (6, -24), (2.5, -10), (0, -1)])
             + gust * back([(17, -90), (6, -46), (2.5, -19), (0.8, -9), (0, -7)])
             + hiss * back([(17, -90), (6, -44), (2.5, -25), (0, -13)]))
    with PB.seeded(62310 + v):
        # (a touch of the rock it carries, coming on through the roar, and the land round about taking it up)
        x = x + rocks(d, 160.0 * back([(17, -60), (6, -24), (2.5, -8), (0, 0)]) + 1e-3, 55, 520, (0.6, 1.2, 2.2), (0.5, 0.36, 0.14)) * back([(17, -74), (6, -38), (2.5, -25), (0, -19)]) * T.unit(x).std() * np.sqrt(np.mean(x[-n_of(1.0):] ** 2))
        x = land(x, 2.2, 0.1, (1100, 170), 0.8, seed=180 + v)
        x *= np.clip(t / 0.7, 0, 1) ** 2
        x *= np.clip((d - t) / 0.015, 0, 1)
    write(f"flow_rise{v}", x * T.fade(n, 0.05, 0.002), kind="flow_rise")


def build_flow_far():
    """The flow heard from beyond where it stops: a dark rush swelling out of the collapse's thunder, ebbing away."""
    d = 22.0
    n = n_of(d)
    t = times(d)
    with PB.seeded(62401):
        env = db_curve(t, [(0, -44), (5, -20), (11, -3), (14, 0), (18, -9), (22, -40)])
        x = (T.unit(band(white(d), 120, 900, 1.5)) * boil(n, 1.0, 6.0, 4.0) * 0.5
             + T.unit(band(white(d), 40, 180, 2)) * boil(n, 0.8, 5.0, 3.5))
        x = land(x * env, 3.0, 0.3, (800, 180), 1.5, seed=9)
    write("flow_far", PB.causal_lowcut(x * T.fade(n, 2.0, 3.0), 18.0))


# (the Hurricane's trees going, as heard: its file, and the stretch of it round the break)
SPLINTERS = {1: ("crack1", 1.0, 2.6), 2: ("crack3", 0.42, 2.2), 3: ("crack4", 1.25, 2.9)}


def build_splinter(v):
    """Trees going, close to the front: the Hurricane's own trees, each the moment of a break and its splintering, taken
    as they're built there (a ragged avalanche of fibres with a trunk's weight in it, no two alike), in the flow's air: the
    top gone, heavier, its echoes closer in."""
    name, a, b = SPLINTERS[v]
    y = decoded_ogg(ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds" / "hurricane" / f"{name}.ogg")
    x = y[n_of(a):n_of(b)]
    n = len(x)
    with PB.seeded(62510 + v):
        x = T.unit(F.cband(x, 70, 2800, 2)) + T.unit(F.cband(x, 2800, None, 1)) * 0.02
        P.put(x, T.thud(n_of(0.8), rng().uniform(1.5, 2.2)) * 0.5, rng().uniform(0.01, 0.05))
        x = land(x, 1.0, 0.12, (1800, 260), 0.35, seed=160 + v)
    write(f"splinter{v}", PB.causal_lowcut(x, 40.0) * T.fade(n, 0.002, 0.45), kind="splinter")


def build_grind(v):
    """Rock on rock, carried along under the front: stick and slip, dark, the ground in it."""
    d = [3.0, 2.2][v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(62600 + v):
        x = T.unit(T.stick_slip(d, [13, 19][v - 1], 90, 620, 0.9, 5.0)) + T.unit(band(white(d), 45, 170, 2)) * 0.6
        x *= np.clip(t / 0.5, 0, 1) * np.clip((d - t) / 0.9, 0, 1) * boil(n, 2.0, 9.0, 3.0)
        x = land(band(x, 35, 1500, 2), 1.4, 0.2, (1500, 240), 0.5, seed=90 + v)
    write(f"grind{v}", x * T.fade(n, 0.05, 0.3), kind="grind")


def build_flow_hit():
    """The front reaching the player: not a crack but a body of hot rock and ash arriving at sixty miles an hour, the way
    the Nuke's shockwave arrives, only with no way out the other side. Its air comes up in a few tens of ms: the wind
    across the whole of the spectrum (the octaves' levels as a table, gusting), a low shove and then a few uneven ones, the
    rock in it hitting the land all round in the first second; then the top shuts down over a second, the sound closing
    in on the ears, a heavy roar left over nothing above a few hundred Hz, for `flow_in` to take on."""
    d = 5.0
    n = n_of(d)
    t = times(d)
    t0 = LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(62710):
        tab_t = np.array([0.0, 0.05, 0.3, 0.8, 1.7, 3.2, 5.0])
        tab = np.array([[-30, -21, -17, -16, -17, -20, -24, -29, -36, -48],
                         [-27, -18, -14, -13, -14, -17, -21, -26, -33, -45],
                         [-26, -17, -14, -14, -17, -22, -28, -36, -46, -60],
                         [-26, -17, -15, -18, -25, -35, -47, -60, -72, -86],
                         [-27, -19, -18, -24, -34, -47, -62, -76, -90, -100],
                         [-33, -25, -25, -31, -42, -56, -72, -86, -100, -110],
                         [-42, -34, -34, -40, -52, -66, -82, -96, -110, -120]], dtype=float)
        w = P.snoise(d, tab_t + t0, tab, 1024, 256, corr=np.ones(10))[0]
        # (the gusts: a shared swell, each gust its own, the top moving most)
        gt = P.poisson_times(t0 + 0.02, d - 0.8, lambda v: 10.0 * np.exp(-(v - t0) / 0.8) + 1.5)
        gust = P.bumps(n, gt, rng().uniform(0.02, 0.09, len(gt)), rng().uniform(0.08, 0.3, len(gt)), np.minimum(rng().pareto(2.5, len(gt)) * 0.5 + 0.4, 2.5))
        gust = 0.55 + 0.45 * gust / (gust.mean() + 1e-9)
        top = band(w, 700, None, 2)
        w = (w - top) * gust ** 0.7 + top * gust ** 1.3
        # (the rock in it: blows all round, thick in the first second, a few heavy ones)
        rate = 150.0 * np.exp(-u / 0.42) * (1 - np.exp(-u / 0.03)) * on + 1e-3
        rk = rocks(d, rate, 70, 950, (0.5, 1.1, 2.1), (0.5, 0.36, 0.14)) * np.exp(-u / 0.8)
        # (the shove: one big and a few uneven, felt)
        pt = np.concatenate([[t0 + 0.012], P.poisson_times(t0 + 0.14, t0 + 2.4, lambda v: 4.5 * np.exp(-(v - t0) / 0.9))])
        amps = np.concatenate([[3.0], np.minimum(rng().pareto(2.2, len(pt) - 1) * 0.5 + 0.4, 2.0) * rng().choice([-1.0, 1.0], len(pt) - 1)])
        push = P.bumps(n, pt, np.r_[0.016, rng().uniform(0.03, 0.08, len(pt) - 1)], np.r_[0.14, rng().uniform(0.06, 0.18, len(pt) - 1)], amps)
        push = F.cband(push, 12, 80, 2)
        ref = T.loudest(w)
        body = bare_blow(1.6, 26, 170, 0.014, 0.16)
        x = w + push / (np.abs(push).max() + 1e-9) * ref * 3.6 + rk * ref * 0.42
        P.put(x, body * ref * 1.6, t0)
        # (nothing before the front; it comes up fast, not at once)
        x = x * (1 - np.exp(-u / 0.008)) * on
        x = lows_heard(x, 70, 360, -5.0)
        L, R = N.glue(x, x)
        L, R = N.overdrive(L, R, t0)
        # (the wall's blow, felt: a deep sub falling in pitch, the chest's punch, the crack of the rock in it striking,
        # the wind just after it let down a moment, so it lands as a blow and then swallows the player)
        hit = impact(n, t0, (66.0, 36.0, 28.0), 0.09, (40.0, 260.0), 0.1, (300.0, 2600.0), 0.02, (1.0, 1.0, 0.45))
        x = slam((L + R) / 2, t0, hit, 0.5, -4.0, (0.07, 0.35, 0.9))
    write("flow_hit", PB.causal_lowcut(x * on, 16.0) * T.fade(n, 0.0005, 1.6), knee=0.5)


def build_flow_in(v):
    """Inside the flow: a dense muffled roar right against the ears for four seconds, ash hissing past, embers ticking in
    it, hardly anything above a few hundred Hz; by 8.5 s (the pass's near-black lifting) the roar has gone on over and the
    top comes back, and what is left is the murk's hiss and wind. The shorter takes are the same run squeezed: a wall
    that reaches the player late has lost most of its load."""
    d = INS[v - 1]
    n = n_of(d)
    t = times(d)
    k = d / INS[0]
    a, b = 4.0 * k, 8.5 * k
    with PB.seeded(62800 + v):
        roar = T.unit(band(white(d), 45, 300, 2)) * boil(n, 0.5, 5.0, 3.0)
        press = T.unit(band(white(d), 18, 58, 3)) * boil(n, 0.2, 1.5, 3.0)
        chest = T.unit(band(white(d), 300, 700, 2)) * boil(n, 2.0, 10.0, 3.0) * 0.14
        ash = T.unit(band(white(d), 1100, 3400, 2)) * boil(n, 1.0, 9.0, 3.0) * 0.022
        wind = T.unit(band(white(d), 240, 1300, 1.5)) * boil(n, 0.4, 3.0, 4.0) * 0.1
        em = np.zeros(n)
        tc = 0.5
        while tc < d - 0.5:
            P.put(em, soundlib.click(n_of(0.02), 0.0, rng().uniform(0.01, 0.07), 500, 2600, rng().uniform(0.0008, 0.0026)), tc)
            tc += rng().exponential(0.075 * (1 + 2.0 * np.clip((tc - a) / (b - a), 0, 1)))
        x = (roar * db_curve(t, [(0, -2), (0.6, 0), (a, -1), (b, -13), (d, -27)])
             + press * 0.9 * db_curve(t, [(0, 0), (a, -1), (b, -13), (d, -30)])
             + chest * db_curve(t, [(0, 0), (a, 0), (b, -3), (d, -13)])
             + ash * db_curve(t, [(0, -3), (a, 0), (b, 11), (d - 1.5 * k, 8), (d, -10)])
             + wind * db_curve(t, [(0, -30), (a, -18), (b, 0), (d - 1.5 * k, -2), (d, -22)])
             + band(em, None, 2800, 2) * 2.0 * db_curve(t, [(0, 0), (a, 0), (b, -8), (d, -20)]))
    write(f"flow_in{v}", PB.causal_lowcut(x, 16.0) * T.fade(n, 0.12, 1.5 * k), kind="flow_in")


# =========================================================================================================  the aftermath
def build_after():
    """The long fading rumble with the last far thunder of the land settling in it, and over it the wind thinning to a low
    empty moan, gone by 87.8 s (the file starts at 66.3)."""
    d = AFTER_D
    n = n_of(d)
    t = times(d)
    with PB.seeded(62901):
        rum = T.unit(band(white(d), 18, 85, 3)) * boil(n, 0.1, 0.9, 4.0)
        roll = T.unit(band(white(d), 60, 200, 2)) * np.clip(N.grains(d, 2.2, (0.15, 0.3, 0.6)), 0, 5) ** 0.7
        fc = 215.0 * np.exp(0.17 * PB.slow_random(n, 0.04, 0.3))
        moan = P.glide_band(d, fc, 0.16) * np.clip(0.6 + 0.5 * PB.slow_random(n, 0.1, 0.7), 0.03, None)
        moan2 = P.glide_band(d, fc * 1.51, 0.2) * np.clip(0.4 + 0.5 * PB.slow_random(n, 0.15, 0.8), 0.0, None) * 0.28
        hush = T.unit(band(white(d), 300, 1500, 1.5)) * boil(n, 0.2, 1.3, 3.0) * 0.12
        x = (rum * db_curve(t, [(0, -3), (6, -2), (12, -10), (17, -22), (d, -55)])
             + roll * db_curve(t, [(0, -9), (6, -10), (12, -21), (17, -38), (d, -70)])
             + (moan + moan2 + hush) * db_curve(t, [(0, -32), (6, -21), (13, -14.5), (18, -16), (20.5, -28), (d, -60)]))
    write("after", PB.causal_lowcut(x * T.fade(n, 4.0, 2.5), 15.0))


def build_patter():
    """Ash and small rock falling on blocks. Ash is soft: so fine and so many that it's a dry rustling wash, its top not much
    over 3 kHz; in it grains of pumice, a soft dull tap each with its body under it, never a tick; now and then a stone.
    Thick, then thinner. Nothing regular, nothing bright."""
    d = PATTER_D
    n = n_of(d)
    t = times(d)
    with PB.seeded(63010):
        density = lambda s: np.interp(s, [0, 3, 7, 12, 15.5, d], [12, 70, 85, 48, 10, 0.5])
        fall = density(t) / 85.0
        ash = T.unit(F.cband(white(d), 300, 2300, 2)) * boil(n, 0.3, 2.5, 3.0) * boil(n, 30.0, 160.0, 2.0)
        tap = np.zeros(n)
        tc = 0.05
        while tc < d - 0.3:
            m = n_of(0.05)
            q = np.arange(m) / SR
            g = F.cband(rng().standard_normal(m), rng().uniform(220, 480), rng().uniform(900, 2200), 2)
            g = g * (1 - np.exp(-q / 0.0007)) * np.exp(-q / rng().uniform(0.003, 0.01))
            P.put(tap, g * min(rng().pareto(2.5) * 0.25 + 0.08, 1.0), tc)
            tc += rng().exponential(1.0 / density(tc))
        st = np.zeros(n)
        tc = 2.0
        while tc < d - 3.5:
            P.put(st, F.knock(rng().uniform(0.12, 0.34), 0.25) * rng().uniform(0.2, 0.7), tc)
            tc += rng().exponential(0.9) + 0.1
        x = T.unit(tap) * 0.3 + st * 0.2 + ash * 0.16 * np.clip(fall * 1.6, 0, 1) ** 0.6
        x = land(x, 1.0, 0.1, (2600, 500), 0.35, seed=170)
    # (its top taken down further: no tap may stand out of the wash as a bright tick)
    write("patter", F.cband(PB.causal_lowcut(x, 120.0), None, 2600, 2) * T.fade(n, 1.6, 2.2))


BUILD = {
    "sat_sky": build_sat, "sat_land": lambda: None,
    "tremor": build_tremor, "fountain": build_fountain, "steam": build_steam, "hush": build_hush, "seism": build_seism, "report": build_report,
    "report_far": lambda: None, "boom": build_boom, "boom_far": lambda: None, "report_sub": build_report_sub, "plate_sub": build_plate_sub, "column": build_column, "column_far": lambda: None, "collapse": build_collapse,
    "collapse_far": lambda: None, "flow_far": build_flow_far, "flow_hit": build_flow_hit, "after": build_after,
    "patter": build_patter,
    "creak": lambda: [build_creak(v + 1) for v in range(VARIANTS["creak"])],
    "crack": lambda: [build_crack(v + 1) for v in range(VARIANTS["crack"])],
    "rockfall": lambda: [build_rockfall(v + 1) for v in range(VARIANTS["rockfall"])],
    "whistle": lambda: [build_whistle(v + 1) for v in range(VARIANTS["whistle"])],
    "thud": lambda: [build_thud(v + 1) for v in range(VARIANTS["thud"])],
    "spatter": lambda: [build_spatter(v + 1) for v in range(VARIANTS["spatter"])],
    "thud_far": lambda: [build_thud_far(v + 1) for v in range(VARIANTS["thud_far"])],
    "flow_rise": lambda: [build_flow_rise(v + 1) for v in range(VARIANTS["flow_rise"])],
    "flow_in": lambda: [build_flow_in(v + 1) for v in range(VARIANTS["flow_in"])],
    "splinter": lambda: [build_splinter(v + 1) for v in range(VARIANTS["splinter"])],
    "grind": lambda: [build_grind(v + 1) for v in range(VARIANTS["grind"])],
    **{k: (lambda k=k: build_lightning(k)) for k in LIGHTNING},
    "front": lambda: [build_front(v + 1) for v in range(VARIANTS["front"])],
}


# ===========================================================================================================  listening
def decoded_ogg(path):
    """A file as the game plays it: decoded and summed to mono."""
    ch = int(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout.split()[0])
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ar", str(SR), "-f", "f32le", "-"], capture_output=True, check=True)
    return np.frombuffer(r.stdout, "<f4").astype(float).reshape(-1, ch).mean(axis=1)


def game_mix(lines, ogg_of, d):
    """`lines` (time, event, volume, pitch; or time, "stop", event) mixed as the game does (each file summed to mono, 0.596
    in each ear, its pitch a change of speed, on its tick, a `stopsound` cutting its voices a tick after it's due), then
    the output limiter. (mono mix, its peak before the limiter in dB, seconds the limiter held it down)."""
    mix = np.zeros((n_of(d), 2))
    files = {}
    tick = lambda t: np.ceil(float(t) * 20 - 1e-6) / 20
    stops = [(tick(l[0]) + 0.05, l[2]) for l in lines if l[1] == "stop"]
    for l in lines:
        if l[1] == "stop":
            continue
        t, ev, vol, pitch = l[:4]
        f = ogg_of(ev)
        if f is None:
            continue
        if f not in files:
            files[f] = decoded_ogg(f)
        y = files[f]
        p = float(pitch)
        if abs(p - 1) > 1e-4:
            pos = np.arange(0, len(y) - 1, p)
            i0 = pos.astype(int)
            y = y[i0] * (1 - (pos - i0)) + y[i0 + 1] * (pos - i0)
        i = n_of(tick(t))
        cut = min((c for c, e in stops if e == ev and c > tick(t)), default=None)
        if cut is not None:
            y = y[:n_of(cut - tick(t))]
        m = min(len(y), len(mix) - i)
        if m > 0:
            mix[i:i + m] += (y[:m] * min(float(vol), 1.0) * 0.596)[:, None]
    pre = 20 * np.log10(np.abs(mix).max() + 1e-12)
    print(f"  (the peak before the limiter at {np.abs(mix).max(axis=1).argmax() / SR:.2f} s)")
    held = S.game_limiter(mix)
    return mix, pre, held


def event_ogg(ev):
    """The file of an event `orbital:<laser>.<name>`, as sounds.json has it (`orbital:<name>`: the plasma's)."""
    e = ev.split(":", 1)[1]
    if "." not in e:
        return SOUNDS / f"{e}.ogg"
    laser, name = e.split(".", 1)
    return SOUNDS / laser / f"{name}.ogg"


def timeline(tl, me):
    """The plan's sounds with the player `me` blocks from the vent (mod/src/strike/vc_sound.rs's ignored vc_write_sounds)."""
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "vc_write_sounds", "--", "--ignored"], cwd=ROOT / "mod",
                   env=dict(os.environ, VC_OUT=str(Path(tl).resolve()), VC_ME=str(me)), check=True, capture_output=True)
    return [l.split() for l in Path(tl).read_text().splitlines() if l.strip()]


def band_db(m, lo, hi, w=0.4, hop=0.1):
    """A mono mix's level in a band, over time: (dB each `hop` s)."""
    x = band(m, lo, hi, 3) if (lo or hi) else m
    w_, h = n_of(w), n_of(hop)
    c = np.concatenate([[0.0], np.cumsum(x ** 2)])
    a = np.arange(0, len(x), h)
    return 10 * np.log10((c[np.minimum(a + w_, len(x))] - c[a]) / w_ + 1e-14)


def spectrogram(wav, png, title):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-lavfi",
                    f"aformat=channel_layouts=mono,showspectrumpic=s=1500x520:legend=1:fscale=log:scale=log:start=15:stop=16000:drange=90:color=magma", str(png)], check=True)


def report(name, m):
    """One mix's numbers: loudest 400 ms, peak, crest, its 20-120 Hz level, and a line of level per ten seconds."""
    db = band_db(m, None, None)
    lo = band_db(m, 20, 120)
    hi = band_db(m, 2000, None)
    pk = 20 * np.log10(np.abs(m).max() + 1e-12)
    print(f"{name:26s} loudest400 {db.max():6.1f} dB at {db.argmax() * 0.1:5.1f} s  peak {pk:6.1f}  crest {pk - db.max():5.1f}  20-120Hz {lo.max():6.1f}  >2kHz {hi.max():6.1f}")
    return db


def listen_mix(tag, me, out):
    tl = Path(out) / f"timeline_{tag}.txt"
    lines = timeline(tl, me)
    mix, pre, held = game_mix(lines, event_ogg, 90.0)
    path = Path(out) / f"volcano_mix_{tag}"
    N.write_wav(str(path) + ".wav", mix)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path) + ".wav", "-b:a", "192k", str(path) + ".mp3"], check=True)
    spectrogram(str(path) + ".wav", str(path) + ".png", tag)
    lufs, tp, _ = N.measure(str(path) + ".wav")
    m = mix.mean(axis=1)
    db = report(f"mix {tag}", m)
    print(f"  peak {pre:.2f} dBFS before the game's limiter ({held:.1f} s held down), true peak {tp:.2f} dBTP, {lufs:.1f} LUFS -> {path}.mp3")
    print("  level by 4 s: " + " ".join(f"{db[int(s * 10):int((s + 4) * 10)].max():.0f}" for s in range(0, 88, 4)))
    # (the hush: the file's level over 100 ms, and its 20-120 Hz: what is there from just after 17 s until the seism)
    fine = band_db(m, None, None, 0.1, 0.05)
    at = lambda a, b: fine[int(a * 20):int(b * 20)].max()
    t_seism = next((float(l[0]) for l in lines if l[1].endswith(".seism")), 18.6)
    t_report = next((float(l[0]) for l in lines if l[1].endswith((".report", ".report_far"))), 20.9)
    print(f"  hush 17.1-{t_seism:.2f} s: {at(17.1, t_seism):.1f} dB (peak {20 * np.log10(np.abs(m[n_of(17.1):n_of(t_seism)]).max() + 1e-12):.1f}); last 400 ms before it {db[int(16.6 * 10):int(16.8 * 10)].max():.1f} dB;"
          f" the seism {at(t_seism, t_seism + 1.0):.1f} dB; the wait {t_seism + 1.2:.1f}-{t_report:.2f} s: {at(t_seism + 1.2, t_report):.1f} dB")
    # (the wait never silent: its quietest and loudest 100 ms from the tremor's end to the report, and how far the report's
    # first 400 ms stands over the wait's last)
    wait = fine[int(17.05 * 20):int((t_report - 0.05) * 20)]
    print(f"  the wait 17.05-{t_report:.2f} s: quietest 100 ms {wait.min():.1f} dB, loudest {wait.max():.1f} dB; its last 400 ms"
          f" {db[int((t_report - 0.45) * 10)]:.1f} dB, the report's first {db[int(t_report * 10)]:.1f} dB")
    # (the last of it: nothing cut off, quiet by 88 s)
    tail = band_db(m, None, None, 0.2, 0.1)
    print(f"  at 84 s {tail[840]:.1f} dB, at 86 s {tail[860]:.1f} dB, at 87 s {tail[870]:.1f} dB, after 88 s {tail[880:].max():.1f} dB")
    os.remove(str(path) + ".wav")
    return tp, mix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also the whole strike as the game mixes it, in this folder")
    ap.add_argument("--mixes-only", action="store_true", help="with --listen: rebuild nothing, only the mixes")
    a = ap.parse_args()
    soundlib.init(a.out)
    S.TH = TH
    N.TH = TH
    S.LISTEN = None
    if not a.mixes_only:
        for name in a.only or NAMES:
            BUILD[name]()
        path = Path(a.out) / "assets" / "orbital" / "sounds.json"
        if path.exists():
            sounds = json.loads(path.read_text())
            for name in SINGLE:
                ev = f"{TH}.{name}"
                sounds[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
            for name, k in VARIANTS.items():
                for v in range(1, k + 1):
                    sounds[f"{TH}.{name}{v}"] = {"sounds": [{"name": f"orbital:{TH}/{name}{v}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{TH}.{name}"}
            for name in GONE:
                sounds.pop(f"{TH}.{name}", None)
                f = Path(a.out) / "assets" / "orbital" / "sounds" / TH / f"{name}.ogg"
                if f.exists():
                    f.unlink()
            path.write_text(json.dumps(sounds, indent=2))
    if a.listen:
        os.makedirs(a.listen, exist_ok=True)
        # (the strike fires at 1,000 at the least: the flow is on them at about 66 s, at 1,400 about 78 and past 1,700 never;
        # "caught" has flown in to 800, where it's on them with most of the flow still to come)
        worst = max(listen_mix(tag, me, a.listen)[0] for tag, me in (("1000", 1000), ("1400", 1400), ("2000", 2000), ("caught", 800)))
        print(f"worst true peak over the mixes: {worst:.2f} dBTP")


if __name__ == "__main__":
    main()
