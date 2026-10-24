"""The Godly, Black hole and Meteor storm sound sets (Plasma's lives in sounds_plasma.py): lockon, charge, fire, beam,
rumble, accent, shutdown; the meteor storm has its own list (see OWN). The Plasma set's `collapse` is shared. Files go to
sounds/<theme>/<name>.ogg, events are `<theme>.<name>`."""
from soundlib import *

THEMES = ("godly", "blackhole", "meteor")
NAMES = ["lockon", "charge", "fire", "beam", "rumble", "accent", "shutdown"]
# The meteor storm's set is its own: one storm bed instead of a beam, and a whoosh and a hit for every meteor.
OWN = {"meteor": ["lockon", "charge", "fire", "storm", "rumble", "whoosh1", "whoosh2", "hit1", "hit2", "hit3",
                  "hit_far1", "hit_far2", "hit_far3", "approach", "impact", "shutdown"]}


def names(th):
    return OWN.get(th, NAMES)

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


# =====================================================================================  METEOR STORM
def glide_noise(d, f0, f1, width=0.6, curve=1.0, amp=None):
    """Noise in a band that glides from f0 to f1 Hz over d seconds (log-spaced, `width` octaves wide), built frame by
    frame and overlap-added, so it moves smoothly: wind, roars, whooshes."""
    n = int(SR * d)
    size, hop = 4096, 1024
    out = np.zeros(n + size)
    win = np.hanning(size)
    freqs = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(freqs, 1.0))
    for start in range(0, n, hop):
        u = min(start / max(n - 1, 1), 1.0) ** curve
        fc = f0 * (f1 / f0) ** u
        mag = np.exp(-0.5 * ((lf - np.log2(fc)) / (width / 2.355)) ** 2)
        spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, len(freqs)))
        frame = np.fft.irfft(spec, size) * win
        out[start:start + size] += frame
    out = out[:n]
    out /= np.sqrt(np.mean(out ** 2)) + 1e-9
    return out * (amp if amp is not None else 1.0)


def fade(n, a=0.01, r=0.01):
    """A raised-cosine fade in over `a` seconds and out over `r` seconds."""
    e = np.ones(n)
    na, nr = max(int(a * SR), 1), max(int(r * SR), 1)
    e[:na] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, na))
    e[-nr:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, nr))
    return e


def nwave(n, t0, width=0.004, amp=1.0, hi=6000):
    """A sonic boom's crack: a sharp rise, a slide down through zero, a sharp return (an N-wave), softened."""
    t = np.arange(n) / SR - t0
    w = np.where((t >= 0) & (t <= width), 1.0 - 2.0 * t / width, 0.0)
    return band(w * amp, 20, hi)


def sub_drop(n, t0, f0, f1, decay, rate=4.0, amp=1.0):
    return thump(n, t0, f0, f1, decay, rate) * amp


def pan(x, p):
    """Equal-power pan, p from -1 (left) to 1 (right)."""
    a = (p + 1) * np.pi / 4
    return x * np.cos(a), x * np.sin(a)


def lowpass_glide(x, f0, f1, curve=1.0):
    """`x` through a lowpass whose cutoff glides from f0 to f1 Hz across it (frame by frame, overlap-added)."""
    n = len(x)
    size, hop = 4096, 1024
    win = np.hanning(size)
    out = np.zeros(n + size)
    norm = np.zeros(n + size)
    xp = np.concatenate([x, np.zeros(size)])
    freqs = np.fft.rfftfreq(size, 1 / SR)
    for start in range(0, n, hop):
        u = min(start / max(n - 1, 1), 1.0) ** curve
        fc = f0 * (f1 / f0) ** u
        g = 1 / (1 + (freqs / fc) ** 4)
        out[start:start + size] += np.fft.irfft(np.fft.rfft(xp[start:start + size] * win) * g, size) * win
        norm[start:start + size] += win ** 2
    return out[:n] / np.maximum(norm[:n], 1e-3)


def punch(n, t0, f0=90, f1=45, decay=0.35, drive=4.0):
    """The weight of a blow on speakers that can't play sub-bass: a falling tone driven into distortion, so its
    harmonics (two, three, four times it) carry the thump up into the 80-400 Hz range."""
    x = sub_drop(n, t0, f0, f1, decay, 6.0, 1.0)
    return band(np.tanh(x * drive) / np.tanh(drive), 60, 600)


