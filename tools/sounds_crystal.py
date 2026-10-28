"""The Crystal Bloom's sounds, all synthesised here from noise, sines and filters (nothing sampled):

  wake       the land waking: a deep resonant hum swelling under groans and creaks of the ground, a faint glassy shimmer
             coming up through it (0 is the strike's start, heard from the middle)
  punch1-3   a shard punching up out of the land (positional, mono; 0 is its ground starting to heave, 0.7 s before it
             breaks it): the ground groaning and cracking, the crystal under it fracturing under the strain, the crack of rock and crystal as it breaks through, grinding
             and catching twice (0.34 and 0.66 s after), then the surge: a heavy blow, a glassy ring rising with it, rock
             raining back down, a variation of the Planet Killer's `rise`
  bloom      the bloom running out over the land (0 is 0.3 s before it sets out): chimes and ringing as the spires grow,
             each push its own chime, deeper for the big ones, grinding and cracking where they break the ground
  resonance  the spires humming in sync (0 is the strike's 14 s): a harmonic drone building, harmonic by harmonic, its
             pulses quickening with the light running up them, air and breathy high harmonics shimmering on top; cut dead
             0.32 s before the burst
  shatter    the detonation: `explosion_live` played on another seed and with its own character (a sharper, brighter
             start, a little shorter), with ringing crystalline partials, a shimmer of glitter high up and the glass of the
             spires shattering on top of its weight
  tinkle     shards raining down for seconds after it: each its own glass hit (inharmonic modes struck rough, bouncing
             and skittering on stone, dull on earth), near and far, some in sprays, the odd bigger one breaking, fine
             grit settling, thinning out
  after      what is left: a singing ring dying away over the crater, a low wind, a last few tinkles

    python3 tools/sounds_crystal.py            # writes orbital-sounds/assets/orbital/sounds/crystalbloom/*.ogg and
                                               # adds the events to sounds.json, leaving every other sound as it is
    python3 tools/sounds_crystal.py --plots D  # and a spectrogram and envelope of each, as PNGs in D
"""
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, tt, white, band, smooth_noise
import sounds_themes as T
import sounds_pk_blast as PB

TH = "crystalbloom"
NAMES = ["wake", "punch1", "punch2", "punch3", "bloom", "resonance", "shatter", "tinkle", "after"]
# (the vibrating modes of a free glass bar or a crystal: inharmonic, so they ring like glass, not like a string)
GLASS = (1.0, 2.76, 5.40, 8.93, 13.3)


def rng():
    return soundlib.rng


def ping(n, t0, f, decay, amp=1.0, modes=GLASS, bright=0.6, beat=0.0):
    """One glassy ping at t0: the modes of a struck crystal, the higher dying faster, each a pair a hair apart when
    `beat` is set (the shimmer of a ringing glass), its onset a few samples (no click, no ringing before it)."""
    k0 = int(t0 * SR)
    m = min(int(decay * 6 * SR), n - k0)
    if m <= 0:
        return np.zeros(n)
    s = np.arange(m) / SR
    y = np.zeros(m)
    for j, r in enumerate(modes):
        fj = f * r
        if fj > 17000:
            break
        a = bright ** j / (1 + 0.3 * j)
        dj = decay / (1 + 0.9 * j)
        ph = rng().uniform(0, 2 * np.pi)
        y += np.sin(2 * np.pi * fj * s + ph) * np.exp(-s / dj) * a
        if beat > 0:
            y += np.sin(2 * np.pi * fj * (1 + beat) * s + ph + 1.0) * np.exp(-s / dj) * a * 0.7
    y *= np.minimum(s / 0.0006, 1.0)
    out = np.zeros(n)
    out[k0:k0 + m] = y * amp
    return out


def shatter_burst(n, t0, size=1.0, bright=1.0):
    """Glass breaking: a sharp, bright crack (noise gated hard, high-passed), the crunch under it, and a spray of
    fragments pinging off one another over the next tenth of a second or so. Mono."""
    k0 = int(t0 * SR)
    u = np.maximum(np.arange(n) / SR - t0, 0)
    g = PB.ramp_in(n, k0, 6)
    w = rng().standard_normal(n)
    crack = band(w, 2500, 14000, 2) * np.exp(-u / (0.006 + 0.004 * size)) * 1.4
    crunch = band(rng().standard_normal(n), 500, 3000, 2) * np.exp(-u / (0.02 + 0.03 * size)) * 0.7
    x = (crack * bright + crunch) * g
    for _ in range(int(10 + 22 * size)):
        tp = t0 + 0.002 + rng().gamma(1.5, 0.03 * size)
        f = rng().uniform(1600, 6500) / (0.6 + 0.6 * size)
        x += ping(n, tp, f, rng().uniform(0.02, 0.09), rng().uniform(0.05, 0.25) * size, bright=0.5)
    return x


