"""Shared helpers for the sound generators: noise, filters, reverb, shaped tones and the .ogg writer."""
import os, subprocess, wave
from pathlib import Path
import numpy as np

SR = 44100
rng = np.random.default_rng(20261021)
OUT = str(Path(__file__).resolve().parent.parent / "orbital-sounds")


def init(out):
    global OUT
    OUT = str(out)
    os.makedirs(OUT + "/assets/orbital/sounds", exist_ok=True)



def tt(d):
    return np.arange(int(SR * d)) / SR


def white(d):
    return rng.standard_normal(int(SR * d))


def band(x, lo=None, hi=None, order=2):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g = g / (1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi:
        g = g / (1 + (f / hi) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def smooth_noise(d, rate, n=None):
    """slowly varying random curve in [-1,1], `rate` new values per second"""
    n = n or int(SR * d)
    pts = rng.uniform(-1, 1, int(d * rate) + 3)
    xs = np.linspace(0, len(pts) - 1, n)
    i = np.floor(xs).astype(int)
    f = xs - i
    f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[np.minimum(i + 1, len(pts) - 1)] * f


def exp_env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


def make_ir(length=3.5, tau_lo=1.8, tau_mid=0.9, tau_hi=0.35):
    n = int(SR * length)
    t = np.arange(n) / SR
    base = rng.standard_normal(n)
    ir = (band(base, None, 400) * np.exp(-t / tau_lo) * 1.0
          + band(base, 400, 2500) * np.exp(-t / tau_mid) * 0.7
          + band(base, 2500, 9000) * np.exp(-t / tau_hi) * 0.4)
    ir[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x, wet=0.4, **kw):
    ir = make_ir(**kw)
    n = len(x) + len(ir)
    y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    y = y[: len(x) + int(len(ir) * 0.6)]
    out = np.zeros(len(y))
    out[: len(x)] += x
    return out * (1 - wet * 0.5) + y * wet * 3.0


def soft(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def thump(n, t0, f0=70, f1=24, decay=0.25, rate=9):
    t = np.arange(n) / SR - t0
    m = t >= 0
    f = f1 + (f0 - f1) * np.exp(-np.maximum(t, 0) * rate)
    ph = 2 * np.pi * np.cumsum(f * m) / SR
    return np.sin(ph) * np.exp(-np.maximum(t, 0) / decay) * m


def click(n, t0, amp=1.0, lo=1500, hi=9000, decay=0.006):
    t = np.arange(n) / SR - t0
    m = t >= 0
    seg = rng.standard_normal(n)
    seg = band(seg, lo, hi)
    return seg * np.exp(-np.maximum(t, 0) / decay) * m * amp


def ring(n, t0, freqs, decay=0.3, amp=0.2):
    t = np.arange(n) / SR - t0
    m = t >= 0
    out = np.zeros(n)
    for k, f in enumerate(freqs):
        out += np.sin(2 * np.pi * f * t * m + k) * np.exp(-np.maximum(t, 0) / (decay / (1 + 0.4 * k))) * m
    return out * amp


def finish(name, x, tail_fade=0.05):
    x = x - np.mean(x)
    x = soft(x / (np.percentile(np.abs(x), 99.5) + 1e-9) * 0.8, 1.15)
    nf = int(tail_fade * SR)
    x[-nf:] *= np.linspace(1, 0, nf)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.97
    path = f"{OUT}/assets/orbital/sounds/{name}"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path + ".wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-c:a", "libvorbis", "-q:a", "7", path + ".ogg"], check=True)
    os.remove(path + ".wav")
    print(f"wrote {name:9s} {len(x) / SR:5.2f}s  rms {np.sqrt(np.mean(x ** 2)):.3f}")


