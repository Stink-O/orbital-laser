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


# ==============================================================  the land bursting, with depth: the explosion as it moves
# What `explosion` lacked, measured against the reference with the same code (numbers: reference / `explosion` as fire.ogg
# had it / this, as fire.ogg has it now):
#  - its mids and top were a smooth wash: the share of the 0.8-3 kHz band envelope's movement (1-5.5 s) faster than 2 Hz
#    67 % / 17 % / 42 %, of the 3-10 kHz band's 70 % / 12 % / 30 %; transients a second standing 6 dB out of the 0.8-3
#    and 3-10 kHz bands 1.2 and 1.0 / 0 and 0 / 2.1 and 2.5; in 60-200 Hz 2.9 / 2.1 / 3.7, in 200-800 Hz 1.7 / 0.8 / 1.5;
#    spectral flux 1.0 / 0.87 / 1.0;
#  - one onset and nothing after it: the reference cracks again 30, 140 and 250 ms after the first (found here at 20,
#    170 and 270 ms); its first 50 ms stood 6.5 dB over the roar at 1-3 s / 2.1 / 4.2;
#  - a stereo image that never moved: width (S/M) at 0-1, 1-4 and 4-8 s -26, -20, -24 dB / -20, -26, -26 / -21, -21,
#    -24, and how much it varies over time (250 ms windows) 5.1 dB / 1.7 / 3.4;
#  - no sub-bass blow of its own (the pressure shove was in at zero), and rock coming down in one mono layer.
# So the roar now moves (its colour tilts, three resonances in it drop in pitch as the pressure wave passes and then
# wander, its top boils in uneven little surges, its lows heave in lumps, it drifts across the field, a lowpass over it
# all closes and opens again as the pressure wave rolls past) and things happen inside it: the crack and the cracks after
# it, the land's early reflections, aftershocks going off round it, rolls of thunder low down, fits of crackle, rock
# raining back down all round, and the whole front coming back off distant hills, duller the later it arrives.
def shaped_noise_moving(d, times, table, controls, size=4096, hop=1024, corr=BLAST_CORR):
    """`shaped_noise`, with each frame's spectrum also moved by `controls(tc, lf)` -> (dB for both ears, dB the left ear
    has over the right, how far the ears' likeness is eased toward independent (0-1)), `lf` the log2 frequencies."""
    n = int(SR * d)
    f = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    loct = np.log2(OCT)
    xs = np.concatenate([[np.log2(8.0), np.log2(16.0)], loct, [np.log2(22050.0)]])
    cc0 = np.sqrt(np.interp(lf, loct, corr))
    win = np.hanning(size)
    L = np.zeros(n + 2 * size); R = np.zeros(n + 2 * size)
    for start in range(-size, n, hop):
        tc = (start + size / 2) / SR
        row = np.array([np.interp(tc, times, table[:, k]) for k in range(table.shape[1])])
        ys = np.concatenate([[row[0] - 24, row[0] - 12], row, [row[-1] - 24 * (np.log2(22050) - loct[-1])]])
        db = np.interp(lf, xs, ys)
        both, side, loosen = controls(tc, lf)
        db = db + both
        mag = 10 ** (db / 20) / np.sqrt(np.maximum(f, 20.0) / 1000.0)
        mag[0] = 0
        cc = cc0 * (1 - loosen)
        ss = np.sqrt(1 - cc ** 2)
        z = lambda: (rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))) / np.sqrt(2)
        zc = z()
        zl, zr = cc * zc + ss * z(), cc * zc + ss * z()
        gl, gr = 10 ** (side / 40), 10 ** (-side / 40)
        a = start + size
        L[a:a + size] += np.fft.irfft(mag * gl * zl, size) * win
        R[a:a + size] += np.fft.irfft(mag * gr * zr, size) * win
    k = np.sqrt(size / 2) / np.sqrt(1.5) * 0.7071
    return L[size:size + n] * k, R[size:size + n] * k


def track(n, t0, pts):
    """A curve over `n` samples through (seconds after t0, value) points, held at its ends."""
    ts, vs = zip(*pts)
    return np.interp(np.arange(n) / SR - t0, ts, vs)


def burst(n, k0, tau, lo, hi, tau_lo=None):
    """A short broadband slam starting hard at sample k0: noise filtered first and gated after, so nothing comes before
    it; its low part (under `lo`) dies over `tau_lo`, the rest over `tau`."""
    u = np.maximum(np.arange(n) - k0, 0) / SR
    g = ramp_in(n, k0, 8)
    w = rng().standard_normal(n)
    x = band(w, lo, hi, 2) * np.exp(-u / tau)
    if tau_lo:
        x += band(rng().standard_normal(n), 30, lo, 2) * np.exp(-u / tau_lo) * 0.8
    return x * g


def pan2(x, p):
    a = (p + 1) * np.pi / 4
    return x * np.cos(a) * 1.4142, x * np.sin(a) * 1.4142


def delay_into(L, R, x, dt, gain, p, lo=None, hi=None):
    """`x` added `dt` seconds late, filtered, panned (an echo or a reflection: always well after what it echoes, so the
    filter's ringing never comes before the sound it belongs to)."""
    k = int(dt * SR)
    m = min(len(x), len(L) - k)
    if m <= 0:
        return
    y = band(x[:m], lo, hi, 2) if (lo or hi) else x[:m]
    l, r = pan2(y * gain, p)
    L[k:k + m] += l; R[k:k + m] += r