def boom(n, t0, f0=60, f1=22, decay=1.2, body=0.4, crack=0.6):
    """One explosion: a crack, a sub blow, the punch of it you can hear on any speaker, a crunch and a body of low
    noise."""
    t = np.arange(n) / SR - t0
    m = t >= 0
    x = sub_drop(n, t0, f0, f1, decay, 4.0, 1.0)
    x = np.tanh(x * 1.6) / np.tanh(1.6)
    x += punch(n, t0, f0 * 1.6, f1 * 2.0, decay * 0.4) * 0.8
    x += band(rng.standard_normal(n), 50, 400) * np.exp(-np.maximum(t, 0) / 0.18) * m * body
    x += band(rng.standard_normal(n), 400, 2500) * np.exp(-np.maximum(t, 0) / 0.05) * m * body * 0.6
    x += nwave(n, t0, 0.004, crack, 6000)
    return x


# ---- realistic-footage building blocks ---------------------------------------------------------------------------------
def crackle(d, rate=400.0, decay=0.002, lo=200, hi=6000, heavy=1.6):
    """The rough, impulsive crackle of a big blast or a fireball tearing through the air: sharp spikes at random,
    their sizes heavy-tailed (a few much bigger than the rest), not smooth hiss."""
    n = int(SR * d)
    x = np.zeros(n)
    k = rng.poisson(rate * d)
    at = rng.integers(0, n, k)
    amp = rng.pareto(heavy, k) * rng.choice([-1.0, 1.0], k)
    np.add.at(x, at, amp)
    kern = np.exp(-np.arange(int(decay * SR * 6)) / (decay * SR))
    x = np.convolve(x, kern)[:n]
    x = band(x, lo, hi)
    return x / (np.percentile(np.abs(x), 99.5) + 1e-9)


def flange(x, d0, d1, mix=0.8, curve=1.0):
    """Mix in a copy delayed by a time gliding from d0 to d1 seconds: the moving comb filter of something passing over
    the ground (its sound and its reflection off the ground arriving a changing moment apart)."""
    n = len(x)
    u = (np.arange(n) / max(n - 1, 1)) ** curve
    dl = (d0 + (d1 - d0) * u) * SR
    idx = np.arange(n) - dl
    i0 = np.clip(np.floor(idx).astype(int), 0, n - 1)
    fr = idx - np.floor(idx)
    y = x[i0] * (1 - fr) + x[np.clip(i0 + 1, 0, n - 1)] * fr
    y[idx < 0] = 0
    return x + mix * y


def overload(x, drive=3.0):
    """A microphone overloaded by a blast: driven into clipping, so its slam is hard and gritty."""
    return np.clip(x * drive, -1.0, 1.0) * 0.7 + np.tanh(x * drive) * 0.3


def echoes(x, taps, lo=40, hi=900):
    """Echoes back off the land: muffled, later, quieter copies. `taps` is [(delay s, gain, pan)], stereo out."""
    n = len(x) + int(max(t for t, _, _ in taps) * SR) + 1
    L = np.zeros(n); R = np.zeros(n)
    L[: len(x)] += x; R[: len(x)] += x
    dull = band(x, lo, hi)
    for t, g, pn in taps:
        k = int(t * SR)
        l, r = pan(dull * g, pn)
        L[k:k + len(x)] += l; R[k:k + len(x)] += r
    return L, R


def rock_clack(n, t0, size=1.0):
    """One rock landing: a hard clack and, for a big one, a thud under it."""
    a = click(n, t0, 0.5 * size, rng.uniform(800, 1600), rng.uniform(3500, 7000), rng.uniform(0.003, 0.012))
    if size > 0.6:
        a += thump(n, t0, rng.uniform(110, 180), 60, 0.06 * size, 14.0) * 0.6 * size
    return a


def debris_rain(d, t_lo, t_hi, count, peak=0.35, pan_spread=1.0):
    """Rock and dirt coming back down: clacks of all sizes and a gravel hiss, thickest early on, stereo."""
    n = int(SR * d)
    L = np.zeros(n); R = np.zeros(n)
    for _ in range(count):
        t0 = t_lo + (t_hi - t_lo) * rng.random() ** 1.6
        size = rng.pareto(2.5) * 0.4 + 0.1
        l, r = pan(rock_clack(n, t0, min(size, 1.5)) * peak, rng.uniform(-pan_spread, pan_spread))
        L += l; R += r
    t = np.arange(n) / SR
    env = np.clip((t - t_lo) / 0.4, 0, 1) * np.exp(-np.maximum(t - t_lo, 0) / ((t_hi - t_lo) * 0.35))
    for ch in (L, R):
        ch += band(white(d), 2000, 9000) * env * peak * 0.25
    return L, R


