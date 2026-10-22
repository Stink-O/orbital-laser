"""The Godly sound set (Plasma's lives in sounds_plasma.py): lockon, charge, fire, beam, rumble, accent, shutdown
(the Plasma set's `collapse` is shared). Files go to sounds/godly/<name>.ogg, events are `godly.<name>`."""
from soundlib import *

THEMES = ("godly",)
NAMES = ["lockon", "charge", "fire", "beam", "rumble", "accent", "shutdown"]

D_MAJOR = {"D1": 36.71, "D2": 73.42, "A2": 110.0, "D3": 146.83, "A3": 220.0, "D4": 293.66, "F4#": 369.99, "A4": 440.0, "D5": 587.33}
PENTA = [293.66, 329.63, 369.99, 440.0, 493.88]          # D major pentatonic from D4


def saw_add(f, t, nh=24, vib=None, vib_rate=5.2, vib_depth=0.006, detune=1.0):
    """Band-limited sawtooth by additive synthesis, with optional vibrato."""
    v = 1.0 + (vib_depth * np.sin(2 * np.pi * vib_rate * t + (vib or 0.0)) if vib is not None else 0.0)
    ph = 2 * np.pi * np.cumsum(f * detune * v) / SR
    out = np.zeros_like(t)
    fmax = float(np.max(f))
    for h in range(1, nh + 1):
        if fmax * h < 12000:
            out += np.sin(h * ph) / h
    return out


def formant_ah(x):
    return band(x, 650, 1000) * 1.0 + band(x, 1000, 1400) * 0.6 + band(x, 2500, 3300) * 0.25


def formant_oh(x):
    return band(x, 380, 560) * 1.0 + band(x, 700, 950) * 0.5 + band(x, 2300, 2900) * 0.1


def bell(n, t0, f0, amp=1.0, decay=1.6):
    t = np.arange(n) / SR - t0
    m = t >= 0
    out = np.zeros(n)
    for r, dm, a in ((1.0, 1.0, 1.0), (2.76, 0.62, 0.55), (5.4, 0.38, 0.32), (8.93, 0.22, 0.2), (13.3, 0.12, 0.12)):
        out += np.sin(2 * np.pi * f0 * r * np.maximum(t, 0)) * np.exp(-np.maximum(t, 0) / (decay * dm)) * a * m
    return out * amp


def pluck(n, t0, f, decay=0.9, amp=1.0):
    t = np.arange(n) / SR - t0
    m = t >= 0
    tp = np.maximum(t, 0)
    out = (np.sin(2 * np.pi * f * tp) + 0.45 * np.sin(2 * np.pi * 2 * f * tp) * np.exp(-tp * 3) + 0.2 * np.sin(2 * np.pi * 3 * f * tp) * np.exp(-tp * 5))
    return out * np.exp(-tp / decay) * np.minimum(tp / 0.004, 1.0) * m * amp


def lane(d, lo, hi, rate, depth, amp):
    return band(white(d), lo, hi) * (1 + depth * smooth_noise(d, rate)) * amp


def crackles(n, d, count, t_lo, t_hi, amp_lo, amp_hi, decay_lo=0.003, decay_hi=0.02, f_lo=900, f_hi=6000, bias=1.0):
    out = np.zeros(n)
    for _ in range(count):
        ti = t_lo + (t_hi - t_lo) * rng.random() ** bias
        out += click(n, ti, rng.uniform(amp_lo, amp_hi), rng.uniform(f_lo * 0.5, f_lo), rng.uniform(f_hi * 0.6, f_hi), rng.uniform(decay_lo, decay_hi))
    return out


def echoes(x, n, taps):
    for delay, g, hi in taps:
        dn = int(delay * SR)
        e = np.zeros(n)
        e[dn:] = band(x, 25, hi)[: n - dn] * g
        x = x + e
    return x