def lowpass_track(x, fc, size=2048, hop=512):
    """`x` through a lowpass (12 dB/octave) whose cutoff follows the curve `fc` (Hz per sample): air taking the top off
    a sound as it travels further, frame by frame and overlap-added."""
    n = len(x)
    win = np.hanning(size)
    out = np.zeros(n + size); norm = np.zeros(n + size)
    xp = np.concatenate([x, np.zeros(size)])
    freqs = np.fft.rfftfreq(size, 1 / SR)
    for start in range(0, n, hop):
        c = fc[min(start + size // 2, n - 1)]
        g = 1 / np.sqrt(1 + (freqs / c) ** 4)
        out[start:start + size] += np.fft.irfft(np.fft.rfft(xp[start:start + size] * win) * g, size) * win
        norm[start:start + size] += win ** 2
    return out[:n] / np.maximum(norm[:n], 1e-3)


def aftershock(n, t1, size, far):
    """One secondary blast inside the roar (a pocket of the land going up, a slab collapsing): a deep blow with a
    falling pitch, a dull burst of rock and a fit of crackle; `far` (0-1) darkens and softens it. Mono."""
    k = int(t1 * SR)
    u = np.maximum(np.arange(n) / SR - t1, 0)
    on = np.arange(n) >= k
    blow = soundlib.thump(n, t1, rng().uniform(55, 75), rng().uniform(26, 34), 0.25 + 0.3 * size, 5.0) * np.minimum(u / 0.003, 1)
    blow += soundlib.thump(n, t1, rng().uniform(120, 160), rng().uniform(60, 80), 0.05 + 0.05 * size, 12.0) * np.minimum(u / 0.002, 1) * 0.7
    body = burst(n, k, 0.06 + 0.12 * size, 120, 1500 * (1 - 0.5 * far), 0.18 + 0.25 * size)
    crk = T.crackle(n / SR, rate=1800, decay=0.0015, lo=300, hi=3500 * (1 - 0.5 * far), heavy=1.4) * np.exp(-u / (0.1 + 0.15 * size)) * on
    return (blow * 1.1 + body * 0.5 + crk * 0.2) * size


def debris_stereo(d, t0, amount=1.0, spread=7.0):
    """Rock and earth thrown up by the burst coming back down all round: thuds of clods and slabs, clacks of stone,
    gravel hissing down in surges, each landing somewhere of its own across the field (real stereo spread, the nearer
    ones louder and brighter). Starts about half a second after the burst, thickest two or three seconds in."""
    n = int(SR * d)
    t = np.arange(n) / SR
    L = np.zeros(n); R = np.zeros(n)
    for _ in range(int(160 * amount)):
        t1 = t0 + 0.5 + rng().gamma(2.2, spread * 0.17)
        if t1 > d - 0.4:
            continue
        near = rng().random() ** 1.5                                   # 0 far .. 1 near
        size = min(rng().pareto(2.0) * 0.4 + 0.1, 2.0)
        k0 = int(t1 * SR)
        if rng().random() < 0.65:
            m = min(int((0.12 + 0.35 * size) * SR), n - k0)
            x = T.thud(m, size) * size * 0.9
        else:
            m = min(int(0.25 * SR), n - k0)
            x = T.rock_clack(m, 0.0, min(size, 1.4)) * 0.8
        x = band(x, None, 1500 + 6000 * near, 2) * (0.35 + 0.65 * near) * np.exp(-(t1 - t0) / (spread * 0.6))
        l, r = pan2(x, rng().uniform(-0.85, 0.85))
        L[k0:k0 + m] += l; R[k0:k0 + m] += r
    rate = np.clip((t - t0 - 0.5) / 0.8, 0, 1) * np.exp(-np.maximum(t - t0 - 1.0, 0) / (spread * 0.35))
    for ch in (L, R):
        surge = (0.5 + 0.5 * smooth_noise(d, 3.5, n)) ** 2.5
        ch += T.unit(band(white(d), 1200, 7000)) * rate * surge * 0.05
        ch += T.unit(band(white(d), 250, 1200)) * rate * (0.5 + 0.5 * smooth_noise(d, 2.0, n)) ** 2 * 0.05
    return L, R


def thunder_rolls(d, t0, count=9, length=8.0):
    """The blast rolling off round the land: deep swells of rumble, each arriving on its own from somewhere, low and
    smooth, swelling and dying over a few tenths of a second. Stereo."""
    n = int(SR * d)
    t = np.arange(n) / SR
    L = np.zeros(n); R = np.zeros(n)
    base = T.unit(band(white(d), 28, 170, 2))
    for _ in range(count):
        c = t0 + 0.4 + length * rng().random() ** 1.4
        w = rng().uniform(0.12, 0.45)
        sh = np.where(t < c, np.exp(-0.5 * ((t - c) / (w * 0.1)) ** 2), np.exp(-(t - c) / w)) * rng().uniform(0.5, 1.0) * np.exp(-(c - t0) / (length * 0.5))
        l, r = pan2(base * sh, rng().uniform(-0.4, 0.4))
        L += l; R += r
    return L, R


def grains(d, rate, taus=(0.012, 0.025, 0.05)):
    """A curve of many little surges at random (a Poisson rate a second, sizes heavy-tailed, each rising in 2 ms and
    dying over one of `taus`), averaging 1: the uneven boil of a fireball's roar, not a regular wobble."""
    n = int(SR * d)
    out = np.zeros(n)
    for tau in taus:
        x = np.zeros(n)
        k = rng().poisson(rate * d / len(taus))
        np.add.at(x, rng().integers(0, n, k), np.minimum(rng().pareto(2.5, k) + 0.2, 6.0))
        s = np.arange(int(tau * SR * 6)) / SR
        kern = (1 - np.exp(-s / 0.002)) * np.exp(-s / tau)
        out += np.convolve(x, kern)[:n] / (tau * SR)
    return out / (np.mean(out) + 1e-9)


def explosion_deep(d, t0, stretch=0.65, parts=None):
    """The land bursting: a huge explosion at `t0` in a `d`-second stereo sound, before mastering, that moves.
     crack     : the first ~50 ms, broadband and hard, then three more cracks after it (as the measured blast has them,
                 30, 140 and 250 ms after the first), each further off to one side and duller
     reflections: the crack off the land round it, 9-100 ms later, from either side
     blow      : the pressure wave you feel: a sub-bass drop from 52 Hz down to 26, a short punch from 110 Hz down
                 that small speakers can play, and a rumble of 14-45 Hz under it
     roar      : the measured table's roar (63-125 Hz heavy, the top dying fast, the sub swelling in), now moving: its
                 colour tilting this way and that, three resonances in it sliding down in pitch over the first second or
                 so as the pressure wave passes (and wandering after), its top coming in fits, drifting across the field,
                 the ears' likeness loosening and tightening
     inside it : fits of crackle, aftershocks going off round it (each with its own echo), deep rolls of thunder, rock
                 and earth raining back down across the whole field
     distance  : the whole front coming back off distant hills (0.6-2.7 s, each later one duller and from another side),
                 its own clumpy outdoor tail in each ear, a lowpass that closes as the pressure wave rolls past and
                 opens again, and the air taking more of the top the longer it goes on
    `stretch` scales the time the roar holds (1 = the measured ten seconds). Each seed is its own take. Returns (L, R);
    `parts`, a dict, gets each layer (for measuring)."""
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0.0)
    k0 = int(t0 * SR)
    on = ramp_in(n, k0, 10)
    tab = BLAST_DB + BLAST_TRIM
    tt_ = np.where(BLAST_T <= 0.65, BLAST_T, 0.65 + (BLAST_T - 0.65) * stretch) + t0
    times = np.concatenate([[t0 - 0.1], tt_])
    body_tab = np.vstack([tab[0] - 40.0, tab])

    # ---- the roar, moving
    ctl_n = int(d * 50) + 2                                                    # control curves at 50 points a second
    sn = lambda rate: smooth_noise(d, rate, ctl_n)
    tilt = sn(0.6) * 1.4 + sn(1.7) * 0.6                                       # dB per octave about 150 Hz
    swing = sn(0.3)                                                            # drift across the field
    loose = 0.5 + 0.5 * sn(0.45)
    oct_wob = [sn(rng().uniform(0.8, 1.6)) * 2.5 for _ in range(len(OCT))]
    res = []                                                                   # (start Hz, end Hz, glide s, dB, width oct)
    for f_a, f_b, tau, g_db, w in ((440, 125, 0.55, 5.0, 0.32), (1500, 420, 0.8, 5.5, 0.4), (100, 47, 1.0, 4.5, 0.45)):
        res.append((f_a * rng().uniform(0.9, 1.1), f_b * rng().uniform(0.9, 1.1), tau, g_db, w, sn(0.5) * 0.3, 0.6 + 0.4 * sn(0.7)))
    loct = np.log2(OCT)

    def controls(tc, lf):
        i = int(np.clip(tc, 0, d - 1e-3) * 50)
        a = tc - t0
        ramp = np.clip(a / 0.35, 0, 1)                                         # nothing moves in the crack itself
        both = tilt[i] * ramp * (lf - np.log2(150.0))
        both = both + np.interp(lf, loct, [w[i] for w in oct_wob]) * ramp
        for f_a, f_b, tau, g_db, w, wan, swell in res:
            fc = f_b * (f_a / f_b) ** np.exp(-max(a, 0) / tau) * 2 ** wan[i]
            gg = g_db * swell[i] * np.clip(a / 0.05, 0, 1)
            both = both + gg * np.exp(-0.5 * ((lf - np.log2(fc)) / (w / 2.355)) ** 2)
        # (the first second: the roar's top held down, so the cracks stand out of it as they do in the measured blast)
        a2 = np.clip((a - 0.035) / 0.03, 0, 1) * np.clip((1.0 - a) / 0.5, 0, 1)
        both = both - 9.0 * a2 * np.clip((lf - np.log2(500.0)) / 1.5, 0, 1)
        # (what the resonances add on average taken back out of the low mids once the roar has settled, so its balance
        # stays the measured one)
        both = both - 3.5 * np.clip((a - 0.5) / 0.6, 0, 1) * np.exp(-0.5 * ((lf - np.log2(420.0)) / 0.7) ** 2)
        side = swing[i] * 2.0 * np.clip((lf - np.log2(180.0)) / 2.0, 0, 1) * ramp
        lo = 0.04 * loose[i] * np.clip((lf - np.log2(150.0)) / 2.5, 0, 1) * ramp
        return both, side, lo

    bl, br = shaped_noise_moving(d, times, body_tab, controls)
    # (its top boiling: the 300 Hz-and-up part gated by an uneven curve of little surges, nearly the same in both ears;
    # its lows heaving in lumps a few times a second, the same in both)
    grow = np.clip(u / 0.4, 0, 1)
    common = np.log(grains(d, 45.0) + 0.25) * 0.36 + smooth_noise(d, 2.5, n) * 0.25
    heave = np.exp((np.log(grains(d, 9.0, (0.03, 0.07, 0.15)) + 0.4) * 0.33 + smooth_noise(d, 1.2, n) * 0.2) * grow)
    out = []
    for ch in (bl, br):
        hi = band(ch, 300, None, 2)
        fits = np.exp((common + np.log(grains(d, 25.0) + 0.5) * 0.2) * grow)
        out.append((ch - hi) * heave / np.sqrt(np.mean(heave[k0:] ** 2)) + hi * fits / np.sqrt(np.mean(fits[k0:] ** 2)))
    # (held up as it goes on: what the layers above add early on would otherwise leave it dying away faster than the
    # measured blast, which holds within 3 dB for ten seconds)
    hold = track(n, t0, [(0.8, 1.0), (2.0, 1.3), (4.0, 1.5), (7.0, 1.8), (12.0, 1.8)])
    bl, br = out[0] * hold, out[1] * hold
    roar_lvl = np.sqrt(np.mean(((bl + br) / 2)[k0:k0 + int(1.0 * SR)] ** 2))

    # ---- the crack (as `explosion` builds it: the measured first 50 ms, soft-clipped as an overloaded microphone)
    ct = np.array([0.0, 0.012, 0.03, 0.06, 0.12, 0.3])
    c0 = tab[1]
    ctab = np.vstack([c0 + 8.0, c0 + 2.0, c0 - 4.0 + np.array([0, 0, 0, 0, -2, -4, -6, -8, -10, -12]), tab[2] - 2.0, tab[2] - 8.0, tab[3] - 14.0])
    cl, cr = shaped_noise(d, ct + t0, ctab, 256, 64)
    cs = np.sqrt(np.mean(cl[k0:k0 + int(0.03 * SR)] ** 2) + 1e-12)
    cl = np.tanh(cl / cs * 1.2) * cs / 1.2 * 1.25
    cr = np.tanh(cr / cs * 1.2) * cs / 1.2 * 1.25
    ce = np.exp(-u / 0.05) * 2.0 * (t >= t0)
    cpk = np.max(np.abs((cl + cr) / 2 * ce))
    front = (cl + cr) / 2 * ce                                                 # (mono, for the echoes)
    L = bl + cl * ce
    R = br + cr * ce
    keep = (lambda k, x: parts.__setitem__(k, parts.get(k, 0) + x)) if parts is not None else (lambda k, x: None)
    keep("roar", (bl + br) / 2); keep("crack", (cl + cr) / 2 * ce)
    # the cracks after it: 30, 140 and 250 ms (jittered per take), then a few smaller ones; each to one side, duller
    after_ = [(0.03, 1.0, -0.15, 3500), (0.14, 0.9, 0.25, 2800), (0.25, 0.75, -0.3, 2200)]
    for _ in range(4):
        after_.append((rng().uniform(0.33, 1.1), rng().uniform(0.25, 0.45), rng().uniform(-0.4, 0.4), rng().uniform(1200, 2500)))
    for dt, g, p, hi in after_:
        dt = dt * rng().uniform(0.85, 1.15) if dt < 0.3 else dt
        kk = k0 + int(dt * SR)
        x = burst(n, kk, rng().uniform(0.008, 0.02), 250, hi, rng().uniform(0.05, 0.12))
        # (soft-clipped as the first is, then each at its share of the first's peak)
        x = x / (np.sqrt(np.mean(x[kk:kk + int(0.03 * SR)] ** 2)) + 1e-12)
        x = np.tanh(x * 0.8) / np.max(np.abs(np.tanh(x * 0.8))) * cpk * g
        front += x
        keep("cracks after", x)
        l, r = pan2(x, p)
        L += l; R += r

    # ---- the blow: an instant push and a sub drop under it, the same in both ears
    # (no Friedlander pulse: nearly all of it is under 16 Hz, unheard, and a filter after it would ring ahead of the burst)
    blow = soundlib.thump(n, t0, 52, 26, 1.5, 2.2) * np.minimum(u / 0.004, 1) * 0.9
    blow += soundlib.thump(n, t0, 110, 55, 0.12, 9.0) * np.minimum(u / 0.002, 1) * 0.6
    blow += T.unit(band(white(d), 14, 45, 2)) * np.exp(-u / 0.9) * np.minimum(u / 0.01, 1) * 0.35 * (t >= t0)
    blow = blow * roar_lvl * 1.8
    L += blow; R += blow
    keep("blow", blow)
    front += blow * 0.6

    # ---- the land answering the front: reflections off the ground round it, then distant hills
    fr = front.copy()
    for dt, g, p, hi in ((0.009, 0.4, 0.0, 2500), (0.023, 0.26, -0.3, 1800), (0.041, 0.2, 0.35, 1400),
                         (0.067, 0.16, -0.45, 1100), (0.098, 0.12, 0.3, 900)):
        delay_into(L, R, fr, dt, g, p, 40, hi)
    for dt, g, p, hi in ((0.62, 0.30, -0.5, 1100), (1.18, 0.24, 0.55, 850), (1.9, 0.17, -0.25, 600), (2.7, 0.12, 0.4, 450)):
        delay_into(L, R, fr[:k0 + int(0.6 * SR)], dt * rng().uniform(0.93, 1.07), g, p, 30, hi)

    # ---- inside it: crackle in fits, aftershocks, rolls of thunder, rock coming down
    # (crackle in fits, thick at first and thinning, wandering across the field)
    rate_env = (np.exp(-u / 1.5) * 0.5 + 0.3 * np.exp(-u / (8.0 * stretch))) * np.clip(u / 0.3, 0, 1)
    fit = np.clip(smooth_noise(d, 6.0, n) * 1.2 + smooth_noise(d, 20.0, n) * 0.8 + 0.1, 0, None) ** 2
    crk = T.crackle(d, rate=2600, decay=0.0012, lo=500, hi=4000, heavy=1.35)
    crk = np.tanh(crk / 0.35) * 0.35 * 7.0 * rate_env * fit * roar_lvl * 0.4 * (t >= t0)      # (its rarest spikes eased)
    keep("crackle", crk)
    l, r = pan2(crk, smooth_noise(d, 0.8, n) * 0.35)
    L += l; R += r
    shocks_t = sorted(t0 + 0.4 + 7.5 * stretch / 0.65 * rng().random(14) ** 1.3)
    for t1 in shocks_t:
        if t1 > d - 1.0:
            continue
        far = min((t1 - t0) / 7.0, 1.0)
        size = rng().uniform(0.3, 1.0) * (1 - 0.5 * far)
        x = aftershock(n, t1, size, far) * roar_lvl * 0.9
        keep("aftershocks", x)
        p = rng().uniform(-0.35, 0.35)
        l, r = pan2(x, p)
        L += l; R += r
        delay_into(L, R, x[int(t1 * SR):], t1 + rng().uniform(0.18, 0.45), 0.3, -1.5 * p, 30, 700)
    rl, rr = thunder_rolls(d, t0, 12, 8.0 * stretch / 0.65)
    L += rl * roar_lvl * 0.5; R += rr * roar_lvl * 0.5
    keep("rolls", (rl + rr) / 2 * roar_lvl * 0.5)
    dl, dr = debris_stereo(d, t0, 1.0, 7.0 * stretch / 0.65)
    L += dl * roar_lvl * 1.6; R += dr * roar_lvl * 1.6
    keep("debris", (dl + dr) / 2 * roar_lvl * 1.6)

    # ---- distance: each ear its own clumpy outdoor tail (after the crack, never on it), the air taking the top
    # (the tail's level set where it is heard, 200 Hz-2 kHz: a dark impulse response of unit energy is far louder than
    # unity there)
    send = band((L + R) / 2, 150, None, 2)
    ref_ = np.sqrt(np.mean(band(send, 200, 2000, 2) ** 2))
    wets = []
    for _ in range(2):
        ir = T.outdoor_ir(5.0, density=26.0, darken=(2400, 150), decay=1.5)
        ir = np.concatenate([np.zeros(int(0.025 * SR)), ir])
        m_ = n + len(ir)
        wets.append(np.fft.irfft(np.fft.rfft(send, m_) * np.fft.rfft(ir, m_), m_)[:n])
    k = ref_ / (np.sqrt(np.mean(band(wets[0], 200, 2000, 2) ** 2)) + 1e-12)
    wc = track(n, t0, [(0.3, 0.08), (2.5, 0.16), (6.0, 0.1)]) * k                         # (the land answering more and more)
    L += wets[0] * wc; R += wets[1] * wc
    # (a lowpass over it all that closes as the pressure wave rolls past, darkest two seconds in, as the measured
    # blast's centre of gravity sinks from 112 Hz to 87, then opens again partway; past that the air takes the top)
    fc = track(n, t0, [(0.0, 18000), (0.25, 12000), (1.2, 2200), (2.5, 1500), (4.0, 2600), (6.0, 5000), (9.0, 4500), (14.0, 3000)])
    L = lowpass_track(L, fc); R = lowpass_track(R, fc)
    return L * on, R * on


def soft_clip(x, c, knee=0.55):
    """Peaks over `knee` of `c` rounded off (smoothly, sample by sample) so nothing passes `c`: what a microphone
    overloaded by a blast does, and the reason a recorded blast's first instant is so dense. No gain riding, so nothing
    pumps after the hit the way a limiter's recovery does."""
    k = knee * c
    a = np.abs(x)
    return np.where(a > k, np.sign(x) * (k + (c - k) * np.tanh((a - k) / (c - k))), x)


def finish_blast_decoded(name, L, R, db=-8.0, peak=0.912, tail_fade=0.8, knee=None):
    """`finish_blast`, with the peak held where the game hears it: the file is encoded, decoded and measured, and the
    limiter's ceiling corrected until the decoded peak is `peak` (0.912 is -0.8 dBFS); the loudest 400 ms stays at `db`.
    With `knee`, the peaks are first rounded off by `soft_clip` (the limiter then has next to nothing left to do)."""
    import subprocess
    n = max(len(L), len(R))
    x = np.stack([np.pad(L - L.mean(), (0, n - len(L))), np.pad(R - R.mean(), (0, n - len(R)))], axis=1)
    w, h = int(0.4 * SR), int(0.1 * SR)
    lv = lambda y: max(np.sqrt(np.mean(y.mean(axis=1)[i:i + w] ** 2)) for i in range(0, max(n - w, 1), h))
    target = 10 ** (db / 20)
    path = f"{soundlib.OUT}/assets/orbital/sounds/{name}"
    nf = int(tail_fade * SR)
    c = peak * 0.985
    best = None
    for _ in range(8):
        gain = target / lv(x)
        shape = (lambda z: soft_clip(z, c, knee)) if knee else (lambda z: z)
        for _ in range(6):
            y = limit(shape(x * gain), c)
            got = lv(y)
            gain *= target / got
            if abs(20 * np.log10(target / got)) < 0.05:
                break
        y = limit(shape(x * gain), c)
        y[-nf:] *= np.linspace(1, 0, nf)[:, None]
        write_ogg(path, y, 2)
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path + ".ogg", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
        dec = np.frombuffer(raw, dtype="<f4").reshape(-1, 2)
        pk = float(np.max(np.abs(dec)))
        if best is None or abs(pk / peak - 1) < abs(best[0] / peak - 1):
            best = (pk, y, dec)
        if abs(pk / peak - 1) < 0.005:
            break
        c = min(c * peak / pk, 0.999)
    if best[0] != pk:                                                     # (the encoder's peaks jitter: keep the closest)
        pk, y, dec = best
        write_ogg(path, y, 2)
    gr = 20 * np.log10(np.max(np.abs(x * gain), axis=1).max() / c)       # (by the clip and the limiter together)
    print(f"wrote {name:9s} {n / SR:5.2f}s  stereo  loudest {20 * np.log10(lv(dec.astype(float))):.1f} dB  decoded peak {20 * np.log10(pk):.2f} dBFS  ({gr:.1f} dB off the highest peak)")


# =====================================================  the land bursting, alive: `explosion` with what a recording has
# `explosion` has the measured spectrum of a real, very large explosion and is clean and heavy, but it sounds flat beside
# the recording it was measured on. Measured with the same code on both (reference / `explosion` as fire.ogg had it):
#  - no blow at the start: the reference's first 50 ms stands 6.5 dB over its roar (1-3 s) and peaks 24 ms in, a hard
#    crack and then two and a half swings of a ~60 Hz pressure wave at twice the roar's low amplitude; `explosion`'s
#    stands 2.1 dB over it, peaks 207 ms in and its lows ease in over 50 ms with no swing to them;
#  - no shape to the start: in the reference the crack is over in 15 ms (its mids in 25), the mids then drop away for
#    50 ms (to -30 dB) before the roar rolls in 90 ms in, and the crack comes back off the land 145 ms in (-13 dB) and
#    more softly at about 250 ms; in `explosion` everything just decays smoothly from the crack;
#  - a top that sits still: the 1-4 kHz bands' envelopes move 4.0-4.6 dB (std) with 37-43 % of it at 2-8 Hz, the roar
#    boiling; `explosion`'s 2.1-3.1 dB with 5-12 % (its movement is the slow 0.3-2 Hz wander only);
#  - a top that is smooth noise: the 2-8 kHz bands of the reference are bursty (kurtosis 3.6, 5.4, 6.6 at 2, 4, 8 kHz;
#    Gaussian noise is 3), `explosion`'s are Gaussian (3.0);
#  - a stereo image that never moves: the reference starts as one point dead centre (S/M -25 dB, every band up to 2 kHz
#    0.95-0.99 alike in the two ears) and its top spreads out into the land over seconds (4 kHz 0.94 alike at 0.3-1 s,
#    0.66 at 1-3, 0.30 at 3-8; 8 kHz 0.74 then about 0), its width moving 5.1 dB over time; `explosion` starts wider
#    (S/M -16 dB, its crack's mids 0.8-0.9 alike) and every band is as alike at 10 s as at the start (width moves 1.6 dB);
#  - the roar sagging: the reference's holds within a dB from 0.05 s to 8 s; `explosion`'s sinks 3.6 dB over it.
# What already agreed and is kept: the balance of the octaves over time (within ~2 dB through 8 s), the low-mid body
# (150-400 Hz against 45-120 Hz -9.7 / -9.8 dB at 0.3-1 s), the smooth, Gaussian-or-under lows, nothing tonal in it.
# So `explosion_live` is `explosion`'s roar and debris with: a real start (crack, the pressure wave's swing, the mids
# dropping out, the roar rolling in, the crack coming back off the land), driven into a soft clip as an overloaded
# microphone is; the roar's top boiling in surges and bursts (the noise modulated, no clicks added), the lower bands a
# little; the image starting as one point and the top spreading out over seconds; the roar held up for its first seconds.
OCT_CORR_T = np.array([0.0, 1.0, 2.5, 6.0])
OCT_CORR = np.array([
    [1.0, 1.0, 1.0, 0.99, 0.98, 0.97, 0.97, 0.93, 0.75, 0.6],
    [1.0, 1.0, 1.0, 0.99, 0.97, 0.96, 0.95, 0.86, 0.5, 0.4],
    [1.0, 1.0, 0.99, 0.98, 0.96, 0.93, 0.88, 0.62, 0.15, 0.1],
    [1.0, 1.0, 0.99, 0.97, 0.94, 0.86, 0.72, 0.32, 0.0, 0.0]])


# (the roar's and the crack's levels trimmed, dB per octave, so that with the new start (which sets the loudest 400 ms)
# and the movement the finished sound measures like the reference again, found the same way as `BLAST_TRIM`)
LIVE_TRIM = np.array([
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    [0.0, -1.0, 0.0, -1.0, -0.5, 1.0, -1.0, -1.5, 0.0, 0.0],
    [0.0, 1.0, 2.5, 0.0, 0.0, 1.5, 1.5, -1.0, 0.0, 0.0],
    [0.0, 0.0, 0.0, 0.0, -2.0, 0.0, 0.0, 2.5, 0.0, 0.0],
    [0.0, -1.0, 1.0, -1.0, 2.5, 1.0, 0.0, 2.0, 1.0, 0.0],
    [1.5, 0.5, 1.0, 2.5, 2.0, 2.0, 1.0, 2.5, 3.0, 2.0],
    [1.5, 0.5, 1.0, 2.5, 2.0, 2.0, 1.0, 2.5, 3.0, 2.0],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]])
