"""The Hurricane's sounds, synthesised here from noise and filters (nothing sampled), on the Supercell's wind and its
thunder (tools/sounds_storm.py); the accents built from tools/hu_foley.py's field-recording pieces. Each is its own
file and event, so one can be swapped without touching the plan (strike/hurricane.rs).

The beds are continuous, a minute long each and played once from the strike's start, the storm's whole life written
into them (its build-up, its height, the winds dropping), so nothing in them restarts, steps or overlaps; the plan only
sets each one's level by the distance:

  wind       the wind round the player: a hush, then gusts rising out of it, buffeting, a broad rush, a howl climbing
             with each gust, as hard as the storm's wind blows at that moment (strike/hurricane.rs's SPIN_K)
  roar       the eyewall's roar near (within 330 blocks): a deep turbulent rumble, a freight-train roar boiling over it,
             building with the wind, falling away in pitch and level as it drops
  roar_far   the same from further off: darker, mostly rumble and a distant roar
  rain       wind-driven rain, the wash alone (no drops ticking on things): in from 4 s, heaviest at the storm's height,
             easing as it clears

Over them, now and then, quieter than the beds, each take a different thing (none of them a designed one-shot: dull,
uneven, out in the open):
  debris     (4 takes) debris in a gust: a board cartwheeling and skidding; grit and gravel pelting; something caught
             flapping till it tears loose and bangs; a big branch crashing down through twigs
  crack      (4 takes, mono, played where the tree was) a tree torn up: creaking and groaning, fibres ticking, a ragged
             break with a dull thud in it, splintering, roots ripping, the crown crashing through what is round it
             (snapped mid-trunk; torn out by the roots; quick and violent, its top going too; worried loose)
  whoosh     (4 takes, mono) a body shoved through the gusting air past a player the wind carries: a leafy branch;
             something big and heavy; a cloud of grit; a board close and fast
And the eyewall's lightning (the pass's flashes, mirrored in strike/hurricane.rs's hu_flash_list), its thunder late by
the distance, the Supercell's model drawn afresh:
  thunder      (4 takes) a bolt to the land within ~110 blocks: the strokes' rip, the clap, the boom, a short roll
  thunder_mid  (4 takes) 110-320 blocks: a duller clap, the boom, a longer roll
  thunder_far  (4 takes) further: mostly roll
  rumble       (4 takes) a flash deep in the eyewall or out in a band: thunder up in the cloud, no crack

    python3 tools/sounds_hurricane.py               # writes orbital-sounds/assets/orbital/sounds/hurricane/*.ogg and
                                                    # adds the events to sounds.json, every other sound left as it is
    python3 tools/sounds_hurricane.py --only roar   # one
    python3 tools/sounds_hurricane.py --listen DIR  # and a WAV and an MP3 of each in DIR
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
import hu_foley as F
wander = F.wander

TH = "hurricane"
ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {"debris": 4, "crack": 4, "whoosh": 4, "thunder": 4, "thunder_mid": 4, "thunder_far": 4, "rumble": 4}
NAMES = ["wind", "roar", "roar_far", "rain", "debris", "crack", "whoosh", "thunder", "thunder_mid", "thunder_far", "rumble"]
# (the plan's old events, taken out of sounds.json and their files deleted when it's rebuilt)
GONE = ["buildup", "gusts", "winddown"]
BED = 60.0
# The storm's wind through the strike (strike/hurricane.rs's SPIN_K: keep in step), the beds' envelopes from it.
SPIN_K = [(0.0, 0.04), (8.0, 0.15), (26.0, 1.0), (44.0, 1.0), (50.0, 0.35), (58.0, 0.08), (64.0, 0.0)]


def spin(t):
    return np.interp(t, [k[0] for k in SPIN_K], [k[1] for k in SPIN_K])
# The accents' integrated loudness (LUFS): about the first pass's (its crack1 -21.3, its debris -25, its whooshes -23).
LUFS = {"crack": -21.5, "debris": -25.0, "whoosh": -23.0}
# (the plan picks these takes itself: each its own event)
PICKED = ("debris", "crack", "whoosh", "thunder", "thunder_mid", "thunder_far", "rumble")
# Each file's loudest 400 ms (dB, mono as the game plays it), set against each other so the strike's mix stays under
# -1 dBTP (`--listen` checks it) and the accents sit in the beds.
LEVEL = {"wind": -18.0, "roar": -15.0, "roar_far": -19.0, "rain": -25.0,
         # (the thunder as the Supercell's: strike/hurricane.rs's hu_thunder sets each kind's volume against these)
         "thunder": -14.0, "thunder_mid": -17.5, "thunder_far": -21.0, "rumble": -25.5}


def rng():
    return soundlib.rng


def write_lufs(name, x, lufs):
    """S.write with the file's integrated loudness at `lufs` (as heard decoded: the accents are short and uneven, so
    their loudest 400 ms says less about how loud they play than the whole does), its true peak still held."""
    db = -20.0
    for _ in range(3):
        S.write(name, x, db)
        got = N.measure(f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}.ogg")[0]
        if abs(got - lufs) < 0.15:
            break
        db += lufs - got


def n_of(d):
    return int(SR * d)


def roar_bed(d, far=False, rise=None):
    """The eyewall's roar, stereo: a deep rumble, the boiling roar, a shriek in the gusts. (No debris knocking in it any
    more: the accents carry that, and in a bed it was heard as clinks.)"""
    n = n_of(d)
    boil = lambda lo, hi, db: np.exp(db * PB.slow_random(n, lo, hi) / 8.686)
    g = S.gust_curve(d, rate=0.25, floor=0.55, sharp=1.2)
    if rise is not None:
        g = g * rise
    out = []
    shared_r = T.unit(band(white(d), 22, 110, 3)) * boil(0.3, 3.0, 3.0)
    for sgn in (-1.0, 1.0):
        rumble = shared_r * 1.1 + T.unit(band(white(d), 30, 140, 2)) * 0.3
        roar = T.unit(band(white(d), 120, 950, 2)) * boil(1.0, 9.0, 4.0) * 0.8 + T.unit(band(white(d), 300, 1700, 2)) * boil(2.0, 14.0, 5.0) * 0.4
        x = rumble * (0.7 + 0.5 * g) + roar * g ** 1.3
        if not far:
            shriek = P.glide_band(d, 900.0 + 700.0 * np.clip(g, 0, 1.5), 0.08) * np.clip(g - 0.7, 0, None) ** 1.8 * 0.35
            top = T.unit(band(white(d), 1800, 7000, 2)) * g ** 2.5 * 0.1
            x = x + shriek + top
        else:
            x = band(x, None, 900, 2) * 1.2
        out.append(x * (1 + 0.15 * sgn * PB.slow_random(n, 0.05, 0.3)))
    return out[0], out[1]


def rain_bed(d):
    """The rain alone (sounds_storm.py's rain without its drops ticking and plipping on things): the wide wash, the
    darker wash further off, the low drumming, sheets of it swelling with the wind. Stereo."""
    n = n_of(d)
    sheet = np.exp(2.2 * PB.slow_random(n, 0.05, 0.35) / 8.686)
    L = np.zeros(n); R = np.zeros(n)
    for ch in (L, R):
        wash = T.unit(band(white(d), 600, 11000, 1)) * 0.5 + T.unit(band(white(d), 2000, 7000, 2)) * 0.5
        far = T.unit(band(white(d), 250, 2800, 2)) * 0.45
        drum = T.unit(band(white(d), 70, 420, 2)) * 0.22 * np.clip(1 + 0.4 * PB.slow_random(n, 0.3, 2.0), 0.2, None)
        ch += (wash * 0.32 + far + drum) * sheet
    return L, R


def curve():
    """The storm's wind at each sample of a bed, eased so it never steps."""
    t = np.arange(n_of(BED)) / SR
    k = spin(t)
    # (smoothed over a second: the plan's straight lines between its points heard as swells, not corners)
    w = n_of(1.0)
    k = np.convolve(np.pad(k, (w, w), mode="edge"), np.ones(w) / w, mode="same")[w:-w]
    return t, k


def build_wind():
    with PB.seeded(97010):
        t, k = curve()
        g = S.gust_curve(BED, rate=0.35, floor=0.35, sharp=1.6) * (0.08 + 0.95 * k ** 0.8)
        L, R = S.wind(BED, g)
        # (the pressure swell under it as the storm gathers)
        sw = T.unit(band(white(BED), 20, 65, 3)) * np.clip(t / 12.0, 0, 1) ** 2 * (0.3 + 0.7 * k) * 0.25
        x = S.fades((L + R) * 0.5 + sw, 0.8, 4.0)
    S.write("wind", x, LEVEL["wind"])


def build_roar():
    with PB.seeded(97101):
        t, k = curve()
        env = np.clip(k - 0.08, 0, None) ** 1.3 / 0.92 ** 1.3
        L, R = roar_bed(BED, rise=0.25 + 0.95 * env)
        x = (L + R) * 0.5 * (0.02 + 0.98 * np.clip(env * 1.2, 0, 1))
        # (as the winds drop its top goes first: darkened over their last seconds)
        lo = band(x, None, 450, 2) * 1.5
        mk = np.clip((t - 46.0) / 8.0, 0, 1)
        x = S.fades(x * (1 - mk) + lo * mk, 2.0, 5.0)
    S.write("roar", x, LEVEL["roar"])


def build_roar_far():
    with PB.seeded(97102):
        t, k = curve()
        env = np.clip(k - 0.08, 0, None) ** 1.3 / 0.92 ** 1.3
        L, R = roar_bed(BED, far=True, rise=0.3 + 0.9 * env)
        x = S.fades((L + R) * 0.5 * (0.03 + 0.97 * np.clip(env * 1.2, 0, 1)), 2.0, 5.0)
    S.write("roar_far", x, LEVEL["roar_far"])


def build_rain():
    with PB.seeded(97301):
        t, k = curve()
        L, R = rain_bed(BED)
        e = np.clip((t - 4.0) / 8.0, 0, 1) ** 1.5 * (1.0 - np.clip((t - 50.0) / 8.0, 0, 1)) * (0.55 + 0.45 * k)
        x = S.fades((L + R) * 0.5 * e, 1.0, 3.0)
    S.write("rain", x, LEVEL["rain"])


# ======================================================================================================  the accents
def creak(d, rate, env, wild=0.35):
    """Wood straining against itself: stick and slip, grabs at an uneven rate (`rate` a second, wandering at random,
    a grab now and then missed), each a rough little burst of noise, through the trunk's broad, shifting body (wide bands,
    nothing that rings). Heard as a groaning creak, never a tone. Dry; `env` one value a sample."""
    n = n_of(d)
    rw = rate * wander(n, 0.8, 6.0, 6.0 * wild / 0.35)
    imp = np.zeros(n)
    t = rng().uniform(0, 0.02)
    while t < d:
        k = int(t * SR)
        if rng().random() < 0.82:
            imp[k] += rng().lognormal(0.0, 0.6) * rng().choice([-1.0, 1.0])
        t += (1.0 / max(rw[k], 6.0)) * (1.0 + wild * rng().standard_normal()) ** 2
    kern = rng().standard_normal(n_of(0.003)) * np.exp(-np.arange(n_of(0.003)) / SR / 0.0007)
    x = np.convolve(imp, kern)[:n]
    y = np.zeros(n)
    for lo, hi, a in ((rng().uniform(140, 260), rng().uniform(420, 600), 1.0), (rng().uniform(650, 900), rng().uniform(1300, 1800), 0.6),
                      (rng().uniform(1900, 2600), rng().uniform(3500, 4500), 0.25)):
        y += T.unit(F.cband(x, lo, hi, 2)) * a
    return y * env


def groan(d, env):
    """The trunk's weight bending over: a low, rough grinding (40-350 Hz noise in uneven grabs), no pitch. Dry."""
    n = n_of(d)
    g = np.clip(F.grains(d, 35.0, (0.015, 0.04, 0.09)), 0, 6) ** 1.3
    return T.unit(F.cband(rng().standard_normal(n), 40, 350, 2)) * g * wander(n, 0.6, 4.0, 4.0) * env


def bump(t, at, rise, fall):
    u = t - at
    return np.where(u < 0, np.exp(-0.5 * (u / max(rise, 1e-3)) ** 2), np.exp(-u / fall))


# How each tree goes (`crack` takes): its length; the strain before it gives (s); the main break: when, how many fibres
# go in it and over how long, how big; the splintering after it (s); the roots tearing (start, length, how much); a
# second break (when, how big; None); when its crown crashes through what is round it, how much the leaves thrash.
CRACK = {
    # (snapped half-way up the trunk: a long strain, a big ragged break, the top crashing down through the next trees)
    1: dict(d=4.2, strain=1.0, at=1.05, fibres=95, span=0.22, size=1.6, tear=0.9, roots=None, second=None, crash=2.35, leaves=1.0),
    # (torn out by the roots: a groaning lean, the ground ripping open, the root plate's thud, roots snapping as it goes)
    2: dict(d=4.6, strain=1.5, at=1.6, fibres=40, span=0.35, size=0.9, tear=0.5, roots=(0.9, 2.0, 1.0), second=None, crash=3.1, leaves=0.8),
    # (a quick violent one: hardly a warning, the trunk going, its top snapping off a moment later)
    3: dict(d=3.8, strain=0.35, at=0.45, fibres=120, span=0.12, size=1.9, tear=0.6, roots=None, second=(1.15, 1.1), crash=1.9, leaves=1.2),
    # (worried loose: creaking over and over, three partial breaks, splintering on and on, the roots letting go at last)
    4: dict(d=4.8, strain=1.2, at=1.3, fibres=55, span=0.3, size=1.1, tear=1.6, roots=(2.4, 1.3, 0.7), second=(0.55, 0.6), crash=3.6, leaves=0.9),
}


def build_crack(v):
    """A tree torn up as a field recording a stone's throw off would have it: the wood creaking and groaning, fibres
    ticking as they go, then the break, a ragged avalanche of fractures over a fraction of a second with a dull thud in it
    (the trunk's weight, not a snap that rings), the splintering tearing on after it, roots ripping out of the ground,
    the crown thrashing all through and crashing through what is round it; all of it out in the open, its echoes
    off the land."""
    c = CRACK[v]
    d = c["d"]
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97500 + 11 * v):
        x = np.zeros(n)
        tb = c["at"]
        # (the crown thrashing in the wind all through, harder as it goes over, a rush of it as it crashes)
        lv = (0.4 + 0.6 * np.clip(t / tb, 0, 1)) * wander(n, 0.4, 3.0, 4.0)
        lv += 1.6 * bump(t, c["crash"], 0.12, 0.6) + 0.6 * bump(t, tb, 0.05, 0.8)
        x += F.rustle(d, lv * c["leaves"], density=3000.0) * 0.07
        # (the strain: creaking in fits, louder and closer together into the break)
        t0 = max(tb - c["strain"], 0.02)
        for _ in range(int(2 + 3 * c["strain"])):
            a = rng().uniform(t0, tb + 0.05)
            ln = rng().uniform(0.12, 0.45)
            e = bump(t, a + ln * 0.4, ln * 0.3, ln * 0.35) * (0.4 + 0.6 * np.clip((a - t0) / max(tb - t0, 0.1), 0, 1))
            x += creak(d, rng().uniform(18, 55), e * rng().uniform(0.03, 0.07))
        x += groan(d, bump(t, tb - 0.1, c["strain"] * 0.4 + 0.05, 0.6) * 0.05)
        # (fibres going ahead of it, faster and faster)
        for t1 in F.PB_poisson(t0, tb, lambda u: 4.0 + 40.0 / (1.0 + (tb - u) / 0.1)):
            put = F.put
            put(x, F.fracture(rng().uniform(0.2, 0.8), 0.8, dull=rng().uniform(0.2, 0.7)) * min(rng().pareto(2.5), 2.5) * 0.035, t1)
        # (the break: a ragged avalanche of fractures, densest at its front, a few heavy ones in it)
        def avalanche(at, count, span, size, amp):
            for u in np.sort(rng().beta(0.8, 2.2, count)):
                big = min(rng().pareto(1.8) * 0.4 + 0.3, 2.5) * size
                F.put(x, F.fracture(big, 0.85, dull=rng().uniform(0.0, 0.5)) * amp * (0.35 + 0.65 * rng().random()) * (1 - 0.5 * u), at + span * u)
            # (the trunk's weight let go: a dull, heavy thud a moment in, and the low whump of it)
            m = n_of(0.9)
            F.put(x, F.knock(1.6 * size, 0.15) * amp * 0.8, at + rng().uniform(0.01, 0.04))
            F.put(x, T.thud(m, 1.8 * size) / 6.0 * amp, at + rng().uniform(0.02, 0.06))
        avalanche(tb, c["fibres"], c["span"], c["size"], 0.5)
        if c["second"]:
            dt, sz = c["second"]
            avalanche(tb + dt, int(c["fibres"] * 0.45), c["span"] * 0.7, c["size"] * sz * 0.8, 0.35)
        # (splintering after it: fibres tearing along the grain, thinning out; the wood groaning as it goes over)
        te = tb + c["span"]
        for t1 in F.PB_poisson(te, min(te + c["tear"] * 2.5, d - 0.2), lambda u: 80.0 * np.exp(-(u - te) / (0.35 * c["tear"]))):
            F.put(x, F.fracture(rng().uniform(0.15, 0.9), 0.7, dull=rng().uniform(0.3, 0.8)) * min(rng().pareto(2.2), 2.5) * 0.03, t1)
        x += creak(d, rng().uniform(12, 30), bump(t, te + 0.3, 0.15, 0.5 * c["tear"] + 0.2) * 0.05, wild=0.5)
        x += groan(d, bump(t, te + 0.25, 0.1, 0.4 + 0.4 * c["tear"]) * 0.08)
        # (the roots ripping out, the ground breaking open; the root plate's dull heave)
        if c["roots"]:
            r0, rl, ra = c["roots"]
            e = np.clip((t - r0) / 0.25, 0, 1) * np.exp(-np.clip(t - r0 - rl * 0.5, 0, None) / (rl * 0.5))
            x += F.soil_tear(d, e) * 0.05 * ra
            F.put(x, T.thud(n_of(1.2), 2.6) / 5.0 * ra, r0 + rl * 0.55)
        # (the crown crashing through branches round it: twigs snapping in a burst, a heavy brushing thud)
        ca = c["crash"]
        for t1 in F.PB_poisson(ca - 0.05, min(ca + 1.0, d - 0.2), lambda u: 120.0 * np.exp(-max(u - ca, 0) / 0.25)):
            F.put(x, F.fracture(rng().uniform(0.1, 0.5), 1.0, dull=rng().uniform(0.0, 0.4)) * min(rng().pareto(2.4), 2.5) * 0.025, t1)
        F.put(x, F.knock(1.4, 0.1) * 0.22, ca + rng().uniform(0.05, 0.2))
        # (out in the open: the land's echoes, the top softened by the distance and the rain)
        x = F.space(x, wet=0.7, length=2.8, darken=(2800, 240), decay=1.0, seed_shift=v)
        x = F.cband(x, 35, None, 2)
        x = F.cband(x, None, 7000, 2)
        x = S.fades(x, 0.01, 0.5)
    x = F.tame(x)
    write_lufs(f"crack{v}", x, LUFS["crack"])


