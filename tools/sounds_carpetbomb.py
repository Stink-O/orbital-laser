#!/usr/bin/env python3
"""The Carpet Bomb's sounds, made new for a stick of bombs from a bomber, in the manner of the sounds the owner approved
(the Payload's alternative blast e1b0aae: swept low blows with a noise body, a hard crack, the lows' own harmonics so
the weight carries on small speakers, the first instant driven into a soft clip; the Tsunami's 3456414: third-octave
noise bands with chaotic gains; the Hurricane's and the Payload's torn air: band noise chopped by an irregular flutter).
No tone anywhere: no whistles, chimes or clicks. Two takes of each (A is the one the mod plays).

  drone          a bomber high and far off: a breathy low drone of engines beating against each other, through a lot of
                 air, swelling in and fading as the stick comes down (under the strike's first seconds).
  fall1..3       a bomb coming down. Take C (FALL_TAKE, the one the mod plays): the falling bomb's scream, noise rung in
                a narrow band sliding down with its Doppler shift, airy rush round it, rising and cut dead on its blast.
                Take D: a heavier roar, as the Payload's dive. Takes A, B, E: torn air, a band chopped by an irregular flutter that quickens and deepens as it
                 nears, over a rushing body opening up brighter and a low push of air in its last half second, rising
                 some 28 dB and stopping dead on its blast (carpet.rs starts it its length before the bomb strikes:
                 keep FALLS there in step). Take B lower and rougher, its flutter ripping.
  blast1..3      a medium bomb going off a few hundred blocks off: a hard crack, the pressure wave's push, a deep swept
                 thump with a short low body, the low end's third-octave bands dying each at its own chaotic rate, the
                 air shuddering after, earth settling, a short echo off the land. Each a little different (pitch,
                 length, crack). Take B heavier, longer, a second blow.
  blast_far1..2  the same from the far end of the line: its top taken by the air, its crack dulled, its echoes off the
                 land coming back later and longer.

The last, biggest bomb plays the Payload's alternative blast as it is (no file here). `--mix CUES OUT` mixes a
strike's cues (carpet.rs's cp_write_cues) into a listening file; `--review DIR` writes the review takes (falls and
blasts, A and B) at -16 LUFS.

    python3 tools/sounds_carpetbomb.py                     # writes orbital-sounds/assets/orbital/sounds/carpetbomb/ (take A)
    python3 tools/sounds_carpetbomb.py --mix cues.txt out.ogg
    python3 tools/sounds_carpetbomb.py --review review/variants2
"""
import os
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
SOUNDS = ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds"
# (the falls' lengths: carpet.rs's FALLS)
FALLS = [2.4, 2.7, 3.0]


def load(name: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", str(SOUNDS / f"{name}.ogg"), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)


def shade(x: np.ndarray, gain_db: list, hp: float = 0.0, lp: float = 0.0) -> np.ndarray:
    """Zero-phase EQ: (centre Hz, width Hz, gain dB) bumps, a gentle high-pass and low-pass."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.ones_like(f)
    for c, w, db in gain_db:
        g *= 10 ** (db / 20 * np.exp(-0.5 * ((f - c) / w) ** 2))
    if hp:
        g /= np.sqrt(1 + (hp / np.maximum(f, 1e-3)) ** 4)
    if lp:
        g /= np.sqrt(1 + (f / lp) ** 4)
    return np.stack([np.fft.irfft(np.fft.rfft(x[:, c]) * g, n) for c in range(2)], axis=1)


def room(x: np.ndarray, wet: float, length: float, seed: int) -> np.ndarray:
    """A short outdoor tail: decaying noise per ear, darkening as it goes, convolved in."""
    rng = np.random.default_rng(seed)
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros((len(x) + n, 2))
    for c in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / (0.18 * length))
        ir = np.convolve(ir, np.ones(9) / 9, mode="same") * (np.arange(n) > int(0.012 * SR))
        ir /= np.sqrt((ir ** 2).sum())
        m = len(x) + n
        out[:, c] = np.fft.irfft(np.fft.rfft(x[:, c], m) * np.fft.rfft(ir, m), m)
    dry = np.zeros_like(out)
    dry[: len(x)] = x
    return dry + wet * out


def write(name: str, x: np.ndarray, fade: float = 0.01) -> None:
    """At the source's own level (so they sit against the files they came from), the loudest instants limited."""
    x = x - x.mean(axis=0)
    a = np.abs(x)
    x = np.where(a > 0.9, np.sign(x) * (0.9 + 0.1 * np.tanh((a - 0.9) / 0.1)), x)
    nf = int(fade * SR)
    if nf:
        x[-nf:] *= np.linspace(1, 0, nf)[:, None]
    path = SOUNDS / "carpetbomb" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path) + ".wav", "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(path) + ".wav", "-c:a", "libvorbis", "-q:a", "7", str(path) + ".ogg"], check=True)
    os.remove(str(path) + ".wav")
    print(f"wrote carpetbomb/{name:11s} {len(x) / SR:5.2f}s  peak {20 * np.log10(np.abs(x).max() + 1e-9):5.1f} dB")


