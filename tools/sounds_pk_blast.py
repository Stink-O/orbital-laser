"""The Planet Killer's two hardest hits, built to be clean: the crack of a bolt connecting to the ring, and the huge
explosion of the land bursting (its building blocks serve the fusion and the ring's collapse too).

Everything is synthesised here from noise, pulses and filters; nothing is sampled. The explosion's spectrum over time is
driven by a table of octave-band levels (`BLAST_DB`) that was *measured* on a recording of a real, very large
explosion (the shape and balance, not the sound: no audio from it is in this repo).

What makes a crack sound sharp and what makes one sound sloppy:
 - nothing may come before it: no zero-phase (FFT) filtering of the transient itself (it rings *ahead* of the hit), no
   reverb on it, no compressor with a slow attack after it, and a short silence just before, so the ear gets the onset;
 - it is built from a few distinct parts that start together and die at their own speeds (a hard click, a sizzling
   body, a fast electric chirp, a low thwack), not a pile of noise bursts;
 - the long tail after it is smooth thunder and a few separate crackles, kept low enough to not bury it.
"""
from contextlib import contextmanager
import numpy as np
import soundlib
from soundlib import SR, tt, white, band, smooth_noise, thump
import sounds_themes as T


@contextmanager
def seeded(seed):
    """Draw this sound's randomness from its own stream, so changing it leaves every other sound's draws as they were."""
    st = soundlib.rng.bit_generator.state
    soundlib.rng.bit_generator.state = np.random.default_rng(seed).bit_generator.state
    try:
        yield
    finally:
        soundlib.rng.bit_generator.state = st


def rng():
    return soundlib.rng


def ramp_in(n, k0, k=24):
    """A gate that is 0 before sample k0 and eased in over k samples (the shortest possible onset without a DC step)."""
    g = np.zeros(n)
    g[k0:] = 1.0
    k = min(k, n - k0)
    g[k0:k0 + k] = np.linspace(0, 1, k, endpoint=False)
    return g


# ===================================================================================  the bolt connecting to the ring
def tick(n, k0, amp, tau, polarity=1.0):
    """One distinct electric tick: a bipolar spike (up, then through zero and back), `tau` seconds long."""
    m = int(tau * SR * 8) + 4
    s = np.arange(m) / SR
    p = np.exp(-s / tau) * polarity
    p = p - np.concatenate([[0.0], p[:-1]])                  # first difference: loses the DC, leaves the sharp edge
    out = np.zeros(n)
    m = min(m, n - k0)
    if m > 0:
        out[k0:k0 + m] += p[:m] * amp
    return out


def ticks_poisson(n, t_lo, t_hi, rate_fn, amp_fn, tau_lo=0.00025, tau_hi=0.0007):
    """Distinct ticks at random times with a rate that varies (a thinning process): crackle you can count, not a bed of
    noise."""
    out = np.zeros(n)
    peak = max(rate_fn(t_lo), rate_fn(t_hi), rate_fn((t_lo + t_hi) / 2)) * 1.5
    t = t_lo
    while True:
        t += rng().exponential(1.0 / peak)
        if t >= t_hi:
            break
        if rng().random() > rate_fn(t) / peak:
            continue
        k0 = int(t * SR)
        if k0 >= n - 40:
            break
        a = min(rng().pareto(2.2) * 0.5 + 0.35, 2.5) * amp_fn(t)
        out += tick(n, k0, a, rng().uniform(tau_lo, tau_hi), rng().choice([-1.0, 1.0]))
    return out