def friedlander(n, t0, T, b=1.6):
    """A blast's pressure at a microphone (the Friedlander waveform): an instant jump, a decay through zero at T
    seconds, then the suction of the negative phase after it. No pitch in it, unlike a synthesized 'boom'."""
    t = np.arange(n) / SR - t0
    u = np.maximum(t, 0) / T
    p = (1 - u) * np.exp(-b * u) * (t >= 0)
    rise = int(0.0003 * SR)
    k0 = int(max(t0, 0) * SR)
    p[k0:k0 + rise] *= np.linspace(0, 1, rise)[: len(p[k0:k0 + rise])]
    return p


def outdoor_ir(length, seed_shift=0, density=60.0, darken=(6000, 250), decay=1.6):
    """An outdoor reverb as recordings have it: not a smooth tail but clumps of echoes off hills, trees and ground,
    arriving irregularly, each later one duller and quieter."""
    n = int(SR * length)
    t = np.arange(n) / SR
    taps = np.zeros(n)
    k = rng.poisson(density * length)
    at = (rng.random(k) ** 1.4 * n).astype(int)
    np.add.at(taps, at, rng.standard_normal(k) * rng.pareto(3.0, k))
    clumps = 0.5 + 0.5 * smooth_noise(length, 3.0, n)
    ir = lowpass_glide(taps * clumps * np.exp(-t / decay) + white(length) * 0.05 * np.exp(-t / (decay * 0.6)), darken[0], darken[1], 0.6)
    ir[: int(0.002 * SR)] = 0
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-9)


def convolve_wet(x, ir, wet):
    m = len(x) + len(ir)
    y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[: len(x) + len(ir) // 2]
    out = np.zeros(len(y))
    out[: len(x)] += x
    return out + y * wet


def low_cut(x, f=22.0):
    return band(x, f, None)


def unit(x):
    """`x` scaled to an RMS of 1, so a layer's gain is its level."""
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-9)


def thud(m, size):
    """One dull thud of earth or rock landing, `m` samples: a burst of noise filtered low (no pitch, no ring), the bigger
    it is the deeper and longer, with a short crunch of grit on its front."""
    s = np.arange(m) / SR
    dec = 0.025 + 0.07 * size
    body = unit(band(rng.standard_normal(m), 35, 140 + 320 / (1 + 1.5 * size))) * (1 - np.exp(-s / 0.004)) * np.exp(-s / dec)
    grit = unit(band(rng.standard_normal(m), 150, 700)) * (1 - np.exp(-s / 0.002)) * np.exp(-s / (0.008 + 0.01 * size))
    return body + grit * 0.45


