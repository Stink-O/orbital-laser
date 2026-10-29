"""The Payload's sounds, all synthesised here from noise, pulses, resonators and filters (nothing sampled).

Their levels and shapes over time were *measured* on two references (band levels, envelopes, stereo, transients; no
audio from either is in this repo): a gameplay clip of an orbital bomb coming down a few hundred metres from the player,
and a sound designer's redesign of that bomb's explosion (the `_alt` sounds). The clip's own timeline matches the
strike's (the object strikes 13.6 s in, the blast is heard 1.3 s later), so the tables here are in strike time, at the
levels a player about 450 blocks off hears them: each reference scaled so its blast's loudest 400 ms sits where ours
does (-8 dB). The plan (mod/src/strike/payload.rs) plays them all at full volume in the player's ears, so how loud each
file is against the others is how they sit in the game; its timeline is read from there.

  drift       the approach (0 is when the plan starts it, PL_SEEN - 0.3 + 1.6 s): high up and far off at first, a dark
              roar fading in and swelling as it comes, a few low resonances wandering in it, the burning object
              crackling, a thin tearing whine over it that climbs as it closes (a doppler rise, never a held note);
              handed over to `dive` across its first 1.4 s
  dive        the fast final descent (0 is PL_HIT - PL_DIVE_SND, PL_DIVE_SND before the strike): the roar louder, the
              whine bending up into a shriek, a rush of torn air sweeping up under it, the crackle thickening, the sub
              growing; cut off dead on the strike, the air letting go of it within a fifth of a second
  ground      the land's answer through the ground (0.02 s in is when its wave reaches the player: the plan plays it at
              the strike plus the distance at five times the air's speed): a deep thump, felt more than heard, a sub
              rumble under a near-silence, the ground shuddering once, a faint rattle
  ground_alt  the same as the redesign has it: one boom swelling up out of the ground round 70 Hz, sliding down, dying
  blast       the blast reaching the player (0.02 s in is its arrival): `explosion_live`, the burst this clip was
              measured for, shaped closer to it (a deeper gap after the crack, a sub swelling in, the top let down
              sooner, the low mids a little apart in the two ears)
  blast_alt   the alternative blast, in the redesign's manner: the air coming up out of the hush, a low boom, a gap, a
              bright crack and a second blow, then a wide, mid-heavy roar crackling and dying sooner; level-matched
  rush        the shockwave's front and its dust washing over the player (0.15 s in, with the blast): gusts buffeting
              from side to side, low pushes of air, grit and twigs thrown past, the leaves thrashing, wind dying away
  debris      what comes back down round the player: clods thudding in, stones clacking and bouncing, branches
              cracking down through leaves, slabs landing far off, a patter of grit, near and far, unevenly
  tail        the long tail (0 is 2.4 s after the blast arrives): the roar rolling back off the land in uneven swells,
              each further off and darker, the last of it dying away about 24 s after the blast

Sounds that play over the blast at a moment fixed against it (the rush, the tail) are eased down for the instants
where the two would add up past full scale; the blasts are built before them, so build the whole set (or the blasts
first).

    python3 tools/sounds_payload.py            # writes orbital-sounds/assets/orbital/sounds/payload/*.ogg and adds the
                                               # events to sounds.json, leaving every other sound as it is
"""
import argparse, json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, white, band, smooth_noise
import sounds_themes as T
import sounds_pk_blast as PB

TH = "payload"
NAMES = ["drift", "dive", "ground", "ground_alt", "blast", "blast_alt", "rush", "debris", "tail"]
ROOT = Path(__file__).resolve().parent.parent
PEAK = 0.912                                   # decoded peaks at -0.8 dBFS
OCT = PB.OCT                                   # 31.5 Hz .. 16 kHz


def plan_times():
    """The strike's timeline as mod/src/strike/payload.rs has it, so the files' lead-ins stay in step with it."""
    vals = {"PL_SEEN": 3.0, "PL_TURN": 10.6, "PL_HIT": 13.6, "PL_DIVE_SND": 2.6}
    try:
        src = (ROOT / "mod" / "src" / "strike" / "payload.rs").read_text()
        for k in vals:
            m = re.search(rf"const {k}: f32 = ([0-9.]+);", src)
            if m:
                vals[k] = float(m.group(1))
    except OSError:
        pass
    return vals


TL = plan_times()
SEEN, HIT = TL["PL_SEEN"], TL["PL_HIT"]
DRIFT_AT = SEEN - 0.3 + 1.6                    # (its delay by distance is capped at 1.6 s, and it always shows further off)
DIVE_AT = HIT - TL["PL_DIVE_SND"]
CUT = HIT - DIVE_AT                            # the dive's cut, in its file
XF = 1.4                                       # drift handing the roar over to the dive

# The approach's roar as the reference has it, octave levels (dB, 31.5 Hz .. 16 kHz) over strike time: a dark roar,
# 125-250 Hz heavy, swelling about 9 dB from far off to the strike, its 500 Hz-2 kHz growing most (the 1 kHz octave
# 12 dB), its top not at all; one sound, centred (the ears 0.97-1.0 alike under 300 Hz, 0.85-0.95 to 2 kHz).
APPROACH_T = np.array([2.5, 4.0, 5.5, 7.0, 8.5, 10.0, 11.0, 12.0, 12.8, 13.35, 13.6])
APPROACH_DB = np.array([
    [-46.0, -32.0, -28.5, -30.0, -34.5, -37.0, -41.0, -46.0, -52.0, -64.0],
    [-48.0, -33.0, -26.3, -27.7, -33.7, -34.4, -37.5, -46.0, -52.0, -64.0],
    [-46.0, -31.0, -22.2, -23.5, -31.3, -31.7, -38.0, -47.0, -52.5, -67.0],
    [-46.0, -30.5, -19.5, -21.2, -29.9, -28.5, -36.5, -46.5, -53.0, -67.0],
    [-46.0, -31.0, -18.5, -19.4, -28.8, -27.8, -36.5, -46.0, -52.0, -67.0],
    [-46.0, -30.2, -18.1, -19.3, -27.3, -26.0, -35.5, -45.2, -51.5, -66.0],
    [-45.5, -29.9, -18.3, -19.0, -26.3, -24.8, -34.3, -45.5, -52.5, -67.0],
    [-45.5, -29.7, -18.0, -18.8, -24.8, -24.1, -32.0, -44.2, -55.0, -70.0],
    [-45.5, -29.2, -17.3, -18.5, -24.1, -24.0, -30.8, -42.6, -54.5, -70.0],
    [-45.5, -29.5, -16.8, -18.4, -22.9, -23.2, -29.5, -40.3, -53.0, -68.0],
    [-45.5, -29.5, -16.5, -18.2, -22.5, -22.8, -29.0, -39.5, -52.5, -68.0]])
APPROACH_CORR = np.array([1.0, 1.0, 0.99, 0.98, 0.95, 0.92, 0.88, 0.8, 0.7, 0.6])


# `PB.shaped_noise`'s levels are relative (its blast is normalised after): a table's dB come out this much lower, as
# measured with `oct_levels` (pink noise at -30 dB in every octave measures -53.7 dB)
SN_GAIN = 10 ** (23.7 / 20)


def rng():
    return soundlib.rng


def snoise(d, times, table, size=4096, hop=1024, corr=PB.BLAST_CORR, controls=None):
    """Noise whose octave levels follow `table` (dB, one row per time in `times`), at those levels as `oct_levels`
    measures them: `PB.shaped_noise`, or `PB.shaped_noise_moving` with `controls`. Stereo, the ears as alike as `corr`."""
    if controls is None:
        L, R = PB.shaped_noise(d, times, table, size, hop, corr=corr)
    else:
        L, R = PB.shaped_noise_moving(d, times, table, controls, size, hop, corr=corr)
    return L * SN_GAIN, R * SN_GAIN


def put(x, y, t0):
    k = int(t0 * SR)
    if k < 0:
        y, k = y[-k:], 0
    m = min(len(y), len(x) - k)
    if m > 0:
        x[k:k + m] += y[:m]


def oct_levels(x, a, b):
    """Octave levels (dB, RMS) of `x` between a and b seconds, by the same octave filters the tables were measured with."""
    seg = x[max(int(a * SR), 0):int(b * SR)]
    out = []
    for fc in OCT:
        y = band(seg, fc / 2 ** 0.5, min(fc * 2 ** 0.5, SR * 0.47), 3)
        out.append(20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12))
    return np.array(out)


