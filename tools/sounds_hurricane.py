"""The Hurricane's sounds, synthesised here from noise, resonators and filters (nothing sampled), on the Supercell's
wind and rain (tools/sounds_storm.py). A first pass, meant to be replaced as references come in: each is its own file
and event, so one can be swapped without touching the plan (strike/hurricane.rs).

  buildup    the storm gathering (12 s from the strike's start): a hush, a low pressure swell, the wind rising out
             of it in long gusts, the first rain
  gusts      the wind round the player (14 s beds, faded in and out over 2 s so the plan's overlap): buffeting, a
             broad rush, a howl climbing with each gust
  rain       wind-driven rain (12 s beds): a dense wash, drops, sheets of it swelling with the gusts
  roar       the eyewall's roar near (10 s beds every 8 s, as loud as the wind is strong): a deep turbulent rumble, a
             freight-train roar boiling over it, a high shriek in the gusts, debris rattling and thudding through it
  roar_far   the same from past 330 blocks: darker, mostly rumble and a distant roar
  debris     (4 takes) a burst of debris in the wind: wood and stone clattering, a thud, grit rattling, a shriek of wind
  crack      (4 takes) a tree torn out: a splintering crack, a groan, roots ripping, the crown thrashing
  whoosh     (4 takes, mono) debris rushing past a player the wind carries: a doppler swish, sometimes a clack
  winddown   the winds dropping as everything is flung out (14 s): the roar falling away in pitch and level, a last
             rattle of debris coming down, the rain easing to drips

    python3 tools/sounds_hurricane.py               # writes orbital-sounds/assets/orbital/sounds/hurricane/*.ogg and
                                                    # adds the events to sounds.json, every other sound left as it is
    python3 tools/sounds_hurricane.py --only roar   # one
    python3 tools/sounds_hurricane.py --listen DIR  # and a WAV and an MP3 of each in DIR
"""
import argparse, json, sys
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

TH = "hurricane"
ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {"debris": 4, "crack": 4, "whoosh": 4}
NAMES = ["buildup", "gusts", "rain", "roar", "roar_far", "debris", "crack", "whoosh", "winddown"]
# (the plan picks these takes itself: each its own event)
PICKED = ("debris", "crack", "whoosh")
LEVEL = {"buildup": -19.0, "gusts": -21.0, "rain": -27.0, "roar": -16.0, "roar_far": -20.0, "debris": -20.0,
         "crack": -15.0, "whoosh": -18.0, "winddown": -18.0}


def rng():
    return soundlib.rng


def n_of(d):
    return int(SR * d)


def roar_bed(d, far=False, rise=None):
    """The eyewall's roar, stereo: a deep rumble, the boiling roar, a shriek in the gusts, debris in it."""
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
    lv = np.std(out[0])
    # (debris in it: wood and stones clacking, thuds, grit)
    rate = 4.0 if far else 11.0
    for t1 in P.poisson_times(0.0, d - 0.3, lambda u: rate):
        m = n_of(0.25)
        if rng().random() < 0.6:
            h = P.modal_hit(m, rng().uniform(450, 2200), [1.0, rng().uniform(1.4, 2.3), rng().uniform(2.6, 4.0)],
                            [rng().uniform(0.008, 0.03), 0.01, 0.005], [1.0, 0.6, 0.35], 0.4, 7000)
        else:
            h = T.thud(m, rng().uniform(0.4, 1.4))
        h = h / (np.abs(h).max() + 1e-9) * lv * rng().uniform(0.2, 0.8) * (0.4 if far else 1.0)
        p = rng().uniform(-1, 1)
        P.put(out[0], h * (1 - p) * 0.6, t1)
        P.put(out[1], h * (1 + p) * 0.6, t1)
    return out[0], out[1]


def build_roar():
    with PB.seeded(97101):
        L, R = roar_bed(10.0)
        L, R = S.fades(L, 1.0, 1.0), S.fades(R, 1.0, 1.0)
    S.write("roar", (L, R), LEVEL["roar"])


def build_roar_far():
    with PB.seeded(97102):
        L, R = roar_bed(10.0, far=True)
        L, R = S.fades(L, 1.0, 1.0), S.fades(R, 1.0, 1.0)
    S.write("roar_far", (L, R), LEVEL["roar_far"])