def debris_settle(d, t0, amount=1.0, spread=6.0):
    """Debris coming back down after a blast, as a microphone in the open hears it. All noise, nothing that rings at a
    pitch: the ground rumbling low and rolling as the earth settles, fading over seconds; the dull rush of dirt and gravel
    raining down in uneven surges, darkening as it thins; dull thuds of rock and clods landing (noise bursts filtered
    low, the bigger ones deeper and longer); and stragglers sliding and rolling to rest further off. Starts at t0, peaks
    soon after, thins out over about `spread` seconds. Mono, dry: put it through the blast's outdoor space."""
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    on = t >= t0
    rate = (1 - np.exp(-u / 0.3)) * np.exp(-u / (spread * 0.35)) * on             # how much is landing now
    surge = 0.35 + 0.65 * (0.5 + 0.5 * smooth_noise(d, 2.2, n)) ** 1.5             # it comes down in uneven surges
    x = np.zeros(n)
    # the ground: a deep rumble that rolls slowly and fades over seconds, outlasting the fall
    env = (1 - np.exp(-u / 0.25)) * np.exp(-u / (spread * 0.45)) * on
    roll = 0.55 + 0.45 * smooth_noise(d, 1.6, n)
    x += unit(lowpass_glide(band(white(d), 35, None), 260, 100, curve=0.7)) * env * roll * GROUND * amount
    # dirt and gravel: a dull rush in surges, gritty rather than steady, the top falling away as it thins
    grit = (0.5 + 0.5 * smooth_noise(d, 13.0, n)) ** 2
    x += unit(lowpass_glide(band(white(d), 100, None), 900, 280, curve=0.6)) * rate * surge * (0.4 + 0.6 * grit) * RUSH * amount
    # thuds: rock and clods landing, many small, a few big
    for _ in range(int(70 * amount * spread / 6)):
        t1 = t0 + min(rng.exponential(spread * 0.28), spread) + rng.uniform(0, 0.2)
        if t1 > d - 0.1:
            continue
        size = min(rng.pareto(2.2) * 0.35 + 0.1, 1.6)
        k0 = int(t1 * SR)
        m = min(int((0.12 + 0.35 * size) * SR), n - k0)
        x[k0:k0 + m] += thud(m, size) * size * THUDS * np.exp(-(t1 - t0) / (spread * 0.5))
    # chunks: a heavy mass of earth slumping now and then, deep and soft
    for _ in range(int(6 * amount)):
        t1 = t0 + 0.1 + spread * 0.4 * rng.random() ** 1.5
        if t1 > d - 0.3:
            continue
        k0 = int(t1 * SR)
        m = min(int(0.9 * SR), n - k0)
        x[k0:k0 + m] += thud(m, rng.uniform(1.6, 2.6)) * rng.uniform(0.6, 1.0) * CHUNKS * np.exp(-(t1 - t0) / (spread * 0.45))
    # stragglers: rock sliding and rolling to rest, further off, low and uneven
    for _ in range(int(6 * amount)):
        t1 = t0 + spread * rng.uniform(0.3, 1.0)
        L = rng.uniform(0.6, 1.6)
        if t1 > d - L:
            continue
        m = int(L * SR)
        seg = unit(lowpass_glide(band(white(L), 40, None), rng.uniform(380, 550), rng.uniform(130, 200), 0.8))
        seg *= np.sin(np.linspace(0, np.pi, m)) ** 1.5 * (0.3 + 0.7 * (0.5 + 0.5 * smooth_noise(L, 7.0, m)) ** 2)
        k0 = int(t1 * SR)
        x[k0:k0 + m] += seg * rng.uniform(0.6, 1.0) * STRAGGLERS * amount * np.exp(-(t1 - t0) / (spread * 0.6))
    return x


# the settling layers' levels (RMS), against a blast whose pulse peaks at about 1
GROUND, RUSH, THUDS, CHUNKS, STRAGGLERS = 0.04, 0.25, 0.1, 0.06, 0.05


def blast(d, T, size=1.0, distance=0.0, seed_shift=0):
    """One blast as a microphone records it: the pressure pulse (T seconds to its zero crossing), the air torn up
    behind it roaring and crackling, the mic overloaded by it. `distance` 0 (close) to 1 (far off) muffles it as air
    does and leaves less of the crack. Mono, before any echoes."""
    n = int(SR * d)
    t = np.arange(n) / SR
    pulse = friedlander(n, 0.0, T, 1.4) * 1.6
    roar_t = 0.25 + 1.1 * T / 0.25 * size
    # heard from tens of metres the air has already taken most of the top: the roar starts dark and goes darker
    turb = lowpass_glide(white(d), 3200 * (1 - 0.7 * distance), 150, curve=0.55) * np.clip(t / 0.003, 0, 1) * np.exp(-t / roar_t) * 0.75
    body = band(white(d), 50, 350) * np.clip(t / 0.004, 0, 1) * np.exp(-t / (T * 6 + 0.1)) * 0.8
    crk = crackle(d, rate=900 + 1300 * size, decay=0.004, lo=80, hi=2400 * (1 - 0.6 * distance)) * np.exp(-t / (roar_t * 0.7)) * 0.35
    x = overload(pulse + turb + body + crk, 2.0 - 0.6 * distance)
    return band(x, None, 3200 * (1 - distance) + 450)


def parallel_comp(L, R, amount=0.7, ratio=6.0, thresh=0.12, attack=0.003, release=0.25):
    """Parallel ('New York') compression: a heavily squashed copy blended under the original, so the body and tail of
    a blast come up dense and loud while its front still slams through on top."""
    env = np.maximum(np.abs(L), np.abs(R))
    a, r = np.exp(-1 / (attack * SR)), np.exp(-1 / (release * SR))
    sm = np.zeros_like(env)
    level = 0.0
    for i, v in enumerate(env):
        level = a * level + (1 - a) * v if v > level else r * level + (1 - r) * v
        sm[i] = level
    peak = np.max(env) + 1e-9
    th = thresh * peak
    gain = np.where(sm > th, (th / np.maximum(sm, 1e-9)) ** (1 - 1 / ratio), 1.0)
    cl, cr = L * gain, R * gain
    k = peak / (np.max(np.maximum(np.abs(cl), np.abs(cr))) + 1e-9)
    return L + amount * cl * k, R + amount * cr * k