def calibrated(make, times, table, rounds=2, half=0.35):
    """`make(table)` -> (L, R), run again with its table trimmed until what it makes measures like `table` at each of
    `times` (the noise draws are the same every run: only the levels move)."""
    tab = table.copy()
    for _ in range(rounds):
        L, R = make(tab)
        m = (L + R) / 2
        n = len(m) / SR
        for i, tc in enumerate(times):
            if tc - half < 0 or tc + half > n:
                continue
            got = oct_levels(m, tc - half, tc + half)
            tab[i] += np.clip(table[i] - got, -8, 8)
    return make(tab)


def glide_band(d, fc, width, size=2048, hop=512):
    """Noise in a narrow band (`width` octaves) round a centre that moves (`fc`, Hz, one value a sample): a noise-excited
    resonance sliding about, breathy, never a pure tone. Unit RMS."""
    n = int(SR * d)
    win = np.hanning(size)
    f = np.fft.rfftfreq(size, 1 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    out = np.zeros(n + 2 * size)
    for start in range(-size, n, hop):
        c = fc[min(max(start + size // 2, 0), n - 1)]
        w = width[min(max(start + size // 2, 0), n - 1)] if np.ndim(width) else width
        mag = np.exp(-0.5 * ((lf - np.log2(c)) / (w / 2.355)) ** 2)
        z = rng().standard_normal(len(f)) + 1j * rng().standard_normal(len(f))
        a = start + size
        out[a:a + size] += np.fft.irfft(mag * z, size) * win
    out = out[size:size + n]
    return out / (np.sqrt(np.mean(out ** 2)) + 1e-12)


def bumps(n, times, att, dec, amps):
    """A curve of skewed bumps (rise over `att`, fall over `dec` seconds each) at `times`: gusts, swells, pushes."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for t1, a, dc, g in zip(times, att, dec, amps):
        k0, k1 = int(max(t1 - a * 1.2, 0) * SR), min(int((t1 + dc * 6) * SR), n)
        u = t[k0:k1] - t1
        out[k0:k1] += g * np.where(u < 0, np.exp(-0.5 * (u / (a * 0.5)) ** 2), np.exp(-u / dc))
    return out


def poisson_times(t_lo, t_hi, rate_fn):
    """Event times between t_lo and t_hi at a rate (a second) that changes over time: irregular, as things happen."""
    peak = max(rate_fn(t) for t in np.linspace(t_lo, t_hi, 64)) * 1.2 + 1e-9
    out, t = [], t_lo
    while True:
        t += rng().exponential(1.0 / peak)
        if t >= t_hi:
            return np.array(out)
        if rng().random() < rate_fn(t) / peak:
            out.append(t)


def modal_hit(m, f1, ratios, decays, amps, crack=0.4, hi=9000):
    """A hard thing struck: a few damped, inharmonic modes rung by a short bright noise burst (stone, a snapped branch)."""
    s = np.arange(m) / SR
    x = np.zeros(m)
    for r, dc, a in zip(ratios, decays, amps):
        f = f1 * r
        if f > SR * 0.45:
            continue
        x += np.sin(2 * np.pi * f * s + rng().uniform(0, 2 * np.pi)) * np.exp(-s / dc) * a
    k = max(int(0.0015 * SR), 4)
    burst = rng().standard_normal(m) * np.exp(-s / 0.0007)
    burst = burst - np.concatenate([[0.0], burst[:-1]])
    x = x * np.minimum(s / 0.0003, 1.0) + burst * crack
    return band(x, 300, hi, 2)


def air(x, fc):
    """`x` heard through `fc` Hz of air and distance (a gentle 12 dB/octave lowpass, the same all through)."""
    return band(x, None, fc, 2)


def decoded(name):
    """One of this set's files as the game plays it (decoded), stereo; None if it is not built yet."""
    path = f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}.ogg"
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                             capture_output=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(float)


def duck_under_blasts(L, R, at, ceiling=0.92, release=0.08):
    """`L`, `R` (a sound the plan always starts at the same moment against the blast: the blast's file starts `at`
    seconds into it) eased down for the instants where, played over either blast, the two would add up past `ceiling`:
    the blast's own peaks are already at -0.8 dBFS, and what plays with them has to make room (it is masked there
    anyway). Down at once (2 ms ahead), back over `release` seconds. Prints how much it took."""
    n = len(L)
    need = np.ones(n)
    for nm in ("blast", "blast_alt"):
        b = decoded(nm)
        if b is None:
            print(f"  ({nm} not built yet: not ducked under it)")
            continue
        k = int(round(at * SR))
        lo, hi = max(0, k), min(n, k + len(b))
        if hi <= lo:
            continue
        bb = b[lo - k:hi - k]
        for ch, x in enumerate((L, R)):
            room = np.maximum(ceiling - np.abs(bb[:, ch]), 0.0)
            a = np.abs(x[lo:hi])
            need[lo:hi] = np.minimum(need[lo:hi], np.where(a > room, room / np.maximum(a, 1e-9), 1.0))
    w = int(0.002 * SR)
    gp = np.pad(need, (w, w), constant_values=1.0)
    g = np.lib.stride_tricks.sliding_window_view(gp, 2 * w + 1).min(axis=1)[:n]
    kr = np.exp(-1.0 / (release * SR))
    out = np.empty(n)
    st = 1.0
    for i, v in enumerate(g):
        st = v if v < st else 1.0 - (1.0 - st) * kr
        out[i] = st
    print(f"  ducked under the blasts: at most {20 * np.log10(out.min() + 1e-9):.1f} dB, "
          f"{np.mean(out < 0.89) * n / SR:.2f} s of it more than 1 dB")
    return L * out, R * out


def finish_abs(name, L, R, peak=PEAK, tail_fade=0.3):
    """Write a stereo sound at the level it was built to (the tables are absolute: the strike's sounds play at full
    volume, so how they sit against each other is what was built), its decoded peaks held at `peak` at most by the
    look-ahead limiter (the encoder's overshoot measured and corrected)."""
    n = max(len(L), len(R))
    x = np.stack([np.pad(L, (0, n - len(L))), np.pad(R, (0, n - len(R)))], axis=1)
    x -= x.mean(axis=0)
    nf = int(tail_fade * SR)
    x[-nf:] *= np.linspace(1, 0, nf)[:, None]
    path = f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"
    c = peak * 0.985
    y = x
    for _ in range(6):
        y = PB.limit(x, c) if np.abs(x).max() > c else x.copy()
        PB.write_ogg(path, y, 2)
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path + ".ogg", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                             capture_output=True, check=True).stdout
        pk = float(np.max(np.abs(np.frombuffer(raw, dtype="<f4"))))
        if pk <= peak * 1.004:
            break
        c = c * peak / pk
    lv = 20 * np.log10(T.loudest(y.mean(axis=1)) + 1e-12)
    print(f"wrote {TH}/{name:7s} {n / SR:5.2f}s  stereo  loudest {lv:5.1f} dB  decoded peak {20 * np.log10(pk):6.2f} dBFS")


# =====================================================================================================  the approach
# The whine's pitch over strike time: a slow rise while it is far off and crawling, then faster and faster as it comes
# down (its sound pushed up by its speed towards the player), a shriek at the last.
def whine_pitch(ts):
    pts = [(DRIFT_AT - 1.0, 1.0), (DRIFT_AT + 2.5, 1.03), (DRIFT_AT + 5.0, 1.09), (DIVE_AT, 1.2),
           (HIT - 1.2, 1.42), (HIT - 0.5, 1.72), (HIT, 1.9)]
    xs, ys = zip(*pts)
    return np.interp(ts, xs, ys)


# the whine's modes (ratios to its lowest, inharmonic, each a little off on its own) and its lowest's pitch far off
WHINE_F0 = 940.0
WHINE_MODES = [(1.0, 0.07, 0.0), (1.437, 0.08, -6.0), (2.23, 0.1, -12.0)]


def roar_body(d, t_at, table):
    """The roar: noise whose octave levels follow `table` (APPROACH_T in strike time; this sound starts at `t_at`), a
    few low resonances wandering in it (110-145 Hz and about 260, as the reference has), its colour wavering. Stereo,
    one sound, centred."""
    n = int(SR * d)
    ctl_n = int(d * 50) + 2
    sn = lambda rate: smooth_noise(d, rate, ctl_n)
    tilt = sn(0.4) * 0.8
    wob = [sn(rng().uniform(0.5, 1.4)) * 1.6 for _ in OCT]
    res = [(rng().uniform(108, 122), 0.16, 7.0, sn(0.35) * 0.09, 0.55 + 0.45 * sn(0.6)),
           (rng().uniform(133, 146), 0.14, 6.0, sn(0.3) * 0.08, 0.5 + 0.5 * sn(0.5)),
           (rng().uniform(250, 272), 0.2, 6.5, sn(0.4) * 0.07, 0.5 + 0.5 * sn(0.7))]
    loct = np.log2(OCT)

    def controls(tc, lf):
        i = int(np.clip(tc, 0, d - 1e-3) * 50)
        both = tilt[i] * np.clip(lf - np.log2(200.0), -2, 4) + np.interp(lf, loct, [w[i] for w in wob])
        for f0, w, g, wan, sw in res:
            both = both + g * sw[i] * np.exp(-0.5 * ((lf - np.log2(f0) - wan[i]) / (w / 2.355)) ** 2)
        return both, 0.0, 0.0

    return snoise(d, APPROACH_T - t_at, table, corr=APPROACH_CORR, controls=controls)


def whine(d, t_at, level_db, bright_db, flutter=1.0):
    """The thin, tearing whine of the object through the air: four noise-excited modes, inharmonic, each sliding with
    the doppler rise (`whine_pitch`) and fluttering on its own, the higher ones coming up as it closes (`bright_db`, dB
    over strike time, as the air between takes less of the top). `level_db`: the lowest mode's level over strike time
    (a function). Stereo: nearly one sound, a little wider up top."""
    n = int(SR * d)
    ts = t_at + np.arange(n) / SR
    P = whine_pitch(ts)
    L = np.zeros(n); R = np.zeros(n)
    for k, (r, w, g) in enumerate(WHINE_MODES):
        r = r * (1 + 0.012 * PB.slow_random(n, 0.05, 0.2) * flutter)                # (each mode off on its own, slowly)
        fl = 1 + (0.006 * PB.slow_random(n, 2.0, 7.0) + 0.012 * PB.slow_random(n, 0.2, 1.2)) * flutter
        fc = WHINE_F0 * P * r * fl
        wd = w * (1 + 0.5 * np.abs(PB.slow_random(n, 0.5, 3.0)))
        x = glide_band(d, fc, wd)
        # (its level wavering, unevenly: swells and dips, never a held tone)
        am = np.exp((2.4 * PB.slow_random(n, 0.3, 2.5) + 1.2 * PB.slow_random(n, 4.0, 14.0)) / 8.686)
        lv = 10 ** ((level_db(ts) + g + bright_db(ts) * k / 2.0) / 20)
        y = x * am * lv
        side = glide_band(d, fc * 1.003, wd) * am * lv
        wide = 0.12 + 0.1 * k
        L += y + side * wide; R += y - side * wide
    return L, R


def tearing(d, t_at, level_db, lo=1800, hi=6500, rate=(18, 55)):
    """Air being torn: a band of noise chopped by an irregular, fast flutter (bursts at a few tens a second), swelling
    unevenly. `level_db` over strike time."""
    n = int(SR * d)
    ts = t_at + np.arange(n) / SR
    out = []
    common = PB.slow_random(n, rate[0], rate[1])
    for _ in range(2):
        x = T.unit(band(rng().standard_normal(n), lo, hi, 2))
        chop = 0.7 * common + 0.3 * PB.slow_random(n, rate[0], rate[1])
        g = np.clip(chop * 0.9 + 0.35, 0, None) ** 1.6
        g /= np.sqrt(np.mean(g ** 2)) + 1e-9
        sw = np.exp(3.0 * PB.slow_random(n, 0.4, 2.0) / 8.686)
        out.append(x * g * sw * 10 ** (level_db(ts) / 20))
    return out[0], out[1]


def crackle(d, t_at, rate_fn, level_db, lo=1400, hi=9000):
    """The burning object crackling: sharp ticks at random (Poisson, their sizes heavy-tailed), a few much bigger than
    the rest, so the top is bursty as the reference's is, not a smooth hiss. Stereo, each tick placed on its own."""
    n = int(SR * d)
    L = np.zeros(n); R = np.zeros(n)
    for t1 in poisson_times(0.0, d - 0.01, lambda u: rate_fn(u + t_at)):
        k0 = int(t1 * SR)
        a = min(rng().pareto(1.6) * 0.45 + 0.3, 5.0) * 10 ** (level_db(t1 + t_at) / 20)
        tk = PB.tick(n, k0, a, rng().uniform(0.00012, 0.0005), rng().choice([-1.0, 1.0]))
        p = rng().uniform(-0.35, 0.35)
        L += tk * (1 - p); R += tk * (1 + p)
    return band(L, lo, hi, 2), band(R, lo, hi, 2)


def drift():
    """The approach (see the top). Starts at DRIFT_AT; hands the roar over to `dive` from DIVE_AT over XF seconds."""
    end = DIVE_AT + XF - DRIFT_AT
    d = end + 0.25
    n = int(SR * d)
    t = np.arange(n) / SR
    ts = DRIFT_AT + t
    with PB.seeded(92101):
        L, R = calibrated(lambda tab: roar_body(d, DRIFT_AT, tab), APPROACH_T - DRIFT_AT, APPROACH_DB.copy())
        # (the reference's top is bursty: kurtosis 5-10 over 1 kHz)
        cl, cr = crackle(d, DRIFT_AT, lambda u: 12 + 30 * np.clip((u - DRIFT_AT) / 6.0, 0, 1),
                         lambda u: -49 + 7 * np.clip((u - DRIFT_AT) / 6.5, 0, 1))
        wl, wr = whine(d, DRIFT_AT, lambda u: np.interp(u, [DRIFT_AT, DRIFT_AT + 3, DIVE_AT], [-45, -40, -35]),
                       lambda u: np.interp(u, [DRIFT_AT, DIVE_AT], [-6, 0]))
        tl, tr = tearing(d, DRIFT_AT, lambda u: np.interp(u, [DRIFT_AT, DIVE_AT], [-58, -50]), 1400, 5000)
        L = L + cl + wl + tl; R = R + cr + wr + tr
        # far off at first: fading in as it shows, the top coming up as it nears
        g = np.clip(t / 2.0, 0, 1) ** 1.5
        x = np.clip((ts - DIVE_AT) / XF, 0, 1)
        g = g * np.cos(np.pi / 2 * x)
        L, R = L * g, R * g
        L, R = PB.causal_lowcut(L, 20.0), PB.causal_lowcut(R, 20.0)
    finish_abs("drift", L, R, tail_fade=0.05)


# =========================================================================================================  the dive
def dive():
    """The final descent (see the top): the roar carried on from `drift` and grown, the whine into a shriek, a rush of
    torn air sweeping up, crackle thickening, the sub growing; all of it cut dead on the strike (CUT seconds in), only
    the air's last instant off the land after it. (The land's answer through the ground is `ground`: it comes by
    distance.)"""
    d = CUT + 0.9
    n = int(SR * d)
    t = np.arange(n) / SR
    ts = DIVE_AT + t
    u = np.clip(t / CUT, 0, 1)
    with PB.seeded(92201):
        # (the reference's last seconds hold their level; here it grows a little more in the last second, the mids most)
        tab = APPROACH_DB.copy()
        tab[-2:, 3:7] += np.array([[0.5, 1.0, 1.5, 1.5], [1.5, 2.5, 3.0, 3.0]])
        tab[-2:, 0:3] += np.array([[0.0, 0.5, 0.5], [1.0, 1.5, 1.5]])
        L, R = calibrated(lambda tb: roar_body(d, DIVE_AT, tb), APPROACH_T - DIVE_AT, tab, half=0.25)
        wl, wr = whine(d, DIVE_AT, lambda v: np.interp(v, [DIVE_AT, HIT - 1.0, HIT - 0.3, HIT], [-36, -33, -30, -29.5]),
                       lambda v: np.interp(v, [DIVE_AT, HIT - 0.6, HIT], [0, 2, 3]), flutter=1.3)
        tl, tr = tearing(d, DIVE_AT, lambda v: np.interp(v, [DIVE_AT, HIT - 0.8, HIT], [-52, -48, -45]), 1400, 5000, (20, 70))
        cl, cr = crackle(d, DIVE_AT, lambda v: 40 + 60 * np.clip((v - DIVE_AT) / CUT, 0, 1) ** 2,
                         lambda v: np.interp(v, [DIVE_AT, HIT], [-44, -40]))
        # the rush of torn air: a band sweeping up under the whine, louder and faster as it comes
        fc = 330 * (1450 / 330) ** (u ** 1.8)
        rush = glide_band(d, fc, 0.9 + 0.3 * u)
        rl = rush * 10 ** (np.interp(u, [0, 0.6, 1], [-38, -31, -26]) / 20) * np.exp(1.8 * PB.slow_random(n, 0.5, 3.0) / 8.686)
        rr = glide_band(d, fc * 1.02, 0.9 + 0.3 * u) * 10 ** (np.interp(u, [0, 0.6, 1], [-38, -31, -26]) / 20) * np.exp(1.8 * PB.slow_random(n, 0.5, 3.0) / 8.686)
        # the weight of it bearing down: a sub coming up under the roar
        sub = T.unit(band(white(d), 24, 70, 2)) * 10 ** (np.interp(u, [0, 0.7, 1], [-42, -36, -31]) / 20)
        L = L + wl + tl + cl + rl + sub
        R = R + wr + tr + cr + rr + sub
        # handed over from drift (its roar fading as this one comes up: equal power), cut dead on the strike
        g = np.sin(np.pi / 2 * np.clip(t / XF, 0, 1))
        kc = int(CUT * SR)
        cut = np.ones(n)
        k6 = int(0.006 * SR)
        cut[kc - k6:kc] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k6))
        cut[kc:] = 0.0
        # (whine and crackle a breath under the roar at the very start, so the hand-over is the roar's)
        L, R = L * g * cut, R * g * cut
        # the air letting go of it: the last instant of the roar off the land, gone within a fifth of a second (the
        # reference's top falls 25-30 dB over 180 ms after the strike), dark, after the cut and never on it
        last = (L + R)[kc - int(0.05 * SR):kc] * 0.5
        ir_n = int(0.7 * SR)
        s = np.arange(ir_n) / SR
        ir = (band(rng().standard_normal(ir_n), 700, 2600, 2) * np.exp(-s / 0.04)
              + band(rng().standard_normal(ir_n), 200, 700, 2) * np.exp(-s / 0.09) * 0.9
              + band(rng().standard_normal(ir_n), 45, 200, 2) * np.exp(-s / 0.16) * 0.8) * (1 - np.exp(-s / 0.004))
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        tail_ = np.convolve(last, ir)
        for ch, sgn in ((L, 1.0), (R, -1.0)):
            put(ch, tail_ * 0.55 * (1 + 0.15 * sgn), CUT - 0.05)
        L, R = PB.causal_lowcut(L, 18.0), PB.causal_lowcut(R, 18.0)
    finish_abs("dive", L, R, tail_fade=0.2)


# ======================================================================================  the land's answer, through it
# What both references have between the strike and the air's blast (measured; dB for a player about 450 blocks off):
#  - the bomb clip: a thump 0.15-0.25 s after the strike, its 31.5 and 63 Hz octaves -12 and -11 dB (over 80 ms), a
#    little at 125-250 Hz; then a sub rumble lingering under a near-silence, 31.5 Hz -19 to -25 dB over a second, 63 Hz
#    about -27; the ground shuddering once 0.4-0.6 s in (125 Hz-1 kHz -29 to -36 dB); nothing over 2 kHz (under -55);
#  - the redesign: a boom swelling to its peak 0.12-0.2 s after the strike, round 65-75 Hz and gliding down (its 63 Hz
#    octave -11 dB; 31.5 and 125 Hz 10-20 dB under it), then dying about 22 dB a second (63 Hz -26 dB at 0.27 s, -36 at
#    0.75, -48 at 1.35); nothing over 500 Hz (under -60 dB); the ears 0.96 alike, 0.85 later.
# The ground carries it far faster than the air (the plan: PL_GROUND_V, 5x the air's speed), so it comes first, and
# falls off with distance (the plan plays it at 2/3 volume 450 blocks off: it is built GROUND_UP dB over those levels).
GROUND_UP = 3.5
GROUND_LEAD = 0.02                             # (the plan starts it this much before the ground's wave arrives)


def at_octave(x, a, b, fc, db_):
    """`x` scaled so its octave at `fc` Hz measures `db_` between a and b seconds."""
    k = list(OCT).index(fc)
    got = oct_levels(x, a, b)[k]
    return x * 10 ** ((db_ - got) / 20)


def ground():
    """The land's answer through the ground, as the bomb clip has it: a deep thump, felt more than heard, a sub
    rumble lingering, the ground shuddering once with a faint rattle of loose stones; nothing up top."""
    d = 3.4
    n = int(SR * d)
    t = np.arange(n) / SR
    t1 = GROUND_LEAD
    u = np.maximum(t - t1, 0)
    on = t >= t1
    up = GROUND_UP
    with PB.seeded(92301):
        # the thump: a falling low tone (no ring: it dies in a few swings) and a burst of low noise, rising over 25 ms
        th = soundlib.thump(n, t1, rng().uniform(54, 62), rng().uniform(28, 33), 0.11, 6.0) * (1 - np.exp(-u / 0.022)) * on
        th += T.unit(band(white(d), 22, 110, 2)) * (1 - np.exp(-u / 0.02)) * np.exp(-u / 0.08) * on * 0.45
        th = at_octave(th, t1 + 0.03, t1 + 0.11, 63, -11.0 + up)
        # (and as much under it at 31.5 Hz: the clip's thump is as heavy there)
        ts_ = T.unit(band(white(d), 20, 45, 2)) * (1 - np.exp(-u / 0.015)) * np.exp(-u / 0.1) * on
        th += at_octave(ts_, t1 + 0.03, t1 + 0.11, 31.5, -12.5 + up)
        # (a little body over it: what the ground's surface throws into the air at 125-250 Hz)
        body = T.unit(band(white(d), 100, 320, 2)) * (1 - np.exp(-u / 0.01)) * np.exp(-u / 0.07) * on
        body = at_octave(body, t1 + 0.02, t1 + 0.1, 250, -25.0 + up)
        # the rumble: the land still moving, a second and more, unevenly
        rum = T.unit(band(white(d), 16, 56, 2)) * np.clip(u / 0.15, 0, 1) * np.exp(-np.maximum(u - 0.25, 0) / 1.0) * on
        rum *= np.exp(2.5 * PB.slow_random(n, 0.8, 4.0) / 8.686)
        rum = at_octave(rum, t1 + 0.3, t1 + 0.7, 31.5, -21.0 + up)
        # the ground shuddering once as the surface wave goes under: a dull low-mid flutter, a faint rattle on it
        t2 = t1 + rng().uniform(0.3, 0.38)
        sh_env = np.exp(-0.5 * ((t - t2 - 0.08) / 0.075) ** 2)
        shL = T.unit(band(white(d), 90, 800, 2)); shR = 0.85 * shL + 0.53 * T.unit(band(white(d), 90, 800, 2))
        flut = np.clip(1 + 0.8 * PB.slow_random(n, 9.0, 24.0), 0.1, None)
        shL, shR = shL * sh_env * flut, shR * sh_env * flut
        g = 10 ** ((-35.0 + up - oct_levels((shL + shR) / 2, t2, t2 + 0.16)[3]) / 20)
        shL, shR = shL * g, shR * g
        rat = [T.unit(band(white(d), 1100, 3400, 2)) * np.clip(PB.slow_random(n, 25.0, 70.0), 0, None) ** 2 * sh_env for _ in range(2)]
        rat = [at_octave(r, t2, t2 + 0.16, 2000, -50.0 + up) for r in rat]
        lm = T.unit(band(white(d), 70, 300, 2)) * (1 - np.exp(-u / 0.03)) * np.exp(-u / 0.32) * on
        lm *= np.exp(2.0 * PB.slow_random(n, 2.0, 9.0) / 8.686)
        lm = at_octave(lm, t1 + 0.1, t1 + 0.35, 125, -31.0 + up)
        low = th + body + rum + lm
        L = low + shL + rat[0]; R = low + shR + rat[1]
        L, R = PB.causal_lowcut(L, 15.0), PB.causal_lowcut(R, 15.0)
    finish_abs("ground", L, R, tail_fade=0.8)


def ground_alt():
    """The land's answer as the redesign has it: one boom swelling up out of the ground over a tenth of a second, round
    70 Hz and sliding down, then a low rumble dying away steadily; nothing over 500 Hz."""
    d = 2.6
    n = int(SR * d)
    t = np.arange(n) / SR
    t1 = GROUND_LEAD
    u = np.maximum(t - t1, 0)
    on = t >= t1
    up = GROUND_UP
    with PB.seeded(92311):
        tp = rng().uniform(0.12, 0.15)
        f = 50.0 + rng().uniform(22, 28) * np.exp(-u / 0.3)
        ph = 2 * np.pi * np.cumsum(f * on) / SR
        env = np.where(u < tp, (u / tp) ** 1.3, np.exp(-(u - tp) / 0.075)) * on
        boom = np.sin(ph) * env + T.unit(band(white(d), 38, 110, 2)) * env * 0.35
        boom = at_octave(boom, t1 + tp - 0.04, t1 + tp + 0.04, 63, -11.0 + up)
        sub = T.unit(band(white(d), 20, 45, 2)) * env
        sub = at_octave(sub, t1 + tp - 0.04, t1 + tp + 0.04, 31.5, -22.0 + up)
        rL = T.unit(band(white(d), 30, 95, 2)); rR = 0.92 * rL + 0.39 * T.unit(band(white(d), 30, 95, 2))
        renv = np.clip((u - 0.06) / 0.14, 0, 1) * np.exp(-np.maximum(u - 0.2, 0) / 0.39) * np.exp(1.5 * PB.slow_random(n, 1.0, 5.0) / 8.686)
        g = 10 ** ((-26.0 + up - oct_levels((rL + rR) / 2 * renv, t1 + 0.22, t1 + 0.35)[1]) / 20)
        L = boom + sub + rL * renv * g
        R = boom + sub + rR * renv * g
        L, R = PB.causal_lowcut(L, 15.0), PB.causal_lowcut(R, 15.0)
    finish_abs("ground_alt", L, R, tail_fade=0.6)


# ========================================================================================================  the blast
def bands3(x, f1, f2):
    """`x` split into under f1, f1-f2 and over f2 Hz (zero-phase, the three summing back to `x` exactly)."""
    a = band(x, None, f1, 4)
    b = band(x, None, f2, 4) - a
    return a, b, x - a - b


def blast():
    """`explosion_live` (the burst the reference was measured for: see sounds_pk_blast.py) on its own seed, then shaped
    toward this reference where it differs (measured with the same code on both, reference / explosion_live alone):
     - the gap after the crack: the reference's 350 Hz-1.5 kHz drop 32 dB under the crack 40-70 ms in / 21 dB, and its
       90-350 Hz 22 dB 50-110 ms in / 8 dB: here both taken down further, the roar rolling in on time;
     - the sub swelling in: its 31.5 Hz octave -11 dB (re the loudest 400 ms) at 0.3-1 s and -10 at 1-3 s / -16 and -12;
     - its body 125 Hz-1 kHz 2-3 dB lighter after a second, its 1-10 kHz 4-8 dB lighter from 2.5 s (the reference's top
       dies sooner);
     - its image: the reference's low mids a little apart in the two ears after the start (S/M -22 dB at 1-8 s / -30),
       its 4 kHz still 0.7 alike / 0.3: the side of 150 Hz-1.5 kHz lifted, moving, and the top's narrowed."""
    d = 19.0
    t0 = 0.02
    with PB.seeded(91301):
        EL, ER = PB.explosion_live(d, t0, stretch=0.9, debris=1.0, whump=1.25, live=1.0)
        n = len(EL)
        t = np.arange(n) / SR
        u = np.maximum(t - t0, 0)
        g_lm = 10 ** (np.interp(u, [0.0, 0.035, 0.05, 0.1, 0.13, 1.0, 2.0], [0, 0, -9, -9, 0, 0, -2.5]) / 20)
        g_hi = 10 ** (np.interp(u, [0.0, 0.03, 0.045, 0.075, 0.09, 1.0, 2.5, 4.0, 9.0],
                                [0, 0, -9, -9, 0, 0, -3.0, -5.0, -4.0]) / 20)
        side_g = 10 ** ((np.interp(u, [0.0, 0.25, 1.0, 3.0], [0, 2.5, 6.0, 6.5]) + 2.0 * PB.slow_random(n, 0.3, 2.0)) / 20)
        top_side = np.interp(u, [0.0, 0.5, 1.5], [1.0, 0.85, 0.55])
        outs = []
        for ch in (EL, ER):
            a, b, c = bands3(ch, 90, 350)
            outs.append((a, b, c))
        L = outs[0][0] + outs[0][1] * g_lm + outs[0][2] * g_hi
        R = outs[1][0] + outs[1][1] * g_lm + outs[1][2] * g_hi
        M, S = (L + R) / 2, (L - R) / 2
        s_lo, s_mid, s_hi = bands3(S, 150, 1500)
        sh = band(s_hi, 2500, None, 2)
        S = s_lo + s_mid * side_g + (s_hi - sh) + sh * top_side
        # the sub swelling in under the roar, centred
        sub = T.unit(band(rng().standard_normal(n), 22, 45, 2))
        sub *= np.clip((u - 0.12) / 0.4, 0, 1) ** 1.5 * np.exp(-np.maximum(u - 0.8, 0) / 2.0) * (t >= t0)
        lo_ref = np.sqrt(np.mean(band(M, 25, 45, 2)[int(1.0 * SR):int(3.0 * SR)] ** 2))
        M = M + sub * lo_ref * 0.6
        L, R = M + S, M - S
        L, R = PB.causal_lowcut(L, 16.0), PB.causal_lowcut(R, 16.0)
        # (the start driven a little harder into the overloaded microphone's soft clip, 5 dB over the loudest 400 ms:
        # the reference's first 50 ms stand 6.5 dB over its roar with only 5 dB from them to its peak, so it is that
        # dense; at our level and peak the limiter would otherwise take the crack down 3-4 dB)
        free = 1 + 1e3 * np.clip((u - 0.07) / 0.05, 0, 1) ** 2
        L0, R0 = L, R
        lv = T.loudest((L + R) / 2)
        for _ in range(4):
            c = lv * 10 ** (5.0 / 20) * free
            L = PB.soft_clip(L0, c, 0.5); R = PB.soft_clip(R0, c, 0.5)
            lv = T.loudest((L + R) / 2)
    PB.finish_blast_decoded(f"{TH}/blast", L, R, -8.0, PEAK, 1.5)


# The redesign's blast (the second reference, a sound designer's take on the same bomb), measured with the same code as
# the bomb clip's and set to the same loudest 400 ms (-8 dB): octave levels (dB) over time after it arrives. Unlike the
# clip's it does not start with a crack: the air comes up out of near-silence over a tenth of a second, a low boom
# peaks 0.15 s in (45-90 Hz), the mids drop out, the crack comes 0.23-0.26 s in (bright up to 16 kHz) and a second low
# blow 0.3 s in; then a roar that is mid-heavy and wide (its 250 Hz-1 kHz octaves 0.1-0.5 alike in the two ears, the
# clip's 0.9-1.0), holding a second or two and dying faster (6 dB down by 1-2 s, 10 by 3-4 s; the clip's 1.5 and 2).
ALT_T = np.array([0.31, 0.43, 0.65, 1.0, 1.5, 2.15, 3.0, 4.0, 5.5, 7.5, 10.5])
ALT_DB = np.array([
    [-13.8, -14.1, -15.6, -23.5, -27.1, -29.2, -31.6, -32.6, -33.1, -38.4],
    [-15.7, -12.5, -16.6, -24.8, -29.0, -29.2, -30.2, -33.1, -39.9, -49.2],
    [-16.7, -11.4, -18.5, -25.8, -31.4, -31.4, -33.3, -38.7, -49.0, -57.7],
    [-19.4, -16.3, -21.6, -28.5, -30.1, -29.7, -32.4, -40.4, -52.6, -63.2],
    [-19.6, -18.2, -22.9, -29.7, -30.1, -30.9, -35.4, -46.2, -60.6, -66.5],
    [-21.4, -17.4, -24.9, -30.1, -30.7, -33.1, -40.7, -55.0, -65.4, -69.9],
    [-24.2, -19.1, -27.2, -33.8, -34.7, -38.0, -47.9, -60.8, -68.4, -73.2],
    [-24.0, -20.4, -30.2, -40.7, -43.3, -47.1, -56.0, -64.3, -70.2, -76.8],
    [-27.0, -25.0, -37.0, -47.0, -50.0, -54.0, -61.0, -68.0, -74.0, -84.0],
    [-34.0, -32.0, -45.0, -55.0, -58.0, -62.0, -69.0, -76.0, -82.0, -92.0],
    [-46.0, -44.0, -57.0, -67.0, -70.0, -74.0, -81.0, -88.0, -94.0, -104.0]])
# (the roar's levels trimmed, dB per row and octave, so the finished sound measures like the redesign: what the start,
# the crackle and the boil add after a second would otherwise leave it 2-6 dB too loud there)
ALT_TRIM = np.zeros_like(ALT_DB)
ALT_TRIM[3:, 2:] = np.array([-2.0, -3.0, -4.5, -5.5, -5.0, -5.0, -5.0, -5.0])[:, None]
ALT_TRIM[3:, :2] = np.array([-1.0, -1.5, -2.0, -2.5, -2.5, -2.5, -2.5, -2.5])[:, None]
ALT_CORR_T = np.array([0.3, 0.65, 1.5, 3.0, 5.0])
ALT_CORR = np.array([
    [0.99, 0.92, 0.74, 0.5, 0.5, 0.4, 0.25, 0.15, 0.3, 0.45],
    [0.9, 0.9, 0.55, 0.55, 0.2, 0.15, 0.06, 0.1, 0.1, 0.3],
    [0.7, 0.55, 0.53, 0.25, 0.15, 0.12, 0.04, 0.04, 0.1, 0.4],
    [0.9, 0.55, 0.55, 0.35, 0.25, 0.17, 0.07, 0.2, 0.2, 0.4],
    [0.97, 0.85, 0.7, 0.45, 0.35, 0.35, 0.4, 0.5, 0.5, 0.5]])


def blast_alt():
    """The alternative blast, in the redesign's manner (see ALT_DB): the air coming up out of the hush, a low boom, a
    gap, a bright crack and a second blow, then a wide, mid-heavy roar crackling, dying sooner than `blast`'s. Same
    level as `blast` (its loudest 400 ms -8 dB, peaks -0.8 dBFS), its arrival also 0.02 s in."""
    d = 11.5
    t0 = 0.02
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(91311):
        # ---- the roar (from 0.2 s), wide and moving
        times = np.concatenate([[0.2, 0.27], ALT_T + 0.04]) + t0
        tab = np.vstack([ALT_DB[0] - 40.0, ALT_DB[0] - 12.0, ALT_DB + ALT_TRIM])
        bl, br = PB.shaped_noise_tv(d, times, tab, ALT_CORR_T + t0, ALT_CORR, 4096, 1024, wander=1.6, wander_from=t0 + 0.3)
        bl, br = bl * SN_GAIN, br * SN_GAIN
        # (its mids and top boiling, unevenly, as the redesign's do)
        boil = [np.exp((2.6 * PB.slow_random(n, 1.5, 10.0) + 1.2 * PB.slow_random(n, 12.0, 40.0)) / 8.686) for _ in range(2)]
        ramp = np.clip((u - 0.3) / 0.4, 0, 1)
        outs = []
        for ch, bo in ((bl, boil[0]), (br, boil[1])):
            hi = band(ch, 250, None, 2)
            outs.append(ch - hi + hi * (1 + (bo - 1) * ramp))
        L, R = outs
        # ---- the air coming up out of the hush: a broadband wash rising over 0.13 s, its top last
        wash = []
        for _ in range(2):
            w_ = T.unit(band(rng().standard_normal(n), 200, 9000, 2))
            w_ = band(w_, None, 2000, 1) * 0.9 + w_ * 0.06
            wash.append(w_ * np.clip(u / 0.13, 0, 1) ** 2.5 * np.exp(-np.maximum(u - 0.13, 0) / 0.03) * on * 10 ** (-28.0 / 20))
        # (what the redesign's start is measured against: its roar's 63 Hz and 1 kHz octaves at 0.5-1 s, -13 and -31 dB)
        roar63 = oct_levels((L + R) / 2, t0 + 0.5, t0 + 1.0)[1]
        roar1k = oct_levels((L + R) / 2, t0 + 0.5, t0 + 1.0)[5]
        # ---- the low blows, the same in both ears: a sub push peaking 0.11 s in (20-45 Hz, 4.5 dB over the roar's 63 Hz
        # octave); a boom of ~62 Hz swelling over 60 ms to 0.15 s and dropping away in 10 (45-90 Hz, 9.5 dB over it);
        # a punch of 90-250 Hz on its back; a second blow 0.31-0.37 s in
        def blow_at(tp, f0, rise, fall, a):
            uu = u - tp
            env = np.where(uu < 0, np.exp(-0.5 * (uu / rise) ** 2), np.exp(-uu / fall)) * on
            ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.12 * np.exp(-np.maximum(uu, 0) / 0.05)) * on) / SR
            return np.sin(ph + rng().uniform(0, 6.28)) * env * a
        sub = blow_at(0.11, 32.0, 0.018, 0.03, 1.0) + blow_at(0.31, 36.0, 0.015, 0.04, 0.8)
        boom = blow_at(0.15, 62.0, 0.02, 0.011, 1.0) + blow_at(0.365, 58.0, 0.02, 0.025, 0.7) + blow_at(0.33, 66.0, 0.012, 0.02, 0.5)
        punch = (T.unit(band(rng().standard_normal(n), 90, 260, 2)) * np.exp(-0.5 * ((u - 0.158) / 0.007) ** 2)
                 + T.unit(band(rng().standard_normal(n), 90, 260, 2)) * np.exp(-0.5 * ((u - 0.285) / 0.012) ** 2) * 0.8) * on
        def peak10(x, lo, hi):
            y = band(x, lo, hi, 2)
            w = int(0.01 * SR)
            return 20 * np.log10(max(np.sqrt(np.mean(y[i:i + w] ** 2)) for i in range(0, int(0.6 * SR), w // 2)) + 1e-12)
        sub *= 10 ** ((roar63 + 4.5 - peak10(sub, 20, 45)) / 20)
        boom *= 10 ** ((roar63 + 9.5 - peak10(boom, 45, 90)) / 20)
        punch *= 10 ** ((roar63 + 1.5 - peak10(punch, 90, 250)) / 20)
        blow = sub + boom + punch
        # ---- the crack: a bright burst 0.232 s in, its mids first and its top 10-15 ms after, wide; smaller ones at
        # 0.32 and 0.34 (its 1-4 kHz 6.5 dB over the roar's 1 kHz octave)
        crack = [np.zeros(n), np.zeros(n)]
        for tc, a, top_lag, w in ((0.232, 1.0, 0.012, 0.022), (0.322, 0.35, 0.004, 0.012), (0.342, 0.3, 0.004, 0.01)):
            for k in range(2):
                uu = u - tc
                m_env = np.where(uu < 0, 0.0, (1 - np.exp(-uu / 0.002)) * np.exp(-uu / w)) * on
                h_env = np.where(uu < top_lag, 0.0, (1 - np.exp(-(uu - top_lag) / 0.002)) * np.exp(-(uu - top_lag) / (w * 1.1))) * on
                mid = T.unit(band(rng().standard_normal(n), 250, 3500, 2))
                top = T.unit(band(rng().standard_normal(n), 3500, 18000, 2))
                crack[k] += (mid * m_env + top * h_env * 10 ** (-6.0 / 20)) * a
        cg = 10 ** ((roar1k + 8.5 - peak10((crack[0] + crack[1]) / 2, 1000, 4000)) / 20)
        crack = [c * cg for c in crack]
        # (the wash under all of it: 250 Hz-1 kHz 4 dB under the roar's 1 kHz octave as it peaks)
        wg = 10 ** ((roar1k - 4.0 - peak10((wash[0] + wash[1]) / 2, 250, 1000)) / 20)
        wash = [w_ * wg for w_ in wash]
        # ---- crackle in the roar: a few sharp spikes up top, much bigger than the rest, thinning out
        cl, cr = crackle(d, 0.0, lambda v: 0.0 if v < t0 + 0.35 else 14.0 * np.exp(-(v - t0 - 0.35) / 1.2) + 2.0,
                         lambda v: -40.0 - 4.0 * max(v - t0 - 0.35, 0), lo=1800, hi=12000)
        L = L + wash[0] + blow + crack[0] + cl
        R = R + wash[1] + blow + crack[1] + cr
        L, R = PB.causal_lowcut(L * on, 18.0), PB.causal_lowcut(R * on, 18.0)
        # (its first 0.6 s driven into a soft clip 7.5 dB over its loudest 400 ms, as the redesign's start is (its peak
        # 7.7 dB over it): dense, and the master's limiter has next to nothing left to ride down)
        free = 1 + 1e3 * np.clip((u - 0.6) / 0.1, 0, 1) ** 2
        L0, R0 = L, R
        lv = T.loudest((L + R) / 2)
        for _ in range(4):
            c = lv * 10 ** (7.5 / 20) * free
            L = PB.soft_clip(L0, c, 0.5); R = PB.soft_clip(R0, c, 0.5)
            lv = T.loudest((L + R) / 2)
    PB.finish_blast_decoded(f"{TH}/blast_alt", L, R, -8.0, PEAK, 1.5)


# =========================================================================================================  the rush
def rush():
    """The shockwave's front and its dust washing over the player (FRONT seconds in, with the blast): gusts buffeting
    from one side and the other, low pushes of air, grit and twigs thrown past, the leaves thrashing, then wind dying
    away over seconds, as the dust on the screen does (60 % of it gone with 0.8 s, the rest with 3.5 s)."""
    d = 9.0
    FRONT = 0.15
    n = int(SR * d)
    t = np.arange(n) / SR
    tau = t - FRONT
    on = np.clip((tau + 0.01) / 0.12, 0, 1) ** 1.5 * (tau > -0.01)
    E = on * (0.6 * np.exp(-np.maximum(tau, 0) / 0.8) + 0.4 * np.exp(-np.maximum(tau, 0) / 3.5))
    with PB.seeded(92401):
        L = np.zeros(n); R = np.zeros(n)
        # ---- the gusts: wind noise, each ear its own gusts over a shared swell, so they swing from side to side
        gt = poisson_times(FRONT + 0.03, d - 1.0, lambda v: 6.0 * np.exp(-(v - FRONT) / 1.2) + 1.2)
        common = bumps(n, gt, rng().uniform(0.05, 0.16, len(gt)), rng().uniform(0.12, 0.45, len(gt)),
                       np.minimum(rng().pareto(2.5, len(gt)) * 0.5 + 0.4, 2.5))
        tabT = np.array([0.0, 1.0, 4.0, 9.0])
        tab = np.array([[-56, -44, -37, -35, -37, -41, -47, -53, -61, -73],
                        [-56, -44, -37, -35, -37, -41, -47, -54, -63, -75],
                        [-58, -46, -38, -36, -38, -42, -48, -56, -66, -78],
                        [-61, -48, -40, -38, -40, -44, -51, -60, -70, -82]], dtype=float)
        wl, wr = snoise(d, tabT, tab, 2048, 512, corr=np.array([1.0, 0.95, 0.8, 0.6, 0.45, 0.35, 0.3, 0.25, 0.2, 0.2]))
        for ch, w in ((L, wl), (R, wr)):
            own = bumps(n, gt + rng().uniform(-0.06, 0.06, len(gt)), rng().uniform(0.05, 0.16, len(gt)),
                        rng().uniform(0.1, 0.4, len(gt)), np.minimum(rng().pareto(2.5, len(gt)) * 0.5 + 0.3, 2.5))
            gust = 0.35 + 0.55 * common / (common.mean() + 1e-9) * 0.5 + 0.45 * own / (own.mean() + 1e-9) * 0.5
            # (a strong gust brighter: its top let through more)
            hi_part = band(w, 900, None, 2)
            bright = np.clip(gust / 1.5, 0.4, 1.6)
            # (a little more of it once the blast's own top has fallen away, so the wind is heard going over)
            ch += ((w - hi_part) + hi_part * bright) * gust * E * (1 + 0.4 * np.clip((tau - 0.5) / 0.7, 0, 1))
        # ---- the leaves and grass thrashing: bursty rustle up top, thickest as the front goes through, each ear its own
        for ch in (L, R):
            fol = T.unit(band(rng().standard_normal(n), 2200, 9500, 2))
            g = PB.grains(d, 70.0, (0.004, 0.009, 0.02))
            g = np.clip(g, 0, 8.0) ** 1.3
            g /= np.sqrt(np.mean(g ** 2)) + 1e-9
            env = on * (0.75 * np.exp(-np.maximum(tau, 0) / 0.9) + 0.25 * np.exp(-np.maximum(tau, 0) / 3.0))
            ch += fol * g * env * 10 ** (-46.0 / 20)
        # ---- grit and twigs thrown past: sharp ticks at random (most in the first second), the sizes heavy-tailed,
        # each at its own place; a few small stones and twigs knocking
        for t1 in poisson_times(FRONT + 0.02, d - 0.5, lambda v: 70.0 * np.exp(-(v - FRONT) / 0.6) + 4.0 * np.exp(-(v - FRONT) / 3.0)):
            k0 = int(t1 * SR)
            a = min(rng().pareto(1.8) * 0.4 + 0.25, 4.0) * 10 ** (-35.0 / 20) * np.exp(-max(t1 - FRONT, 0) / 2.5)
            tk = band(PB.tick(int(0.01 * SR), 0, a, rng().uniform(0.00015, 0.0006), rng().choice([-1.0, 1.0])), 1800, 11000, 2)
            p = rng().uniform(-0.9, 0.9)
            put(L, tk * (1 - p) * 1.2, t1); put(R, tk * (1 + p) * 1.2, t1)
        for t1 in poisson_times(FRONT + 0.1, FRONT + 2.5, lambda v: 7.0 * np.exp(-(v - FRONT) / 0.8)):
            m = int(0.08 * SR)
            hit = modal_hit(m, rng().uniform(1400, 3800), [1.0, rng().uniform(1.5, 2.1), rng().uniform(2.6, 3.7)],
                            [rng().uniform(0.003, 0.012), 0.004, 0.003], [1.0, 0.6, 0.35], 0.6)
            hit *= 10 ** ((-37.0 + rng().uniform(-6, 3)) / 20) / (np.abs(hit).max() + 1e-9) * 3.0
            p = rng().uniform(-0.9, 0.9)
            put(L, hit * (1 - p), t1); put(R, hit * (1 + p), t1)
        # ---- the pressure of it: low pushes of air, uneven, felt more than heard, the same in both ears
        pt = poisson_times(FRONT + 0.05, FRONT + 2.2, lambda v: 4.0 * np.exp(-(v - FRONT) / 0.9))
        push = bumps(n, pt, rng().uniform(0.03, 0.08, len(pt)), rng().uniform(0.06, 0.18, len(pt)),
                     np.minimum(rng().pareto(2.2, len(pt)) * 0.5 + 0.4, 2.5) * rng().choice([-1.0, 1.0], len(pt)))
        push = band(push, 12, 70, 2) * 10 ** (-31.0 / 20) / (np.sqrt(np.mean(band(push, 12, 70, 2)[int(FRONT * SR):int((FRONT + 2) * SR)] ** 2)) + 1e-9)
        L += push; R += push
        # (nothing before the front: the blast's crack has the first instant to itself)
        g0 = np.clip((tau + 0.005) / 0.02, 0, 1)
        L, R = L * g0, R * g0
        L, R = PB.causal_lowcut(L, 14.0), PB.causal_lowcut(R, 14.0)
        # (the plan starts the blast 0.13 s after this: room made under its peaks)
        L, R = duck_under_blasts(L, R, FRONT - 0.02, ceiling=0.95)
    finish_abs("rush", L, R, tail_fade=1.0)


# =======================================================================================================  the debris
def debris():
    """What comes back down round the player, starting a moment in: clods of earth thudding in, stones clacking (some
    bouncing once), branches cracking down through leaves, slabs landing far off, a patter of grit; each thing landing
    somewhere of its own, the near ones sharp and loud, the far ones dull and in the land's echo; uneven, thick at
    first, thinning out over seven or eight seconds."""
    d = 9.5
    n = int(SR * d)
    with PB.seeded(92501):
        L = np.zeros(n); R = np.zeros(n)
        fL = np.zeros(n); fR = np.zeros(n)                     # (the far bus: through the land's echo)

        def place(x, t1, near, p):
            gl, gr = (1 - p) * 0.5 + 0.5 * near * (1 - p), (1 + p) * 0.5 + 0.5 * near * (1 + p)
            put(L, x * gl * near, t1); put(R, x * gr * near, t1)
            put(fL, x * (1 - near) * (1 - p * 0.5), t1); put(fR, x * (1 - near) * (1 + p * 0.5), t1)

        rate = lambda v: 9.0 * np.clip(v / 0.4, 0, 1) * np.exp(-max(v - 0.6, 0) / 2.2) + 0.6 * np.exp(-v / 6.0)
        for t1 in poisson_times(0.08, d - 1.2, rate):
            near = rng().random() ** 1.6
            kind = rng().random()
            if kind < 0.45:                                    # a clod of earth: a dull thud and a spray of dirt
                size = min(rng().pareto(2.0) * 0.35 + 0.25, 2.0)
                m = int((0.18 + 0.3 * size) * SR)
                x = T.thud(m, size) * size
                s = np.arange(m) / SR
                spray = T.unit(band(rng().standard_normal(m), 600, 5000, 2)) * np.exp(-s / rng().uniform(0.012, 0.035)) * np.minimum(s / 0.002, 1)
                x = x * 0.11 + spray * 0.035 * (0.4 + 0.6 * near)
            elif kind < 0.78:                                  # a stone: a hard clack, sometimes a bounce
                size = rng().uniform(0.3, 1.0)
                m = int(0.35 * SR)
                f1 = rng().uniform(900, 3200) / (0.6 + size)
                x = modal_hit(m, f1, [1.0, rng().uniform(1.45, 2.2), rng().uniform(2.4, 3.9), rng().uniform(4.1, 5.6)],
                              [rng().uniform(0.004, 0.02), rng().uniform(0.003, 0.01), 0.004, 0.002], [1.0, 0.7, 0.45, 0.25], 0.5)
                x = x / (np.abs(x).max() + 1e-9) * 0.09 * size
                x += T.thud(m, 0.3 * size) * 0.03 * size
                if rng().random() < 0.35:
                    put(x, x * rng().uniform(0.25, 0.5), rng().uniform(0.07, 0.22))
            elif kind < 0.9:                                   # a branch: a crack and leaves rushing down with it
                m = int(0.6 * SR)
                s = np.arange(m) / SR
                x = modal_hit(m, rng().uniform(500, 1100), [1.0, rng().uniform(2.3, 2.9), rng().uniform(4.2, 5.5)],
                              [0.012, 0.006, 0.003], [1.0, 0.5, 0.3], 1.2, 7000)
                x = x / (np.abs(x).max() + 1e-9) * 0.06
                lv = T.unit(band(rng().standard_normal(m), 2500, 9000, 2)) * np.clip(PB.slow_random(m, 15, 60), 0, None) ** 1.5
                x += lv * np.sin(np.pi * np.clip(s / rng().uniform(0.25, 0.5), 0, 1)) * 0.012
            else:                                              # a slab of rock, landing heavily somewhere off
                m = int(0.9 * SR)
                x = T.thud(m, rng().uniform(1.6, 2.6)) * 0.16
                near = near * 0.4
            x = air(x, 1800 + 9000 * near)
            place(x, t1, 0.25 + 0.75 * near, rng().uniform(-0.85, 0.85))
        # the patter: grit and small stones raining all round, dense at first
        for t1 in poisson_times(0.15, d - 1.0, lambda v: 110.0 * np.clip(v / 0.5, 0, 1) * np.exp(-max(v - 0.5, 0) / 1.6)):
            k0 = int(t1 * SR)
            a = min(rng().pareto(2.4) * 0.35 + 0.15, 2.0) * 0.022
            tk = PB.tick(int(0.006 * SR), 0, a, rng().uniform(0.0002, 0.0008), rng().choice([-1.0, 1.0]))
            tk = band(tk, 1200, 9000, 2)
            p = rng().uniform(-1, 1)
            put(L, tk * (1 - p * 0.8), t1); put(R, tk * (1 + p * 0.8), t1)
        # (the far ones through the land's echo, each ear its own)
        for src, dst in ((fL, L), (fR, R)):
            ir = T.outdoor_ir(1.6, density=40.0, darken=(2400, 300), decay=0.6)
            m_ = n + len(ir)
            wet = np.fft.irfft(np.fft.rfft(src, m_) * np.fft.rfft(ir, m_), m_)[:n]
            dst += src * 0.55 + wet * 0.5
        # (its lows eased: the blast's roar has them covered, and room is left under its peaks, which the debris lands
        # on at a moment that changes with the distance)
        f = T.fade(n, 0.002, 2.0) * 10 ** (-3.0 / 20)
        L = L - band(L, None, 280, 2) * 0.68; R = R - band(R, None, 280, 2) * 0.68
        L, R = PB.causal_lowcut(L * f, 22.0), PB.causal_lowcut(R * f, 22.0)
    finish_abs("debris", L, R, tail_fade=0.5)


# ===========================================================================================================  the tail
def tail():
    """The long tail (0 is 2.4 s after the blast arrives): the roar rolling back off the land in swells that come
    unevenly, each further off, darker and wider than the last, and under them the low roar outlasting the blast's own,
    dying away by about 24 s after it arrived. (The reference's roar holds within 2-4 dB for ten seconds and has only a
    few distinct swells, 3-5 dB, at 7.6, 10.3, 10.8 and 14.7 s: so the rolls are few and moderate.)"""
    d = 22.0
    n = int(SR * d)
    t = np.arange(n) / SR
    with PB.seeded(92601):
        L = np.zeros(n); R = np.zeros(n)
        tr = rng().uniform(0.8, 1.6)
        k = 0
        while tr < d - 6.0:
            far = min(tr / 14.0, 1.0)
            ln = rng().uniform(1.6, 3.4) + 1.5 * far
            m = int(ln * SR)
            s = np.arange(m) / SR
            att = rng().uniform(0.12, 0.35) + 0.3 * far
            dec = rng().uniform(0.6, 1.1) + 0.9 * far
            env = (1 - np.exp(-s / att)) ** 2 * np.exp(-s / dec)
            env /= env.max() + 1e-9
            hi = 280 - 150 * far
            lvl = 10 ** ((-19.5 - 9.0 * far + rng().uniform(-2.5, 1.5)) / 20)
            # (the nearer rolls with a dull boom at their front: the blast coming back off a far slope)
            boom = T.unit(band(rng().standard_normal(m), 120, 650 - 300 * far, 2)) * np.exp(-s / 0.18) * (1 - np.exp(-s / 0.02)) * (1 - far) * 0.3
            corr = 0.9 - 0.6 * far
            a_ = T.unit(band(rng().standard_normal(m), 28, hi, 2))
            for ch, sgn in ((L, 1.0), (R, -1.0)):
                own = T.unit(band(rng().standard_normal(m), 28, hi, 2))
                x = (corr * a_ + np.sqrt(1 - corr ** 2) * own) * env + boom
                p = rng().uniform(-0.5, 0.5) * sgn
                put(ch, x * lvl * (1 + p), tr)
            tr += rng().gamma(1.8, 0.95 + 0.25 * k)
            k += 1
        # the low roar after the blast's own has gone (it fades 16-19 s after arriving): from 13 s, dying by 22 s
        bed_env = 10 ** (np.interp(t + 2.4, [10.0, 13.5, 16.0, 18.0, 20.0, 22.0, 24.4], [-60, -24, -21, -23, -28, -36, -60]) / 20)
        bl, br = PB.shaped_noise(d, np.array([0.0, d]), np.array([[-12, -6, -6, -12, -20, -28, -36, -46, -56, -70],
                                                                  [-14, -6, -8, -15, -24, -33, -42, -52, -62, -76]], dtype=float),
                                 corr=np.array([1.0, 0.99, 0.95, 0.85, 0.7, 0.5, 0.4, 0.3, 0.2, 0.2]))
        # (at the level bed_env gives it, slowly heaving)
        unit_ = 1.0 / (np.sqrt(np.mean(((bl + br) / 2) ** 2)) + 1e-12)
        heave = np.exp(1.6 * PB.slow_random(n, 0.15, 1.2) / 8.686)
        L += bl * unit_ * bed_env * heave
        R += br * unit_ * bed_env * heave
        f = T.fade(n, 0.6, 3.0)
        L, R = PB.causal_lowcut(L * f, 16.0), PB.causal_lowcut(R * f, 16.0)
        # (the plan starts this 2.42 s after the blast: room made under its peaks)
        L, R = duck_under_blasts(L, R, -2.42)
    finish_abs("tail", L, R, tail_fade=1.0)


BUILD = {"drift": drift, "dive": dive, "ground": ground, "ground_alt": ground_alt, "blast": blast, "blast_alt": blast_alt,
         "rush": rush, "debris": debris, "tail": tail}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    a = ap.parse_args()
    soundlib.init(a.out)
    print(f"timeline from payload.rs: drift at {DRIFT_AT:.2f} s, dive at {DIVE_AT:.2f} s (cut {CUT:.2f} s in), strike {HIT:.2f} s")
    for name in a.only or NAMES:
        BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    if not path.exists():
        return
    sounds = json.loads(path.read_text())
    for name in NAMES:
        ev = f"{TH}.{name}"
        sounds[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
    path.write_text(json.dumps(sounds, indent=2))


if __name__ == "__main__":
    main()
