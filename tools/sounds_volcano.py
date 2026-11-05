"""The Supervolcano's sounds, all synthesised here from noise, pulses and filters (nothing sampled). Every file is mono:
Horizon sums each sound file to mono anyway, so a stereo tail would only cost size.

Timeline, as mod/src/strike/vc_sound.rs plays them (strike seconds; `late` = the player's distance from the vent / 343):

  beam        0        a thin high pressure over the beam, cut on the hit; almost nothing
  tick        2 + late the hit, a tiny dry tick, then nothing at all
  tremor      2 + ground (the ground carries it five times faster than the air): under hearing at first, rising slowly
                       into a deep rolling rumble (it is the dread: most of its rise is in its last four seconds); the
                       ground lets go at the eruption (10 s into the file), it falls away and leaves the silence the
                       report comes out of
  creak1-4    3.5-12   stone creaking under the player, dry and close, never out on the land
  crack1-4    6-12     stone cracking under the player: a dull snap and a thump, no air in it
  steam       8 + late the ring cracks venting: a hiss (only within ~800 blocks)
  report      12 + late one enormous concussive report, a physical thump more than a bang, rolling off the land for 20 s
  report_far  the same moment, cross-faded in by distance
  report_sub  the same moment: the push alone, under it (and at pitch 0.8 with the land dropping, in the collapse)
  column      12 + late the column: a huge jet's roar with a tearing crackle on top (supersonic jet noise's: the roar's
                       own peaks steepened into shocks, `steepen`), a sub rumble, the vents pulsing; it falters and drops
                       at 32 s into the file, the collapse
  column_far  the same moment, cross-faded in by distance: darker, the crackle a dull tearing
  whistle1-3  a bomb falling close: a falling tearing whistle, cut on its landing
  thud1-4     a bomb landing close (positional)
  thud_far1-3 a bomb landing off on the land: a dull thump, late by the distance
  bolt1-4     plume lightning: dirty, dry, many strokes on top of each other, sharp and crackling, hardly a roll
  bolt_far1-4 further off: a low dry stuttering rumble
  collapse    44 + late a colossal deep groan of the ground going, the land mass dropping (a slow enormous blow 3 s in),
                       then the sustained thunder of it falling
  collapse_far the same moment, cross-faded in by distance
  flow_rise1-3 ending on the flow's arrival: a low hiss and a rushing roar growing as the front closes (the longest that fits)
  flow_far    the flow heard from beyond where it stops: a dark rush swelling and ebbing, no hit
  splinter1-3 trees going, heard only with the front close (positional)
  grind1-2    rock grinding along the front, the same
  flow_hit    the front reaching the player: a heavy soft blow, a sandblast shutting down to nothing above a few hundred Hz
  flow_in1-2  inside the flow (22 s and 12 s): a dense muffled roar, the hiss of ash, embers crackling, hardly any top
  after       57.5     a long fading rumble, the wind thinning to a low empty moan, to nothing by 80 s
  patter      59       ash and small rock falling on blocks, thinning to nothing by 80 s

    python3 tools/sounds_volcano.py                 # writes orbital-sounds/assets/orbital/sounds/supervolcano/*.ogg and
                                                    # adds the events to sounds.json, every other sound left as it is
    python3 tools/sounds_volcano.py --only column   # one (report before report_far, collapse before collapse_far:
                                                    # each pair is built together)
    python3 tools/sounds_volcano.py --listen DIR    # and the whole strike heard from 500, 900 and 1,500 blocks and caught
                                                    # in the flow, as the game mixes it, with a spectrogram and levels of each
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
VARIANTS = {"creak": 4, "crack": 4, "whistle": 3, "thud": 4, "thud_far": 3, "bolt": 4, "bolt_far": 4,
            "flow_rise": 3, "flow_in": 2, "splinter": 3, "grind": 2}
SINGLE = ["beam", "tick", "tremor", "steam", "report", "report_far", "report_sub", "column", "column_far", "collapse", "collapse_far",
          "flow_far", "flow_hit", "after", "patter"]
NAMES = SINGLE + list(VARIANTS)
# Each file's loudest 400 ms (dB, as the game plays it before its 0.596). The report and the collapse the loudest moments
# by a long way; the column under them, so the climax has headroom.
LEVEL = {"beam": -33.0, "tick": -30.0, "tremor": -12.5, "creak": -21.0, "crack": -14.0, "steam": -28.0,
         "report": -4.5, "report_far": -5.0, "report_sub": -8.5, "column": -13.0, "column_far": -14.5,
         "whistle": -23.0, "thud": -13.0, "thud_far": -18.0, "bolt": -15.0, "bolt_far": -23.0,
         "collapse": -5.5, "collapse_far": -6.0, "flow_rise": -12.0, "flow_far": -19.0, "flow_hit": -8.5, "flow_in": -13.0,
         "splinter": -19.0, "grind": -20.0, "after": -22.0, "patter": -30.0}
LEAD = 0.02                # (the report's and the hit's silence at the start of their files)
ERUPT_IN_TREMOR = 10.0     # (the eruption, into `tremor`, which starts at 2 s)
FALTER = 32.0              # (the collapse, into `column`, which starts at 12 s: keep vc_sound.rs's beats in step)
DROP = 3.0                 # (the land mass dropping, into `collapse`)
COLUMN_D = 40.0
RISES = (3.4, 7.0, 13.0)   # (flow_rise's lengths: vc_sound.rs's VC_RISES)
INS = (22.0, 12.0)         # (flow_in's lengths: vc_sound.rs's VC_INS)


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


# =============================================================================================================  the beam
def build_beam():
    """The beam coming down: a thin high pressure, more felt in the ears than heard, cut on the hit."""
    d = 2.08
    n = n_of(d)
    t = times(d)
    with PB.seeded(61001):
        a = P.glide_band(d, np.linspace(7100, 7700, n), 0.035)
        b = P.glide_band(d, np.linspace(10800, 11900, n), 0.03)
        c = P.glide_band(d, np.linspace(4800, 5000, n), 0.05)
        x = a + 0.5 * b + 0.25 * c
        x *= np.clip(t / 1.7, 0, 1) ** 1.4 * boil(n, 2.0, 9.0, 1.2)
        x *= np.clip((d - 0.012 - t) / 0.03, 0, 1)
    write("beam", x)


def build_tick():
    """The hit, a long way off: one tiny dry tick, a dull knock in it, and a faint answer off the land."""
    d = 1.6
    n = n_of(d)
    with PB.seeded(61002):
        x = soundlib.click(n, 0.01, 1.0, 1800, 7000, 0.0016)
        x += soundlib.click(n, 0.013, 0.5, 300, 1400, 0.006)
        x += band(soundlib.click(n, 0.52, 0.05, 200, 1200, 0.03), None, 900, 2)
    write("tick", x * T.fade(n, 0.001, 0.4))


# ===========================================================================================================  the tremor
def build_tremor():
    """Below hearing at first, then a deep rolling rumble with the ground under it. Almost all its rise comes late: the
    first six seconds sit where the ear barely finds them. The ground's jolt at the eruption and then it falls away."""
    d = 16.5
    n = n_of(d)
    t = times(d)
    E = ERUPT_IN_TREMOR
    with PB.seeded(61101):
        roll = np.clip(0.45 + 0.42 * PB.slow_random(n, 0.18, 1.1), 0.0, None) ** 1.4    # (the rolling: swells that come and go)
        shudder = np.clip(1 + (0.25 + 0.6 * np.clip((t - 3) / 7, 0, 1)) * PB.slow_random(n, 7.0, 13.0), 0.05, None)
        deep = T.unit(band(white(d), 11, 32, 3)) * boil(n, 0.2, 1.0, 3.0)
        rolling = T.unit(band(white(d), 26, 72, 2)) * roll * shudder
        body = T.unit(band(white(d), 65, 210, 2)) * roll ** 1.3 * boil(n, 2.0, 9.0, 3.0)
        grind = T.stick_slip(d, 6.0, 70, 340, 0.9, 4.0) * np.clip(0.4 + 0.5 * PB.slow_random(n, 0.3, 1.5), 0, None)
        x = (deep * db_curve(t, [(0, -60), (1.5, -46), (5, -33), (8, -26), (E, -19)])
             + rolling * db_curve(t, [(0, -90), (2, -66), (4.5, -46), (7, -32), (9, -24), (E, -18)])
             + body * db_curve(t, [(0, -100), (4, -78), (6.5, -50), (8.5, -36), (E, -27)])
             + T.unit(grind) * db_curve(t, [(0, -100), (5, -80), (7.5, -46), (9, -35), (E, -30)]))
        # (the ground lets go: a short heavy shove and then nothing to speak of, the silence the report comes out of)
        x = x * db_curve(t, [(0, 0), (E, 0), (E + 0.2, -15), (E + 0.6, -31), (E + 1.5, -41), (E + 3.5, -50), (d, -80)])
        x = x + soundlib.thump(n, E, 42, 20, 0.2, 7.0) * 0.05 * (t >= E)
        x = lows_heard(x, 60, 280, -9.0)
    write("tremor", PB.causal_lowcut(x * T.fade(n, 0.5, 1.5), 12.0))


