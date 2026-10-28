"""The Sinkhole's sounds, all synthesised here from noise, pulses and filters (nothing sampled):

  rumble     the unease (0 is the strike's start, heard from the middle): a sub-bass rumble felt more than heard,
             swelling and sagging unevenly, building to the collapse (8.6 s in), a low grind creeping in under it, then
             dying away
  groan1-3   the ground under strain (positional, mono): deep, earthy resonances sliding down, rock grinding against rock
             in uneven grabs, dull knocks deep down; each its own length and shape
  crack1-3   rock snapping (positional, mono): a hard broadband crack, a low thump under it, a short crumble of grit,
             heard off the land round it; each take its own
  give       the first give (positional, mono): a crack, the heavy drop of the middle (a pressure pulse and a sub shove),
             earth crumbling and a dusty rush after
  collapse   the middle going (0.6 s of strain first, then the boom): `explosion_live` on its own seed, darker and
             longer, with an earthy body (more low-mid, the top rolled off), a sub blow, rock grinding as it gives,
             and rocks tumbling after
  rockfall   the rest going, ring after ring (0 is 1.2 s after the boom): a grinding roar, slabs striking the bottom
             one after another (deep thuds, unevenly spaced, further and further off), rocks rattling down the walls
  trickle    the echoing near-silence after (0 is 17.5 s): a low wind over the hole, pebbles running down the walls and
             bouncing, each its own, now and then a small slide, all heard in the pit's long echo

    python3 tools/sounds_sinkhole.py            # writes orbital-sounds/assets/orbital/sounds/sinkhole/*.ogg and adds the
                                                # events to sounds.json, leaving every other sound as it is
    python3 tools/sounds_sinkhole.py --only crack1 --plots D
"""
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, tt, white, band, smooth_noise, thump, click
import sounds_themes as T
import sounds_pk_blast as PB

TH = "sinkhole"
NAMES = ["rumble", "groan1", "groan2", "groan3", "crack1", "crack2", "crack3", "give", "collapse", "rockfall", "trickle"]
# (peaks at about -0.8 dBFS once decoded)
CEIL = 0.875


def rng():
    return soundlib.rng


def put(x, y, t0):
    k = int(t0 * SR)
    m = min(len(y), len(x) - k)
    if m > 0:
        x[k:k + m] += y[:m]


def rock_crack(d, size=1.0, bright=1.0):
    """A rock snapping: a sharp broadband crack (a few ms), its ringing body (a short burst of band noise, uneven), a
    thump under it, then grit crumbling off for a moment. Mono, `d` seconds, the crack at 0.02 s."""
    n = int(SR * d); t = tt(d)
    t0 = 0.02
    x = T.nwave(n, t0, 0.0015 + 0.001 * size, 1.4 * bright, 9000)
    x += click(n, t0, 1.1 * bright, rng().uniform(900, 1500), rng().uniform(6000, 10000), rng().uniform(0.004, 0.009))
    # (a second and third splinter a few ms after: real cracks are never one clean pulse)
    for _ in range(rng().integers(2, 5)):
        x += click(n, t0 + rng().uniform(0.004, 0.05), rng().uniform(0.2, 0.6) * bright, 700, 7000, rng().uniform(0.002, 0.006))
    body = band(white(d), 250, 2400) * np.exp(-np.maximum(t - t0, 0) / (0.05 + 0.04 * size)) * (t >= t0)
    x += body * (0.4 + 0.5 * smooth_noise(d, 40, n)) * 0.6
    x += thump(n, t0 + 0.004, 120 * (1.2 - 0.4 * size), 38, 0.12 + 0.12 * size, 10.0) * 0.9 * size
    # grit crumbling off after it
    for _ in range(int(14 * size) + 4):
        tc = t0 + 0.05 + rng().gamma(1.3, 0.12 * size + 0.05)
        if tc < d - 0.1:
            x += click(n, tc, rng().uniform(0.03, 0.15), 1500, 8000, rng().uniform(0.001, 0.004))
    return x