CRACK_TRIM = np.array([0.0, 0.0, 4.0, -2.0, 5.0, 0.0, 2.5, 1.0, 2.0, 0.0])


def shaped_noise_tv(d, times, table, ctimes, ctable, size=4096, hop=1024, wander=0.0, wander_rate=1.2, wander_from=0.0):
    """`shaped_noise`, with how alike the two ears are per octave changing over time too (`ctable`, a row per time in
    `ctimes`)."""
    n = int(SR * d)
    f = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    loct = np.log2(OCT)
    xs = np.concatenate([[np.log2(8.0), np.log2(16.0)], loct, [np.log2(22050.0)]])
    win = np.hanning(size)
    L = np.zeros(n + 2 * size); R = np.zeros(n + 2 * size)
    wob = [wander * 2.2 * smooth_noise(d, wander_rate, n) for _ in OCT] if wander > 0 else None
    for start in range(-size, n, hop):
        tc = (start + size / 2) / SR
        row = np.array([np.interp(tc, times, table[:, k]) for k in range(table.shape[1])])
        if wob is not None:
            row = row + np.array([w[min(max(int(tc * SR), 0), n - 1)] for w in wob]) * np.clip((tc - wander_from) / 1.2, 0, 1)
        crow = np.array([np.interp(tc, ctimes, ctable[:, k]) for k in range(ctable.shape[1])])
        cc = np.sqrt(np.clip(np.interp(lf, loct, crow), 0, 1))
        ss = np.sqrt(1 - cc ** 2)
        ys = np.concatenate([[row[0] - 24, row[0] - 12], row, [row[-1] - 24 * (np.log2(22050) - loct[-1])]])
        db = np.interp(lf, xs, ys)
        mag = 10 ** (db / 20) / np.sqrt(np.maximum(f, 20.0) / 1000.0)
        mag[0] = 0
        z = lambda: (rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))) / np.sqrt(2)
        zc = z()
        sl = np.fft.irfft(mag * (cc * zc + ss * z()), size) * win
        sr_ = np.fft.irfft(mag * (cc * zc + ss * z()), size) * win
        a = start + size
        L[a:a + size] += sl; R[a:a + size] += sr_
    k = np.sqrt(size / 2) / np.sqrt(1.5) * 0.7071
    return L[size:size + n] * k, R[size:size + n] * k