def build_creak(v):
    """Stone under strain right under the player: slow uneven grabs, darkening, close and dry, nothing out on the land."""
    d = [1.5, 2.4, 1.1, 2.0][v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(61200 + v):
        rate = [11, 7, 16, 9][v - 1]
        x = T.stick_slip(d, rate, 70, 420, 0.85, 5.0)
        x = T.unit(x) + T.unit(band(white(d), 40, 120, 2)) * 0.5 * np.clip(0.5 + 0.5 * PB.slow_random(n, 2.0, 7.0), 0, None)
        x *= np.clip(t / (d * 0.35), 0, 1) ** 1.2 * np.exp(-t / (d * 0.5))
        x = band(x, 28, 900, 2)
        # (inside the rock: a very short thick room, no air)
        x = x + conv(x, np.exp(-np.arange(n_of(0.08)) / (0.018 * SR)) * rng().standard_normal(n_of(0.08))) * 0.05
    write(f"creak{v}", x * T.fade(n, 0.02, 0.25), kind="creak")


def build_crack(v):
    """A crack in the rock under the player: the snap dulled by the stone it came through, a thump felt through the feet."""
    d = 1.8
    n = n_of(d)
    with PB.seeded(61300 + v):
        x = H.rock_crack(d, [0.8, 1.2, 0.6, 1.0][v - 1], 0.7)
        x = band(x, 22, 1500, 2)
        x += soundlib.thump(n, 0.02, 64, 26, 0.2, 9.0) * 0.8
    write(f"crack{v}", x * T.fade(n, 0.002, 0.5), kind="crack")


def build_steam():
    """The ring cracks venting, out on the land: a hiss in uneven jets, its top taken off by the distance."""
    d = 8.5
    n = n_of(d)
    t = times(d)
    with PB.seeded(61401):
        jets = np.clip(0.7 + 0.5 * PB.slow_random(n, 0.4, 2.0), 0.05, None) * boil(n, 6.0, 30.0, 2.0)
        x = T.unit(band(white(d), 1400, 6500, 2)) * jets + T.unit(band(white(d), 500, 1800, 2)) * 0.35 * jets
        x *= np.clip(t / 1.8, 0, 1) ** 2
        x = land(x, 2.0, 0.3, (3500, 800), 0.8, seed=11)
    write("steam", x * T.fade(n, 0.2, 2.5))


# ===========================================================================================================  the report
def far_of(x, d, lo_gain=0.85, seed=0, soften=0.09):
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


def report_body():
    """The report (see the module's notes): one long pressure pulse with a boom riding it, the ground's answer and a second
    heave of the vent behind it, a dark short roar, then the land giving it back for twenty seconds."""
    d = 26.0
    n = n_of(d)
    t = times(d)
    t0 = LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(61501):
        push = band(T.friedlander(n, t0, 0.28, 1.5), 13, 150, 2)
        push = push / (np.abs(push).max() + 1e-9)
        boom = S.blow(n, t0, 64.0, 37.0, 29.0, 0.10, 0.006, ((0.62, 0.22), (0.32, 0.7), (0.06, 2.0)), drive=3.5, octv=0.34, h3=0.2, harm=0.5)
        boom2 = S.blow(n, t0 + 0.34, 48.0, 33.0, 27.0, 0.10, 0.018, ((0.7, 0.26), (0.3, 0.8)), drive=3.0) * 0.5
        boom3 = S.blow(n, t0 + 1.02, 41.0, 30.0, 25.0, 0.10, 0.04, ((0.7, 0.3), (0.3, 0.9)), drive=2.5) * 0.3
        low = push * 1.3 + boom + boom2 + boom3
        benv = np.maximum(band(np.abs(low), None, 10, 1), 0)
        body = T.unit(band(white(d), 42, 125, 3)) * benv * 0.55
        # (the front: a dull knock, not a crack; the air's edge only)
        knock = T.unit(band(white(d), 130, 520, 2)) * (1 - np.exp(-u / 0.0015)) * np.exp(-u / 0.035) * on
        edge = T.unit(band(white(d), 520, 3200, 2)) * (1 - np.exp(-u / 0.0006)) * np.exp(-u / 0.009) * on
        ref = np.sqrt(np.mean(low[n_of(t0):n_of(t0 + 0.4)] ** 2))
        hit = knock * ref * 0.9 + edge * ref * 0.28
        # (the dark roar it drags with it, handing over to the column's)
        renv = (1 - np.exp(-np.maximum(u - 0.03, 0) / 0.09)) * (0.65 * np.exp(-u / 0.8) + 0.35 * np.exp(-u / 3.0)) * on
        roar = T.unit(band(white(d), 55, 760, 1)) * boil(n, 1.5, 10.0, 3.0) * renv * ref * 0.35
        x = low + body + hit + roar
        # (the land giving it back: echoes darker each time, rolls, a heaving sub bed)
        src = band(x, None, 700, 2)
        for dt, g, hi in ((1.35, 0.26, 900), (2.6, 0.2, 640), (4.1, 0.16, 450), (6.2, 0.13, 320), (8.9, 0.1, 230), (12.4, 0.07, 170), (16.3, 0.04, 130)):
            e = band(src, 22, hi, 2)
            ir = rng().standard_normal(n_of(0.5)) * np.exp(-np.arange(n_of(0.5)) / (0.14 * SR))
            P.put(x, conv(e, ir / np.sqrt(np.sum(ir ** 2))) * g, dt)
        rl, rr = PB.thunder_rolls(d, t0 + 0.9, count=20, length=17.0)
        rolls = (rl + rr) / 2
        x += rolls / (T.loudest(rolls) + 1e-9) * ref * 0.3
        bed = T.unit(band(white(d), 17, 62, 3)) * boil(n, 0.1, 0.9, 3.0) * db_curve(t, [(0, -60), (0.8, -22), (3, -21), (8, -25), (15, -33), (22, -44), (26, -70)])
        x += bed * ref * 3.2
        x = land(x, 3.0, 0.14, (2200, 200), 1.2, seed=3)
        x = lows_heard(x, 70, 420, -4.0)
        L, R = N.glue(x, x)
        L, R = N.overdrive(L * on, R * on, t0)
        x = PB.causal_lowcut((L + R) / 2 * on * T.fade(n, 0.0005, 3.5), 15.0)
    return x


def build_report_sub():
    """The push itself, played with the report and again with the land's drop (pitched down): only the sub, the part of
    the report that's felt. A file of its own, so together they go past what one file can."""
    d = 2.6
    n = n_of(d)
    with PB.seeded(61503):
        x = S.blow(n, LEAD, 47.0, 30.0, 24.0, 0.09, 0.006, ((0.72, 0.2), (0.28, 0.62)), drive=1.0, octv=0.0, h3=0.0, harm=0.0)
        push = band(T.friedlander(n, LEAD, 0.3, 1.5), 13, 90, 2)
        x = x + push / (np.abs(push).max() + 1e-9) * 0.7
    write("report_sub", PB.causal_lowcut(band(x, None, 110, 2) * T.fade(n, 0.0005, 0.9), 14.0), knee=0.6)


def build_report():
    x = report_body()
    # (the lows rounded a little over their loudest: this is what is felt, and a thump needs density, not peaks)
    lo = band(x, None, 130, 3)
    c = T.loudest(lo) * 10 ** (3.0 / 20)
    x = x - lo + PB.soft_clip(lo[:, None], c, 0.5)[:, 0]
    # (the blow alone at the top of it: what rolls off after sits under it, so it is a thump and not a long loud noise)
    x = x * db_curve(np.arange(len(x)) / SR, [(0, 0), (0.65, 0), (1.6, -3), (4, -4.5), (26, -4.5)])
    write("report", x, knee=0.5)
    with PB.seeded(61502):
        y = far_of(x, 26.0, seed=31)
    write("report_far", y * T.fade(len(y), 0.0005, 3.0), knee=0.5)


# ===========================================================================================================  the column
def column_parts():
    """The column's pieces: the mass flow through time, then (sub, rumble, roar, jet) each unit level, to be mixed near
    or far. The jet is the roar steepened into shocks, so its crackle comes with the turbulence's own peaks."""
    d = COLUMN_D
    n = n_of(d)
    t = times(d)
    F0 = FALTER
    flow = np.interp(t, [0, 0.5, 3.5, 10, 18, F0], [0, 0.04, 0.74, 0.88, 1.0, 1.0])
    flow = ease(flow, 0.6)
    lurch = np.interp(t, [F0, F0 + 0.5, F0 + 1.0, F0 + 1.6, F0 + 2.4, F0 + 3.2, F0 + 4.2, F0 + 6.0, d],
                      [1, 0.60, 0.72, 0.34, 0.44, 0.16, 0.09, 0.02, 0.0])
    lurch = ease(lurch, 0.12)
    f = flow * lurch
    breath = boil(n, 0.05, 0.4, 1.6)
    # (the vents' deep pulsing: uneven heaves, one a second or so, each a push of the sub and a surge of the roar)
    times_ = pulse_train(d, 1.15, 0.35, 1.0)
    train = np.zeros(n)
    amps = np.minimum(np.exp(rng().normal(0, 0.45, len(times_))), 2.4)
    np.add.at(train, np.minimum((times_ * SR).astype(int), n - 1), amps)
    s = np.arange(n_of(2.2)) / SR
    kern = (1 - np.exp(-s / 0.09)) * np.exp(-s / 0.52)
    pulse = np.convolve(train, kern)[:n]
    pulse = pulse / (np.percentile(pulse, 99) + 1e-9)
    sub = T.unit(band(white(d), 15, 46, 3)) * boil(n, 0.1, 0.8, 3.0) * (0.8 + 0.6 * pulse) * f ** 0.6 * breath
    rum = T.unit(band(white(d), 38, 135, 2)) * boil(n, 0.5, 5.0, 3.5) * (0.8 + 0.6 * pulse) * f ** 0.8 * breath
    # (the roar's slow boil and the bursts on it, which drive the steepening: the shocks come in flurries)
    gust = boil(n, 1.0, 8.0, 4.5)
    burst = np.clip(N.grains(d, 14.0, (0.03, 0.08, 0.2)), 0, 6) ** 0.7
    base = band(white(d), 110, 2600, 1)
    roar = T.unit(band(white(d), 100, 950, 1.5)) * gust * (0.9 + 0.25 * pulse) * f * breath
    src = T.unit(base) * gust * burst ** 0.5
    k = 1.1e-4 * (f * breath) ** 1.2 * burst ** 0.5
    jet = steepen(src, k)
    jet = T.unit(band(jet, 450, 13500, 1)) * f ** 1.2 * (0.9 + 0.2 * pulse)
    return sub, rum, roar, jet, pulse, f


def build_column():
    """The jet. Near: the whole of it. Far: the sub and the rumble as they were, the roar darker, the crackle a dull
    tearing, in the land's long reverb. The same noises, so the two cross-fade as one sound."""
    with PB.seeded(61601):
        sub, rum, roar, jet, pulse, f = column_parts()
        print(f"column: crackle (skewness of dp/dt) {skew_dt(jet[n_of(14):n_of(30)]):.2f}")
        d = COLUMN_D
        n = n_of(d)
        near = sub * 0.9 + rum * 0.95 + roar * 0.66 + jet * 0.42
        near = lows_heard(near, 70, 300, -9.0)
        far = sub * 1.15 + rum * 1.1 + band(roar, None, 640, 2) * 0.62 + band(jet, None, 1700, 2) * 0.22
        far = land(far, 3.5, 0.35, (1000, 200), 1.8, seed=21)
        far = lows_heard(far, 70, 300, -8.0)
    write("column", PB.causal_lowcut(near * T.fade(n, 0.4, 1.6), 14.0), knee=0.6)
    write("column_far", PB.causal_lowcut(far * T.fade(n, 0.4, 1.6), 14.0), knee=0.6)


# =============================================================================================================  the bombs
def build_whistle(v):
    """A lava bomb coming down close by: a tearing whistle sliding down as it comes, cut on its landing."""
    d = [3.2, 4.2, 2.6][v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(61700 + v):
        u = t / d
        fc = np.array([1250, 1050, 1500])[v - 1] * (0.40 / 1.0) ** (u ** 1.6)
        x = P.glide_band(d, fc, 0.11) * np.clip(1 + 0.7 * PB.slow_random(n, 25.0, 70.0), 0.05, None)
        x += P.glide_band(d, fc * 1.9, 0.22) * 0.4 * np.clip(1 + 0.9 * PB.slow_random(n, 30.0, 90.0), 0, None)
        rush = T.unit(band(white(d), 260, 2600, 1)) * np.clip(1 + 0.6 * PB.slow_random(n, 8.0, 30.0), 0.05, None) * 0.5
        x = (x + rush) * db_curve(t, [(0, -42), (d * 0.5, -22), (d * 0.85, -9), (d, 0)])
        x *= np.clip((d - t) / 0.012, 0, 1)
    write(f"whistle{v}", x * T.fade(n, 0.1, 0.002), kind="whistle")


def build_thud(v):
    """A bomb landing close: a heavy thump, rock breaking under it, molten stuff and stones thrown out and pattering."""
    d = 2.6
    n = n_of(d)
    with PB.seeded(61800 + v):
        size = [1.1, 0.8, 1.4, 1.0][v - 1]
        x = soundlib.thump(n, 0.01, 92, 30, 0.2 + 0.1 * size, 9.0) * 1.2
        x += H.rock_crack(d, size, 0.75) * 0.5
        for _ in range(int(16 * size)):
            tc = 0.08 + rng().gamma(1.4, 0.2)
            if tc < d - 0.2:
                m = n_of(0.05)
                P.put(x, F.knock(rng().uniform(0.1, 0.45), 0.5)[:m] * rng().uniform(0.03, 0.14), tc)
        x = land(x, 1.8, 0.3, (2800, 200), 0.8, seed=40 + v)
        x = lows_heard(x, 70, 320, -6.0)
    write(f"thud{v}", PB.causal_lowcut(x, 22.0) * T.fade(n, 0.002, 0.7), kind="thud")


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


# =========================================================================================================  the lightning
def dirty(seed, d, count, span, top, roll_db, roll_tau, wet, hi=9000.0):
    """Plume lightning: `count` strokes crowding into `span` s, each a little N-wave, the leaders' tearing laid over them.
    Its channels are short and full of ash, so where a storm's bolt rolls on, this crackles and stops: dry, a little
    low grumble, a sputter of small discharges after it."""
    n = n_of(d)
    t = times(d)
    with PB.seeded(seed):
        train = np.zeros(n)
        at = 0.02 + span * rng().random(count) ** 1.6
        for i, tc in enumerate(sorted(at)):
            w = rng().uniform(0.0012, 0.0045)
            a = (rng().uniform(0.3, 1.0) * (1.0 if i < 3 else 0.75)) * rng().choice([-1.0, 1.0])
            P.put(train, S.nwave(w) * a, tc)
        x = band(train, 160, hi, 2)
        x = x / (np.abs(x).max() + 1e-9)
        # (the tearing: a burst of fine snaps through the strokes)
        g = np.clip(N.grains(d, 700.0, (0.0008, 0.002, 0.005)), 0, 12) ** 1.3
        tear = T.unit(band(white(d), 900, top, 2)) * g * db_curve(t, [(0, -60), (0.02, -7), (span, -11), (span + 0.25, -32), (span + 0.6, -70), (d, -90)])
        # (the sputter: small discharges thinning out)
        sp = np.zeros(n)
        for _ in range(int(14 + 16 * d / 3)):
            tc = span + rng().gamma(1.1, 0.34)
            if tc < d - 0.1:
                P.put(sp, soundlib.click(n_of(0.03), 0.0, rng().uniform(0.02, 0.16), 1200, min(top * 1.2, 9000), rng().uniform(0.0006, 0.002)), tc)
        # (the grumble, short and lumpy)
        clump = np.clip(N.grains(d, 11.0, (0.03, 0.07, 0.16)), 0, 8) ** 0.8
        gr = T.unit(band(white(d), 42, 240, 2)) * clump * db_curve(t, [(0, -60), (0.03, roll_db), (span + roll_tau, roll_db - 7), (span + roll_tau * 2.5, roll_db - 30), (d, -90)])
        y = x + tear + sp + gr
    return y, n


def build_bolt(v):
    with PB.seeded(62000 + v):
        count = [12, 18, 9, 15][v - 1]
        span = [0.34, 0.5, 0.22, 0.42][v - 1]
    x, n = dirty(62010 + v, 3.2, count, span, 7500.0, -9.0, 0.55, 0.2)
    with PB.seeded(62020 + v):
        x = land(x, 1.4, 0.18, (2400, 300), 0.45, 30.0, seed=60 + v)
        x = lows_heard(x, 70, 320, -9.0)
    write(f"bolt{v}", PB.causal_lowcut(x, 30.0) * T.fade(n, 0.001, 0.5), knee=0.6, kind="bolt")


def build_bolt_far(v):
    """Further off: the strokes run together into a low dry stutter, none of the air's edge left."""
    with PB.seeded(62100 + v):
        count = [10, 14, 8, 12][v - 1]
        span = [0.7, 1.1, 0.5, 0.9][v - 1]
    x, n = dirty(62110 + v, 5.0, count, span, 1500.0, -3.0, 1.0, 0.35, hi=900.0)
    with PB.seeded(62120 + v):
        x = land(band(x, 30, 800, 2), 3.2, 0.5, (700, 120), 1.5, 30.0, seed=70 + v)
    write(f"bolt_far{v}", PB.causal_lowcut(x, 24.0) * T.fade(n, 0.01, 1.2), kind="bolt_far")


# ==========================================================================================================  the collapse
def collapse_body():
    """A colossal groan of the ground going (rock sliding on rock, down through the audible floor, cracks going off in
    it); the land mass dropping, a slow enormous blow with no edge; then the sustained thunder of it falling: big
    impacts overlapping into one long roll, a grinding roar over it, thinning over twelve seconds."""
    d = 24.0
    n = n_of(d)
    t = times(d)
    Td = DROP
    with PB.seeded(62201):
        u = np.maximum(t - Td, 0)
        on = t >= Td
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


def build_collapse():
    x = collapse_body()
    write("collapse", x, knee=0.5)
    with PB.seeded(62202):
        y = far_of(x, 24.0, lo_gain=0.9, seed=33, soften=0.0001)
    write("collapse_far", y * T.fade(len(y), 0.6, 3.0), knee=0.5)


# ==============================================================================================================  the flow
def build_flow_rise(v):
    """The front closing: a low hiss first, then a rushing roar opening up as it comes, what's in front of it (trees,
    rock) carried in it. Its end is the hit (the file stops there, under `flow_hit`), and it fades in from nothing."""
    d = RISES[v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(62300 + v):
        u = t / d
        hiss = T.unit(band(white(d), 700, 4200, 1.5)) * boil(n, 1.0, 7.0, 3.0)
        rush = T.unit(band(white(d), 150, 1500, 1.5)) * boil(n, 2.0, 12.0, 5.0)
        grain = np.clip(N.grains(d, 40.0, (0.01, 0.03, 0.07)), 0, 7) ** 0.7
        roar = T.unit(band(white(d), 40, 230, 2)) * grain ** 0.6
        sub = T.unit(band(white(d), 20, 60, 3)) * boil(n, 0.4, 3.0, 3.0)
        x = (hiss * db_curve(u, [(0, -30), (0.6, -22), (1, -13)])
             + T.lowpass_glide(rush, 500.0, 3800.0, 1.6) * db_curve(u, [(0, -40), (0.5, -19), (0.85, -7), (1, -1)])
             + roar * db_curve(u, [(0, -40), (0.5, -17), (0.85, -7), (1, -1)])
             + sub * db_curve(u, [(0, -40), (0.6, -16), (1, -5)]))
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


def build_splinter(v):
    """Trees going, close to the front: a run of snaps and splinters, trunks knocked down in it, darkened by the flow."""
    d = [1.3, 1.6, 1.1][v - 1]
    n = n_of(d)
    with PB.seeded(62500 + v):
        x = np.zeros(n)
        tc = 0.02
        while tc < d * 0.75:
            size = rng().uniform(0.5, 1.5)
            P.put(x, F.fracture(size, 0.7, rng().uniform(0.1, 0.5)) * rng().uniform(0.3, 1.0), tc)
            tc += rng().gamma(1.3, 0.05)
        for _ in range(3):
            P.put(x, F.knock(rng().uniform(0.6, 1.3), 0.6) * rng().uniform(0.4, 0.9), rng().uniform(0.1, d * 0.8))
        x = land(band(x, 60, 5200, 2), 1.2, 0.25, (2400, 300), 0.45, seed=80 + v)
    write(f"splinter{v}", x * T.fade(n, 0.001, 0.3), kind="splinter")


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
    """The front reaching the player: not a crack, a body of hot ash arriving at sixty miles an hour. A heavy soft shove,
    a sandblast for a moment, and the world shutting down to nothing over a few hundred Hz."""
    d = 5.0
    n = n_of(d)
    t = times(d)
    t0 = LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(62701):
        push = band(T.friedlander(n, t0, 0.42, 1.2), 14, 130, 2)
        push = push / (np.abs(push).max() + 1e-9)
        boom = S.blow(n, t0, 54.0, 32.0, 26.0, 0.14, 0.015, ((0.55, 0.32), (0.45, 1.1)), drive=3.0)
        blast = T.unit(band(white(d), 60, 7000, 1)) * boil(n, 6.0, 40.0, 4.0)
        blast = T.lowpass_glide(blast, 6500.0, 240.0, 0.32) * (1 - np.exp(-u / 0.006)) * np.exp(-u / 1.5) * on
        gr = np.clip(N.grains(d, 500.0, (0.002, 0.005, 0.01)), 0, 9)
        grit = T.unit(band(white(d), 1200, 5500, 2)) * gr * np.exp(-u / 0.2) * (1 - np.exp(-u / 0.01)) * on
        x = push * 1.1 + boom + blast * 0.32 + grit * 0.1
        x = lows_heard(x, 70, 360, -5.0)
    write("flow_hit", PB.causal_lowcut(x * on, 16.0) * T.fade(n, 0.0005, 1.6), knee=0.5)


def build_flow_in(v):
    """Inside the flow: a dense muffled roar right against the ears, ash hissing past, embers ticking in it, hardly
    anything above a few hundred Hz. Thins at its end, as the flow lifts and leaves the player under it."""
    d = INS[v - 1]
    n = n_of(d)
    t = times(d)
    with PB.seeded(62800 + v):
        roar = T.unit(band(white(d), 45, 300, 2)) * boil(n, 0.5, 5.0, 3.0)
        press = T.unit(band(white(d), 18, 58, 3)) * boil(n, 0.2, 1.5, 3.0)
        chest = T.unit(band(white(d), 300, 700, 2)) * boil(n, 2.0, 10.0, 3.0) * 0.14
        ash = T.unit(band(white(d), 1100, 3400, 2)) * boil(n, 1.0, 9.0, 3.0) * 0.022
        em = np.zeros(n)
        tc = 0.5
        while tc < d - 0.5:
            P.put(em, soundlib.click(n_of(0.02), 0.0, rng().uniform(0.01, 0.07), 500, 2600, rng().uniform(0.0008, 0.0026)), tc)
            tc += rng().exponential(0.075)
        x = roar + press * 0.9 + chest + ash + band(em, None, 2800, 2) * 2.0
        x *= db_curve(t, [(0, -2), (0.6, 0), (d * 0.55, -2), (d * 0.8, -9), (d, -40)])
    write(f"flow_in{v}", PB.causal_lowcut(x, 16.0) * T.fade(n, 0.12, 2.5), kind="flow_in")


# =========================================================================================================  the aftermath
def build_after():
    """The long fading rumble, and over it the wind thinning to a low empty moan, gone by 80 s (the file starts at 57.5)."""
    d = 22.45
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
             + (moan + moan2 + hush) * db_curve(t, [(0, -32), (6, -21), (13, -14.5), (18, -16), (21, -30), (d, -60)]))
    write("after", PB.causal_lowcut(x * T.fade(n, 4.0, 2.5), 15.0))


def build_patter():
    """Ash and small rock falling on blocks: a dry fine ticking, thick then thinner, now and then a stone, the soft hiss of
    ash settling under it. Each its own; nothing regular."""
    d = 21.0
    n = n_of(d)
    t = times(d)
    with PB.seeded(63001):
        density = lambda s: np.interp(s, [0, 3, 8, 14, 19, d], [12, 70, 85, 48, 10, 0.5])
        x = np.zeros(n)
        tc = 0.05
        while tc < d - 0.3:
            m = n_of(0.012)
            s = np.arange(m) / SR
            g = F.cband(rng().standard_normal(m), rng().uniform(900, 2200), rng().uniform(3500, 7500), 2) * np.exp(-s / rng().uniform(0.0006, 0.0022))
            P.put(x, g * min(rng().pareto(2.5) * 0.25 + 0.08, 1.0), tc)
            tc += rng().exponential(1.0 / density(tc))
        st = np.zeros(n)
        tc = 2.0
        while tc < d - 3.0:
            P.put(st, F.knock(rng().uniform(0.08, 0.3), 0.8) * rng().uniform(0.2, 0.7), tc)
            tc += rng().exponential(0.9) + 0.1
        hiss = T.unit(band(white(d), 1800, 8000, 1.5)) * boil(n, 0.2, 1.5, 3.0) * db_curve(t, [(0, -60), (3, -35), (9, -33), (15, -40), (d, -75)])
        x = T.unit(band(x, 500, 9000, 1)) * 0.35 + st * 0.25 + hiss
    write("patter", x * T.fade(n, 1.6, 3.5))


BUILD = {
    "beam": build_beam, "tick": build_tick, "tremor": build_tremor, "steam": build_steam, "report": build_report,
    "report_far": lambda: None, "report_sub": build_report_sub, "column": build_column, "column_far": lambda: None, "collapse": build_collapse,
    "collapse_far": lambda: None, "flow_far": build_flow_far, "flow_hit": build_flow_hit, "after": build_after,
    "patter": build_patter,
    "creak": lambda: [build_creak(v + 1) for v in range(VARIANTS["creak"])],
    "crack": lambda: [build_crack(v + 1) for v in range(VARIANTS["crack"])],
    "whistle": lambda: [build_whistle(v + 1) for v in range(VARIANTS["whistle"])],
    "thud": lambda: [build_thud(v + 1) for v in range(VARIANTS["thud"])],
    "thud_far": lambda: [build_thud_far(v + 1) for v in range(VARIANTS["thud_far"])],
    "bolt": lambda: [build_bolt(v + 1) for v in range(VARIANTS["bolt"])],
    "bolt_far": lambda: [build_bolt_far(v + 1) for v in range(VARIANTS["bolt_far"])],
    "flow_rise": lambda: [build_flow_rise(v + 1) for v in range(VARIANTS["flow_rise"])],
    "flow_in": lambda: [build_flow_in(v + 1) for v in range(VARIANTS["flow_in"])],
    "splinter": lambda: [build_splinter(v + 1) for v in range(VARIANTS["splinter"])],
    "grind": lambda: [build_grind(v + 1) for v in range(VARIANTS["grind"])],
}


# ===========================================================================================================  listening
def decoded_ogg(path):
    """A file as the game plays it: decoded and summed to mono."""
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True, check=True)
    return np.frombuffer(r.stdout, "<f4").astype(float)


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
    held = S.game_limiter(mix)
    return mix, pre, held


def event_ogg(ev):
    """The file of an event `orbital:<laser>.<name>`, as sounds.json has it."""
    laser, name = ev.split(":", 1)[1].split(".", 1)
    return ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds" / laser / f"{name}.ogg"


def timeline(tl, me, caught=False):
    """The plan's sounds with the player `me` blocks from the vent (mod/src/strike/vc_sound.rs's ignored vc_write_sounds)."""
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "vc_write_sounds", "--", "--ignored"], cwd=ROOT / "mod",
                   env=dict(os.environ, VC_OUT=str(Path(tl).resolve()), VC_ME=str(me), VC_CAUGHT="1" if caught else "0"), check=True, capture_output=True)
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