def bolt_leader(n, creep, shoot, take):
    """A bolt feeling its way out (0 to `creep`): ticks, sparse at first, quickening and louder; then, until `shoot`, a
    short rising zip. Quiet beside the strike: seven of these overlap, and they must stay a few separate ticks, not a
    wash of noise."""
    t = np.arange(n) / SR
    x = ticks_poisson(n, 0.03, creep, lambda u: 5 + 38 * (u / creep) ** 2, lambda u: 0.06 + 0.16 * (u / creep) ** 1.5, 0.0003, 0.0009)
    zl = int((shoot - creep) * SR)
    k0 = int(creep * SR)
    zip_ = band(white(zl / SR + 0.001), 900, 9000)[:zl]
    sweep = np.linspace(0, 1, zl)
    zip_ = zip_ * sweep ** 2 * 0.07
    x[k0:k0 + zl] += zip_
    return x


def bolt_crack(n, k0, take):
    """The strike itself: starts at sample k0 at full level, in a few parts that start together.
     click  : the first millisecond: a bright pulse, the edge
     snap   : 1.5-10 kHz noise, gone in ~5 ms: the sharpness
     zap    : a quick electric chirp falling from a few kHz: what makes it lightning and not a gunshot
     body   : 200-1500 Hz noise, ~25 ms: weight
     thwack : a damped low tone dropping fast, the blow you feel
     sub    : a slow low thump under it
    Distinct per take (the chirp's start, the thwack's pitch and the body's decay differ) so two cracks close together are
    not the same waveform twice."""
    t = np.arange(n) / SR - k0 / SR
    on = (t >= 0)
    g = ramp_in(n, k0, 6)
    u = np.maximum(t, 0)
    w = soundlib.rng.standard_normal(n)
    # (stationary noise filtered first, gated after: the gate is the onset, nothing rings before it)
    snap = band(w, 1500, 10000, 2) * np.exp(-u / (0.0028 + 0.0004 * take))
    hiss = band(soundlib.rng.standard_normal(n), 5000, 16000, 2) * np.exp(-u / 0.0012)
    tc = (0.0003, 0.00042, 0.00055)[take - 1]
    cw = soundlib.rng.standard_normal(n)
    click = (cw - np.roll(cw, 1)) * np.exp(-u / tc) * 0.55         # (differenced noise: bright, DC-free, different every take)
    f0 = (6200, 5200, 4300)[take - 1]
    ph = 2 * np.pi * np.cumsum(f0 * np.exp(-u / 0.009) + 700.0 * on) / SR
    zap = np.sin(ph) * np.exp(-u / 0.007) * np.minimum(u / 0.0004, 1.0)
    body = band(soundlib.rng.standard_normal(n), 220, 1600, 2) * np.exp(-u / (0.014 + 0.003 * take))
    fth = (240, 185, 140)[take - 1]
    th_ph = 2 * np.pi * np.cumsum(fth * (0.5 + 0.5 * np.exp(-u / 0.02)) * on) / SR
    thwack = np.sin(th_ph) * np.exp(-u / (0.04 + 0.01 * take)) * np.minimum(u / 0.0015, 1.0)
    sub = thump(n, k0 / SR, (78, 62, 50)[take - 1], (38, 31, 26)[take - 1], 0.2, 8.0) * np.minimum(u / 0.004, 1.0)
    x = (click * 1.6 + snap * 1.5 + hiss * 0.45 + zap * 0.30 + body * 0.9 + thwack * 0.6 + sub * 0.5) * g
    return x


def bolt_thunder(n, k0, take, length=5.0):
    """The roll after the crack: deep, smooth, arriving over ~70 ms (after the crack, never with it), the stretches of
    the bolt coming in one after another as clumps that die away, darkening; a whisper of mid on top of it early."""
    d = n / SR
    t = np.arange(n) / SR
    u = np.maximum(t - k0 / SR, 0)
    on = (t >= k0 / SR)
    rise = 1 - np.exp(-u / 0.06)
    clumps = np.zeros(n)
    for k in range(7):
        # (the stretches of the bolt arriving one after another: spaced out in order, each a little quieter and wider, and
        # jittered, so the opening of the roll is about as loud take to take)
        c = (0.1 + 0.2 * k ** 1.35) * rng().uniform(0.85, 1.15) * length / 5.0
        w = (0.14 + 0.05 * k) * rng().uniform(0.85, 1.15)
        clumps += np.exp(-0.5 * ((u - c) / w) ** 2) * (0.95 - 0.09 * k) * rng().uniform(0.85, 1.0) * np.exp(-c / (length * 0.33))
    low = T.unit(band(soundlib.rng.standard_normal(n), 24, 120, 2))
    mid = T.unit(T.lowpass_glide(band(soundlib.rng.standard_normal(n), 120, None, 2), 700, 130, curve=0.5))
    env = rise * np.exp(-u / (length * 0.3)) * on
    shape = 0.45 + clumps
    x = (low * 0.9 + mid * 0.45 * np.exp(-u / 0.9)) * env * shape
    return x