def gust(d, at, rise, fall):
    """A gust's envelope round `at`: it comes on, buffets unevenly, dies away (never a tidy bell)."""
    n = n_of(d)
    t = np.arange(n) / SR
    return bump(t, at, rise, fall) * np.clip(wander(n, 1.0, 6.0, 4.0), 0, None)


def build_debris(v):
    """A burst of debris in the wind as a recorder out in the storm would catch it, through a gust: v1 a board
    tumbling and skidding over the ground; v2 a squall of grit and gravel pelting down with small stones in it; v3
    something caught and flapping (a torn sheet, a leafy branch) until it tears free and bangs into something; v4 a
    big branch crashing down through twigs, bouncing. All dull and uneven, none of it ringing; out in the open."""
    d = {1: 3.0, 2: 3.0, 3: 3.2, 4: 3.0}[v]
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97400 + 7 * v):
        g = gust(d, rng().uniform(0.7, 1.1), rng().uniform(0.25, 0.4), rng().uniform(0.8, 1.2))
        x = F.buffet(d, g, deep=0.8) * 0.05
        if v == 1:
            # (a board cartwheeling over the ground: knocks at uneven gaps, now a skid, now airborne a moment)
            ts = rng().uniform(0.2, 0.35)
            a = 1.0
            while ts < d - 0.6:
                if rng().random() < 0.2:
                    ln = rng().uniform(0.12, 0.35)
                    F.put(x, F.scrape(ln, 1.2) * 0.05 * a, ts)
                    ts += ln + rng().uniform(0.0, 0.05)
                else:
                    F.put(x, F.knock(rng().uniform(0.5, 1.3), rng().uniform(0.2, 0.6)) * 0.12 * a * rng().lognormal(0.0, 0.5), ts)
                    ts += rng().exponential(0.12) + 0.035 + (0.25 if rng().random() < 0.12 else 0.0)
                a *= rng().uniform(0.86, 1.04)
            x += F.rustle(d, g, density=1500.0) * 0.02
        elif v == 2:
            # (grit and gravel pelting in the gust: countless dull little hits, small stones among them, a clod)
            e = g ** 1.3
            for t1 in F.PB_poisson(0.05, d - 0.1, lambda u: 900.0 * float(e[min(int(u * SR), n - 1)]) + 5.0):
                F.put(x, F.fracture(rng().uniform(0.05, 0.25), 0.9, dull=rng().uniform(0.2, 0.7)) * min(rng().pareto(2.6), 2.0) * 0.008, t1)
            for t1 in F.PB_poisson(0.1, d - 0.3, lambda u: 9.0 * float(e[min(int(u * SR), n - 1)])):
                F.put(x, F.knock(rng().uniform(0.15, 0.4), 0.9) * rng().uniform(0.05, 0.14), t1)
            F.put(x, T.thud(n_of(0.6), 1.2) / 6.0 * 0.6, rng().uniform(0.9, 1.6))
            x += T.unit(F.cband(white(d), 300, 3000, 1)) * np.clip(F.grains(d, 200.0, (0.003, 0.008)), 0, 6) * e * 0.012
        elif v == 3:
            # (caught and flapping: uneven slaps of it in the wind, in fits, harder with the gust; then torn loose, a bang)
            ts = 0.15
            tear = rng().uniform(2.0, 2.3)
            while ts < tear:
                k = min(int(ts * SR), n - 1)
                m = n_of(rng().uniform(0.015, 0.04))
                s = np.arange(m) / SR
                slap = F.cband(rng().standard_normal(m), rng().uniform(120, 300), rng().uniform(2000, 4500), 2) * (1 - np.exp(-s / rng().uniform(0.0015, 0.004))) * np.exp(-s / rng().uniform(0.006, 0.015))
                F.put(x, slap / (np.abs(slap).max() + 1e-9) * (0.01 + 0.05 * g[k]) * min(rng().lognormal(0.0, 0.6), 3.0), ts)
                ts += rng().uniform(0.05, 0.11) * (1.0 + 0.5 * rng().standard_normal() ** 2) + (0.2 if rng().random() < 0.06 else 0.0)
            x += F.rustle(d, g * (t < tear), density=1800.0) * 0.025
            F.put(x, F.knock(1.5, 0.4) * 0.3, tear + rng().uniform(0.15, 0.3))
            F.put(x, F.scrape(0.3, 0.8) * 0.03, tear + 0.35)
        else:
            # (a big branch crashing down: twigs snapping in a burst, the limb's dull thump, a bounce, leaves settling)
            ca = rng().uniform(0.5, 0.75)
            for t1 in F.PB_poisson(ca - 0.08, d - 0.4, lambda u: 140.0 * np.exp(-max(u - ca, 0) / 0.3)):
                F.put(x, F.fracture(rng().uniform(0.1, 0.6), 0.9, dull=rng().uniform(0.0, 0.5)) * min(rng().pareto(2.3), 2.5) * 0.02, t1)
            F.put(x, F.knock(1.8, 0.2) * 0.35, ca + 0.03)
            F.put(x, T.thud(n_of(0.8), 1.7) / 6.0 * 0.7, ca + 0.04)
            F.put(x, F.knock(1.0, 0.3) * 0.14, ca + rng().uniform(0.25, 0.4))
            F.put(x, F.knock(0.6, 0.4) * 0.06, ca + rng().uniform(0.55, 0.75))
            lv = 0.3 * g + 1.5 * bump(t, ca, 0.05, 0.5)
            x += F.rustle(d, lv, density=3200.0) * 0.035
        # (out in the storm: its echoes, the top taken off by the distance and the rain)
        x = F.space(x, wet=0.55, length=2.2, darken=(3000, 250), decay=0.8, seed_shift=10 + v)
        x = F.cband(F.cband(x, 30, None, 2), None, 6500, 2)
        x = S.fades(x, 0.05, 0.5)
    x = F.tame(x)
    write_lufs(f"debris{v}", x, LUFS["debris"])