def master(x):
    """Mastering EQ for the meteor storm: the deep sub-bass pulled down (most speakers can't play it, and it swamps
    everything else), the body from 150 Hz to 2 kHz brought well up, a little presence round 3 kHz. Without it the
    booms are nearly all below 60 Hz and sound thin and flat on anything but a subwoofer."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    g = 0.3 + 0.7 / (1 + (70.0 / np.maximum(f, 1.0)) ** 3)                  # sub shelf: down about 10 dB under 50 Hz
    g *= 1 + 3.2 * np.exp(-0.5 * ((lf - np.log2(450.0)) / 1.3) ** 2)       # body: up to about +12 dB round 450 Hz
    g *= 1 + 1.0 * np.exp(-0.5 * ((lf - np.log2(3000.0)) / 0.7) ** 2)      # presence: up about 6 dB round 3 kHz
    return np.fft.irfft(X * g, len(x))


def finish_m(name, x, tail_fade=0.05):
    finish(name, master(x), tail_fade)


def finish_st_m(name, left, right, tail_fade=0.05, level=0.97):
    finish_st(name, master(left), master(right), tail_fade, level)


def meteor():
    th = "meteor"
    # lock-on: something heavy locking into place: two low clunks, a filtered swell rising under them
    d = 2.2; n = int(SR * d); t = tt(d)
    clunks = np.zeros(n)
    for t0, a in ((0.0, 1.0), (0.32, 0.8)):
        clunks += click(n, t0, 0.9 * a, 200, 5000, 0.006) + punch(n, t0, 130, 70, 0.12, 5.0) * a * 0.9
        clunks += ring(n, t0, [180.0, 271.0, 405.0], 0.18, 0.12 * a)
    swell = [lowpass_glide(white(d), 300, 2500, curve=1.5) * np.clip(t / 1.6, 0, 1) ** 2 * fade(n, 0.05, 0.4) * 0.12 for _ in range(2)]
    hum = np.sin(2 * np.pi * 55 * t) * np.clip(t / 0.3, 0, 1) * np.exp(-t / 1.4) * 0.35
    l, r = reverb_st(clunks + hum, 0.3, length=1.8, tau_lo=1.0, tau_mid=0.6, tau_hi=0.25)
    finish_st_m(f"{th}/lockon", l + np.pad(swell[0], (0, len(l) - n)), r + np.pad(swell[1], (0, len(r) - n)), 0.2, 0.8)

    # charge: the wind getting up all round, thunder rolling far off on either side, streaks hissing over
    d = 4.0; n = int(SR * d); t = tt(d); p = t / d
    L = np.zeros(n); R = np.zeros(n)
    for ch in (L, R):
        ch += glide_noise(d, 220, 700, 1.4, curve=1.4) * (0.15 + 0.85 * p ** 1.6) * (1 + 0.35 * smooth_noise(d, 2.5)) * 0.45
    for t0, a, pn in ((0.4, 0.4, -0.7), (1.6, 0.55, 0.6), (2.7, 0.75, -0.2)):
        e = np.clip((t - t0) / 0.25, 0, 1) ** 2 * np.exp(-np.maximum(t - t0, 0) / 0.9)
        l, r = pan(band(white(d), 25, 180) * e * a, pn); L += l; R += r
    for t0, pn in ((1.1, -0.8), (2.3, 0.8), (3.2, 0.0)):
        e = np.exp(-((t - t0) / 0.35) ** 2)
        l, r = pan(glide_noise(d, 3200, 1400, 0.8) * e * 0.2, pn); L += l; R += r
    sub = np.sin(2 * np.pi * np.cumsum(glide(30, 38, t, d)) / SR) * p ** 2 * 0.8
    L += sub; R += sub
    f = fade(n, 0.4, 0.05)
    l1, r1 = reverb_st(L * f, 0.3, length=2.6, tau_lo=1.8, tau_mid=0.8, tau_hi=0.3)
    l2, r2 = reverb_st(R * f, 0.3, length=2.6, tau_lo=1.8, tau_mid=0.8, tau_hi=0.3)
    finish_st_m(f"{th}/charge", l1 * 0.8 + l2 * 0.2, r2 * 0.8 + r1 * 0.2, 0.02, 0.85)

    # fire: the sky tearing open overhead, from one side to the other, booms cracking, the air crackling
    d = 5.5; n = int(SR * d); t = tt(d)
    tear = glide_noise(d, 900, 70, 1.6, curve=0.6) * np.exp(-t / 1.8) * fade(n, 0.02, 0.5) * 0.9
    sweep = np.clip(t / 2.5, 0, 1) * 2 - 1
    L = tear * np.cos((sweep + 1) * np.pi / 4); R = tear * np.sin((sweep + 1) * np.pi / 4)
    low = band(white(d), 20, 120) * exp_env(n, 0.05, 1.6) * 1.2
    L += low; R += low
    for t0, a, pn in ((0.08, 1.0, 0.0), (0.9, 0.6, -0.6), (1.9, 0.5, 0.7)):
        l, r = pan(boom(n, t0, 70, 30, 0.6, 0.3, 0.8) * a, pn); L += l; R += r
    for ch in (L, R):
        ch += band(crackles(n, d, 80, 0.1, 3.5, 0.03, 0.25, bias=1.5), None, 6000)
    l, r = reverb_st(L, 0.45, length=3.6, tau_lo=2.6, tau_mid=1.3, tau_hi=0.4)
    l2, r2 = reverb_st(R, 0.45, length=3.6, tau_lo=2.6, tau_mid=1.3, tau_hi=0.4)
    finish_st_m(f"{th}/fire", l + l2 * 0.15, r2 + r * 0.15, 0.3, 0.95)

    # storm: the bed under the whole storm (12 s), wide: wind all round, far-off whooshes crossing from side to side,
    # thunder and thuds rolling in from every direction. Quieter than the hits, so they stand out from it.
    d = 12.0; n = int(SR * d); t = tt(d)
    L = np.zeros(n); R = np.zeros(n)
    for ch in (L, R):
        ch += glide_noise(d, 160, 120, 1.8) * (0.7 + 0.3 * smooth_noise(d, 0.6)) * 0.5
        ch += glide_noise(d, 500, 650, 1.2) * (0.5 + 0.5 * smooth_noise(d, 0.9)) ** 2 * 0.25
    for _ in range(16):
        t0 = rng.uniform(0.3, d - 1.2)
        dur = rng.uniform(0.8, 1.6)
        seg = glide_noise(dur, rng.uniform(1600, 2600), rng.uniform(500, 900), 0.7)
        e = np.sin(np.linspace(0, np.pi, len(seg))) ** 2 * rng.uniform(0.08, 0.2)
        p0, p1 = rng.uniform(-1, 1), rng.uniform(-1, 1)
        pp = np.linspace(p0, p1, len(seg))
        k0 = int(t0 * SR)
        m = min(len(seg), n - k0)
        L[k0:k0 + m] += (seg * e * np.cos((pp + 1) * np.pi / 4))[:m]
        R[k0:k0 + m] += (seg * e * np.sin((pp + 1) * np.pi / 4))[:m]
    for _ in range(20):
        t0 = rng.uniform(0.5, d - 0.6)
        l, r = pan(boom(n, t0, rng.uniform(55, 85), 26, rng.uniform(0.3, 0.7), 0.25, 0.15) * rng.uniform(0.15, 0.45), rng.uniform(-0.9, 0.9))
        L += l; R += r
    f = fade(n, 1.0, 2.0)
    l, r = reverb_st(L * f, 0.35, length=3.0, tau_lo=2.2, tau_mid=1.0, tau_hi=0.3)
    l2, r2 = reverb_st(R * f, 0.35, length=3.0, tau_lo=2.2, tau_mid=1.0, tau_hi=0.3)
    finish_st_m(f"{th}/storm", l + l2 * 0.1, r2 + r * 0.1, 0.05, 0.6)

    # rumble: the ground shaking, low thumps under it, wide
    d = 4.0; n = int(SR * d); t = tt(d)
    L = np.zeros(n); R = np.zeros(n)
    for ch in (L, R):
        ch += band(white(d), 18, 110) * (1 + 0.6 * smooth_noise(d, 4)) * 1.1
    for _ in range(5):
        l, r = pan(sub_drop(n, rng.uniform(0.2, d - 0.8), 50, 24, 0.6, 5.0, rng.uniform(0.3, 0.7)), rng.uniform(-0.7, 0.7))
        L += l; R += r
    f = fade(n, 0.5, 1.2)
    l, r = reverb_st(L * f, 0.3, length=2.4, tau_lo=1.6, tau_mid=0.6, tau_hi=0.2)
    finish_st_m(f"{th}/rumble", l, r, 0.02, 0.8)

    # whoosh (positional, so mono), two takes: one meteor tearing in for 1.3 s. A ripping, crackling roar and a
    # hiss growing as it nears, swept by the comb filter of its reflection off the ground, cut as it lands
    for take in (1, 2):
        d = 1.3; n = int(SR * d); t = tt(d); p = t / d
        rip = crackle(d, rate=900 + 400 * take, decay=0.0015, lo=250, hi=5000) * 0.6
        roar = glide_noise(d, 260 + 60 * take, 480, 1.6)
        hiss = glide_noise(d, 3500, 2200, 0.9) * 0.35
        x = (rip + roar + hiss) * p ** (2.2 + 0.4 * take)
        x = flange(x, 0.004, 0.0004, 0.85, curve=1.5)
        finish_m(f"{th}/whoosh{take}", x * fade(n, 0.12, 0.005), 0.005)

    # hit1-3 (positional, mono): a meteor landing close by, tiny, medium and big, made the way the big impact is: the
    # blast as a microphone records it, debris settling after it, both in clumps of echoes off the land around
    for take, (T, size, d) in enumerate(((0.045, 0.35, 3.5), (0.075, 0.6, 4.5), (0.11, 0.9, 6.0)), 1):
        n = int(SR * d)
        x = blast(d, T, size)
        x += debris_settle(d, 0.35 + 0.15 * size, amount=0.35 + 0.6 * size, spread=1.8 + 2.5 * size)
        x = convolve_wet(x, outdoor_ir(2.5 + 2.0 * size, density=40.0, darken=(4500, 220), decay=0.6 + 1.0 * size), 0.6)
        x = low_cut(x)
        finish(f"{th}/hit{take}", x / (np.max(np.abs(x)) + 1e-9), 0.3)

    # hit_far1-3 (positional, mono): the same three, a long way off: the air has taken the crack and the hiss, what is
    # left is the dull blow and the land rolling it back for a few seconds
    for take, (T, size, d) in enumerate(((0.045, 0.35, 4.5), (0.075, 0.6, 5.5), (0.11, 0.9, 7.0)), 1):
        x = blast(d, T * 1.3, size, distance=0.8)
        x = convolve_wet(x, outdoor_ir(4.0, density=25.0, darken=(1500, 150), decay=1.2 + 0.8 * size), 1.0)
        x = low_cut(x)
        finish(f"{th}/hit_far{take}", x / (np.max(np.abs(x)) + 1e-9), 0.4)

    # approach: the big one coming in for 6.5 s, like a jet the size of a mountain: a crackling, tearing roar growing
    # from far off, sweeping through the comb filter of its reflection as it closes, a pressure you can feel building
    # under it, the sky hissing, then nothing: the flash comes before the sound does
    d = 6.6; n = int(SR * d); t = tt(d); p = np.clip(t / 6.5, 0, 1)
    L = np.zeros(n); R = np.zeros(n)
    for k, ch in enumerate((L, R)):
        roar = glide_noise(d, 70, 320, 2.0, curve=1.5) * p ** 2.0
        rip = crackle(d, rate=1400, decay=0.002, lo=120, hi=4500) * p ** 2.6 * 0.9
        hiss = glide_noise(d, 3000, 6000, 1.2, curve=2.0) * p ** 4 * 0.35
        ch += flange(roar + rip + hiss, 0.012 + 0.001 * k, 0.0008, 0.8, curve=1.3)
    press = sub_drop(n, 0.0, 30, 30, 1e9, 0.0, 1.0) * p ** 3 * 0.9
    cut = fade(n, 0.6, 0.01) * np.clip((6.5 - t) / 0.01, 0, 1)
    finish_st_m(f"{th}/approach", (L + press) * cut, (R + press) * cut, 0.01, 0.95)

    # impact: the extinction event, as footage of a very large blast carries it. One enormous pressure pulse, a
    # quarter of a second long, felt more than heard, overloads the mic; the air torn up behind it roars and crackles
    # as the front rolls over; wind buffets the mic; the land answers for seconds in clumps of echoes, each duller
    # than the last; rock and dirt rain down; the ground rumbles on
    d = 14.0; n = int(SR * d); t = tt(d)
    # the pressure: a half-second pulse under a quarter-second one, so it lands as a shove you feel, then the suction
    pulse = (friedlander(n, 0.0, 0.45, 1.2) * 1.4 + friedlander(n, 0.0, 0.25, 1.3) * 1.2
             + friedlander(n, 0.07, 0.09, 1.8) * 0.4)
    # the punch: the first fraction of a second packed with low noise (no pitch in it), then the weight rolling on
    punch_ = band(white(d), 28, 220) * np.clip(t / 0.002, 0, 1) * np.exp(-t / 0.22) * 1.7
    shove = band(white(d), 18, 90) * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.7) * 1.2
    turb = lowpass_glide(white(d), 2600, 130, curve=0.55) * np.clip(t / 0.004, 0, 1) * np.exp(-t / 1.3) * 0.8
    crk = crackle(d, rate=2200, decay=0.005, lo=70, hi=2000) * np.exp(-t / 0.9) * fade(n, 0.004, 0.5) * 0.3
    gusts = np.zeros(n)
    for _ in range(12):
        t0 = rng.uniform(0.1, 3.5)
        gusts += band(white(d), 8, 60) * np.exp(-((t - t0) / rng.uniform(0.1, 0.35)) ** 2) * rng.uniform(0.4, 1.0)
    front = band(overload(pulse + punch_ + shove + turb + crk + gusts * 0.35, 2.6), None, 3200)
    # the debris coming down, in the same outdoor space: its lows (under 150 Hz) one and the same in both ears, so the
    # rumble sits centred on headphones; above that each ear hears its own rain of it
    falls = [debris_settle(d, 1.1 + 0.1 * k, amount=1.6, spread=8.0) * 1.1 for k in range(2)]
    fall_lo = convolve_wet(band(falls[0], None, 150), outdoor_ir(3.0, density=40.0, darken=(4000, 250), decay=1.2), 0.5)
    outs = []
    for k in range(2):
        # each ear its own echoes off the land
        ir = outdoor_ir(7.0, density=35.0, darken=(3500, 140), decay=2.6)
        y = convolve_wet(front, ir, 0.9)
        fw = convolve_wet(band(falls[k], 150, None), outdoor_ir(3.0, density=40.0, darken=(4000, 250), decay=1.2), 0.5)
        mm = min(len(y), len(fw), len(fall_lo))
        y[:mm] += fw[:mm] + fall_lo[:mm]
        outs.append(y)
    m = min(len(o) for o in outs)
    L, R = outs[0][:m], outs[1][:m]
    rumble = band(white(m / SR), 16, 80) * np.exp(-np.arange(m) / SR / 4.0) * (1 + 0.5 * smooth_noise(m / SR, 2.0)) * 0.35
    L = low_cut(L + rumble); R = low_cut(R + rumble)
    # everything under 120 Hz the same in both ears: the weight sits dead centre on headphones, and hits harder there
    lo = (band(L, None, 120) + band(R, None, 120)) * 0.5
    L = L - band(L, None, 120) + lo; R = R - band(R, None, 120) + lo
    L, R = parallel_comp(L, R, amount=0.8)
    finish_st(f"{th}/impact", L, R, 0.8, 0.99)

    # shutdown: afterwards. Wind over the crater, fires crackling here and there, rock settling far off
    d = 6.0; n = int(SR * d); t = tt(d)
    L = np.zeros(n); R = np.zeros(n)
    for ch in (L, R):
        ch += glide_noise(d, 400, 300, 1.4) * (0.6 + 0.4 * smooth_noise(d, 0.8)) * 0.35
    for _ in range(140):
        l, r = pan(click(n, rng.uniform(0, d - 0.3), rng.uniform(0.03, 0.2), 1500, 7000, rng.uniform(0.002, 0.01)), rng.uniform(-1, 1))
        L += l; R += r
    for _ in range(4):
        l, r = pan(sub_drop(n, rng.uniform(0.3, 4.5), 45, 22, 0.5, 6.0, rng.uniform(0.15, 0.35)), rng.uniform(-0.8, 0.8))
        L += l; R += r
    f = fade(n, 0.8, 2.0)
    l, r = reverb_st(L * f, 0.35, length=2.6, tau_lo=1.8, tau_mid=0.8, tau_hi=0.3)
    l2, r2 = reverb_st(R * f, 0.35, length=2.6, tau_lo=1.8, tau_mid=0.8, tau_hi=0.3)
    finish_st_m(f"{th}/shutdown", l + l2 * 0.1, r2 + r * 0.1, 0.3, 0.6)


BUILDERS = {"godly": godly, "blackhole": blackhole, "meteor": meteor}


def build_all(only=None):
    for th in THEMES:
        if only is None or th in only:
            BUILDERS[th]()