def stone_groan(d, f0, f1, take):
    """The ground straining: deep resonances (narrow noise bands, no pitch to ring) sliding down, rock grinding in
    uneven grabs, a few dull knocks deep down, swelling and easing unevenly."""
    n = int(SR * d); t = tt(d)
    swell = np.clip(t / (d * rng().uniform(0.2, 0.45)), 0, 1) ** 1.4 * (0.5 + 0.5 * (0.5 + 0.5 * smooth_noise(d, 0.9 + 0.3 * take, n))) * T.fade(n, 0.05, d * 0.3)
    res = np.zeros(n)
    for k, (w, a) in enumerate(((0.25, 1.0), (0.35, 0.5), (0.45, 0.3))):
        res += T.glide_noise(d, f0 * (1.6 ** k), f1 * (1.6 ** k), w, curve=0.7) * a
    x = T.unit(res) * swell
    # grinding: rock on rock, darker than metal's
    x += T.stick_slip(d, 9 + 5 * take, 90, 520, 0.8, 5.0) * swell ** 1.5 * 0.45
    x += T.unit(band(white(d), 18, 45)) * swell * 0.5
    for _ in range(rng().integers(2, 5) if d > 2.0 else 0):
        t1 = rng().uniform(0.3, d - 0.8)
        m = min(int(0.7 * SR), n - int(t1 * SR))
        x[int(t1 * SR):int(t1 * SR) + m] += T.thud(m, rng().uniform(1.5, 2.6)) * rng().uniform(0.3, 0.7)
    for _ in range(rng().integers(1, 4) if d > 2.0 else 0):
        tc = rng().uniform(0.4, d - 0.6)
        put(x, rock_crack(1.0, rng().uniform(0.2, 0.5), 0.5) * rng().uniform(0.15, 0.35), tc)
    return x


def rumble():
    d = 24.0; n = int(SR * d); t = tt(d)
    with PB.seeded(88101):
        build = np.clip(t / 8.6, 0, 1) ** 1.6
        after = np.where(t < 8.6, 1.0, np.exp(-(t - 8.6) / 5.0))
        env = (0.15 + 0.85 * build) * after * (0.55 + 0.45 * (0.5 + 0.5 * smooth_noise(d, 0.7, n))) * T.fade(n, 1.5, 3.0)
        L = np.zeros(n); R = np.zeros(n)
        for ch in (L, R):
            sub = T.unit(band(white(d), 16, 42)) * 1.0 + T.unit(band(white(d), 40, 90)) * 0.45
            grind = T.stick_slip(d, 6.0, 70, 300, 0.9, 4.0) * build ** 2 * 0.25
            ch += (sub + grind) * env * (0.8 + 0.2 * smooth_noise(d, 3.0, n))
        L, R = T.centre_lows(T.low_cut(L, 14), T.low_cut(R, 14))
    T.finish_loud(f"{TH}/rumble", L, R, -15.0, 2.0, CEIL)


def groan(take):
    with PB.seeded(88200 + take):
        d = [3.4, 4.6, 2.8][take - 1]
        f0, f1 = [(85, 48), (64, 36), (110, 60)][take - 1]
        x = stone_groan(d, f0, f1, take)
        x = T.convolve_wet(x, T.outdoor_ir(2.2, density=40.0, darken=(2200, 120), decay=1.0), 0.45)
    T.finish_loud(f"{TH}/groan{take}", T.low_cut(x, 18), None, -12.0, 0.4, CEIL)


def crack(take):
    with PB.seeded(88300 + take):
        d = 2.6
        x = rock_crack(d, [0.7, 1.0, 0.5][take - 1], [1.0, 0.85, 1.15][take - 1])
        x = T.convolve_wet(x, T.outdoor_ir(2.0, density=55.0, darken=(4500, 180), decay=0.8), 0.35)
    T.finish_loud(f"{TH}/crack{take}", T.low_cut(x, 20), None, -10.0, 0.3, CEIL)