def bolt_hum(n, k0, take):
    """The crackle settling into the ring's hum: a buzz that comes up under the crackle and eases out as `arcs` carries it."""
    d = n / SR
    t = np.arange(n) / SR
    u = np.maximum(t - k0 / SR, 0)
    on = (t >= k0 / SR)
    f = 98.0 + 3.0 * (take - 2)
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.006 * smooth_noise(d, 0.8, n))) / SR
    buzz = T.unit(band(soundlib.rng.standard_normal(n), 160, 3000, 2)) * (0.5 + 0.5 * np.sin(ph)) ** 5
    env = np.clip(u / 0.35, 0, 1) ** 1.5 * np.exp(-np.maximum(u - 0.9, 0) / 1.1) * on
    return buzz * env


def bolt_connect(take, creep=1.0, shoot=1.14, d=8.4):
    """One take of the bolt: mono (positional). `shoot` is where it connects (the strike's own timing)."""
    n = int(SR * d)
    k0 = int(shoot * SR)
    t = np.arange(n) / SR
    lead = bolt_leader(n, creep, shoot, take)
    # (a held breath: the last 12 ms before the strike is silent, so the crack has an edge to start from)
    gate = np.ones(n)
    k_ = int(0.012 * SR)
    gate[k0 - k_:k0] = np.linspace(0.35, 0.0, k_) ** 1.5
    lead = lead * gate
    crack = bolt_crack(n, k0, take)
    # (the crack's highest spikes eased down, so every take peaks alike and the sound's level, set by its peak, is the same
    # take to take: the random spikes of the noise in it would otherwise make one take a few dB quieter than another)
    crack = 2.8 * np.tanh(crack / 2.8)
    # crackle after it: separate ticks, thinning out as the roll takes over
    crk = ticks_poisson(n, shoot + 0.004, shoot + 2.2, lambda u: 420 * np.exp(-(u - shoot) / 0.28) + 18, lambda u: 0.5 * np.exp(-(u - shoot) / 0.9) + 0.03, 0.00025, 0.0008)
    thunder = bolt_thunder(n, k0, take)
    # the land answering: two dull echoes of the strike (off the ground and a far slope), well after it, so they read as
    # echoes and never as a smeared onset
    echo = np.zeros(n)
    for dt, gn, fc in ((0.042, 0.16, 1800), (0.118, 0.10, 900), (0.27, 0.06, 500)):
        k = k0 + int(dt * SR)
        seg = band(crack[k0:k0 + int(0.12 * SR)], None, fc, 2)
        m = min(len(seg), n - k)
        echo[k:k + m] += seg[:m] * gn
    low = band(thunder, None, 1100, 2)
    # the thunder (not the crack) through a little of the land's reverb
    wet = T.convolve_wet(low * 0.0 + thunder, T.outdoor_ir(3.0, density=22.0, darken=(2200, 130), decay=1.2), 0.28)[:n]
    hum = bolt_hum(n, k0, take)
    x = lead * 1.0 + crack * 1.0 + crk * 0.3 + echo + wet * 0.11 + hum * 0.14
    return x


def _decoded_peak(path):
    import subprocess
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return float(np.max(np.abs(np.frombuffer(raw, dtype="<f4"))))


