#!/usr/bin/env python3
"""The Carpet Bomb's sounds: no new synthesis, every one reshaped from a sound the owner approved (the taste guide's
Approved references), so they fit a stick of bombs dropped from a bomber rather than one object falling from orbit.

  whistle1..3   a bomb's fall: the Payload's fall (payload/dive, 342ea56) from its first breath to its dead cut, played
                faster and faster less so (a varispeed from about 1.5 to 1.1 times): shortened to 2.0-2.6 s, pitched up,
                its pitch sweeping down as it comes; the dive's air shaded towards a whistle round 900 Hz (before the
                varispeed, so the colour sweeps down with it) and its lowest roar thinned. It ends dead, on the blast
                (strike/carpet.rs starts it its length before the bomb strikes: keep WHISTLES there in step).
  crump1..3     a bomb's blast close by: the head of the Payload's alternative blast (payload/blast_alt, e1b0aae), its
                boom and first second, then let go fast (each a little shorter or longer), a short tail of its own room
                after: a punchy crump with air after it, so ten in a row keep their rhythm and never stack into mud.
  crump_far1..2 the same from the far end of the line: its far take (payload/blast_alt_far), duller still.

The last, biggest bomb plays the Payload's whole alternative blast with its rush and tail and the Nuke's under it (no
file here). `--mix CUES OUT` mixes a strike's cues (`t event volume pitch` a line: carpet.rs's cp_write_cues) into a
listening file.

    python3 tools/sounds_carpetbomb.py                     # writes orbital-sounds/assets/orbital/sounds/carpetbomb/
    python3 tools/sounds_carpetbomb.py --mix cues.txt out.ogg
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
# (the whistles' lengths and their speed at the start and at the cut: carpet.rs's WHISTLES)
WHISTLES = [(2.0, 1.55, 1.15), (2.3, 1.45, 1.1), (2.6, 1.35, 1.0)]
# (the crumps: how long the boom holds, how fast it goes after, the whole length)
CRUMPS = [(0.30, 0.15, 1.1), (0.36, 0.18, 1.25), (0.42, 0.21, 1.4)]


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


def varispeed(x: np.ndarray, start: float, length: float, r0: float, r1: float) -> np.ndarray:
    """`length` seconds read from `start` on at a speed going smoothly from r0 to r1 (pitch and pace together)."""
    n = int(length * SR)
    u = np.arange(n) / n
    rate = r0 + (r1 - r0) * (u * u * (3 - 2 * u))
    pos = start * SR + np.concatenate([[0.0], np.cumsum(rate[:-1])])
    i = np.clip(pos.astype(int), 0, len(x) - 2)
    fr = (pos - i)[:, None]
    return x[i] * (1 - fr) + x[i + 1] * fr


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


def whistles() -> None:
    dive = load("payload/dive")
    cut = 3.0  # the dive's dead cut, in its file (payload.rs's PL_DIVE_SND)
    # (shaded towards a whistle, its lowest roar thinned: a bomb's fins, not a fireball's roar)
    src = shade(dive, [(900, 110, 11.0), (1800, 220, 4.0)], hp=260)
    for k, (length, r0, r1) in enumerate(WHISTLES):
        n = int(length * SR)
        u = np.arange(n) / n
        span = (np.cumsum(r0 + (r1 - r0) * (u * u * (3 - 2 * u))) / SR)[-1]
        start = cut - span
        pad = 0
        if start < 0:
            pad, start = int(-start * SR), 0.0
        s = np.concatenate([np.zeros((pad, 2)), src])
        y = varispeed(s, start + pad / SR, length, r0, r1)
        # (coming in out of nothing, high up, the last half second loudest)
        y *= (np.minimum(u / 0.35, 1.0) ** 1.5)[:, None]
        write(f"whistle{k + 1}", y, fade=0.006)


def crumps() -> None:
    for far, name, takes in ((False, "payload/blast_alt", CRUMPS), (True, "payload/blast_alt_far", CRUMPS[:2])):
        x = load(name)
        for k, (hold, tau, length) in enumerate(takes):
            n = int(length * SR)
            t = np.arange(n) / SR
            env = np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))
            y = x[:n] * env[:, None]
            if far:
                y = shade(y, [], lp=900)
            y = room(y, 0.35 if far else 0.25, 1.2 if far else 0.9, 7 + k)
            m = len(y)
            y[m - int(0.3 * SR):] *= np.linspace(1, 0, int(0.3 * SR))[:, None] ** 2
            write(f"crump{'_far' if far else ''}{k + 1}", y, fade=0.0)


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


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--mix":
        mix(sys.argv[2], sys.argv[3])
    else:
        whistles()
        crumps()
