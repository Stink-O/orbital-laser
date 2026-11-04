"""The Fold's sounds (laser 14), synthesised from slowly sliding partials, breathy filtered noise and resonators; nothing
sampled. As strike/fold.rs plays them (strike seconds):

  drone     0 s: one long ambient bed for the whole come-up (37 s). A low chord of detuned partials breathing in and
            out like a choir with no words, sliding slowly up a fifth over the first half minute while it swells,
            breathy noise moving through bands over it, glassy high partials twinkling in from the come-up on; at
            32 s it is drawn in (pitch rushing up, the level rising), then it is gone at 36 s: the last second of the
            file is near silence, a faint sub only.
  bloom     37 s: the release, one big resonant bloom: a wide chord opening out of the silence and ringing (bell-like
            inharmonic modes, a long reverb), a low swell under it; 9 s.
  comedown  39 s: what is left fading: the chord sinking, slower and thinner, noise washing out, a few glassy partials
            falling away; 12 s.

    python3 tools/sounds_fold.py            # writes orbital-sounds/assets/orbital/sounds/fold/*.ogg and the fold.* events
    python3 tools/sounds_fold.py --listen DIR   # also a WAV of each
"""
import argparse, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, band, smooth_noise, reverb_st

ROOT = Path(__file__).resolve().parent.parent
rng = np.random.default_rng(1414)


def ss(a, b, x):
    u = np.clip((x - a) / (b - a), 0, 1)
    return u * u * (3 - 2 * u)


def bed(d, f0_of_t, level_of_t, seed, parts=(1, 1.5, 2, 3, 4.02, 5.01, 6.03), amps=(1, .55, .7, .35, .22, .15, .1), side=0):
    """A choir-like pad: detuned partials of a sliding fundamental, each breathing on its own slow curve."""
    r = np.random.default_rng(seed)
    n = int(d * SR)
    t = np.arange(n) / SR
    f0 = f0_of_t(t)
    out = np.zeros(n)
    for p, a in zip(parts, amps):
        for v in range(3):
            det = 1 + (r.uniform(-1, 1) * 0.0035) + (side * 0.0007)
            ph = np.cumsum(f0 * p * det) / SR * 2 * np.pi + r.uniform(0, 6.28)
            breath = 0.55 + 0.45 * smooth_noise(d, 0.35 + 0.2 * r.random(), n)
            out += a * breath * np.sin(ph + 0.6 * np.sin(2 * np.pi * (0.1 + 0.07 * v) * t + r.uniform(0, 6)))
    return out * level_of_t(t) / 9.0


def breath(d, level_of_t, lo0, hi0, rate):
    n = int(d * SR)
    t = np.arange(n) / SR
    x = np.random.default_rng(int(d * 100)).standard_normal(n)
    # (the band slides: three bands cross-faded through the file)
    y = np.zeros(n)
    for k, (lo, hi) in enumerate([(lo0, hi0), (lo0 * 2, hi0 * 2.2), (lo0 * 4, hi0 * 3)]):
        w = 0.5 + 0.5 * np.sin(2 * np.pi * rate * t + k * 2.1)
        y += band(x, lo, hi) * w
    return y * level_of_t(t)


def drone():
    d = 37.0
    n = int(d * SR)
    t = np.arange(n) / SR
    # pitch: 55 Hz rising a fifth by 30 s, then drawn in (rushing up), the file ends silent
    def f0(t):
        slide = 55 * (1 + 0.5 * ss(0, 30, t))
        pull = 1 + 1.6 * ss(32, 36, t) ** 2
        return slide * pull
    swell = 0.05 + 0.95 * ss(0, 26, t) ** 1.3
    collapse = 1 + 0.5 * ss(32, 35.3, t)
    gone = 1 - ss(35.3, 36.1, t)
    tail = 0.012 * ss(36.0, 36.4, t) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.6 * t))
    lvl = lambda t: swell * collapse * gone
    chans = []
    for side in (-1, 1):
        x = bed(d, f0, lvl, 7 + side, side=side)
        # glassy partials twinkling in as the come-up begins
        g = np.zeros(n)
        r = np.random.default_rng(31 + side)
        for i in range(60):
            t0 = r.uniform(7, 33)
            f = 55 * 2 ** r.uniform(3.0, 5.2)
            e = np.exp(-np.maximum(t - t0, 0) / r.uniform(0.6, 2.0)) * (t >= t0) * np.minimum((t - t0) * 40, 1)
            g += 0.05 * e * np.sin(2 * np.pi * f * t)
        g *= ss(7, 20, t) * gone
        b = breath(d, lambda t: 0.5 * swell * gone, 200, 900, 0.07 + 0.01 * side) * 0.25
        # (a slow thrum under the swell)
        sub = 0.5 * np.sin(2 * np.pi * f0(t) * 0.5 * t * 0 + np.cumsum(f0(t) * 0.5) / SR * 2 * np.pi) * swell * gone
        chans.append(x + g + b + 0.12 * sub + tail * np.sin(2 * np.pi * 38 * t))
    l, rr = reverb_st(chans[0], wet=0.22, tau_lo=2.2, tau_mid=1.1, tau_hi=0.5, length=3.5)
    l2, rr2 = reverb_st(chans[1], wet=0.22, tau_lo=2.2, tau_mid=1.1, tau_hi=0.5, length=3.5)
    left = l[:n]; right = rr2[:n]
    # (the reverb's tail is cut with the bed: the last second is the beat of near silence, a faint sub only)
    gate = 1 - ss(35.4, 36.2, t)
    sub = 0.004 * ss(36.0, 36.5, t) * np.sin(2 * np.pi * 36 * t) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.5 * t))
    return left * gate + sub, right * gate + sub