def write_ogg(path, x, channels=1):
    import subprocess, wave, os
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path + ".wav", "wb") as w:
        w.setnchannels(channels); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-c:a", "libvorbis", "-q:a", "7", path + ".ogg"], check=True)
    os.remove(path + ".wav")


def finish_bolt(name, x, db=-15.0, peak=0.912, tail_fade=0.6):
    """Mono out for a bolt: every take's loudest 400 ms at `db` (so the three takes sit at one level, whatever their random
    draw), its peak -- the crack -- held at `peak` (decoded, about -0.8 dBFS) by the look-ahead limiter, which has next to
    nothing to do when the crack is already the peak."""
    x = x - np.mean(x)
    m = x
    w, h = int(0.4 * SR), int(0.1 * SR)
    lo = max(np.sqrt(np.mean(m[i:i + w] ** 2)) for i in range(0, max(len(m) - w, 1), h))
    x = x * (10 ** (db / 20) / lo)
    nf = int(tail_fade * SR)
    path = f"{soundlib.OUT}/assets/orbital/sounds/{name}"
    c = peak
    for _ in range(4):
        y = limit(x[:, None], c)[:, 0]
        y[-nf:] *= np.linspace(1, 0, nf)
        write_ogg(path, y)
        got = _decoded_peak(path + ".ogg")
        if abs(got / peak - 1) < 0.004:
            break
        c = min(c * peak / got, 0.999)
    mm = y
    lo2 = max(np.sqrt(np.mean(mm[i:i + w] ** 2)) for i in range(0, max(len(mm) - w, 1), h))
    print(f"wrote {name:9s} {len(x) / SR:5.2f}s  mono    decoded peak {20 * np.log10(got):.2f} dBFS  loudest {20 * np.log10(lo2):.1f} dB")


def finish_peak(name, x, peak=0.912, tail_fade=0.6):
    """Mono sound out with its *decoded* peak at `peak` (0.912 is -0.8 dBFS), no squashing at all, so a crack stays as sharp
    as it was built. A hard click loses a few dB in the Vorbis encoder, so the file is encoded, decoded, measured and its
    gain corrected (once or twice) until what the game plays peaks where it should."""
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9)
    nf = int(tail_fade * SR)
    x[-nf:] *= np.linspace(1, 0, nf)
    path = f"{soundlib.OUT}/assets/orbital/sounds/{name}"
    g = peak
    for _ in range(4):
        write_ogg(path, x * g)
        got = _decoded_peak(path + ".ogg")
        if abs(got / peak - 1) < 0.004:
            break
        g = min(g * peak / got, 0.999)
    print(f"wrote {name:9s} {len(x) / SR:5.2f}s  mono    decoded peak {20 * np.log10(got):.2f} dBFS")