def build_buildup():
    d = 12.0
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97001):
        rise = np.clip(t / d, 0, 1)
        g = S.gust_curve(d, rate=0.25, floor=0.05) * (0.12 + 0.88 * rise ** 1.5)
        L, R = S.wind(d, g)
        sw = T.unit(band(white(d), 20, 65, 3)) * rise ** 2.0 * (1 + 0.3 * PB.slow_random(n, 0.1, 0.6))
        L += sw * 0.25; R += sw * 0.25
        dl, dr = S.rain(d, 0.35)
        ramp = np.clip((t - 6.0) / 5.0, 0, 1) ** 2
        L += dl * ramp * 0.6; R += dr * ramp * 0.6
        # (the roar far off, starting to build at the end)
        rl, rr = roar_bed(d, far=True, rise=np.clip((t - 7.0) / 5.0, 0, 1))
        k = 0.3 * T.loudest((L + R) / 2) / (T.loudest((rl + rr) / 2) + 1e-12)
        L += rl * k * np.clip((t - 7.0) / 5.0, 0, 1); R += rr * k * np.clip((t - 7.0) / 5.0, 0, 1)
        L, R = S.fades(L, 0.6, 0.8), S.fades(R, 0.6, 0.8)
    S.write("buildup", (L, R), LEVEL["buildup"])


def build_gusts():
    d = 14.0
    with PB.seeded(97201):
        g = S.gust_curve(d, rate=0.4, floor=0.3, sharp=1.8) * 1.15
        L, R = S.wind(d, g)
        L, R = S.fades(L, 2.0, 2.0), S.fades(R, 2.0, 2.0)
    S.write("gusts", (L, R), LEVEL["gusts"])


def build_rain():
    d = 12.0
    with PB.seeded(97301):
        L, R = S.rain(d, 1.6)
        L, R = S.fades(L, 1.5, 1.5), S.fades(R, 1.5, 1.5)
    S.write("rain", (L, R), LEVEL["rain"])


def build_debris(v):
    d = 2.6
    n = n_of(d)
    with PB.seeded(97400 + 7 * v):
        x = np.zeros(n)
        # (a gust's shriek under it)
        g = np.exp(-((np.arange(n) / SR - 0.6) / 0.7) ** 2)
        x += T.unit(band(white(d), 500, 3000, 2)) * g * 0.25
        for t1 in P.poisson_times(0.05, d - 0.4, lambda u: 16.0 * np.exp(-u / 1.2)):
            m = n_of(0.3)
            r = rng().random()
            if r < 0.5:
                h = P.modal_hit(m, rng().uniform(380, 1900), [1.0, rng().uniform(1.5, 2.4), rng().uniform(2.8, 4.2)],
                                [rng().uniform(0.01, 0.04), 0.012, 0.006], [1.0, 0.6, 0.3], 0.4, 6500)
            elif r < 0.8:
                h = T.thud(m, rng().uniform(0.5, 1.5))
            else:
                h = band(rng().standard_normal(m) * np.exp(-np.arange(m) / SR / 0.05), 1500, 8000, 2)
            P.put(x, h / (np.abs(h).max() + 1e-9) * rng().uniform(0.25, 1.0), t1)
        gr = np.clip(N.grains(d, 300.0, (0.002, 0.005)), 0, 6) ** 1.5
        x += T.unit(band(white(d), 2000, 8000, 2)) * gr * 0.05 * np.exp(-np.arange(n) / SR / 1.0)
        x = S.fades(x, 0.01, 0.5)
    S.write(f"debris{v}", x, LEVEL["debris"])


