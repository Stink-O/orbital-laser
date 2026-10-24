"""The Godly and Black hole sound sets (Plasma's lives in sounds_plasma.py): lockon, charge, fire, beam, rumble, accent,
shutdown (the Plasma set's `collapse` is shared). Files go to sounds/<theme>/<name>.ogg, events are `<theme>.<name>`."""
from soundlib import *

THEMES = ("godly", "blackhole")
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


# =====================================================================================  BLACK HOLE
def glide(f0, f1, t, d, curve=1.0):
    """A frequency curve from f0 to f1 over d seconds, exponential in pitch."""
    u = np.clip(t / d, 0, 1) ** curve
    return f0 * (f1 / f0) ** u


def sine_ph(f):
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def blackhole():
    th = "blackhole"
    # lock-on: a sub drop under a metallic ping that bends down as if pulled in
    d = 2.2; n = int(SR * d); t = tt(d)
    ping = sum(sine_ph(glide(f, f * 0.55, t, 1.4, 0.6)) * a for f, a in ((1244.5, 0.6), (1661.2, 0.35), (2489.0, 0.2))) * np.exp(-t / 0.5)
    x = thump(n, 0.0, 90, 26, 0.9, 4.0) * 1.4 + ping + band(white(d), 3000, 10000) * exp_env(n, 0.001, 0.03) * 0.3
    finish(f"{th}/lockon", reverb(x, 0.5, length=3.0, tau_lo=2.2, tau_mid=1.2, tau_hi=0.4), 0.2)

    # charge: an inhale. Noise sucked in harder and harder, a cluster of tones gliding down, a sub swelling, crackle
    # speeding up, and all of it cut dead just before the fire
    d = 4.0; n = int(SR * d); t = tt(d); p = t / d
    inhale = band(white(d), 200, 6000) * p ** 2.6 * (1 + 0.5 * smooth_noise(d, 6))
    inhale = band(inhale * (0.6 + 0.4 * np.sin(2 * np.pi * (2 + 14 * p ** 2) * t)), 120, 9000)
    tones = sum(sine_ph(glide(f, f * 0.25, t, d, 1.3)) * (0.25 + 0.75 * p) for f in (880.0, 1046.5, 1318.5, 1760.0)) * 0.18
    sub = np.sin(2 * np.pi * np.cumsum(glide(55, 28, t, d)) / SR) * p ** 2 * 1.4
    crackle = crackles(n, d, 160, 0.4, 3.85, 0.05, 0.35, bias=0.45)
    x = (inhale * 1.1 + tones + sub + crackle) * np.minimum(t / 0.1, 1.0) * np.clip((3.93 - t) / 0.04, 0, 1)
    finish(f"{th}/charge", reverb(x, 0.3, length=2.0, tau_lo=1.2, tau_mid=0.7, tau_hi=0.3), 0.01)

    # fire: a vast low brass blast tuned down, a sub boom, a crack of the air folding in, and long metallic groans after
    d = 7.0; n = int(SR * d); t = tt(d)
    brass = np.zeros(n)
    for i, fr in enumerate((36.71, 55.0, 73.42, 77.78, 110.0)):
        brass += saw_add(glide(fr * 1.04, fr * 0.94, t, 5.0), t, 30, vib=i * 0.7, vib_rate=3.1, vib_depth=0.008) * 0.32
    brass = band(soft(brass * 1.6, 2.0), 25, 2400) * np.minimum(t / 0.02, 1.0) * (0.25 + 0.75 * np.exp(-t / 2.4))
    crack = band(white(d), 600, 12000) * exp_env(n, 0.001, 0.09) * 1.4
    boom = thump(n, 0.0, 60, 20, 2.2, 2.0) * 2.2
    groan = sum(sine_ph(glide(f0, f0 * 0.4, t, 6.0)) * np.exp(-t / 2.2) * a for f0, a in ((311.1, 0.3), (466.2, 0.18), (622.3, 0.1)))
    groan = groan * (1 + 0.6 * smooth_noise(d, 9))
    x = brass * 1.4 + crack + boom + groan
    finish(f"{th}/fire", reverb(soft(x, 1.3), 0.6, length=4.5, tau_lo=3.0, tau_mid=1.5, tau_hi=0.5), 0.3)

    # beam: the hole's drone. A low chord with a slow phaser sweep, a throb, and a high whine swinging round and round
    d = 4.0; n = int(SR * d); t = tt(d)
    chord = sum(saw_add(np.full(n, fr), t, 26, vib=fr, vib_rate=0.7, vib_depth=0.004) * a for fr, a in ((36.71, 0.5), (55.0, 0.4), (73.42, 0.35), (82.41, 0.2)))
    ph = band(chord, 25, 300) + 0.5 * band(chord, 300, 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * t + 1.0))
    throb = 0.7 + 0.3 * np.sin(2 * np.pi * 2.4 * t)
    whine = sine_ph(1500 + 450 * np.sin(2 * np.pi * 0.9 * t)) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.9 * t + 1.57)) ** 2 * 0.08
    whine += sine_ph(2250 + 600 * np.sin(2 * np.pi * 0.9 * t + 2.1)) * 0.03
    hiss = band(white(d), 2000, 9000) * (0.06 + 0.04 * np.sin(2 * np.pi * 0.25 * t))
    x = (ph * throb + whine + hiss) * np.minimum(np.minimum(t / 0.3, (d - t) / 0.3), 1.0)
    finish(f"{th}/beam", reverb(x, 0.3, length=2.5, tau_lo=1.6, tau_mid=0.8, tau_hi=0.3), 0.01)

    # rumble: the ground giving way to it, very low
    d = 3.4; n = int(SR * d); t = tt(d)
    x = band(white(d), 18, 160) * (1 + 0.8 * smooth_noise(d, 5)) * 1.6 + np.sin(2 * np.pi * 29.1 * t) * (0.6 + 0.4 * smooth_noise(d, 2)) * 0.9
    x = x * np.minimum(np.minimum(t / 0.5, (d - t) / 0.9), 1.0)
    finish(f"{th}/rumble", reverb(x, 0.3, length=2.4, tau_lo=1.6, tau_mid=0.6, tau_hi=0.2), 0.02)

    # accent: something huge torn up and dragged past: a whoosh swinging by and a metal groan falling away
    d = 2.6; n = int(SR * d); t = tt(d)
    pas = np.exp(-((t - 0.9) / 0.35) ** 2)
    whoosh = band(white(d), 300, 7000) * pas * 0.8
    whoosh = whoosh + band(white(d), 80, 600) * pas * 0.7
    groan = sine_ph(glide(420, 70, t, 2.2, 0.8)) * np.exp(-t / 1.0) * (1 + 0.7 * smooth_noise(d, 14)) * 0.45
    groan += sine_ph(glide(630, 105, t, 2.2, 0.8)) * np.exp(-t / 0.8) * 0.2
    x = whoosh + groan + crackles(n, d, 40, 0.3, 1.6, 0.05, 0.3)
    finish(f"{th}/accent", reverb(x, 0.45, length=3.0, tau_lo=2.0, tau_mid=1.0, tau_hi=0.4), 0.2)

    # shutdown: it evaporates. A shimmer rushing up in pitch, a bright pop at 0.8 s, then a glittering tail
    d = 3.6; n = int(SR * d); t = tt(d)
    pre = t < 0.8
    rise = sum(sine_ph(glide(f, f * 6.0, t, 0.8, 2.0)) * a for f, a in ((220.0, 0.3), (330.0, 0.22), (440.0, 0.15))) * (t / 0.8) ** 2 * pre
    hiss = band(white(d), 1500, 11000) * (t / 0.8) ** 3 * pre * 0.5
    k0 = int(0.8 * SR)
    pop = np.zeros(n)
    pop[k0:] = band(rng.standard_normal(n - k0), 200, 14000) * exp_env(n - k0, 0.0005, 0.07) * 1.6 + thump(n - k0, 0.0, 120, 30, 0.7, 6.0) * 1.6
    glitter = np.zeros(n)
    for _ in range(60):
        glitter += bell(n, rng.uniform(0.82, 2.8), float(rng.choice([1760.0, 2093.0, 2637.0, 3136.0, 3520.0])), rng.uniform(0.04, 0.16), 0.6)
    x = rise + hiss + pop + glitter
    finish(f"{th}/shutdown", reverb(x, 0.5, length=3.4, tau_lo=2.2, tau_mid=1.3, tau_hi=0.6), 0.2)


BUILDERS = {"godly": godly, "blackhole": blackhole}


def build_all(only=None):
    for th in THEMES:
        if only is None or th in only:
            BUILDERS[th]()