# =====================================================================================  the land bursting: a huge explosion
OCT = np.array([31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
# What a very large explosion sounds like as a recording has it, measured on a reference clip: the level of each octave
# band (dB, against the loudest stretch) in the stretches 0-0.05 s, 0.05-0.3, 0.3-1, 1-3, 3-8, 8-12 and 12-16 s after the
# blast (given at the middle of each, in seconds). Dominated by 63-125 Hz throughout; the first 50 ms is broadband (the
# crack: 125 Hz to 1 kHz within 4 dB of each other); after it the top falls away fast (4 kHz is 13 dB down at 0.3 s, 25 dB
# at 3 s) and the sub swells in over a second or two; the whole thing holds near its peak level for about ten seconds.
# (Bumps in the 1-2 kHz octaves that came from something other than the blast are smoothed out.)
BLAST_T = np.array([0.0, 0.025, 0.175, 0.65, 2.0, 5.5, 10.0, 14.0, 19.0, 24.0])
BLAST_DB = np.array([
    [-21.7, -9.3, -4.7, -8.3, -8.3, -8.8, -13.8, -20.6, -28.9, -47.4],
    [-21.7, -9.3, -4.7, -8.3, -8.3, -8.8, -13.8, -20.6, -28.9, -47.4],
    [-18.5, -5.3, -8.8, -13.3, -18.3, -21.3, -27.0, -31.6, -35.5, -44.9],
    [-13.4, -7.3, -8.6, -17.1, -22.3, -24.4, -29.9, -36.2, -44.2, -55.7],
    [-11.8, -6.6, -10.6, -19.0, -24.1, -30.1, -37.1, -46.0, -53.9, -62.6],
    [-15.6, -8.4, -8.8, -15.7, -24.1, -29.9, -37.0, -40.5, -48.4, -63.3],
    [-17.9, -12.1, -9.9, -20.1, -24.9, -30.0, -38.0, -39.1, -50.5, -64.9],
    [-20.7, -15.1, -17.3, -22.6, -30.8, -32.0, -36.0, -42.3, -47.1, -62.0],
    [-27.0, -21.0, -23.0, -29.0, -37.0, -41.0, -45.0, -52.0, -58.0, -70.0],
    [-45.0, -40.0, -42.0, -48.0, -56.0, -60.0, -66.0, -72.0, -78.0, -90.0]])
# The synthesis needs a little different from what was measured to *measure* the same (the crack and the body overlap in
# time, the debris adds mid): this trim, in dB, per row and octave, was found by measuring the finished sound with the same
# code that measured the reference and adjusting until they agreed (it comes to a couple of dB rms against the measurements).
BLAST_TRIM = np.array([
    [-11.0,  -1.7,   2.1,  -0.7,  -1.5,  -0.9,  -0.9,  -0.1,  -0.3,  -2.5],
    [-11.0,  -1.7,   2.1,  -0.7,  -1.5,  -0.9,  -0.9,  -0.1,  -0.3,  -2.5],
    [  1.8,   4.6,   1.8,  -1.0,  -2.4,  -3.9,  -4.3,  -2.0,   2.5,   5.7],
    [  2.1,   2.5,   1.5,  -1.4,  -2.6,  -0.0,   3.1,   3.4,   1.0,  -1.5],
    [  1.9,   1.2,  -1.4,  -3.7,  -4.7,  -3.6,  -2.2,  -2.9,  -2.7,  -0.2],
    [ -2.2,   0.2,   0.9,   0.1,  -0.0,  -0.1,   0.5,   2.6,   3.2,   1.9],
    [ -0.2,   1.8,   2.5,   0.2,  -0.4,  -0.2,   0.0,   1.5,   0.7,  -0.6],
    [  0.9,   1.6,   0.5,  -0.5,  -0.5,   1.6,   2.7,   2.4,   2.5,   1.4],
    [  0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0],
    [  0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0]])
# how alike the two ears are, by octave: the lows are one sound dead centre, the top is wide (measured: S/M -27 dB at
# 31-60 Hz, -22 dB at 60-200, -16 at 200-800, -19 at 1-3k, -5.5 at 3-10k)
BLAST_CORR = np.array([1.0, 1.0, 0.99, 0.97, 0.95, 0.95, 0.85, 0.55, 0.4, 0.3])


def shaped_noise(d, times, table, size=4096, hop=1024, corr=BLAST_CORR, stereo=True, wander=0.0, wander_rate=1.2, wander_from=0.0):
    """Noise whose octave-band levels follow `table` (dB, one row per time in `times`) over time, built frame by frame in
    the spectrum (random phase, so it is noise, nothing that rings), a left and right that are as alike as `corr` says per
    octave. Level is the octave's own RMS: equal dB in every octave is pink noise. Returns (L, R) (both the same when
    not `stereo`)."""
    n = int(SR * d)
    f = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    loct = np.log2(OCT)
    # (extend each row past the table's ends: -12 dB/octave below 31 Hz, -24 dB/octave above 16 kHz)
    xs = np.concatenate([[np.log2(8.0), np.log2(16.0)], loct, [np.log2(22050.0)]])
    cc = np.sqrt(np.interp(lf, loct, corr))
    ss = np.sqrt(1 - cc ** 2)
    win = np.hanning(size)
    L = np.zeros(n + 2 * size); R = np.zeros(n + 2 * size)
    # (each octave's level wanders a few dB on its own, slowly, as a real blast's rolls and surges do; it averages out)
    wob = [wander * 2.2 * smooth_noise(d, wander_rate, n) for _ in OCT] if wander > 0 else None
    for start in range(-size, n, hop):
        tc = (start + size / 2) / SR
        row = np.array([np.interp(tc, times, table[:, k]) for k in range(table.shape[1])])
        if wob is not None:
            row = row + np.array([w[min(max(int(tc * SR), 0), n - 1)] for w in wob]) * np.clip((tc - wander_from) / 1.2, 0, 1)
        ys = np.concatenate([[row[0] - 24, row[0] - 12], row, [row[-1] - 24 * (np.log2(22050) - loct[-1])]])
        db = np.interp(lf, xs, ys)
        mag = 10 ** (db / 20) / np.sqrt(np.maximum(f, 20.0) / 1000.0)
        mag[0] = 0
        z = lambda: (rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))) / np.sqrt(2)
        zc = z()
        if stereo:
            zl, zr = cc * zc + ss * z(), cc * zc + ss * z()
        else:
            zl = zr = zc
        sl = np.fft.irfft(mag * zl, size) * win
        sr_ = np.fft.irfft(mag * zr, size) * win
        a = start + size
        L[a:a + size] += sl; R[a:a + size] += sr_
    k = np.sqrt(size / 2) / np.sqrt(1.5) * 0.7071
    return L[size:size + n] * k, R[size:size + n] * k