# How each thing rushes past (`whoosh` takes): its length, when it is nearest, how long it takes to go by before and
# after, how deep its body, what rides on it.
WHOOSH = {
    1: dict(d=2.0, tc=0.95, pre=0.32, post=0.4, deep=1.0, kind="leaves"),   # a leafy branch tumbling by
    2: dict(d=2.6, tc=1.15, pre=0.5, post=0.6, deep=1.7, kind="heavy"),     # something big and heavy (a door, a sheet of roof)
    3: dict(d=2.0, tc=0.9, pre=0.35, post=0.45, deep=0.8, kind="grit"),     # a cloud of grit and twigs
    4: dict(d=1.6, tc=0.7, pre=0.2, post=0.28, deep=1.2, kind="close"),     # a board, close and fast
}


def build_whoosh(v):
    """A body shoved through the gusting air past the player as a recording out in it would have it: turbulent and
    uneven, mostly the low buffeting and a broad rush, lurching in surges, its pressure never smooth; brightest only as
    it is nearest. No sweep, no swish: its spectrum stays put, only how much of it there is moves. What rides on it is
    each take's own: leaves thrashing, a heavy body lurching, grit ticking, a board's uneven tumble."""
    c = WHOOSH[v]
    d = c["d"]
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97600 + 5 * v):
        u = t - c["tc"]
        near = 1.0 / (1.0 + (u / np.where(u < 0, c["pre"], c["post"])) ** 2)
        env = near ** 1.4 * np.clip(wander(n, 1.5, 9.0, 3.0), 0, None)
        x = F.buffet(d, env, deep=c["deep"])
        if c["kind"] == "leaves":
            x += F.rustle(d, env ** 1.3, density=3500.0) * 0.45
            for t1 in F.PB_poisson(0.1, d - 0.2, lambda s: 25.0 * float(near[min(int(s * SR), n - 1)])):
                F.put(x, F.fracture(rng().uniform(0.05, 0.3), 1.0, dull=0.3) * min(rng().pareto(2.5), 2.0) * 0.05, t1)
        elif c["kind"] == "heavy":
            # (its bulk lurching as it tumbles: uneven heaves of air at no steady rate)
            heave = np.clip(F.grains(d, 7.0, (0.06, 0.12)), 0, 5) ** 1.5
            x += T.unit(F.cband(white(d), 30, 260, 2)) * heave * near * 0.9
        elif c["kind"] == "grit":
            for t1 in F.PB_poisson(0.05, d - 0.1, lambda s: 500.0 * float(near[min(int(s * SR), n - 1)]) ** 1.5):
                F.put(x, F.fracture(rng().uniform(0.03, 0.2), 0.9, dull=rng().uniform(0.2, 0.6)) * min(rng().pareto(2.6), 2.0) * 0.02, t1)
        else:
            flut = np.clip(F.grains(d, 18.0, (0.02, 0.04)), 0, 5)
            x += T.unit(F.cband(white(d), 150, 1500, 1)) * flut * near ** 1.5 * 0.5
        x = F.space(x, wet=0.25, length=1.6, darken=(3500, 300), decay=0.6, ground=False, seed_shift=20 + v)
        x = F.cband(F.cband(x, 25, None, 2), None, 8000, 2)
        x = S.fades(x, 0.15, 0.35)
    x = F.tame(x)
    write_lufs(f"whoosh{v}", x, LUFS["whoosh"])