def bloom():
    d = 9.0
    n = int(d * SR)
    t = np.arange(n) / SR
    chans = []
    for side in (-1, 1):
        x = np.zeros(n)
        r = np.random.default_rng(90 + side)
        # a wide chord opening out of silence, ringing: inharmonic modes on a low fundamental
        base = 82.4
        for k, ratio in enumerate([1, 2.0, 2.76, 3.0, 4.07, 5.4, 6.7, 8.1, 10.4]):
            f = base * ratio * (1 + 0.002 * side * r.uniform(-1, 1))
            dec = 5.0 / (1 + 0.35 * k)
            env = np.minimum(t / (0.12 + 0.05 * k), 1) * np.exp(-t / dec)
            x += (1.0 / (1 + 0.4 * k)) * env * np.sin(2 * np.pi * f * t + r.uniform(0, 6))
        # the choir swell behind it
        pad = bed(d, lambda t: 82.4 * np.ones_like(t) * (1 + 0.02 * np.sin(t * 0.5)), lambda t: ss(0, 1.5, t) * np.exp(-t / 3.2), 55 + side, side=side)
        low = np.sin(2 * np.pi * 41.2 * t) * ss(0, 0.3, t) * np.exp(-t / 2.5) * 0.9
        x = x * 0.5 + pad * 2.2 + low * 0.5
        chans.append(x)
    l, _ = reverb_st(chans[0], wet=0.45, tau_lo=3.0, tau_mid=1.8, tau_hi=0.7, length=4.5)
    _, rr = reverb_st(chans[1], wet=0.45, tau_lo=3.0, tau_mid=1.8, tau_hi=0.7, length=4.5)
    return l[:n], rr[:n]


def comedown():
    d = 12.0
    n = int(d * SR)
    t = np.arange(n) / SR
    chans = []
    for side in (-1, 1):
        f0 = lambda t: 82.4 * (1 - 0.18 * ss(0, 11, t))
        lvl = lambda t: 0.8 * np.exp(-t / 5.0) * (1 - ss(9, 12, t))
        x = bed(d, f0, lvl, 140 + side, parts=(1, 1.5, 2, 3), amps=(1, .5, .6, .25), side=side) * 2.0
        b = breath(d, lambda t: 0.3 * np.exp(-t / 3.5), 300, 1500, 0.11) * 0.3
        r = np.random.default_rng(160 + side)
        g = np.zeros(n)
        for i in range(24):
            t0 = r.uniform(0, 8)
            f = 82.4 * 2 ** r.uniform(3.2, 5.0) * (1 - 0.1 * t0 / 12)
            e = np.exp(-np.maximum(t - t0, 0) / r.uniform(0.7, 1.8)) * (t >= t0) * np.minimum((t - t0) * 40, 1)
            g += 0.06 * e * np.sin(2 * np.pi * f * t)
        chans.append(x + b + g)
    l, _ = reverb_st(chans[0], wet=0.3, tau_lo=2.4, tau_mid=1.4, tau_hi=0.6, length=4.0)
    _, rr = reverb_st(chans[1], wet=0.3, tau_lo=2.4, tau_mid=1.4, tau_hi=0.6, length=4.0)
    return l[:n], rr[:n]


NAMES = {"drone": drone, "bloom": bloom, "comedown": comedown}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen")
    a = ap.parse_args()
    soundlib.init(a.out)
    for name, fn in NAMES.items():
        if a.only and a.only != name:
            continue
        l, r = fn()
        soundlib.finish_st(f"fold/{name}", l, r, tail_fade=0.3 if name != "drone" else 0.05)
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    for name in NAMES:
        sounds[f"fold.{name}"] = {"sounds": [{"name": f"orbital:fold/{name}", "stream": True}], "subtitle": f"subtitles.orbital.fold.{name}"}
    path.write_text(json.dumps(sounds, indent=2))


main()