sys.path.insert(0, str(Path(__file__).resolve().parent))
import soundlib  # noqa: E402
from soundlib import band  # noqa: E402
import sounds_pk_blast as PB  # noqa: E402
import sounds_themes as T  # noqa: E402


def rng():
    return soundlib.rng


def unit(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def noise(n, lo, hi, order=2):
    return unit(band(rng().standard_normal(n), lo, hi, order))


def chop(n, r0, r1, u, depth):
    """An irregular flutter whose movement quickens from r0 to r1 (Hz bands) as `u` goes 0 to 1: the air torn, never a
    steady beat. Unit RMS, `depth` (0-1, over time) how deep it cuts."""
    a = PB.slow_random(n, r0[0], r0[1])
    b = PB.slow_random(n, r1[0], r1[1])
    c = a * (1 - u) + b * u
    g = np.clip(c * 0.9 + 0.35, 0, None) ** 1.6
    g /= np.sqrt(np.mean(g ** 2)) + 1e-9
    return 1 + (np.minimum(g, 2.6) - 1) * depth


def to_level(L, R, db, window=None):
    """Both ears scaled so the loudest 400 ms (or the RMS over `window` seconds) of their mid is at `db`."""
    m = (L + R) / 2
    if window:
        a, b = int(window[0] * SR), int(window[1] * SR)
        cur = np.sqrt(np.mean(m[a:b] ** 2)) + 1e-12
    else:
        cur = T.loudest(m) + 1e-12
    g = 10 ** (db / 20) / cur
    return L * g, R * g


def stereo(x):
    return np.stack(x, axis=1)


# ---- the bomber -----------------------------------------------------------------------------------------------------
def drone(seed=7101, d=7.0):
    """A bomber high and far off: its engines a breathy low drone (noise rung at a few of their harmonics, never a pure
    tone, two engines a hair apart so they beat), all through a lot of air, swelling in and dying away."""
    with PB.seeded(seed):
        n = int(d * SR)
        t = np.arange(n) / SR
        f = np.fft.rfftfreq(n, 1 / SR)
        out = []
        common = rng().standard_normal(n)
        for ch in range(2):
            z = np.fft.rfft(0.85 * common + 0.53 * rng().standard_normal(n))
            g = np.zeros_like(f)
            for f0 in (88.0, 90.5):                      # (two engines, beating about 2.5 times a second)
                for h, a in ((1, 1.0), (2, 0.8), (3, 0.55), (4, 0.4), (6, 0.25), (8, 0.15)):
                    g += a * np.exp(-0.5 * ((f - f0 * h) / (2.2 * h)) ** 2)
            g += 0.05 / (1 + (f / 400) ** 2)             # (the air rushing past the airframe, far off)
            g /= 1 + (f / 700.0) ** 4                    # (and kilometres of air taking its top)
            x = np.fft.irfft(z * g, n)
            out.append(unit(x))
        sw = np.exp((2.5 * PB.slow_random(n, 0.1, 0.6)) / 8.686)
        env = np.clip(t / 1.8, 0, 1) ** 1.5 * np.clip((d - t) / 2.6, 0, 1) ** 1.2 * sw
        L, R = out[0] * env, out[1] * env
        return to_level(L, R, -24.0)


def glide(n, fc, width):
    """Noise rung in a narrow band (`width` octaves) round a centre that moves (`fc`, Hz, a value a sample): a breathy,
    noisy resonance sliding about, never a pure tone (payload.py's glide_band). Unit RMS."""
    size, hop = 2048, 512
    win = np.hanning(size)
    f = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    out = np.zeros(n + 2 * size)
    for start in range(-size, n, hop):
        c = fc[min(max(start + size // 2, 0), n - 1)]
        mag = np.exp(-0.5 * ((lf - np.log2(c)) / (width / 2.355)) ** 2)
        z = rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))
        a = start + size
        out[a:a + size] += np.fft.irfft(mag * z, size) * win
    return unit(out[size:size + n])


def fall_scream(k, length):
    """Take C: the falling bomb's scream, done as the real thing sounds: a shriek of air over its fins, noise rung in a
    narrow band that slides down as it comes (its Doppler shift falling away as it drops towards the listener), a
    fainter partial over it, airy rush round it, rising and cut dead on the blast."""
    with PB.seeded(7600 + 31 * k):
        n = int(length * SR)
        t = np.arange(n) / SR
        u = t / length
        sh = [0.94, 1.0, 1.07][k]
        fhi, flo = 2050.0 * sh, 760.0 * sh
        fc = fhi * (flo / fhi) ** (u ** 0.85)
        fc = fc * (1 + 0.006 * PB.slow_random(n, 3.0, 9.0) + 0.01 * PB.slow_random(n, 0.3, 1.5))
        tone = glide(n, fc, 0.16) + 0.25 * glide(n, fc * 2.02, 0.2)
        air = noise(n, 1300 * sh, 7000) * np.exp(2.0 * PB.slow_random(n, 2.0, 12.0) / 8.686)
        body = noise(n, 250, 1200) * (0.2 + 0.8 * u)
        lvl = 10 ** ((-34.0 + 34.0 * u ** 1.5) / 20)
        am = np.exp((1.8 * PB.slow_random(n, 0.5, 3.0) + 0.8 * PB.slow_random(n, 6.0, 18.0)) / 8.686)
        m = (tone * 0.9 * am + air * 0.32 + body * 0.25) * lvl
        side = glide(n, fc * 1.004, 0.2) * 0.12 * lvl * (0.3 + 0.7 * u)
        L, R = m + side, m - side
        e = int(0.004 * SR)
        L[-e:] *= np.linspace(1, 0, e)
        R[-e:] *= np.linspace(1, 0, e)
        L, R = to_level(L, R, -16.0, window=(length - 0.4, length))
        return PB.soft_clip(L, 0.9, 0.6), PB.soft_clip(R, 0.9, 0.6)


def fall_roar(k, length):
    """Take D: a heavier rush, as the Payload's approved dive has it: a low, growing roar (noise with a few low
    resonances wandering in it, its colour wavering), torn air over it, the push of air low down in its last half
    second; per bomb, rising and cut dead on its blast."""
    with PB.seeded(7700 + 31 * k):
        n = int(length * SR)
        t = np.arange(n) / SR
        u = t / length
        sh = [0.92, 1.0, 1.08][k]
        f = np.fft.rfftfreq(n, 1 / SR)
        g = 1 / np.sqrt(1 + (60.0 / np.maximum(f, 1)) ** 4) / np.sqrt(1 + (f / (700.0 * sh)) ** 3)
        for f0, w, db in ((115 * sh, 12, 8.0), (142 * sh, 14, 6.0), (262 * sh, 30, 6.0)):
            g = g * 10 ** (db / 20 * np.exp(-0.5 * ((f - f0) / w) ** 2))
        roar = []
        for c in range(2):
            roar.append(unit(np.fft.irfft(np.fft.rfft(rng().standard_normal(n)) * g, n)))
        bright = noise(n, 700 * sh, 2600 * sh) * (0.15 + 0.85 * u)
        tear = noise(n, 1500 * sh, 5500) * chop(n, (10, 24), (24, 55), u, 0.25 + 0.35 * u * u)
        push = noise(n, 50, 220, 3) * np.clip((u - 0.75) / 0.25, 0, 1) ** 2
        wav = np.exp((2.2 * PB.slow_random(n, 0.4, 2.5) + 0.8 * PB.slow_random(n, 5.0, 14.0)) / 8.686)
        lvl = 10 ** ((-30.0 + 30.0 * u ** 1.6) / 20)
        c0 = 0.85
        L = ((roar[0]) * wav + bright * 0.45 + tear * 0.35 + push * 1.3) * lvl
        R = ((c0 * roar[0] + np.sqrt(1 - c0 ** 2) * roar[1]) * wav + bright * 0.45 + tear * 0.35 + push * 1.3) * lvl
        e = int(0.004 * SR)
        L[-e:] *= np.linspace(1, 0, e)
        R[-e:] *= np.linspace(1, 0, e)
        L, R = to_level(L, R, -16.0, window=(length - 0.4, length))
        return PB.soft_clip(L, 0.9, 0.6), PB.soft_clip(R, 0.9, 0.6)


# ---- the fall -------------------------------------------------------------------------------------------------------
def fall(take, k, length):
    """A bomb coming down, `length` seconds to its blast: torn air rising to a dead stop (see the top)."""
    with PB.seeded(7200 + 31 * k + (1000 if take == "B" else 0)):
        n = int(length * SR)
        t = np.arange(n) / SR
        u = t / length
        near = u ** 2
        sh = [0.92, 1.0, 1.09][k]
        lvl = 10 ** ((-30.0 + 28.0 * u ** 1.7) / 20)
        if take == "A":
            tear_lo, tear_hi, body_lo, body_hi = 1600 * sh, 6500 * sh, 280 * sh, 1700 * sh
            r0, r1, dep = (9, 26), (30, 75), 0.35 + 0.6 * near
        elif take == "E":
            # (round 2's flutter reworked: much less of it, more rush, lower, so it has weight)
            tear_lo, tear_hi, body_lo, body_hi = 900 * sh, 3800 * sh, 130 * sh, 1000 * sh
            r0, r1, dep = (6, 14), (14, 30), 0.12 + 0.2 * near
        else:
            tear_lo, tear_hi, body_lo, body_hi = 900 * sh, 4200 * sh, 160 * sh, 1100 * sh
            r0, r1, dep = (14, 34), (40, 95), 0.55 + 0.45 * near
        Ls, Rs = [], []
        tear_c = noise(n, tear_lo, tear_hi)
        dark = noise(n, body_lo, body_hi * 0.55)
        bright = noise(n, body_hi * 0.55, body_hi * 1.6)
        push = noise(n, 70, 320, 3)
        for ch in range(2):
            c = 0.92 - 0.3 * near
            own = noise(n, tear_lo, tear_hi)
            tear = (c * tear_c + np.sqrt(1 - c ** 2) * own) * chop(n, r0, r1, u, dep)
            # (the rush opening up brighter as it closes; swelling unevenly)
            sw = np.exp(2.6 * PB.slow_random(n, 0.5, 2.5) / 8.686)
            body = (dark * (1 - 0.6 * u) + bright * (0.25 + 0.75 * u)) * sw
            if take == "B":
                body = body * chop(n, (6, 14), (18, 40), u, 0.25 + 0.4 * near)
            # (the air the bomb shoves ahead of it, low, in its last half second)
            low = push * np.clip((u - 0.78) / 0.22, 0, 1) ** 2.5 * (1.6 if take == "B" else 1.1)
            if take == "E":
                roar = noise(n, 55, 260, 3) * (0.25 + 0.75 * u) * np.exp(2.0 * PB.slow_random(n, 0.5, 3.0) / 8.686)
                x = (tear * 0.4 + body * 1.0 + low * 1.5 + roar * 0.8) * lvl
            else:
                x = (tear * 0.75 + body * (0.55 if take == "A" else 0.8) + low) * lvl
            (Ls if ch == 0 else Rs).append(x)
        L, R = Ls[0], Rs[0]
        # (dead on the blast: the last 4 ms let go)
        m = int(0.004 * SR)
        L[-m:] *= np.linspace(1, 0, m)
        R[-m:] *= np.linspace(1, 0, m)
        L, R = to_level(L, R, -16.0, window=(length - 0.4, length))
        return PB.soft_clip(L, 0.9, 0.6), PB.soft_clip(R, 0.9, 0.6)


# ---- the blasts -----------------------------------------------------------------------------------------------------
THIRDS = [40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150]


def blow(n, u, tp, f0, rise, fall, sweep=0.22, body=0.5):
    """A low blow (payload.py's alt blast's): a swept sine swelling over `rise` and gone over `fall`, with a noise body."""
    uu = u - tp
    env = np.where(uu < 0, np.exp(-0.5 * (uu / rise) ** 2), np.exp(-uu / fall))
    ph = 2 * np.pi * np.cumsum(f0 * (1 + sweep * np.exp(-np.maximum(uu, 0) / 0.05))) / SR
    return (np.sin(ph + rng().uniform(0, 6.28)) + noise(n, 36, 150, 3) * body) * env


def harmonics(M, on_from, db):
    """The lows' own 2nd and 3rd harmonics (80-260 Hz), so the weight carries on a phone's speaker too."""
    lo = band(M, 30, 120, 3)
    a = np.sqrt(np.mean(lo ** 2)) * 2.5 + 1e-12
    v = lo / a
    sat = (np.tanh(v) - v) + 0.8 * v * v / (1 + 0.4 * v * v)
    new = band(band(sat, 80, None, 3), None, 260, 4)
    have = np.sqrt(np.mean(band(M, 90, 260, 2) ** 2)) + 1e-12
    got = np.sqrt(np.mean(new ** 2)) + 1e-12
    return new * have / got * 10 ** (db / 20) * on_from


def blast(take, k, far):
    """A medium bomb going off (see the top), as heard close (a hundred or two blocks) or from the far end of the line."""
    heavy = take == "B"
    with PB.seeded(7400 + 17 * k + (1000 if heavy else 0) + (500 if far else 0)):
        d = 4.2 if far else 3.2
        t0 = 0.02
        n = int(d * SR)
        t = np.arange(n) / SR
        u = np.maximum(t - t0, 0)
        on = (t >= t0).astype(float)
        var = [1.0, 0.93, 1.07][k % 3]
        # ---- the crack: broadband and hard, its mids first, its top a hair after; a smaller second one for take B
        crack = [np.zeros(n), np.zeros(n)]
        cracks = [(0.0, 1.0)] + ([(0.085 * var, 0.45)] if heavy else [])
        for tc, a in cracks:
            for c in range(2):
                uu = u - tc
                env = np.where(uu < 0, 0.0, (1 - np.exp(-uu / 0.0012)) * np.exp(-uu / (0.014 * var))) * on
                top = np.where(uu < 0.003, 0.0, np.exp(-(uu - 0.003) / 0.009)) * on
                crack[c] += (noise(n, 350, 4000) * env + noise(n, 3500, 16000) * top * 0.45) * a
        # ---- the pressure wave's push: a swing and a half of ~28 Hz, then the deep thump, then a punch on its back
        T_ = 0.05 / var
        nw = np.where((u > 0) & (u < 1.5 * T_), np.sin(2 * np.pi * u / T_) * np.exp(-u / (0.6 * T_)), 0.0)
        f0 = (46.0 if heavy else 54.0) * var
        thump = blow(n, u, 0.018, f0, 0.012, (0.11 if heavy else 0.07) * var, body=0.6)
        if heavy:
            thump += 0.6 * blow(n, u, 0.11 * var, f0 * 0.88, 0.015, 0.09, body=0.5)
        punch = noise(n, 80, 220, 3) * np.exp(-0.5 * ((u - 0.03) / 0.009) ** 2) * on
        # ---- the low body: third-octave bands of noise, each dying at its own rate, their gains chaotic
        body = [np.zeros(n), np.zeros(n)]
        for fc in THIRDS:
            tau = (0.55 if heavy else 0.38) * var * (fc / 80.0) ** -0.45 * np.exp(0.25 * rng().standard_normal())
            lvl = 10 ** ((-6.0 * np.log2(max(fc, 50) / 50.0) / 1.0 * 0.5 + 3.0 * rng().standard_normal()) / 20)
            chaos = np.exp(4.0 * PB.slow_random(n, 1.0, 9.0) / 8.686)
            rise = np.clip(u / 0.02, 0, 1) ** 2
            env = rise * np.exp(-u / tau) * chaos * lvl * on
            common = noise(n, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3)
            for c in range(2):
                corr = 0.95 if fc < 200 else 0.7
                body[c] += (corr * common + np.sqrt(1 - corr ** 2) * noise(n, fc / 2 ** (1 / 6), fc * 2 ** (1 / 6), 3)) * env
        # (the air shuddering after it: the body's level fluttering, fading)
        shud = 1 + (0.45 if heavy else 0.35) * PB.slow_random(n, 6.0, 15.0) * np.exp(-u / 0.9) * np.clip((u - 0.05) / 0.1, 0, 1)
        body = [b * shud for b in body]
        # ---- earth settling after (dull, no stone patter): debris_settle, quiet
        earth = T.debris_settle(d, t0 + 0.35, amount=(0.9 if heavy else 0.6), spread=2.6) if hasattr(T, "debris_settle") else np.zeros(n)
        earth = band(earth, 60, 1400, 2)
        # ---- levels: the thump the loudest thing in it, the crack bright over the body's mids for a moment
        th = unit(thump) * 1.0
        nwv = unit(nw) * 0.55
        bod = [unit(b) * 0.55 for b in body]
        crk = [unit(c) * (0.9 if not far else 0.5) for c in crack]
        L = th + nwv + 0.35 * unit(punch) + bod[0] + crk[0]
        R = th + nwv + 0.35 * unit(punch) + bod[1] + crk[1]
        e = unit(earth) * 0.06 if np.any(earth) else 0.0
        L = L + e
        R = R + e
        M = (L + R) / 2
        hm = harmonics(M, np.clip((u - 0.01) / 0.02, 0, 1), -2.0)
        L, R = L + hm, R + hm
        # ---- through the air, off the land
        if far:
            L, R = band(L, None, 1300, 2), band(R, None, 1300, 2)
            x = stereo([L, R])
            for dt, g in ((0.38 * var, 0.42), (0.74 * var, 0.3), (1.2 * var, 0.2)):
                ech = band(np.convolve((L + R) / 2, np.exp(-np.arange(int(0.06 * SR)) / (0.02 * SR)) / (0.02 * SR), "same"), None, 700, 2)
                k0 = int(dt * SR)
                pan = rng().uniform(-0.5, 0.5)
                x[k0:, 0] += ech[: n - k0] * g * (1 - pan)
                x[k0:, 1] += ech[: n - k0] * g * (1 + pan)
            x = room(x, 0.5, 2.2, 31 + k)
        else:
            x = stereo([L, R])
            ech = band(np.roll((L + R) / 2, int(0.16 * var * SR)), None, 2200, 2)
            ech[: int(0.16 * var * SR)] = 0
            x[:, 0] += ech * 0.22
            x[:, 1] += ech * 0.18
            x = room(x, 0.22, 1.2, 21 + k)
        x = x[:n]
        x[:, 0], x[:, 1] = PB.causal_lowcut(x[:, 0], 26.0), PB.causal_lowcut(x[:, 1], 26.0)
        # (the first instant driven into a soft clip, as a microphone overloaded by a blast: dense and punchy)
        lv = T.loudest(x.mean(axis=1))
        free = 1 + 1e3 * np.clip((u - 0.4) / 0.1, 0, 1) ** 2
        c = lv * 10 ** (8.0 / 20) * free
        x[:, 0] = PB.soft_clip(x[:, 0], c, 0.5)
        x[:, 1] = PB.soft_clip(x[:, 1], c, 0.5)
        L, R = to_level(x[:, 0], x[:, 1], -11.0 if far else -9.0)
        m = int(0.3 * SR)
        fade = np.linspace(1, 0, m) ** 2
        L[-m:] *= fade
        R[-m:] *= fade
        return L, R


def falls(take):
    """The three falls of a take: A, B, E the torn-air ones, C the scream, D the roar."""
    make_one = {"C": fall_scream, "D": fall_roar}.get(take, lambda k, ln: fall(take, k, ln))
    return {f"fall{k + 1}": make_one(k, ln) for k, ln in enumerate(FALLS)}


# The fall the mod plays (the others are review takes).
FALL_TAKE = "C"


def make(take="A", outdir=None):
    """Every file of a take, written to the mod's sounds (take A, its falls FALL_TAKE's) or to `outdir`."""
    out = {}
    out.update(falls(FALL_TAKE if outdir is None else take))
    for k in range(3):
        out[f"blast{k + 1}"] = blast(take, k, False)
    for k in range(2):
        out[f"blast_far{k + 1}"] = blast(take, k, True)
    out["drone"] = drone()
    if outdir is None:
        for name, (L, R) in out.items():
            write(name, stereo([L, R]), fade=0.0)
    return out


def mix(cues: str, out: str) -> None:
    """The cues (`t event volume pitch` a line) mixed into one stereo file, each at its volume and pitch (pitch plays
    it faster and higher, as the game does)."""
    lines = [l.split() for l in Path(cues).read_text().splitlines() if l.strip()]
    end = max(float(t) for t, *_ in lines) + 25.0
    acc = np.zeros((int(end * SR), 2))
    cache = {}
    for t, event, vol, pitch in lines:
        file = event.removeprefix("orbital:").replace(".", "/", 1)
        if file not in cache:
            cache[file] = load(file)
        x = cache[file]
        p = float(pitch)
        if abs(p - 1.0) > 1e-3:
            pos = np.arange(0, len(x) - 1, p)
            i = pos.astype(int)
            fr = (pos - i)[:, None]
            x = x[i] * (1 - fr) + x[i + 1] * fr
        i0 = int(float(t) * SR)
        n = min(len(x), len(acc) - i0)
        acc[i0:i0 + n] += x[:n] * float(vol)
    peak = np.abs(acc).max()
    print(f"mix peak {20 * np.log10(peak + 1e-9):.1f} dB (limited, then down to -1 dB)")
    a = np.abs(acc)
    acc = np.where(a > 0.8, np.sign(acc) * (0.8 + 0.2 * np.tanh((a - 0.8) / 0.2)), acc)
    acc *= 0.89 / (np.abs(acc).max() + 1e-9)
    tmp = out + ".wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(acc, -1, 1) * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "7", out], check=True)
    os.remove(tmp)
    print("wrote", out)


def review(outdir: str) -> None:
    """The review's takes, each at -16 LUFS: the fall as a stick of three from 300 blocks with the take A blast under
    it (fall_A, fall_B), and the blasts as four walking in from 600, 450, 300 and 200 blocks (blast_A, blast_B)."""
    os.makedirs(outdir, exist_ok=True)
    takes = {tk: make(tk, outdir) for tk in ("A", "B")}
    ground = load("payload/ground_alt")

    def put(acc, t, LR, vol):
        x = stereo(list(LR)) if isinstance(LR, tuple) else LR
        i0 = int(round(t * SR))
        j0 = max(0, -i0)
        i0 = max(i0, 0)
        m = min(len(x) - j0, len(acc) - i0)
        if m > 0:
            acc[i0:i0 + m] += x[j0:j0 + m] * vol

    def bomb(acc, tk, k, t, d, vol):
        """A bomb striking at `t`, `d` blocks off: the ground's thump first, its blast (near and far crossfaded) after."""
        fs = float(np.clip((d - 220) / 260, 0, 1))
        fs = fs * fs * (3 - 2 * fs)
        put(acc, t + d / 1715.0 - 0.02, ground, 0.3 * vol)
        put(acc, t + d / 343.0 - 0.02, takes[tk][f"blast{k % 3 + 1}"], vol * (1 - fs))
        put(acc, t + d / 343.0 - 0.02, takes[tk][f"blast_far{k % 2 + 1}"], vol * fs)

    near = lambda d: 0.3 + 0.6 * min(200.0 / d, 1.0) ** 1.3
    for tk in ("A", "B"):
        # the fall: a stick of three from 300 blocks, the drone under the start, blast A under it
        t0 = 3.4
        acc = np.zeros((int((t0 + 7.0) * SR), 2))
        put(acc, 0.0, takes[tk]["drone"], 0.8)
        for k, (d, dt) in enumerate([(300.0, 0.0), (274.0, 0.9), (248.0, 1.8)]):
            ln = FALLS[k]
            put(acc, t0 + dt - ln, takes[tk][f"fall{k + 1}"], 0.45 + 0.1 * k)
            bomb(acc, "A", k, t0 + dt, d, near(d))
        lufs_write(acc, f"{outdir}/fall_{tk}.ogg")
        # the blasts: four walking in, heard 0.9 s apart, then silence
        acc = np.zeros((int(12.0 * SR), 2))
        for k, d in enumerate([600.0, 450.0, 300.0, 200.0]):
            heard = 2.0 + 0.9 * k
            bomb(acc, tk, k, heard - d / 343.0, d, near(d))
        acc[-SR:] *= np.linspace(1, 0, SR)[:, None] ** 2
        lufs_write(acc, f"{outdir}/blast_{tk}.ogg")


def review3(outdir: str) -> None:
    """Round 3's falls (C the scream, D the roar, E the flutter reworked), each as a stick of three from 300 blocks with
    the A blast under it, at -16 LUFS."""
    os.makedirs(outdir, exist_ok=True)
    blasts = make("A", outdir)
    ground = load("payload/ground_alt")

    def put(acc, t, LR, vol):
        x = stereo(list(LR)) if isinstance(LR, tuple) else LR
        i0 = int(round(t * SR))
        j0 = max(0, -i0)
        i0 = max(i0, 0)
        m = min(len(x) - j0, len(acc) - i0)
        if m > 0:
            acc[i0:i0 + m] += x[j0:j0 + m] * vol

    near = lambda d: 0.3 + 0.6 * min(200.0 / d, 1.0) ** 1.3
    for tk in ("C", "D", "E"):
        fl = falls(tk)
        t0 = 3.4
        acc = np.zeros((int((t0 + 7.0) * SR), 2))
        put(acc, 0.0, blasts["drone"], 0.8)
        for k, (d, dt) in enumerate([(300.0, 0.0), (274.0, 0.9), (248.0, 1.8)]):
            put(acc, t0 + dt - FALLS[k], fl[f"fall{k + 1}"], 0.45 + 0.1 * k)
            fs = float(np.clip((d - 220) / 260, 0, 1))
            fs = fs * fs * (3 - 2 * fs)
            put(acc, t0 + dt + d / 1715.0 - 0.02, ground, 0.3 * near(d))
            put(acc, t0 + dt + d / 343.0 - 0.02, blasts[f"blast{k % 3 + 1}"], near(d) * (1 - fs))
            put(acc, t0 + dt + d / 343.0 - 0.02, blasts[f"blast_far{k % 2 + 1}"], near(d) * fs)
        lufs_write(acc, f"{outdir}/fall_{tk}.ogg")


def lufs_write(acc: np.ndarray, out: str, target: float = -16.0) -> None:
    """Loudness matched (integrated, EBU R128) to `target`, the loudest instants limited under -1 dBFS."""
    tmp = out + ".wav"

    def wav(x):
        with wave.open(tmp, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())

    def loud(x):
        wav(x)
        r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", tmp, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
        return float([l for l in r.splitlines() if l.strip().startswith("I:")][-1].split()[1])

    x = acc / (np.abs(acc).max() + 1e-9) * 0.5
    for _ in range(3):
        x = x * 10 ** ((target - loud(x)) / 20)
        a = np.abs(x)
        x = np.where(a > 0.8, np.sign(x) * (0.8 + 0.09 * np.tanh((a - 0.8) / 0.09)), x)
    wav(x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "7", out], check=True)
    print(f"wrote {out}  {loud(x):.1f} LUFS  peak {20 * np.log10(np.abs(x).max()):.1f} dBFS  {len(x) / SR:.1f} s")
    os.remove(tmp)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--mix":
        mix(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "--review":
        review(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "--review3":
        review3(sys.argv[2])
    elif len(sys.argv) == 2 and sys.argv[1] == "--falls":
        # (only the falls rewritten: the blasts' files left as they are)
        for name, (L, R) in falls(FALL_TAKE).items():
            write(name, stereo([L, R]), fade=0.0)
    else:
        make("A")