def glitter(n, t_lo, t_hi, rate_fn, amp_fn, f_lo=4000, f_hi=12000):
    """A shimmer of tiny glints high up: very short pings (a few ms), thousands a second at its thickest, at random
    pitches, thinning out. Stereo."""
    L = np.zeros(n); R = np.zeros(n)
    peak = max(rate_fn(t_lo), rate_fn((t_lo + t_hi) / 2), rate_fn(t_hi)) * 1.3
    t = t_lo
    while True:
        t += rng().exponential(1.0 / peak)
        if t >= t_hi:
            break
        if rng().random() > rate_fn(t) / peak:
            continue
        k0 = int(t * SR)
        f = np.exp(rng().uniform(np.log(f_lo), np.log(f_hi)))
        d = rng().uniform(0.002, 0.012)
        m = min(int(d * 6 * SR), n - k0)
        if m <= 4:
            continue
        s = np.arange(m) / SR
        y = np.sin(2 * np.pi * f * s + rng().uniform(0, 6.28)) * np.exp(-s / d) * np.minimum(s / 0.0003, 1) * amp_fn(t) * rng().uniform(0.3, 1.0)
        p = rng().uniform(-1, 1)
        L[k0:k0 + m] += y * np.cos((p + 1) * np.pi / 4) * 1.41
        R[k0:k0 + m] += y * np.sin((p + 1) * np.pi / 4) * 1.41
    return L, R


def modal(g, m, exc, freqs, decays, amps):
    """`exc` (a short burst of noise) struck into a body's modes: each mode a damped sine at its own phase, the burst
    convolved through them all, so the onset is as rough as the burst and no two strikes ring quite alike. Mono, `m`
    samples."""
    s = np.arange(m) / SR
    ir = np.zeros(m)
    for f, dk, a in zip(freqs, decays, amps):
        if f < 16500:
            ir += np.sin(2 * np.pi * f * s + g.uniform(0, 2 * np.pi)) * np.exp(-s / dk) * a
    return np.convolve(exc, ir)[:m]


def burst(g, m, decay, lo=None, hi=None):
    """A burst of noise `m` samples long, dying over `decay` seconds: what strikes a body in `modal`."""
    s = np.arange(m) / SR
    x = g.standard_normal(m) * np.exp(-s / decay)
    return band(x, lo, hi) if (lo or hi) else x


def fracture(g, n, t0, size=1.0):
    """A crystal mass cracking under stress, deep in the ground: a quick run of micro-fractures (each a rough burst
    through a dense, short, inharmonic set of modes, so it snaps and grits rather than rings) and the dull knock of the
    whole body taking the strain under it. Mono, placed at t0."""
    m = int(0.45 * SR)
    y = np.zeros(m)
    tc = 0.0
    for i in range(int(g.integers(4, 9) + 3 * size)):
        k = int(tc * SR)
        if k >= m - 64:
            break
        nm = int(g.integers(14, 24))
        fr = np.exp(g.uniform(np.log(650), np.log(7000), nm))
        dec = g.uniform(0.003, 0.022, nm) * (900 / fr) ** 0.35
        amp = g.lognormal(0, 0.7, nm) * (1500 / fr) ** 0.3
        e = burst(g, int(0.006 * SR), g.uniform(0.0003, 0.0022))
        c = modal(g, m - k, e, fr, dec, amp)
        c += band(burst(g, m - k, g.uniform(0.0008, 0.003)), 900, 9000) * np.abs(c).max() * 0.8
        y[k:] += c / (np.abs(c).max() + 1e-9) * g.uniform(0.25, 1.0) * (1.0 if i else 1.3)
        tc += g.gamma(1.3, 0.012 + 0.012 * size)
    # (the body taking it: a few low modes struck by a soft, long burst, a knock more than a note)
    fr = np.array([g.uniform(110, 160), g.uniform(230, 300), g.uniform(390, 520)]) * (1.1 - 0.2 * size)
    body = modal(g, m, burst(g, int(0.04 * SR), 0.012, 60, 900), fr, g.uniform(0.025, 0.06, 3), (1.0, 0.6, 0.35))
    body = band(body, 60, 1500)
    y += body / (np.abs(body).max() + 1e-9) * (0.35 + 0.25 * size)
    out = np.zeros(n)
    k0 = int(t0 * SR)
    out[k0:k0 + m] = y[:n - k0]
    return out


