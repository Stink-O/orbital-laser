"""The Payload's sounds, all synthesised here from noise, pulses and filters (nothing sampled):

  drift    the object high up, drifting (0 is as it shows, 3 s into the strike): a faint, thin high whine that wavers
           and slides as it loops, a soft far-off rumble under it, both swelling and fading unevenly; it never settles
           into a steady tone
  dive     its dive (0 is the turn, 11 s in; it strikes 2.6 s later): the whine bending up into a tearing whistle, a
           rising roar of air and fire under it, louder and harsher as it comes, cut off dead at the strike
  blast    the blast reaching the player (0 is its arrival, late by the distance): `explosion_live` on its own seed, as
           loud as the Planet Killer's burst, a little drier and closer
  rush     the shockwave's dust going past (0 is 0.15 s before it arrives): a gust tearing through, dust and grit
           hissing, wind buffeting and gusting on, dying away over seconds
  debris   what comes back down round the player: heavy clods thudding into the ground near and far, unevenly, and a
           patter of grit and small stones, thinning out
  tail     the long rolling tail (0 is 2.4 s after the blast arrives): the roar breaking into rolls off the land,
           further and further off, a low rumble under it, fading to nothing over about 20 s

    python3 tools/sounds_payload.py            # writes orbital-sounds/assets/orbital/sounds/payload/*.ogg and adds the
                                               # events to sounds.json, leaving every other sound as it is
"""
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, tt, white, band, smooth_noise, click
import sounds_themes as T
import sounds_pk_blast as PB

TH = "payload"
NAMES = ["drift", "dive", "blast", "rush", "debris", "tail"]
# (peaks at about -0.8 dBFS once decoded)
CEIL = 0.875


def rng():
    return soundlib.rng


def put(x, y, t0):
    k = int(t0 * SR)
    m = min(len(y), len(x) - k)
    if m > 0:
        x[k:k + m] += y[:m]


def wavering_tone(d, f0, f_dev, rate, n):
    """A thin tone that slides about f0 (by up to f_dev Hz) on a slow random curve: never steady, never a chime."""
    f = f0 + f_dev * smooth_noise(d, rate, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) + 0.25 * np.sin(2.01 * ph + 0.3) + 0.08 * np.sin(3.03 * ph)


def drift():
    d = 9.0; n = int(SR * d); t = tt(d)
    with PB.seeded(91101):
        L = np.zeros(n); R = np.zeros(n)
        env = np.clip(t / 2.0, 0, 1) ** 1.5 * (0.6 + 0.4 * (0.5 + 0.5 * smooth_noise(d, 0.5, n))) * T.fade(n, 0.5, 1.2)
        for ch, s in ((L, 0), (R, 1)):
            # (the whine: high and thin, through a little air, wavering as it loops)
            whine = wavering_tone(d, 3150 + 60 * s, 180, 0.35, n) * 0.06
            whine += band(white(d), 2600, 4200) * 0.05 * (0.5 + 0.5 * smooth_noise(d, 1.2, n))
            rumble = T.unit(band(white(d), 28, 90)) * 0.5 + T.roar_bed(d, 90, 320, 0.8, 0.6) * 0.3
            ch += (whine + rumble * 0.6) * env
        L, R = T.wide_tail(L, 2.0, 1.4, (3000, 120), 0.5)[0], T.wide_tail(R, 2.0, 1.4, (3000, 120), 0.5)[1]
        m = min(len(L), len(R), n)
        L, R = T.centre_lows(T.low_cut(L[:m], 20), T.low_cut(R[:m], 20))
    T.finish_loud(f"{TH}/drift", L, R, -24.0, 1.0, CEIL)


def dive():
    hit = 2.6
    d = 2.75; n = int(SR * d); t = tt(d)
    with PB.seeded(91201):
        u = np.clip(t / hit, 0, 1)
        grow = u ** 2.2
        cut = np.where(t < hit, 1.0, np.exp(-(t - hit) / 0.012))
        L = np.zeros(n); R = np.zeros(n)
        for ch, s in ((L, 0), (R, 1)):
            # (the whistle bending up as it comes: a glide, not a note)
            f = 1900 + 2300 * u ** 1.6 + 120 * smooth_noise(d, 3.0, n)
            ph = 2 * np.pi * np.cumsum(f) / SR
            whistle = (np.sin(ph) + 0.3 * np.sin(2 * ph + 0.7)) * (0.05 + 0.18 * grow)
            whistle += T.glide_noise(d, 1800, 5200, 0.4, curve=1.6) * (0.1 + 0.35 * grow)
            roar = T.roar_bed(d, 70, 900, 4.0, 0.5) * (0.15 + 0.85 * grow) * 0.9
            tear = T.crackle(d, rate=800 + 4000 * s, decay=0.0012, lo=500, hi=7000) * grow ** 1.5 * 0.5
            sub = T.unit(band(white(d), 25, 70)) * grow * 0.6
            ch += (whistle + roar + tear + sub) * cut
        L, R = T.centre_lows(T.low_cut(L, 20), T.low_cut(R, 20))
    T.finish_loud(f"{TH}/dive", L, R, -9.0, 0.02, CEIL)