def listen_mix(tag, me, out, caught=False):
    tl = Path(out) / f"timeline_{tag}.txt"
    lines = timeline(tl, me, caught)
    mix, pre, held = game_mix(lines, event_ogg, 84.0)
    path = Path(out) / f"volcano_mix_{tag}"
    N.write_wav(str(path) + ".wav", mix)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path) + ".wav", "-b:a", "192k", str(path) + ".mp3"], check=True)
    spectrogram(str(path) + ".wav", str(path) + ".png", tag)
    lufs, tp, _ = N.measure(str(path) + ".wav")
    m = mix.mean(axis=1)
    db = report(f"mix {tag}", m)
    print(f"  peak {pre:.2f} dBFS before the game's limiter ({held:.1f} s held down), true peak {tp:.2f} dBTP, {lufs:.1f} LUFS -> {path}.mp3")
    print("  level by 4 s: " + " ".join(f"{db[int(s * 10):int((s + 4) * 10)].max():.0f}" for s in range(0, 84, 4)))
    # (the last of it: nothing cut off, quiet by 80 s)
    tail = band_db(m, None, None, 0.2, 0.1)
    print(f"  at 78 s {tail[780]:.1f} dB, at 80 s {tail[800]:.1f} dB, after 81 s {tail[810:].max():.1f} dB")
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
            path.write_text(json.dumps(sounds, indent=2))
    if a.listen:
        os.makedirs(a.listen, exist_ok=True)
        worst = max(listen_mix(tag, me, a.listen, c)[0] for tag, me, c in (("500", 500, False), ("900", 900, False), ("1500", 1500, False), ("caught", 620, True)))
        print(f"worst true peak over the mixes: {worst:.2f} dBTP")


if __name__ == "__main__":
    main()