def give():
    with PB.seeded(88401):
        d = 5.0; n = int(SR * d); t = tt(d)
        x = rock_crack(d, 1.3, 1.1)
        x += T.heavy(n, 0.06, 0.22, 2.0, 1.2, 0.9, 0.4) * 1.1
        L, R = T.debris_rain(d, 0.15, 2.4, 70, 0.3, 0.0)
        x += L + R
        # the dust rushing up and the earth settling
        x += band(white(d), 300, 3000) * np.clip((t - 0.1) / 0.2, 0, 1) * np.exp(-np.maximum(t - 0.1, 0) / 0.9) * 0.18
        x = T.convolve_wet(x, T.outdoor_ir(3.0, density=40.0, darken=(3000, 140), decay=1.3), 0.4)
    T.finish_loud(f"{TH}/give", T.low_cut(x, 16), None, -8.0, 0.4, CEIL)


def collapse():
    """The boom 0.6 s in: `explosion_live` made earthy, the strain before it."""
    pre = 0.6
    d = 18.0; n = int(SR * d); t = tt(d)
    with PB.seeded(88501):
        EL, ER = PB.explosion_live(d, pre, stretch=1.25, debris=1.6, whump=1.4, live=0.8)
        lv = T.loudest((EL + ER) / 2)
        # (earthy: the top rolled off a little, the low-mid body pushed)
        def earth(x):
            hi = band(x, 3000, None, 2)
            body = band(x, 90, 500, 2)
            return x - hi * 0.45 + body * 0.35
        EL, ER = earth(EL), earth(ER)
        u = np.maximum(t - pre, 0)
        # the strain: a groan rising into it
        strain = stone_groan(pre + 0.3, 70, 120, 2)
        strain = np.pad(strain, (0, n - len(strain))) * (t < pre + 0.05)
        # the ground giving: rock grinding as it goes, swelling then tailing off
        grind = T.stick_slip(d, 7.0, 60, 450, 0.9, 3.0) * np.clip(u / 0.5, 0, 1) * np.exp(-u / 4.0) * (t >= pre)
        sub = T.sub_drop(n, pre, 48, 22, 3.0, 2.5, 1.0)
        L = EL.copy(); R = ER.copy()
        gk = lv / (T.loudest(grind) + 1e-9)
        sk = lv / (T.loudest(strain) + 1e-9)
        bk = lv / (T.loudest(sub) + 1e-9)
        for ch, p in ((L, -0.3), (R, 0.3)):
            ch += grind * gk * 0.35 + strain * sk * 0.25 + sub * bk * 0.6
        # rocks tumbling after, near and far
        dl, dr = T.debris_rain(d, pre + 0.8, pre + 7.0, 160, 0.4)
        dk = lv / (T.loudest((dl + dr) / 2) + 1e-9)
        L += dl * dk * 0.2; R += dr * dk * 0.2
        # (the boom's roar dies into the rockfall's after a few seconds, rather than holding)
        tail = np.where(u < 2.5, 1.0, np.exp(-(u - 2.5) / 2.8))
        L, R = T.centre_lows(T.low_cut(L * tail, 16), T.low_cut(R * tail, 16))
    PB.finish_blast(f"{TH}/collapse", L, R, -8.0, 0.895, 0.8)


def rockfall():
    d = 15.0; n = int(SR * d); t = tt(d)
    with PB.seeded(88601):
        env = np.clip(t / 0.8, 0, 1) * np.where(t < 5.5, 1.0, np.exp(-(t - 5.5) / 2.6))
        L = np.zeros(n); R = np.zeros(n)
        for ch in (L, R):
            ch += T.roar_bed(d, 60, 700, 2.0, 0.6) * env * 0.5
            ch += T.stick_slip(d, 11.0, 80, 600, 0.9, 4.0) * env * 0.35
        # slabs striking the bottom: uneven, some together, further off as it runs out (duller, later)
        tk = 1.2
        while tk < 11.5:
            far = np.clip((tk - 1.0) / 10.0, 0, 1)
            m = int(1.6 * SR)
            hit = T.heavy(m, 0.0, rng().uniform(0.12, 0.3), 1.6, 1.0, 0.9, 0.35) * (1.0 - 0.55 * far)
            hit = band(hit, None, 1800 - 1200 * far, 2)
            l, r = T.pan(hit, rng().uniform(-0.8, 0.8))
            put(L, l, tk + far * 0.08); put(R, r, tk + far * 0.08)
            tk += rng().gamma(1.4, 0.35) * (0.6 + 0.6 * far)
        dl, dr = T.debris_rain(d, 0.3, 9.0, 340, 0.3)
        L += dl * 0.8; R += dr * 0.8
        L, R = T.wide_tail(L, 3.0, 1.8, (2500, 120), 0.6)[0], T.wide_tail(R, 3.0, 1.8, (2500, 120), 0.6)[1]
        m = min(len(L), len(R))
        L, R = T.centre_lows(T.low_cut(L[:m], 16), T.low_cut(R[:m], 16))
    T.finish_loud(f"{TH}/rockfall", L, R, -10.0, 1.5, CEIL)