def explosion(d, t0, stretch=1.0, crack=1.5, debris=1.0, table=None, ctable=None):
    """A huge explosion starting at `t0` in a `d`-second stereo sound, before any mastering.
     crack  : the first ~50 ms, broadband and hard (its own fast spectrum), the front of the shock
     body   : the roar, shaped over time by the measured table (63-125 Hz heavy, the top dying fast, the sub swelling in
              over a second or two, holding its level for seconds), its two ears alike in the lows and wide up top
     thump  : the pressure wave, a very low, very short push you feel in the chest
     debris : rock and earth thrown up coming down, thuds and clacks, in surges
    `stretch` scales the time the roar holds and dies over (1 = as measured: ten seconds), for the smaller hits."""
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0.0)
    k0 = int(t0 * SR)
    on = ramp_in(n, k0, 10)
    # the roar's table, shifted to start at t0 and stretched after its first second
    tt_ = np.where(BLAST_T <= 0.65, BLAST_T, 0.65 + (BLAST_T - 0.65) * stretch) + t0
    tab = BLAST_DB + BLAST_TRIM if table is None else table
    body_tab = np.vstack([tab[0] - 40.0, tab])
    bl, br = shaped_noise(d, np.concatenate([[t0 - 0.1], tt_]), body_tab, 4096, 1024, wander=2.4 * min(1.0, stretch + 0.3), wander_from=t0)
    # (the crack at its own, fast, resolution)
    ct = np.array([0.0, 0.012, 0.03, 0.06, 0.12, 0.3])
    c0 = tab[1]
    ctab = np.vstack([c0 + 8.0, c0 + 2.0, c0 - 4.0 + np.array([0, 0, 0, 0, -2, -4, -6, -8, -10, -12]), tab[2] - 2.0, tab[2] - 8.0, tab[3] - 14.0]) if ctable is None else ctable
    cl, cr = shaped_noise(d, ct + t0, ctab, 256, 64)
    # slow surges in the roar (a few dB), different in each ear a little
    surge = 1.0 + 0.22 * smooth_noise(d, 0.9, n)
    # (the crack driven into a soft clip, as a microphone overloaded by a blast does: far denser for the same peak, so
    # the limiter at the end does not leave it quieter than the roar that follows it)
    cs = np.sqrt(np.mean(cl[k0:k0 + int(0.03 * SR)] ** 2) + 1e-12)
    cl = np.tanh(cl / cs * 1.2) * cs / 1.2 * 1.25
    cr = np.tanh(cr / cs * 1.2) * cs / 1.2 * 1.25
    L = bl * surge * 1.0 + cl * crack * np.exp(-u / 0.05)
    R = br * surge * 1.0 + cr * crack * np.exp(-u / 0.05)
    # the pressure wave: a very low shove, the same in both ears
    shove = soundlib.rng.standard_normal(n)
    shove = band(shove, 14, 50, 2) * np.exp(-u / 0.42) * np.minimum(u / 0.006, 1.0)
    shove = T.unit(shove) * 0.8
    L = L + shove * 0.0; R = R + shove * 0.0
    # rock and earth thrown up coming down: thuds and clacks, thickest early
    if debris > 0:
        deb = T.debris_settle(d, t0 + 0.25, amount=1.5 * debris, spread=8.0 * stretch)
        deb = band(deb, None, 1800, 2)
        L = L + deb * 0.085; R = R + deb * 0.085
    return L * on, R * on