# =====================================================================================  GODLY
def godly():
    th = "godly"
    # lock-on: a bright bell strike
    d = 2.0; n = int(SR * d)
    x = bell(n, 0.0, 880, 1.0, 1.6) + bell(n, 0.0, 1320, 0.4, 1.2) + band(white(d), 4000, 12000) * exp_env(n, 0.001, 0.04) * 0.4
    finish(f"{th}/lockon", reverb(x, 0.45, length=3.0, tau_lo=1.8, tau_mid=1.2, tau_hi=0.6))

    # charge: a choir swelling in note by note, bells scattering, air and a pedal tone rising
    d = 4.0; n = int(SR * d); t = tt(d); p = t / d
    x = np.zeros(n)
    for i, (name, fr) in enumerate((("D3", 146.83), ("A3", 220.0), ("D4", 293.66), ("F4#", 369.99), ("A4", 440.0), ("D5", 587.33))):
        entry = 0.05 + 0.12 * i
        env = np.clip((p - entry) / 0.5, 0, 1) ** 1.6
        x += saw_add(np.full(n, fr), t, 18, vib=i * 1.3) * env * 0.35
    x = formant_ah(x) * 3.0
    for _ in range(int(40 * 4)):
        ti = d * rng.random() ** 0.6
        x += bell(n, ti, float(rng.choice([1174.7, 1318.5, 1480.0, 1760.0, 1976.0])), rng.uniform(0.05, 0.22) * (ti / d + 0.2), 0.7)
    x += band(white(d), 3000, 10000) * p ** 3 * 0.35 + np.sin(2 * np.pi * 36.7 * t) * p ** 2 * 1.2
    finish(f"{th}/charge", reverb(x * np.minimum(t / 0.2, 1.0), 0.45, length=3.0, tau_lo=1.8, tau_mid=1.2, tau_hi=0.6))

    # fire: a blast of brass and choir on the chord, a cymbal crash, a sub boom and falling bells
    d = 6.5; n = int(SR * d); t = tt(d)
    brass = np.zeros(n)
    for fr in (73.42, 146.83, 220.0, 293.66, 369.99, 440.0):
        brass += saw_add(np.full(n, fr), t, 22, vib=fr, vib_depth=0.004) * 0.25
    brass = brass * np.minimum(t / 0.012, 1.0) * (np.exp(-t / 1.6) * 0.8 + 0.2 * np.exp(-t / 0.15))
    choir = np.zeros(n)
    for i, fr in enumerate((146.83, 220.0, 293.66, 369.99, 440.0, 587.33)):
        choir += saw_add(np.full(n, fr), t, 18, vib=i * 1.7) * 0.3
    choir = formant_ah(choir) * 3.4 * np.minimum(t / 0.05, 1.0) * np.exp(-t / 2.8)
    crash = band(white(d), 3000, 14000) * exp_env(n, 0.005, 1.6) * 1.0
    boom = thump(n, 0.0, 70, 30, 1.4, 3.0) * 1.7
    bells = sum(bell(n, 0.05 + 0.12 * i, 880 * r, 0.35, 2.2) for i, r in enumerate((1.0, 1.25, 1.5, 1.875, 2.0, 2.5)))
    x = brass * 1.3 + choir + crash + boom + bells
    finish(f"{th}/fire", reverb(soft(x, 1.2), 0.6, length=4.2, tau_lo=2.8, tau_mid=1.6, tau_hi=0.7), 0.3)

    # beam: a sustained choir and organ pad, sparkling bells
    d = 4.0; n = int(SR * d); t = tt(d)
    ch = np.zeros(n)
    for i, fr in enumerate((146.83, 220.0, 293.66, 369.99, 440.0, 587.33, 660.0)):
        ch += saw_add(np.full(n, fr), t, 18, vib=i * 1.1, vib_depth=0.007, detune=1.0 + 0.0015 * (i % 3 - 1)) * 0.3
    ch = formant_ah(ch) * 3.0 * (0.85 + 0.15 * np.sin(2 * np.pi * 0.4 * t))
    organ = sum(np.sin(2 * np.pi * 146.83 * h * t + h) * a for h, a in ((1, 1.0), (2, 0.6), (3, 0.4), (4, 0.3), (6, 0.15))) * 0.35
    sparkle = np.zeros(n)
    for _ in range(26):
        sparkle += bell(n, rng.uniform(0, d - 0.5), float(rng.choice([1174.7, 1318.5, 1480.0, 1760.0, 1976.0, 2349.3])), rng.uniform(0.12, 0.35), 1.2)
    x = (ch + organ + sparkle + band(white(d), 4000, 11000) * 0.06) * np.minimum(np.minimum(t / 0.35, (d - t) / 0.35), 1.0)
    finish(f"{th}/beam", reverb(x, 0.35, length=3.0, tau_lo=1.8, tau_mid=1.2, tau_hi=0.6), 0.01)

    # rumble: an organ pedal under a low choir
    d = 3.4; n = int(SR * d); t = tt(d)
    ped = (np.sin(2 * np.pi * 36.71 * t) + 0.7 * np.sin(2 * np.pi * 73.42 * t) + 0.3 * np.sin(2 * np.pi * 110.1 * t)) * (0.8 + 0.2 * np.sin(2 * np.pi * 3.2 * t))
    low = np.zeros(n)
    for i, fr in enumerate((73.42, 110.0, 146.83)):
        low += saw_add(np.full(n, fr), t, 14, vib=i * 2.0) * 0.4
    low = formant_oh(low) * 2.6
    x = (ped * 1.6 + low) * np.minimum(np.minimum(t / 0.6, (d - t) / 1.0), 1.0)
    finish(f"{th}/rumble", reverb(x, 0.4, length=3.0, tau_lo=1.8, tau_mid=1.0, tau_hi=0.4), 0.02)

    # accent: a harp glissando up the pentatonic and a bell to finish
    d = 2.4; n = int(SR * d)
    x = np.zeros(n)
    notes = [f * m for m in (1.0, 2.0, 4.0) for f in PENTA][:14]
    for i, fr in enumerate(notes):
        x += pluck(n, 0.06 * i, fr, 0.9, 0.5 + 0.03 * i)
    x += bell(n, 0.06 * len(notes) + 0.05, 1760.0, 0.7, 1.6)
    finish(f"{th}/accent", reverb(x, 0.45, length=3.0, tau_lo=1.8, tau_mid=1.2, tau_hi=0.6), 0.2)

    # shutdown: the choir fading under a descending harp and one last chime
    d = 3.4; n = int(SR * d); t = tt(d)
    ch = np.zeros(n)
    for i, fr in enumerate((146.83, 220.0, 293.66, 369.99, 440.0)):
        ch += saw_add(np.full(n, fr), t, 16, vib=i * 1.4) * 0.3
    ch = formant_ah(ch) * 3.0 * np.exp(-t / 1.1) * np.minimum(t / 0.05, 1.0)
    harp = np.zeros(n)
    for i, fr in enumerate(list(reversed([f * m for m in (2.0, 4.0) for f in PENTA]))[:10]):
        harp += pluck(n, 0.1 + 0.11 * i, fr, 0.7, 0.45)
    x = ch + harp + bell(n, 1.7, 1318.5, 0.6, 1.8)
    finish(f"{th}/shutdown", reverb(x, 0.5, length=3.4, tau_lo=2.0, tau_mid=1.3, tau_hi=0.6), 0.2)


BUILDERS = {"godly": godly}


def build_all(only=None):
    for th in THEMES:
        if only is None or th in only:
            BUILDERS[th]()