# ========================================================================================================  thunder
# The Supercell's model (sounds_storm.py's thunder: the channel's pulses arriving over seconds, the strokes' rip, the
# boom, the land's echoes), its parameters for each distance, drawn afresh for the Hurricane's own takes.
def build_thunder(v):
    """A bolt from the eyewall to the land close by (within ~110 blocks)."""
    d = 6.0
    with PB.seeded(98000 + 31 * v):
        gd = rng().uniform(30, 90)
        h = rng().uniform(700, 1300)
        st = S.strokes_of(int(rng().integers(3, 6)))
        f = rng().uniform(45, 56)
        boom = [(0.004, f * 1.45, f, f * 0.7, 0.05, 0.003, ((0.55, 0.22), (0.35, 0.7), (0.1, 1.6)), 1.0),
                (st[1][0] + 0.004, f * 1.2, f * 0.92, f * 0.68, 0.06, 0.006, ((0.6, 0.3), (0.4, 0.9)), 0.5),
                (rng().uniform(0.45, 0.9), f * 0.95, f * 0.8, f * 0.64, 0.2, 0.06, ((0.5, 0.5), (0.5, 1.4)), 0.3),
                (rng().uniform(1.3, 2.2), f * 0.85, f * 0.72, f * 0.6, 0.3, 0.12, ((1.0, 1.2),), 0.15)]
        rip = (1200, 12000, st[-1][0] + rng().uniform(0.05, 0.1), int(rng().integers(40, 80)), -2.5)
        run, br = rng().uniform(400, 1300), int(rng().integers(4, 8))
    L, R = S.thunder(98500 + 31 * v, d, gd, h, run, br, st, boom,
                     0.0, -25.0, -12.0, (2.8, 0.2, (2200, 220), 0.9, 0.72),
                     [(0.3, 0.16, 2200), (0.75, 0.11, 1400), (1.3, 0.08, 900), (2.1, 0.05, 600)], 0.7, rip=rip,
                     clap=(250, 8000, 2.0))
    L, R = S.body_drive(L, R, 0.03, 3.0)
    L, R = N.glue(L, R)
    L, R = S.fades(L, 0.0, 1.0), S.fades(R, 0.0, 1.0)
    S.write(f"thunder{v}", (L, R), LEVEL["thunder"], knee=0.6)