def blast():
    d = 16.0; n = int(SR * d)
    with PB.seeded(91301):
        EL, ER = PB.explosion_live(d, 0.02, stretch=0.9, debris=1.0, whump=1.25, live=1.0)
        L, R = T.centre_lows(T.low_cut(EL, 16), T.low_cut(ER, 16))
    PB.finish_blast(f"{TH}/blast", L, R, -8.0, 0.895, 0.8)


def rush():
    d = 10.0; n = int(SR * d); t = tt(d)
    with PB.seeded(91401):
        u = np.maximum(t - 0.15, 0)
        hit = np.clip((t - 0.05) / 0.12, 0, 1) ** 2
        L = np.zeros(n); R = np.zeros(n)
        for ch in (L, R):
            gust = T.roar_bed(d, 250, 5000, 3.5, 0.7) * hit * np.exp(-u / 1.6) * 0.9
            grit = band(white(d), 2500, 9000) * hit * np.exp(-u / 0.9) * 0.35
            grit *= 0.5 + 0.5 * np.abs(smooth_noise(d, 18.0, n))
            wind = T.roar_bed(d, 90, 900, 0.9, 0.8) * hit * (0.25 + 0.75 * np.exp(-u / 4.0)) * 0.6
            # (buffets: uneven pushes of air)
            buf = T.unit(band(white(d), 20, 60)) * (0.5 + 0.5 * smooth_noise(d, 2.2, n)) ** 2 * hit * np.exp(-u / 2.5)
            ch += gust + grit + wind + buf * 0.5
        dl, dr = T.debris_rain(d, 0.3, 3.0, 90, 0.18)
        L += dl * 0.25; R += dr * 0.25
        f = T.fade(n, 0.002, 2.5)
        L, R = T.centre_lows(T.low_cut(L * f, 18), T.low_cut(R * f, 18))
    T.finish_loud(f"{TH}/rush", L, R, -11.0, 1.0, CEIL)


def debris():
    d = 11.0; n = int(SR * d)
    with PB.seeded(91501):
        L = np.zeros(n); R = np.zeros(n)
        # clods thudding in: unevenly, more at first, some near (sharp, heavy), most further off (dull)
        tk = rng().uniform(0.05, 0.3)
        while tk < d - 2.0:
            near = rng().random() ** 2.2
            m = int(1.2 * SR)
            hit = T.heavy(m, 0.0, rng().uniform(0.05, 0.16), 1.0 + near, 1.0, 0.6, 0.25) * (0.25 + 0.75 * near)
            hit += band(white(1.2), 400, 3000) * np.exp(-np.arange(m) / SR / 0.05) * 0.4 * near
            hit = band(hit, None, 900 + 3500 * near, 2)
            l, r = T.pan(hit, rng().uniform(-0.9, 0.9))
            put(L, l, tk); put(R, r, tk)
            tk += rng().gamma(1.2, 0.18 + 0.05 * tk)
        dl, dr = T.debris_rain(d, 0.1, d - 2.0, 420, 0.25)
        L += dl; R += dr
        f = T.fade(n, 0.01, 2.0)
        L, R = T.centre_lows(T.low_cut(L * f, 20), T.low_cut(R * f, 20))
    T.finish_loud(f"{TH}/debris", L, R, -13.0, 1.0, CEIL)


def tail():
    d = 22.0; n = int(SR * d); t = tt(d)
    with PB.seeded(91601):
        L = np.zeros(n); R = np.zeros(n)
        env = np.exp(-t / 7.0) * T.fade(n, 0.8, 4.0)
        for ch in (L, R):
            ch += T.roar_bed(d, 40, 400, 0.7, 0.6) * env * 0.8
            ch += T.unit(band(white(d), 18, 50)) * env * 0.6
        # rolls off the land: swells of low roar, each further off, never evenly spaced
        tr = 0.3
        k = 0
        while tr < d - 4.0:
            m = int(rng().uniform(1.5, 3.2) * SR)
            far = min(tr / 14.0, 1.0)
            w = np.hanning(m) ** rng().uniform(0.8, 1.6)
            rb = T.roar_bed(m / SR, 35, 500 - 300 * far, 2.0, 0.5)
            m = min(m, len(rb)); w = w[:m]
            roll = rb[:m] * w * (1.0 - 0.7 * far) * 0.9
            l, r = T.pan(roll, rng().uniform(-0.8, 0.8))
            put(L, l, tr); put(R, r, tr)
            tr += rng().gamma(1.6, 0.9 + 0.25 * k)
            k += 1
        L, R = T.wide_tail(L, 4.0, 2.4, (1600, 90), 0.7)[0], T.wide_tail(R, 4.0, 2.4, (1600, 90), 0.7)[1]
        m = min(len(L), len(R), n)
        f = T.fade(m, 0.8, 4.0)
        L, R = T.centre_lows(T.low_cut(L[:m] * f, 16), T.low_cut(R[:m] * f, 16))
    T.finish_loud(f"{TH}/tail", L, R, -14.0, 2.0, CEIL)


BUILD = {"drift": drift, "dive": dive, "blast": blast, "rush": rush, "debris": debris, "tail": tail}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "orbital-sounds"))
    a = ap.parse_args()
    soundlib.init(a.out)
    for name in a.only or NAMES:
        BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    for name in NAMES:
        ev = f"{TH}.{name}"
        sounds[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
    path.write_text(json.dumps(sounds, indent=2))


if __name__ == "__main__":
    main()