def causal_lowcut(x, f, poles=2):
    """Everything under `f` Hz taken out by a filter that only looks back (one-pole lowpasses subtracted), so a hard
    onset has nothing ringing ahead of it: the game's zero-phase low cut afterwards then has nothing left to ring with."""
    tau = 1.0 / (2 * np.pi * f)
    m = int(tau * 12 * SR)
    h = np.exp(-np.arange(m) / (tau * SR)); h /= h.sum()
    for _ in range(poles):
        nf = 1 << int(np.ceil(np.log2(len(x) + m)))
        x = x - np.fft.irfft(np.fft.rfft(x, nf) * np.fft.rfft(h, nf), nf)[:len(x)]
    return x


def slow_random(n, lo, hi, rate=1000):
    """A random curve with unit spread whose movement is all between `lo` and `hi` Hz (built at `rate` and eased up to
    the sound's rate)."""
    m = int(n * rate / SR) + 4
    k = SR / rate                                               # (`band` reads frequencies at the sound's rate)
    g = band(rng().standard_normal(m), lo * k, hi * k, 2)
    g = g / (np.std(g) + 1e-12)
    return np.interp(np.arange(n) * rate / SR, np.arange(m), g)


def surges(n, sig_db, slow, fast, share, t0, spread, drift=0.0):
    """Two gains (left, right) for one band of the roar: it swells and sinks by about `sig_db` dB (spread over 1.5-12 Hz:
    the roar boiling), with `fast` dB more over 15-60 Hz (bursts within it); `share` of it the same in the whole roar
    (`slow` is that common curve), and the two ears moving together at first and apart as it spreads out
    (`spread`: how far apart, 0-1, after 4 s); `drift` dB more over 0.3-1.5 Hz (slow heaves). The mean power is kept."""
    t = np.arange(n) / SR
    own = slow_random(n, 1.5, 12.0)
    g = share * slow + np.sqrt(1 - share ** 2) * own
    w = np.interp(t, [t0, t0 + 1.0, t0 + 4.0], [1.0, 1.0 - 0.4 * spread, 1.0 - spread])
    out = []
    for _ in range(2):
        e = slow_random(n, 1.5, 12.0)
        gs = w * g + np.sqrt(1 - w ** 2) * e
        gf = slow_random(n, 25.0, 90.0)
        gd = slow_random(n, 0.3, 1.5) if drift > 0 else 0.0
        lg = (sig_db * gs + fast * gf + drift * gd) / 8.686
        v = (sig_db ** 2 + fast ** 2 + drift ** 2) / 8.686 ** 2
        out.append(np.exp(lg - v))                   # (E[exp(2·lg)] = exp(2v): the power stays as it was)
    return out