def build_thunder_mid(v):
    """A bolt 110-320 blocks off: a duller clap with a little tearing in it, the boom, a longer roll."""
    d = 6.5
    with PB.seeded(98700 + 31 * v):
        gd = rng().uniform(140, 320)
        h = rng().uniform(800, 1600)
        st = S.strokes_of(int(rng().integers(2, 5)))
        f = rng().uniform(43, 53)
        boom = [(0.01, f * 1.35, f, f * 0.72, 0.08, 0.01, ((0.5, 0.3), (0.5, 1.1)), 1.0),
                (rng().uniform(0.5, 1.1), f * 1.0, f * 0.84, f * 0.68, 0.22, 0.08, ((0.5, 0.6), (0.5, 1.6)), 0.3),
                (rng().uniform(1.6, 2.8), f * 0.88, f * 0.74, f * 0.64, 0.3, 0.15, ((1.0, 1.5),), 0.18)]
        rip = (900, 5500, st[-1][0] + rng().uniform(0.04, 0.08), int(rng().integers(12, 24)), -9.0)
        run, br = rng().uniform(700, 2000), int(rng().integers(4, 8))
    L, R = S.thunder(98900 + 31 * v, d, gd, h, run, br, st, boom,
                     -3.0, -26.0, -12.0, (3.4, 0.24, (1500, 200), 1.2, 0.8),
                     [(0.5, 0.16, 1300), (1.1, 0.11, 850), (1.9, 0.08, 560), (3.0, 0.05, 380)], 0.5, t0=0.04, fc_ref=50.0,
                     rip=rip, roll_corr=0.85, echo_pan=0.45, clap=(150, 3500, 4.0))
    L, R = S.body_drive(L, R, 0.04, 2.0)
    L, R = S.fades(L, 0.0, 1.6), S.fades(R, 0.0, 1.6)
    S.write(f"thunder_mid{v}", (L, R), LEVEL["thunder_mid"], knee=0.6)