def limit(x, ceiling, look=0.0015, release=0.15):
    """A look-ahead peak limiter (the same gain on every channel): the gain dips in time for each peak and recovers over
    `release` seconds, so peaks are brought under `ceiling` without the distortion of clipping them."""
    a = np.max(np.abs(x), axis=1)
    g = np.minimum(1.0, ceiling / np.maximum(a, 1e-9))
    w = max(int(look * SR), 2)
    gp = np.pad(g, (w, w), constant_values=1.0)
    win = np.lib.stride_tricks.sliding_window_view(gp, 2 * w + 1)
    g = win.min(axis=1)[: len(g)]
    k = np.exp(-1.0 / (release * SR))
    out = np.empty_like(g)
    s = 1.0
    for i, v in enumerate(g):
        s = v if v < s else 1.0 - (1.0 - s) * k
        out[i] = min(s, v)
    ma = np.convolve(np.pad(out, (w, w), mode="edge"), np.ones(2 * w + 1) / (2 * w + 1), mode="valid")
    return x * ma[:, None]


def finish_blast(name, L, R, db=-8.0, ceiling=0.905, tail_fade=0.8):
    """Stereo out: its loudest 400 ms at `db` dB (as the other big hits are measured), peaks held under `ceiling` by the
    limiter (0.905 leaves the encoder room: the decoded file peaks at about -0.8 dBFS)."""
    n = max(len(L), len(R))
    x = np.stack([np.pad(L - L.mean(), (0, n - len(L))), np.pad(R - R.mean(), (0, n - len(R)))], axis=1)
    m = x.mean(axis=1)
    w, h = int(0.4 * SR), int(0.1 * SR)
    target = 10 ** (db / 20)
    gain = target / max(np.sqrt(np.mean(m[i:i + w] ** 2)) for i in range(0, max(n - w, 1), h))
    for _ in range(3):
        y = limit(x * gain, ceiling)
        m = y.mean(axis=1)
        got = max(np.sqrt(np.mean(m[i:i + w] ** 2)) for i in range(0, max(n - w, 1), h))
        gain *= target / got
        if abs(20 * np.log10(target / got)) < 0.05:
            break
    y = limit(x * gain, ceiling)
    nf = int(tail_fade * SR)
    y[-nf:] *= np.linspace(1, 0, nf)[:, None]
    write_ogg(f"{soundlib.OUT}/assets/orbital/sounds/{name}", y, 2)
    print(f"wrote {name:9s} {n / SR:5.2f}s  stereo  loudest {db:.1f} dB  peak {20 * np.log10(np.abs(y).max()):.2f} dBFS (before the encoder)")