def glass_hit(g, size, stone, rough=1.0):
    """One shard of glass landing: a hard tick of contact, the shard's own modes (inharmonic, few and short, each
    struck through a rough burst), on stone maybe bouncing a few times, quicker and softer each time, and skittering;
    on earth dull and short, more knock than ring. Mono, peak 1, about a third of a second."""
    m = int(0.36 * SR)
    s = np.arange(m) / SR
    # (the shard's modes: a big piece lower and longer, a sliver high and brief; spaced unevenly, as a flake's are)
    nm = int(g.integers(5, 11))
    base = np.exp(g.uniform(np.log(1700), np.log(5200))) * (1.6 - size)
    fr = base * np.cumprod(np.concatenate(([1.0], 1 + g.uniform(0.18, 0.9, nm - 1))))
    dec = g.uniform(0.005, 0.022, nm) * (0.6 + 0.8 * size) * (base / fr) ** 0.6 * (1.0 if stone else 0.45)
    amp = g.lognormal(0, 0.6, nm) * (base / fr) ** 0.5
    y = np.zeros(m)
    hits = [(0.0, 1.0)]
    if stone and g.random() < 0.6:
        dt, a, tb = g.uniform(0.03, 0.1), 1.0, 0.0
        for _ in range(int(g.integers(1, 5))):
            tb += dt; a *= g.uniform(0.25, 0.6); dt *= g.uniform(0.4, 0.75)
            if tb > 0.25:
                break
            hits.append((tb, a))
    for tb, a in hits:
        k = int(tb * SR)
        e = burst(g, int(0.004 * SR), g.uniform(0.0002, 0.0012) * rough)
        r = modal(g, m - k, e, fr * g.uniform(0.985, 1.015, nm), dec * g.uniform(0.7, 1.2, nm), amp * g.uniform(0.5, 1.3, nm))
        r /= np.abs(r).max() + 1e-9
        tick = band(burst(g, m - k, g.uniform(0.0002, 0.0007)), 3000 if stone else 1200, 15000 if stone else 5000)
        tick /= np.abs(tick).max() + 1e-9
        y[k:] += (r * (1.0 if stone else 0.5) + tick * g.uniform(0.3, 0.8)) * a
    if not stone:
        th = band(burst(g, m, g.uniform(0.003, 0.007)), 500, 2000)
        y += th / (np.abs(th).max() + 1e-9) * 0.3
    if stone and g.random() < 0.35:
        # (skittering on: grit dragged over stone for a moment, in uneven grabs)
        k = int(g.uniform(0.01, 0.05) * SR)
        ln = int(g.uniform(0.03, 0.12) * SR)
        grab = (g.random(ln // 90 + 2) ** 3)[np.minimum(np.arange(ln) // 90, ln // 90 + 1)]
        sk = band(g.standard_normal(ln), 2500, 9000) * grab * np.hanning(ln)
        y[k:k + ln] += sk[:m - k] / (np.abs(sk).max() + 1e-9) * g.uniform(0.15, 0.35)
    return y / (np.abs(y).max() + 1e-9)


def env_of(x, w=0.08):
    """The loudness of `x` over time: its RMS over a sliding `w` seconds."""
    k = max(int(w * SR), 1)
    c = np.cumsum(np.concatenate(([0.0], x * x)))
    e = (c[k:] - c[:-k]) / k
    e = np.concatenate((np.full(k // 2, e[0]), e, np.full(len(x) - len(e) - k // 2, e[-1])))
    return np.sqrt(np.maximum(e, 0))


def singing(d, f0, ratios, swell, wobble=0.004, beat=0.6):
    """A ringing chord held and swelling: each partial a pair of sines a few tenths of a hertz apart (the slow beating of
    a singing glass), drifting a little. Mono."""
    n = int(SR * d)
    x = np.zeros(n)
    for k, (r, a) in enumerate(ratios):
        f = f0 * r
        drift = 1 + wobble * smooth_noise(d, 0.2 + 0.05 * k, n)
        ph = 2 * np.pi * np.cumsum(f * drift) / SR
        x += (np.sin(ph + k) + 0.8 * np.sin(ph * (1 + beat / f) + 2 * k)) * a
    return x * swell


def wake():
    # 8.5 s, heard from the middle from the strike's start: the ground's hum swelling (low partials beating, a resonant
    # body round 80-160 Hz), the ground groaning and creaking as it heaves, cracks ticking; and up through it, faintly,
    # a glassy shimmer, rising as the first shard nears (3.5 s)
    d = 8.5; n = int(SR * d); t = tt(d)
    with PB.seeded(71001):
        swell = np.clip(t / 3.5, 0, 1) ** 1.6
        hum = T.drone(d, ((41.2, 1.0), (41.7, 0.8), (61.8, 0.5), (82.4, 0.45), (123.6, 0.22), (164.8, 0.12)), 0.35, 0.35) * swell
        body = T.unit(band(white(d), 60, 200)) * swell * (0.5 + 0.5 * smooth_noise(d, 0.9, n)) * 0.25
        groan = T.groan(d, 52, 44, 0.8, 0, 1) * np.clip((t - 0.5) / 2.5, 0, 1) * 0.35
        crk = T.crackle(d, rate=40, decay=0.004, lo=250, hi=3000, heavy=1.5)
        # (its biggest spikes eased down: the cracks tick under the hum, none of them a hit)
        sd = np.std(crk) + 1e-9
        crk = np.tanh(crk / (4 * sd)) * 4 * sd * np.clip(t / 3.0, 0, 1) * 0.25
        sub = T.unit(band(white(d), 16, 50)) * swell * 0.4
        L = np.zeros(n); R = np.zeros(n)
        for k, ch in enumerate((L, R)):
            shim = singing(d, 1180 + 37 * k, ((1.0, 0.5), (1.5, 0.35), (2.76, 0.25), (4.1, 0.12)), np.clip((t - 1.0) / 5.0, 0, 1) ** 2, beat=0.9 + 0.4 * k)
            ch += shim * 0.05 * (0.6 + 0.4 * smooth_noise(d, 0.7 + 0.2 * k, n))
        mono = hum * 0.9 + body + groan + crk + sub
        L, R = L + mono, R + mono
        f = T.fade(n, 0.6, 1.5)
        L, R = T.wide_tail(L * f, 3.0, 1.4, (2600, 120), 0.5)[0], T.wide_tail(R * f, 3.0, 1.4, (2600, 120), 0.5)[1]
        m = min(len(L), len(R))
        L, R = T.centre_lows(L[:m], R[:m])
    T.finish_loud(f"{TH}/wake", L, R, -15.0, 1.0, 0.89)
    return L, R


def punch(take):
    # positional, mono: 0 is its ground beginning to heave; it breaks the ground at 0.7, catches at +0.34 and +0.66, and
    # surges up at +0.9 (strike.wgsl's cb_grow), settling 1.5 s later
    br = 0.7
    catches = (br + 0.34, br + 0.66)
    surge = br + 0.9
    d = 8.5; n = int(SR * d); t = tt(d)
    with PB.seeded(72000 + take):
        x = np.zeros(n)
        heave = np.clip(t / br, 0, 1) ** 1.5 * (t < surge)
        x += T.unit(band(white(d), 20, 80)) * heave * 0.22
        x += T.crackle(d, rate=70 + 25 * take, decay=0.004, lo=200, hi=2600, heavy=1.4) * heave * (t < br + 0.1) * 0.25
        # (the crystal under the ground cracking under the strain, twice, as loud as the glassy rings it replaces, which
        # are still drawn, unheard, so every other layer of the take keeps its random draws)
        for j, (tc, old) in enumerate(((br * 0.4, ping(n, br * 0.4, 520 + 60 * take, 1.2, 0.05, beat=0.004)),
                                       (br * 0.75, ping(n, br * 0.75, 780 + 50 * take, 0.9, 0.05, beat=0.004)))):
            g = np.random.default_rng(72100 + 10 * take + j)
            fx = fracture(g, n, tc + g.uniform(-0.03, 0.03), 0.6 + 0.4 * j)
            k0, k1 = int(tc * SR), int((tc + 0.5) * SR)
            x += fx * np.sqrt(np.mean(old[k0:k1] ** 2) / (np.mean(fx[k0 - 2000:k1] ** 2) + 1e-12)) * 0.8
        # breaking through: rock and crystal cracking at once, a thud
        x += T.nwave(n, br, 0.003, 0.7, 6000) + shatter_burst(n, br, 0.9, 0.8) * 0.6
        x += T.heavy(n, br, 0.16, 1.4, 1.0, 0.6, 0.3) * 0.8
        # the struggle: stone grinding, a glassy squeal in it, catching twice
        moving = np.clip((t - br) / 0.05, 0, 1) * (t < surge)
        grind = T.stick_slip(d, 28 + 5 * take, 160, 1100, 0.7, 5.0) * 0.5 + T.crackle(d, rate=450, decay=0.0025, lo=250, hi=4500, heavy=1.3) * 0.3
        squeal = T.stick_slip(d, 60 + 10 * take, 1800 + 300 * take, 2600 + 300 * take, 0.8, 6.0) * 0.18
        x += (grind + squeal) * moving * 0.45
        x += T.groan(d, 48 + 4 * take, 40 + 3 * take, 0.8, 4, take) * moving * 0.2
        for c in catches:
            x += T.heavy(n, c, 0.1, 1.1, 1.0, 0.35, 0.18) * 1.0
            k0 = int(c * SR); m = int(0.5 * SR)
            x[k0:k0 + m] += T.thud(m, 2.2) * 0.45
            x += ping(n, c, 300 + 40 * take, 0.6, 0.12, bright=0.5)
        # a breath of near silence, then the surge: a deep blow, the ground blown open, the crystal ringing as it rides up
        after = np.maximum(t - surge, 0); on = t >= surge
        x += T.heavy(n, surge, 0.45, 2.4, 1.4, 1.8, 0.6) * 2.0
        x += T.nwave(n, surge, 0.005, 1.4, 6000)
        x += T.lowpass_glide(white(d), 3000, 200, curve=0.55) * np.clip(after / 0.004, 0, 1) * np.exp(-after / 0.8) * on * 0.8
        f0 = (196.0, 174.6, 220.0)[take - 1]
        rise = np.clip(after / 1.4, 0, 1)
        for k, r in enumerate((1.0, 1.5, 2.0, 2.76, 4.0, 5.4)):
            ph = 2 * np.pi * np.cumsum(f0 * r * (0.94 + 0.06 * (1 - (1 - rise) ** 2)) * on) / SR
            x += np.sin(ph + k) * (1 - np.exp(-after / 0.08)) * np.exp(-after / (1.9 - 0.2 * k)) * on * 0.07 / (1 + 0.4 * k)
        x += T.crackle(d, rate=1400, decay=0.003, lo=150, hi=4000, heavy=1.4) * np.exp(-after / 0.6) * on * 0.35
        # rock and grit raining back down round it
        x += T.pad_to(T.debris_settle(d, surge + 0.25, amount=1.4, spread=5.0), n) * T.fade(n, 0.001, 1.0) * 0.85
        for _ in range(110):
            t1 = surge + 0.4 + 5.0 * rng().random() ** 1.7
            if t1 > d - 0.1:
                continue
            x += T.rock_clack(n, t1, min(rng().pareto(2.5) * 0.35 + 0.08, 1.2)) * 0.2 * np.exp(-(t1 - surge) / 3.0)
        x = T.convolve_wet(x, T.outdoor_ir(5.0, density=30.0, darken=(2000, 120), decay=1.6), 0.5)[:n + int(1.5 * SR)]
        x *= T.duck(np.arange(len(x)) / SR, surge - 0.07, surge, 0.12)
        x, _ = T.parallel_comp(x, x.copy(), amount=0.45)
    T.finish_loud(f"{TH}/punch{take}", T.low_cut(x, 16), None, -15.0, 1.0, 0.89)
    return x, x


def bloom():
    # 9.5 s from 0.3 s before the bloom sets out (the strike's 7.3 s): a spire breaking the ground every tenth of a
    # second or so, out over 4.6 s, each growing in three pushes (a chime with each, the first the brightest); the big
    # ones deep, the small ones high; grinding and cracking where they come up; the ground rumbling under it all
    d = 9.5; n = int(SR * d); t = tt(d)
    with PB.seeded(73001):
        L = np.zeros(n); R = np.zeros(n)
        # (a pentatonic-ish set of crystal pitches, so the many chimes ring together and not as a clash)
        scale = np.array([233.1, 261.6, 311.1, 349.2, 392.0, 466.2, 523.3, 622.3, 698.5, 784.0, 932.3, 1046.5])
        for i in range(40):
            t0 = 0.3 + 4.6 * (i / 40) ** 0.9 + rng().uniform(0, 0.35)
            big = rng().random() ** 2
            dur = 1.3 + 2.2 * big
            f = scale[int((1 - big) * (len(scale) - 1) * rng().uniform(0.7, 1.0))] * (0.5 if big > 0.6 else 1.0)
            p = rng().uniform(-0.9, 0.9)
            x = np.zeros(n)
            for push, (at, a) in enumerate(((0.0, 1.0), (0.18, 0.55), (0.55, 0.4))):
                tp = t0 + at * dur
                if tp > d - 0.5:
                    continue
                x += ping(n, tp, f * (1.0, 1.5, 2.0)[push] ** 0.25, 1.4 + 1.6 * big, 0.11 * a * (0.6 + 0.6 * big), bright=0.55, beat=0.003)
            # (breaking the ground: a crunch of earth and a crack of crystal)
            x += shatter_burst(n, t0, 0.25 + 0.4 * big, 0.5) * 0.25
            k0 = int(t0 * SR); m = min(int(0.4 * SR), n - k0)
            x[k0:k0 + m] += T.thud(m, 1.2 + 1.5 * big) * 0.25 * (0.5 + big)
            l, r = T.pan(x, p)
            L += l; R += r
        grind = T.stick_slip(d, 30, 150, 900, 0.7, 5.0) * 0.12 + T.crackle(d, rate=220, decay=0.003, lo=300, hi=3500, heavy=1.4) * 0.12
        env = np.clip((t - 0.3) / 0.5, 0, 1) * np.exp(-np.maximum(t - 5.5, 0) / 1.2)
        rumble = T.unit(band(white(d), 18, 90)) * env * 0.35
        shim = singing(d, 1567, ((1.0, 0.4), (1.25, 0.3), (1.5, 0.3), (2.0, 0.2)), env * np.clip(t / 4.0, 0, 1), beat=0.7) * 0.04
        L += grind * env + rumble + shim; R += grind * env + rumble + shim
        L, R = L * T.fade(n, 0.05, 1.5), R * T.fade(n, 0.05, 1.5)
        L, R = T.wide_tail(L, 3.0, 1.5, (5000, 300), 0.45)[0], T.wide_tail(R, 3.0, 1.5, (5000, 300), 0.45)[1]
        m = min(len(L), len(R))
        L, R = T.centre_lows(L[:m], R[:m])
    T.finish_loud(f"{TH}/bloom", L, R, -15.0, 1.0, 0.89)
    return L, R


def resonance():
    # 8 s from the strike's 14 s to the burst at 22: a drone of the spires humming as one, harmonic by harmonic coming
    # in (55 Hz up to its 24th), each pair of sines beating slowly; its pulses quickening with the light running up them
    # (strike.wgsl's pulse_f: half a pulse a second to seven); a shimmer of air on top; a rising whine of air; then
    # cut dead at 7.68 s, the breath before the burst
    d = 8.0; n = int(SR * d); t = tt(d)
    cut_at = 7.68
    with PB.seeded(74001):
        u = np.clip(t / 7.6, 0, 1)
        res = u * u * (3 - 2 * u)
        rate = 0.5 + 6.5 * res * res
        pulse = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(rate) / SR)) ** 3
        L = np.zeros(n); R = np.zeros(n)
        f0 = 55.0
        for h in range(1, 25):
            onset = 0.2 + 6.2 * ((h - 1) / 23) ** 1.3
            a = np.clip((t - onset) / 0.8, 0, 1) ** 2 / h ** 0.75
            for k, ch in enumerate((L, R)):
                drift = 1 + 0.0015 * smooth_noise(d, 0.3, n)
                ph = 2 * np.pi * np.cumsum(f0 * h * drift * (1 + 0.0007 * k) * (1 + 0.012 * res)) / SR
                ch += (np.sin(ph + h) + 0.7 * np.sin(ph * (1 + 0.5 / (f0 * h)) + 2 * h + k)) * a * 0.08
        # the shimmer on top: air round the spires (a band of noise, its texture drifting) and the drone's own high
        # harmonics breathed rather than rung (narrow noise riding each, a pair a hair apart, beating slowly), at the
        # loudness of the glitter it replaced, moment by moment; the glitter is still drawn, unheard, so the whine and
        # the sub after it keep their random draws
        gl = glitter(n, 1.0, cut_at, lambda s: 30 + 900 * np.clip((s - 1) / 6.6, 0, 1) ** 2, lambda s: 0.02 + 0.06 * np.clip((s - 1) / 6.6, 0, 1), 3000, 9000)
        shims = []
        with PB.seeded(74101):
            for k, old in enumerate(gl):
                air = band(white(d), 3200, 8500, 2) * (0.65 + 0.35 * smooth_noise(d, 1.3 + 0.4 * k, n))
                air /= np.std(air) + 1e-9
                hp = np.zeros(n)
                for h in (59, 67, 76, 88, 101, 117, 134):
                    for b in (0.0, 0.35 + 0.1 * k):
                        ph = 2 * np.pi * np.cumsum(f0 * h * (1 + 0.012 * res) + b) / SR
                        breath = band(white(d), None, 9.0, 1)
                        hp += np.sin(ph + rng().uniform(0, 6.28)) * breath / h ** 0.5
                hp /= np.std(hp) + 1e-9
                sh = air * 0.7 + hp * 0.45
                shims.append(sh / (env_of(sh, 0.25) + 1e-9) * env_of(old, 0.25))
        shim_L, shim_R = shims
        whine = T.glide_noise(d, 900, 4200, 0.35, curve=2.4) * res ** 2.5 * 0.08
        sub = T.unit(band(white(d), 18, 55)) * res * 0.45
        mono = whine + sub
        L = (L * pulse + mono + shim_L)
        R = (R * pulse + mono + shim_R)
        cut = np.clip(t / 0.3, 0, 1) * np.clip((cut_at - t) / 0.006, 0, 1)
        L, R = T.centre_lows(L * cut, R * cut)
        L, R = T.parallel_comp(L, R, amount=0.6)
    T.finish_loud(f"{TH}/resonance", L, R, -13.5, 0.004, 0.89)
    return L, R


def shatter():
    # the detonation (0 is the burst, heard from the middle): `explosion_live`, on its own seed and with its own
    # character (its start brighter and the crack harder, a little shorter), its weight kept; on top of it the crystal:
    # a hard glassy snap in its first milliseconds, ringing partials (a chord of crystal modes struck all at once,
    # shimmering as they beat, the high ones dying first), glitter sparkling high up for seconds, and the glass of the
    # spires shattering all round, burst on burst, thinning out into tinkling. Clean: every hit starts on its sample.
    d = 16.0; n = int(SR * d); t = tt(d)
    t0 = 0.05
    with PB.seeded(75101):
        EL, ER = PB.explosion_live(d, t0, stretch=0.55, debris=0.6, whump=1.1, live=1.1)
        lv = T.loudest((EL + ER) / 2)
        u = np.maximum(t - t0, 0); on = t >= t0
        # the ring of the crystal: struck modes of a few big bodies, low to high, beating
        ringL = np.zeros(n); ringR = np.zeros(n)
        for f, dec, a in ((146.8, 3.2, 1.0), (220.0, 2.8, 0.8), (293.7, 2.4, 0.7), (369.9, 2.0, 0.6), (493.9, 1.7, 0.5), (659.3, 1.4, 0.45), (880.0, 1.1, 0.35), (1174.7, 0.9, 0.3)):
            for k, ch in enumerate((ringL, ringR)):
                ch += ping(n, t0 + 0.004 + 0.003 * k, f * (1 + 0.0015 * k), dec, a, bright=0.55, beat=0.002 + 0.001 * k)
        ring = (ringL, ringR)
        # the snap of it all breaking at once
        snap = shatter_burst(n, t0, 2.0, 1.6)
        # glass shattering all round, burst on burst, then thinning
        shL = np.zeros(n); shR = np.zeros(n)
        for _ in range(46):
            tb = t0 + 0.02 + rng().gamma(1.4, 0.45)
            if tb > d - 1.0:
                continue
            size = min(rng().pareto(2.0) * 0.3 + 0.2, 1.6)
            x = shatter_burst(n, tb, size, 1.0) * np.exp(-(tb - t0) / 2.5)
            l, r = T.pan(x, rng().uniform(-0.9, 0.9))
            shL += l; shR += r
        gL, gR = glitter(n, t0 + 0.01, d - 0.5, lambda s: 2500 * np.exp(-(s - t0) / 1.6) + 80 * np.exp(-(s - t0) / 5.0), lambda s: 0.06 * np.exp(-(s - t0) / 3.0) + 0.01)
        # (each layer set against the explosion's own loudness)
        rk = lv / (T.loudest((ringL + ringR) / 2) + 1e-9)
        sk = lv / (T.loudest((shL + shR) / 2) + 1e-9)
        gk = lv / (T.loudest((gL + gR) / 2) + 1e-9)
        nk = lv / (T.loudest(snap) + 1e-9)
        # (the high layers only: the crystal sits on the explosion's weight, not over it)
        L = EL + ring[0] * rk * 0.42 + snap * nk * 0.55 + shL * sk * 0.38 + gL * gk * 0.3
        R = ER + ring[1] * rk * 0.42 + snap * nk * 0.55 + shR * sk * 0.38 + gR * gk * 0.3
        # (the crystal layers ring on in a wide space: the ring and the glitter only, never the snap)
        rtl, rtr = T.wide_tail((ring[0] + ring[1]) * rk * 0.12, 4.0, 1.8, (7000, 600), 0.6)
        m = min(len(rtl), n)
        L[:m] += rtl[:m] - ((ring[0] + ring[1]) * rk * 0.12)[:m]
        R[:m] += rtr[:m] - ((ring[0] + ring[1]) * rk * 0.12)[:m]
        L, R = T.centre_lows(T.low_cut(L, 16), T.low_cut(R, 16))
    PB.finish_blast(f"{TH}/shatter", L, R, -8.0, 0.88, 0.8)
    return L, R


def tinkle():
    # 10 s from 1.4 s after the burst: the shards coming down all round, near and far (near: bright, loud, few; far:
    # dull, soft, many), the odd big one breaking, fine grit settling, thinning out.
    # Each shard its own: its size, its modes, whether it lands on stone (a tick, a ring, bounces, a skitter) or earth
    # (a dull knock), how far off (the far ones softer, duller and a touch late, the near ones bright and placed);
    # some shards come down in a little spray of pieces, and a few big ones break where they land
    d = 10.0; n = int(SR * d); t = tt(d)
    with PB.seeded(76001):
        g = np.random.default_rng(76002)
        L = np.zeros(n); R = np.zeros(n)

        def put(y, t1, p, near):
            k0 = int(t1 * SR)
            if k0 >= n:
                return
            y = y[:n - k0]
            if near < 0.6:
                # (distance: the highs lost first, then the level)
                y = band(y, None, 3500 + 10000 * near ** 1.2, 2)
            l, r = T.pan(y, p)
            itd = int(abs(p) * 0.00035 * SR * near)
            if p > 0:
                l = np.concatenate((np.zeros(itd), l))[:len(y)]
            else:
                r = np.concatenate((np.zeros(itd), r))[:len(y)]
            L[k0:k0 + len(y)] += l; R[k0:k0 + len(y)] += r

        def shard(t1, near, size, p, amp):
            stone = g.random() < 0.75
            put(glass_hit(g, size, stone) * amp, t1, p, near)

        for _ in range(170):
            t1 = g.gamma(1.6, 1.5)
            if t1 > d - 0.4:
                continue
            near = g.random() ** 2.2
            size = min(g.pareto(3.0) * 0.25 + 0.05 + 0.2 * g.random(), 1.0)
            p = g.uniform(-1, 1) * (0.5 + 0.5 * near)
            amp = (0.05 + 0.35 * near) * (0.5 + size) * g.lognormal(0, 0.3) * np.exp(-t1 / 4.0)
            t1 += (1 - near) * 0.03
            shard(t1, near, size, p, amp)
            # (a spray: a few smaller pieces off the same shard, close by, just after)
            if g.random() < 0.25:
                ts = t1
                for _ in range(int(g.integers(1, 4))):
                    ts += g.gamma(1.4, 0.025)
                    shard(ts, near * g.uniform(0.7, 1.0), size * g.uniform(0.3, 0.7), np.clip(p + g.normal(0, 0.12), -1, 1), amp * g.uniform(0.25, 0.6))
        # the odd big one breaking where it lands: a crack and a crunch, and its pieces scattering off it
        for _ in range(7):
            tb = g.gamma(1.5, 1.2)
            if tb > d - 1.0:
                continue
            near = g.uniform(0.25, 0.9); p = g.uniform(-0.8, 0.8); a = (0.3 + 0.5 * near) * np.exp(-tb / 4.0)
            m = int(0.3 * SR)
            u = np.arange(m) / SR
            sz = g.uniform(0.4, 1.0)
            y = band(g.standard_normal(m), 2500, 14000, 2) * np.exp(-u / (0.004 + 0.004 * sz))
            y = y / (np.abs(y).max() + 1e-9) + band(g.standard_normal(m), 400, 3000, 2) * np.exp(-u / (0.012 + 0.02 * sz)) / 4.0
            put(y * a * 0.6, tb, p, near)
            tp = tb
            for _ in range(int(6 + 10 * sz)):
                tp += g.gamma(1.3, 0.02)
                shard(tp, near * g.uniform(0.75, 1.0), g.uniform(0.05, 0.4), np.clip(p + g.normal(0, 0.2), -1, 1), a * g.uniform(0.15, 0.5))
        # fine grit and splinters settling everywhere: tiny ticks, thousands at first, unpitched, thinning out
        for ch, k in ((L, 0), (R, 1)):
            rate = 1400 * np.exp(-t / 2.2) + 40 * np.exp(-t / 6.0)
            ev = g.random(n) < rate / SR
            imp = np.zeros(n)
            imp[ev] = g.pareto(2.2, ev.sum()) * g.choice([-1.0, 1.0], ev.sum())
            kern = np.exp(-np.arange(int(0.0012 * SR)) / (0.00025 * SR))
            grit = band(np.convolve(imp, kern)[:n], 3500, 11000, 2)
            grit /= np.percentile(np.abs(grit), 99.5) + 1e-9
            ch += grit * 0.03 * (np.exp(-t / 3.0) + 0.1)
        # (glass, not rock: the knocks' and crunches' weight below a few hundred hertz left out, as before)
        L, R = band(L, 320, None, 2), band(R, 320, None, 2)
        f = T.fade(n, 0.2, 2.0)
        L, R = T.wide_tail(L * f, 2.0, 0.9, (8000, 800), 0.35)[0], T.wide_tail(R * f, 2.0, 0.9, (8000, 800), 0.35)[1]
        m = min(len(L), len(R))
    T.finish_loud(f"{TH}/tinkle", L[:m], R[:m], -19.0, 1.0, 0.89)
    return L[:m], R[:m]


def after():
    # 9 s from 5 s after the burst: a singing ring left over the crater, dying slowly, beating; a low wind over the land;
    # a last few tinkles; a deep settling rumble
    d = 9.0; n = int(SR * d); t = tt(d)
    with PB.seeded(77001):
        env = np.clip(t / 1.5, 0, 1) * np.exp(-t / 4.0)
        L = np.zeros(n); R = np.zeros(n)
        for k, ch in enumerate((L, R)):
            ch += singing(d, 293.7 + 0.8 * k, ((1.0, 0.5), (1.5, 0.35), (2.0, 0.25), (2.76, 0.18), (4.0, 0.08)), env, beat=0.45 + 0.2 * k) * 0.12
            ch += T.roar_bed(d, 250 + 40 * k, 500, 0.5, 0.6) * 0.04
            for _ in range(30):
                t1 = rng().uniform(0.2, d - 1.0)
                ch += ping(n, t1, np.exp(rng().uniform(np.log(1800), np.log(6000))), 0.08, 0.06 * np.exp(-t1 / 3.0), bright=0.4)
        rumble = T.unit(band(white(d), 18, 100)) * (0.5 + 0.5 * smooth_noise(d, 0.6, n)) * np.exp(-t / 3.0) * 0.4
        L += rumble; R += rumble
        f = T.fade(n, 0.3, 3.0)
        L, R = T.wide_tail(L * f, 3.0, 1.6, (4000, 200), 0.5)[0], T.wide_tail(R * f, 3.0, 1.6, (4000, 200), 0.5)[1]
        m = min(len(L), len(R))
        L, R = T.centre_lows(L[:m], R[:m])
    T.finish_loud(f"{TH}/after", L, R, -17.0, 1.5, 0.89)
    return L, R


def plot(path, name, ogg):
    """A spectrogram (log frequency, 30 Hz to 18 kHz) over the envelope (dB, the loudest 50 ms window at the top)."""
    import subprocess
    from PIL import Image, ImageDraw
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", ogg, "-f", "f32le", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    ch = 2 if "stereo" in subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channel_layout", "-of", "csv=p=0", ogg], capture_output=True, text=True).stdout else 1
    xs = np.frombuffer(raw, dtype=np.float32).reshape(-1, ch)
    x = xs.mean(axis=1)
    pk = 20 * np.log10(np.abs(xs).max() + 1e-12)
    size, hop = 2048, 256
    frames = max(1, (len(x) - size) // hop)
    win = np.hanning(size)
    W, H, Hs = 900, 260, 120
    spec = np.array([np.abs(np.fft.rfft(x[i * hop:i * hop + size] * win)) for i in range(frames)])
    db = 20 * np.log10(spec + 1e-7)
    freqs = np.fft.rfftfreq(size, 1 / SR)
    ys = np.exp(np.linspace(np.log(18000), np.log(30), H))
    fi = np.clip(np.searchsorted(freqs, ys), 0, len(freqs) - 1)
    xs = np.linspace(0, frames - 1, W).astype(int)
    img = db[xs][:, fi].T
    img = np.clip((img - (img.max() - 80)) / 80, 0, 1)
    rgb = np.stack([img ** 0.7, img ** 1.6, (1 - img) * img * 2.5 + img ** 3], axis=2)
    im = Image.new("RGB", (W, H + Hs + 20), (12, 12, 16))
    im.paste(Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)), (0, 0))
    d = ImageDraw.Draw(im)
    w50 = int(0.05 * SR)
    env = np.array([np.sqrt(np.mean(x[i:i + w50] ** 2) + 1e-12) for i in range(0, max(len(x) - w50, 1), w50 // 2)])
    edb = 20 * np.log10(env)
    pts = [(int(i / len(edb) * W), H + 10 + int(np.clip(-(e - edb.max()) / 60, 0, 1) * Hs)) for i, e in enumerate(edb)]
    d.line(pts, fill=(120, 220, 255))
    for s in range(int(len(x) / SR) + 1):
        xx = int(s * SR / len(x) * W)
        d.line([(xx, H), (xx, H + 8)], fill=(200, 200, 200))
    d.text((5, 3), f"{name}  {len(x) / SR:.2f} s  peak {pk:.2f} dBFS  loudest 400 ms {20 * np.log10(T.loudest(x.astype(np.float64)) + 1e-12):.1f} dB", fill=(255, 255, 255))
    im.save(path)


BUILD = {"wake": wake, "punch1": lambda: punch(1), "punch2": lambda: punch(2), "punch3": lambda: punch(3), "bloom": bloom,
         "resonance": resonance, "shatter": shatter, "tinkle": tinkle, "after": after}


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
            a.plots.mkdir(parents=True, exist_ok=True)
            plot(a.plots / f"{name}.png", name, f"{a.out}/assets/orbital/sounds/{TH}/{name}.ogg")
    # the events, added to sounds.json beside the others (which are left as they are)
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    sounds = json.loads(path.read_text())
    for name in NAMES:
        ev = f"{TH}.{name}"
        sounds[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
    path.write_text(json.dumps(sounds, indent=2))


if __name__ == "__main__":
    main()