def build_crack(v):
    d = 2.8
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97500 + 11 * v):
        x = np.zeros(n)
        # (the splintering: a fast run of sharp cracks, wood fibres going)
        t0 = 0.05
        for k in range(rng().integers(9, 16)):
            tk = t0 + 0.012 * k + rng().uniform(0, 0.02)
            m = n_of(0.08)
            h = band(rng().standard_normal(m) * np.exp(-np.arange(m) / SR / rng().uniform(0.004, 0.012)), 700, 9000, 2)
            P.put(x, h * rng().uniform(0.4, 1.0) * np.exp(-k / 8), tk)
        # (its body: a woody knock and a groan as it goes over)
        m = n_of(0.5)
        body = P.modal_hit(m, rng().uniform(160, 260), [1.0, 2.1, 3.4], [0.09, 0.05, 0.03], [1.0, 0.5, 0.25], 0.5, 3000)
        P.put(x, body / (np.abs(body).max() + 1e-9) * 0.8, t0)
        f = 120.0 * np.exp(-np.clip(t - 0.2, 0, None) / 1.2) + 60.0
        groan = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-((t - 0.6) / 0.45) ** 2) * 0.15
        x += band(groan * (1 + 0.5 * PB.slow_random(n, 5.0, 20.0)), 60, 900, 2)
        # (roots ripping out of the ground, the crown thrashing)
        rip = T.unit(band(white(d), 80, 600, 2)) * np.exp(-((t - 0.45) / 0.3) ** 2) * 0.35
        thrash = T.unit(band(white(d), 1500, 7000, 2)) * np.exp(-((t - 0.9) / 0.6) ** 2) * 0.2
        x += rip + thrash
        x = S.fades(x, 0.002, 0.4)
    S.write(f"crack{v}", x, LEVEL["crack"])


def build_whoosh(v):
    d = 1.4
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97600 + 5 * v):
        tc = rng().uniform(0.45, 0.75)
        w = rng().uniform(0.12, 0.25)
        env = np.exp(-((t - tc) / w) ** 2)
        f = 900.0 * np.exp(-(t - tc) * 2.2)
        x = P.glide_band(d, np.clip(f, 250, 4000), 0.5) * env
        x += T.unit(band(white(d), 400, 5000, 2)) * env * 0.5
        if rng().random() < 0.6:
            m = n_of(0.2)
            h = P.modal_hit(m, rng().uniform(600, 2000), [1.0, 1.8, 3.1], [0.02, 0.01, 0.005], [1.0, 0.5, 0.3], 0.4, 7000)
            P.put(x, h / (np.abs(h).max() + 1e-9) * 0.5 * np.std(x[n_of(tc) - 100:n_of(tc) + 100]) * 8, tc + 0.05)
        x = S.fades(x, 0.02, 0.2)
    S.write(f"whoosh{v}", x, LEVEL["whoosh"])


def build_winddown():
    d = 14.0
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(97701):
        fall = np.clip(1.0 - t / 10.0, 0.05, 1.0) ** 1.6
        L, R = roar_bed(d, rise=fall)
        # (the roar falling in pitch as it fades: its top darkened over time)
        lo = band(L, None, 500, 2); lo_r = band(R, None, 500, 2)
        mixk = np.clip(t / 8.0, 0, 1)
        L = L * (1 - mixk) + lo * mixk * 1.4
        R = R * (1 - mixk) + lo_r * mixk * 1.4
        L *= fall; R *= fall
        dl, dr = S.rain(d, 0.5)
        ease = np.clip(1.0 - t / 13.0, 0, 1)
        k = 0.4 * T.loudest((L[:n_of(2)] + R[:n_of(2)]) / 2) / (T.loudest((dl + dr) / 2) + 1e-12)
        L += dl * ease * k; R += dr * ease * k
        # (a last rattle of debris coming down)
        for t1 in P.poisson_times(0.3, 5.0, lambda u: 10.0 * np.exp(-u / 1.8)):
            m = n_of(0.25)
            h = T.thud(m, rng().uniform(0.5, 1.4))
            h = h / (np.abs(h).max() + 1e-9) * np.std(L[:n_of(1)]) * rng().uniform(0.5, 1.5)
            P.put(L, h, t1); P.put(R, h * rng().uniform(0.5, 1.0), t1)
        L, R = S.fades(L, 0.3, 2.0), S.fades(R, 0.3, 2.0)
    S.write("winddown", (L, R), LEVEL["winddown"])


BUILD = {
    "buildup": build_buildup, "gusts": build_gusts, "rain": build_rain, "roar": build_roar, "roar_far": build_roar_far,
    "debris": lambda: [build_debris(v + 1) for v in range(VARIANTS["debris"])],
    "crack": lambda: [build_crack(v + 1) for v in range(VARIANTS["crack"])],
    "whoosh": lambda: [build_whoosh(v + 1) for v in range(VARIANTS["whoosh"])],
    "winddown": build_winddown,
}


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
        path.write_text(json.dumps(sounds, indent=2))


if __name__ == "__main__":
    main()