def build_thunder_far(v):
    """A bolt further off: mostly roll, its clap a soft knock under it."""
    d = 9.0
    with PB.seeded(99000 + 31 * v):
        gd = rng().uniform(350, 900)
        h = rng().uniform(900, 1900)
        st = S.strokes_of(int(rng().integers(2, 5)))
        f = rng().uniform(40, 50)
        boom = [(0.02, f * 1.25, f, f * 0.8, 0.12, 0.03, ((0.5, 0.4), (0.5, 1.4)), 0.8),
                (rng().uniform(0.6, 1.4), f * 1.05, f * 0.85, f * 0.72, 0.25, 0.1, ((0.5, 0.8), (0.5, 2.2)), 0.6),
                (rng().uniform(2.0, 3.5), f * 0.9, f * 0.75, f * 0.66, 0.3, 0.2, ((1.0, 1.8),), 0.4)]
        run, br = rng().uniform(900, 2600), int(rng().integers(4, 8))
    L, R = S.thunder(99500 + 31 * v, d, gd, h, run, br, st, boom,
                     -6.0, -15.0, -11.0, (4.5, 0.45, (1200, 180), 1.6, 0.82),
                     [(0.6, 0.32, 850), (1.4, 0.24, 560), (2.4, 0.16, 380), (3.6, 0.1, 280)], 0.3, t0=0.06, fc_ref=45.0,
                     roll_corr=0.9, echo_pan=0.35, clap=(70, 700, 0.0))
    L, R = S.fades(L, 0.0, 1.5), S.fades(R, 0.0, 1.5)
    S.write(f"thunder_far{v}", (L, R), LEVEL["thunder_far"], knee=0.6)