def pebble(n, t0, size, dull):
    """One pebble running down a wall: a few bounces, closer together and softer each time, each its own click."""
    x = np.zeros(n)
    gap = rng().uniform(0.12, 0.35)
    amp = size
    tb = t0
    for _ in range(rng().integers(2, 7)):
        if tb > n / SR - 0.05:
            break
        x += click(n, tb, amp, 600 + 1400 * (1 - dull), 3500 + 4000 * (1 - dull), rng().uniform(0.0015, 0.004))
        tb += gap
        gap *= rng().uniform(0.5, 0.8)
        amp *= rng().uniform(0.45, 0.75)
    return x


def trickle():
    d = 17.0; n = int(SR * d); t = tt(d)
    with PB.seeded(88701):
        L = np.zeros(n); R = np.zeros(n)
        for ch in (L, R):
            ch += T.roar_bed(d, 120, 700, 0.6, 0.7) * 0.05 * (0.6 + 0.4 * smooth_noise(d, 0.3, n))
        # pebbles, unevenly: thicker at first, thinning out
        tp = 0.2
        while tp < d - 1.0:
            near = rng().random() ** 1.5
            x = pebble(n, tp, 0.05 + 0.25 * near, 1 - near)
            l, r = T.pan(x, rng().uniform(-0.9, 0.9))
            L += l; R += r
            tp += rng().exponential(0.25 + 0.06 * tp)
        # now and then a little slide of grit
        for _ in range(4):
            ts = rng().uniform(1.0, d - 3.0)
            m = int(rng().uniform(0.6, 1.4) * SR)
            k = int(ts * SR)
            g = band(white(m / SR), 1200, 7000) * np.hanning(m) * rng().uniform(0.04, 0.09)
            l, r = T.pan(g, rng().uniform(-0.7, 0.7))
            L[k:k + m] += l[: n - k]; R[k:k + m] += r[: n - k]
        # the pit's long echo
        L, R = T.wide_tail(L, 4.5, 2.6, (3500, 150), 1.0)[0], T.wide_tail(R, 4.5, 2.6, (3500, 150), 1.0)[1]
        m = min(len(L), len(R))
        f = T.fade(m, 1.0, 3.0)
        L, R = T.centre_lows(T.low_cut(L[:m] * f, 18), T.low_cut(R[:m] * f, 18))
    T.finish_loud(f"{TH}/trickle", L, R, -21.0, 2.0, CEIL)


BUILD = {"rumble": rumble, "groan1": lambda: groan(1), "groan2": lambda: groan(2), "groan3": lambda: groan(3),
         "crack1": lambda: crack(1), "crack2": lambda: crack(2), "crack3": lambda: crack(3), "give": give,
         "collapse": collapse, "rockfall": rockfall, "trickle": trickle}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--plots", type=Path)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "orbital-sounds"))
    a = ap.parse_args()
    soundlib.init(a.out)
    for name in a.only or NAMES:
        BUILD[name]()
        if a.plots:
            import sounds_crystal
            a.plots.mkdir(parents=True, exist_ok=True)
            sounds_crystal.plot(a.plots / f"{name}.png", name, f"{a.out}/assets/orbital/sounds/{TH}/{name}.ogg")
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    for name in NAMES:
        ev = f"{TH}.{name}"
        sounds[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
    path.write_text(json.dumps(sounds, indent=2))


if __name__ == "__main__":
    main()
