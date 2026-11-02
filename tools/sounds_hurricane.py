"""The Hurricane's sounds, synthesised here from noise, resonators and filters (nothing sampled), on the Supercell's
wind and rain (tools/sounds_storm.py). A first pass, meant to be replaced as references come in: each is its own file
and event, so one can be swapped without touching the plan (strike/hurricane.rs).

The beds are continuous, a minute long each and played once from the strike's start, the storm's whole life written
into them (its build-up, its height, the winds dropping), so nothing in them restarts, steps or overlaps; the plan only
sets each one's level by the distance:

  wind       the wind round the player: a hush, then gusts rising out of it, buffeting, a broad rush, a howl climbing
             with each gust, as hard as the storm's wind blows at that moment (strike/hurricane.rs's SPIN_K)
  roar       the eyewall's roar near (within 330 blocks): a deep turbulent rumble, a freight-train roar boiling over it,
             debris rattling and thudding through it, building with the wind, falling away in pitch and level as it drops
  roar_far   the same from further off: darker, mostly rumble and a distant roar
  rain       wind-driven rain: in from 4 s, heaviest at the storm's height, easing to drips as it clears

Over them, now and then, quieter than the beds and darkened by the distance:
  debris     (4 takes) a burst of debris in the wind: wood and stone clattering, a thud, grit
  crack      (4 takes, mono, played where the tree was) a tree torn out: splintering, a groan, roots ripping
  whoosh     (4 takes, mono) debris rushing past a player the wind carries

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

TH = "hurricane"
ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {"debris": 4, "crack": 4, "whoosh": 4}
NAMES = ["wind", "roar", "roar_far", "rain", "debris", "crack", "whoosh"]
# (the plan's old events, taken out of sounds.json and their files deleted when it's rebuilt)
GONE = ["buildup", "gusts", "winddown"]
BED = 60.0
# The storm's wind through the strike (strike/hurricane.rs's SPIN_K: keep in step), the beds' envelopes from it.
SPIN_K = [(0.0, 0.04), (8.0, 0.15), (26.0, 1.0), (44.0, 1.0), (50.0, 0.35), (58.0, 0.08), (64.0, 0.0)]


def spin(t):
    return np.interp(t, [k[0] for k in SPIN_K], [k[1] for k in SPIN_K])
# (the plan picks these takes itself: each its own event)
PICKED = ("debris", "crack", "whoosh")
# Each file's loudest 400 ms (dB, mono as the game plays it), set against each other so the strike's mix stays under
# -1 dBTP (`--listen` checks it) and the accents sit in the beds.
LEVEL = {"wind": -18.0, "roar": -15.0, "roar_far": -19.0, "rain": -25.0, "debris": -23.0, "crack": -19.0, "whoosh": -21.0}


def rng():
    return soundlib.rng


def n_of(d):
    return int(SR * d)


def roar_bed(d, far=False, rise=None, debris_env=None):
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
    # (the debris as thick as the wind is strong: the envelope a hundred times a second, looked up)
    coarse = debris_env[::SR // 100] if debris_env is not None else None
    de = (lambda u: float(coarse[min(int(u * 100), len(coarse) - 1)])) if coarse is not None else (lambda u: 1.0)
    for t1 in P.poisson_times(0.0, d - 0.3, lambda u: rate * de(u) + 1e-3):
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
        L, R = roar_bed(BED, rise=0.25 + 0.95 * env, debris_env=env)
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
        L, R = roar_bed(BED, far=True, rise=0.3 + 0.9 * env, debris_env=env)
        x = S.fades((L + R) * 0.5 * (0.03 + 0.97 * np.clip(env * 1.2, 0, 1)), 2.0, 5.0)
    S.write("roar_far", x, LEVEL["roar_far"])


def build_rain():
    with PB.seeded(97301):
        t, k = curve()
        L, R = S.rain(BED, 1.6)
        e = np.clip((t - 4.0) / 8.0, 0, 1) ** 1.5 * (1.0 - np.clip((t - 50.0) / 8.0, 0, 1)) * (0.55 + 0.45 * k)
        x = S.fades((L + R) * 0.5 * e, 1.0, 3.0)
    S.write("rain", x, LEVEL["rain"])


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
        # (heard through the wind: its top softened, in and out without a click)
        x = S.fades(band(x, None, 5000, 2), 0.02, 0.6)
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


BUILD = {
    "wind": build_wind, "roar": build_roar, "roar_far": build_roar_far, "rain": build_rain,
    "debris": lambda: [build_debris(v + 1) for v in range(VARIANTS["debris"])],
    "crack": lambda: [build_crack(v + 1) for v in range(VARIANTS["crack"])],
    "whoosh": lambda: [build_whoosh(v + 1) for v in range(VARIANTS["whoosh"])],
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