def explosion_live(d, t0, stretch=1.0, debris=1.0, whump=1.0, live=1.0):
    """A huge explosion starting at `t0` in a `d`-second stereo sound, before any mastering: `explosion`'s roar, as heavy
    and clean, with what a recording of a real one has (see above).
     crack   : the first 15 ms (its mids 25), broadband and hard, one point dead centre
     whump   : the pressure wave: two and a half swings of ~60 Hz, from 10 to 55 ms, twice the roar's low amplitude
     the gap : the mids dropping away for 50 ms after the crack, until the roar rolls in 90 ms in, a little over itself
     echo    : the crack coming back off the land, 145 ms in (duller, 13 dB down) and, softer and smeared, about 250 ms
     roar    : the measured table, its top boiling in surges and bursts, its image spreading out over seconds, held up
               over its first seconds
     debris  : as `explosion`'s
    The start is driven into a soft clip, as a microphone overloaded by a blast is: dense, nothing pumping after it."""
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0.0)
    k0 = int(t0 * SR)
    on = ramp_in(n, k0, 10)
    # ---- the roar
    tt_ = np.where(BLAST_T <= 0.65, BLAST_T, 0.65 + (BLAST_T - 0.65) * stretch) + t0
    tab = BLAST_DB + BLAST_TRIM + LIVE_TRIM
    body_tab = np.vstack([tab[0] - 40.0, tab])
    ct = np.where(OCT_CORR_T <= 0.65, OCT_CORR_T, 0.65 + (OCT_CORR_T - 0.65) * stretch) + t0
    bl, br = shaped_noise_tv(d, np.concatenate([[t0 - 0.1], tt_]), body_tab, ct, OCT_CORR, 4096, 1024,
                             wander=2.4 * min(1.0, stretch + 0.3), wander_from=t0)
    # (held up: the roar does not sag over its first seconds)
    hold = 10 ** (np.interp(u, np.array([0.0, 0.65, 1.5, 4.0, 7.0, 10.0]) * np.r_[1, 1, [stretch] * 4] + np.r_[0, 0, [0.65 * (1 - stretch)] * 4],
                            [0.0, 0.0, 1.5 * live, 2.0 * live, 1.0 * live, 0.0]) / 20)
    bl = bl * hold; br = br * hold
    # its bands, each moving: (edges, swell dB, burst dB, how far the ears drift apart)
    split = [(120, 0.0, 0.0, 0.0, 0.0), (350, 1.2, 0.0, 0.0, 0.0), (1000, 2.4, 1.0, 0.1, 0.0), (2800, 3.4, 1.8, 0.3, 2.6),
             (6500, 3.0, 4.2, 0.6, 2.4), (None, 2.4, 4.2, 0.8, 1.5)]
    common = slow_random(n, 1.5, 12.0)
    parts = []
    restL, restR = bl, br
    for k, (fc, sg_, fs_, sp, dr) in enumerate(split):
        if fc is not None:
            lL, lR = band(restL, None, fc, 4), band(restR, None, fc, 4)
            restL, restR = restL - lL, restR - lR
        else:
            lL, lR = restL, restR
        if sg_ > 0:
            gL, gR = surges(n, sg_ * live, common, fs_ * live, 0.6, t0, sp, dr * live)
            # (the movement grows in over the first half second: the start has its own shape)
            ramp = np.clip((u - 0.15) / 0.35, 0, 1)
            gL = 1 + (gL - 1) * ramp; gR = 1 + (gR - 1) * ramp
            lL, lR = lL * gL, lR * gR
        parts.append((fc, lL, lR))
    # the gap: everything over 350 Hz dropping away after the crack until the roar rolls in, a little over itself
    gap_db = np.interp(u, [0.0, 0.02, 0.035, 0.075, 0.095, 0.12, 0.15], [0.0, 0.0, -14.0, -14.0, 2.5, 2.5, 0.0])
    gap = 10 ** (gap_db * live / 20)
    L = np.zeros(n); R = np.zeros(n)
    for fc, lL, lR in parts:
        g = 1.0 if (fc is not None and fc <= 350) else gap
        L += lL * g; R += lR * g
    # ---- the crack: one point, dead centre (its own fast spectrum, as `explosion`'s)
    c0 = tab[1]
    cct = np.array([0.0, 0.012, 0.03, 0.06, 0.12, 0.3])
    ctab = np.vstack([c0 + 8.0, c0 + 2.0, c0 - 4.0 + np.array([0, 0, 0, 0, -2, -4, -6, -8, -10, -12]), tab[2] - 2.0, tab[2] - 8.0, tab[3] - 14.0])
    ctab = ctab + CRACK_TRIM
    cl, cr = shaped_noise(d, cct + t0, ctab, 256, 64, corr=np.array([1.0, 1.0, 1.0, 1.0, 0.99, 0.98, 0.97, 0.93, 0.75, 0.6]))
    hi_env = np.where(u < 0.010, 1.0, np.exp(-(u - 0.010) / 0.005))
    mid_env = np.where(u < 0.022, 1.0, np.exp(-(u - 0.022) / 0.006))
    def crack_of(c):
        h = band(c, 2000, None, 2)
        return (h * hi_env + (c - h) * mid_env) * (t >= t0)
    cl, cr = crack_of(cl), crack_of(cr)
    # ---- the pressure wave: two and a half swings of ~60 Hz, the same in both ears
    f = 62.0 - 10.0 * np.clip(u / 0.06, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * (t >= t0)) / SR
    wenv = np.clip((u - 0.006) / 0.014, 0, 1) ** 2 * np.where(u < 0.045, 1.0, np.exp(-(u - 0.045) / 0.014))
    wh = -np.sin(ph) * wenv
    # (its level against the roar's lows, as measured: twice their amplitude)
    lo_rms = np.sqrt(np.mean(band(L + R, 30, 100, 2)[k0 + int(1.0 * SR):k0 + int(3.0 * SR)] ** 2) / 4 + 1e-20)
    wh = wh * lo_rms * np.sqrt(2) * 3.0 * whump
    # (and the crack's against the roar, as `explosion` set it)
    L = L + cl * 2.1 + wh; R = R + cr * 2.1 + wh
    # ---- the crack coming back off the land: 145 ms in (duller, 13 dB down) and about 250 ms, softer and smeared
    seg = slice(k0, k0 + int(0.03 * SR))
    for dt, gn, fc, smear, pan in ((0.145, 0.22, 5000, 0.0, 0.15), (0.25, 0.13, 2500, 0.025, -0.2)):
        for ch, c in ((0, cl), (1, cr)):
            e = band(c[seg] * 1.5, 250, fc, 2)
            if smear > 0:
                kk = int(smear * SR)
                e = np.convolve(e, np.hanning(kk) / np.sum(np.hanning(kk)) * np.sqrt(kk) * 0.6)
            k = k0 + int(dt * SR)
            m = min(len(e), n - k)
            side = (1 + pan) if ch == 0 else (1 - pan)
            (L if ch == 0 else R)[k:k + m] += e[:m] * gn * side
    # ---- rock and earth coming back down (as `explosion`)
    if debris > 0:
        deb = T.debris_settle(d, t0 + 0.25, amount=1.5 * debris, spread=8.0 * stretch)
        deb = band(deb, None, 1800, 2)
        L = L + deb * 0.085; R = R + deb * 0.085
    # (nothing under 20 Hz, taken out looking back only: see `causal_lowcut`)
    L = causal_lowcut(L * on, 20.0); R = causal_lowcut(R * on, 20.0)
    # ---- the overloaded microphone: the first 80 ms driven into a soft clip 6.6 dB over the loudest 400 ms (which the
    # start itself sets), so the master's limiter (7.1 dB of room: -8 dB loudest, -0.9 dBFS peaks) has next to nothing
    # to take off it; a limiter riding the start down would pull the whole first 200 ms down with it
    free = 1 + 1e3 * np.clip((u - 0.08) / 0.07, 0, 1) ** 2
    L0, R0 = L, R
    lv = T.loudest((L + R) / 2)
    for _ in range(4):
        c = lv * 10 ** (6.6 / 20) * free
        L = soft_clip(L0, c, 0.5); R = soft_clip(R0, c, 0.5)
        lv = T.loudest((L + R) / 2)
    return L * on, R * on