def build_rumble(v):
    """A flash deep in the eyewall or out in a band: thunder in the cloud, no crack, a long soft roll, high up."""
    d = 9.0
    L, R = S.rumble_one(99700 + 17 * v, d)
    L, R = S.fades(L, 0.2, 1.5), S.fades(R, 0.2, 1.5)
    S.write(f"rumble{v}", (L, R), LEVEL["rumble"])


BUILD = {
    "wind": build_wind, "roar": build_roar, "roar_far": build_roar_far, "rain": build_rain,
    "debris": lambda: [build_debris(v + 1) for v in range(VARIANTS["debris"])],
    "crack": lambda: [build_crack(v + 1) for v in range(VARIANTS["crack"])],
    "whoosh": lambda: [build_whoosh(v + 1) for v in range(VARIANTS["whoosh"])],
    "thunder": lambda: [build_thunder(v + 1) for v in range(VARIANTS["thunder"])],
    "thunder_mid": lambda: [build_thunder_mid(v + 1) for v in range(VARIANTS["thunder_mid"])],
    "thunder_far": lambda: [build_thunder_far(v + 1) for v in range(VARIANTS["thunder_far"])],
    "rumble": lambda: [build_rumble(v + 1) for v in range(VARIANTS["rumble"])],
}


def listen_mix(z, out, carry=False):
    """The strike's sounds as a player `z` blocks off hears them in Horizon (their times, takes, volumes and pitches
    from the plan; `carry`: carried off by the wind, its whooshes too), mixed as the game does: each file summed to mono,
    0.596 in each ear, its pitch a change of speed, on its tick, then the game's output limiter (sounds_storm.py's)."""
    tag = f"{z}{'_carried' if carry else ''}"
    tl = Path(out) / f"timeline_{tag}.txt"
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "hu_write_sounds", "--", "--ignored"], cwd=ROOT / "mod",
                   env=dict(os.environ, HU_OUT=str(tl.resolve()), HU_ME=str(z), HU_CARRY="1" if carry else "0"), check=True, capture_output=True)
    mix = np.zeros((n_of(66.0), 2))
    files = {}
    tick = lambda t: np.ceil(float(t) * 20 - 1e-6) / 20
    for l in (l.split() for l in tl.read_text().splitlines() if l.strip()):
        t, ev, vol, pitch = l[:4]
        name = ev.split(".", 1)[1]
        f = f"{out}/{name}.wav"
        if f not in files:
            with wave.open(f) as w:
                y = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float).reshape(-1, w.getnchannels()) / 32768
            files[f] = y.mean(axis=1)
        y = files[f]
        p = float(pitch)
        if abs(p - 1) > 1e-4:
            pos = np.arange(0, len(y) - 1, p)
            i0 = pos.astype(int)
            y = y[i0] * (1 - (pos - i0)) + y[i0 + 1] * (pos - i0)
        i = n_of(tick(t))
        m = min(len(y), len(mix) - i)
        if m > 0:
            mix[i:i + m] += (y[:m] * min(float(vol), 1.0) * 0.596)[:, None]
    pre = 20 * np.log10(np.abs(mix).max() + 1e-12)
    held = S.game_limiter(mix)
    path = f"{out}/hurricane_mix_{tag}"
    N.write_wav(path + ".wav", mix)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-b:a", "192k", path + ".mp3"], check=True)
    lufs, tp, _ = N.measure(path + ".wav")
    print(f"mix {tag}: peak {pre:.2f} dBFS before the game's limiter ({held:.1f} s held down), true peak {tp:.2f} dBTP, {lufs:.1f} LUFS -> {path}.mp3")
    return tp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also the WAV and MP3 of each, in this folder")
    a = ap.parse_args()
    soundlib.init(a.out)
    S.TH = TH
    S.LISTEN = a.listen
    for name in a.only or NAMES:
        BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    if path.exists():
        sounds = json.loads(path.read_text())
        for name in NAMES:
            ev = f"{TH}.{name}"
            files = [f"orbital:{TH}/{name}{v + 1}" for v in range(VARIANTS[name])] if name in VARIANTS else [f"orbital:{TH}/{name}"]
            sounds[ev] = {"sounds": [{"name": f, "attenuation_distance": 256} for f in files], "subtitle": f"subtitles.orbital.{ev}"}
            if name in PICKED:
                for v in range(VARIANTS[name]):
                    sounds[f"{ev}{v + 1}"] = {"sounds": [{"name": files[v], "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
        for name in GONE:
            sounds.pop(f"{TH}.{name}", None)
            f = Path(a.out) / "assets" / "orbital" / "sounds" / TH / f"{name}.ogg"
            if f.exists():
                f.unlink()
        path.write_text(json.dumps(sounds, indent=2))
    if a.listen and not a.only:
        worst = max(listen_mix(z, a.listen, c) for z, c in ((60, False), (150, False), (500, False), (150, True)))
        print(f"worst true peak over the mixes: {worst:.2f} dBTP")


if __name__ == "__main__":
    main()
