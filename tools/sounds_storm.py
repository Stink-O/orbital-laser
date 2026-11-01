"""The Supercell's sounds, all synthesised here from noise, pulses, resonators and filters (nothing sampled).

Thunder is modelled, not drawn: a bolt's channel is a tortuous path from the ground up into the cloud (and on along
its base), with branches; every few metres of it sends out its own short pressure pulse (an N-wave, longer and
duller the further it has come), arriving at the listener as far behind the flash as that bit of the channel is
far away, louder where the channel runs across the line of sight. The nearest part arrives first as a sharp crack,
the rest rolls in over seconds; a bolt's three to five return strokes, 40-90 ms apart, re-fire the channel, so a near
crack rips. Under it a tonal boom (a falling 40-75 Hz fundamental, its harmonics stacked on it so a phone hears the
weight) on the loudest clusters, and low rolls following the arrivals; then the land's echoes.

  buildup     the storm forming (0 is the strike's start): a hush, the wind rising out of it in gusts and a low
              pressure swell, leaves stirring, two far rolls of thunder (narrow, high, dark), the first heavy drops
  gusts       the storm's wind (14 s, faded in and out over 1.8 s, so the plan's beds overlap into one): a deep buffet,
              a broad rush rising and falling with each gust, a howl whose pitch climbs with the gust, leaves and grass
              thrashing; it swings a little from side to side
  rain        the rain bed (12 s, faded in and out over 1.5 s), the only rain there is (the pass draws it): a wide wash
              of countless drops, near drops ticking and plipping, heavier drops on the ground, a low drumming, sheets
              of it swelling with the wind; the wash further off darker
  rumble      thunder from a flicker in the cloud, kilometres off (5 variants): an intra-cloud channel, long and high,
              so no crack, a soft, long roll with echoes, narrow and dark, up in the sky
  crack       a bolt's thunder close by, within ~90 blocks (6 variants; 0 is when it reaches the player): the ripping
              crack of the strokes on the near channel, a heavy tonal boom (a 46-58 Hz fundamental falling, its
              harmonics on it), its body gently overdriven, then a short roll and the land's echoes (6 s, so a fast run
              of them stays a run of claps, not a wall)
  crack_mid   a bolt 90-260 blocks off (5 variants): a duller clap with a little tearing left in it, the boom, a
              lower roll, more echo (6 s)
  crack_far   a bolt further off (5 variants): mostly rumble, its clap only a soft knock under a deep, long roll
  finale      the colossal strike: a long tearing rip of many strokes, a huge crack, three tonal blows overdriven like
              a blast recorded too close, the discharge fizzing, a roll dying over twelve seconds off the land
  roar        a funnel's roar (4 variants, mono, played where the funnel is every second, 3 s each, a constant-power
              window, so the overlapping copies sum to one steady roar that moves with it): a deep turbulent rumble, the
              freight-train roar boiling over it, a rushing top, debris rattling and thudding in it

The bolts are not vanilla's (strike/storm.rs strikes the land itself): a vanilla bolt plays its own full-scale
thunder at the flash, whatever the distance, which `stopsound` could only cut a tick or more in, a pop and a click
before ours arrived. Each variant is its own event too (`supercell.crack3`), so the plan picks the take and never plays
one of the last two again. Every file's decoded true peak is held under -1.15 dBTP and the levels are set against each
other so the whole strike's mix peaks at or under -1 dBTP. `--listen` mixes it as Horizon plays it: every file summed
to mono ((L+R)/2, as the game decodes it), played to the listener at 0.596 in each ear, its pitch a change of speed,
on the tick it is due, then the game's output limiter.

    python3 tools/sounds_storm.py                # writes orbital-sounds/assets/orbital/sounds/supercell/*.ogg and adds
                                                 # the events to sounds.json, leaving every other sound as it is
    python3 tools/sounds_storm.py --only crack   # one
    python3 tools/sounds_storm.py --listen DIR   # and the WAV and MP3 of each, and the strike's mix as heard 60, 150, 500
                                                 # and 1500 blocks off, as the game mixes it, in DIR (and their peaks)
"""
import argparse, json, os, subprocess, sys, wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, white, band
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P
import sounds_nuke as N

TH = "supercell"
ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {"rumble": 5, "crack": 6, "crack_mid": 5, "crack_far": 5, "roar": 4}
NAMES = ["buildup", "gusts", "rain", "rumble", "crack", "crack_mid", "crack_far", "finale", "roar"]
# (the plan picks these takes itself: each variant its own event as well as the group's)
PICKED = ("rumble", "crack", "crack_mid", "crack_far")
# Each file's loudest 400 ms (dB; mono files as the game plays them): set against each other so the strike's mix stays
# under -1 dBTP (`--listen` checks it).
LEVEL = {"buildup": -19.0, "gusts": -23.0, "rain": -28.5, "rumble": -25.5, "crack": -14.0, "crack_mid": -17.5,
         "crack_far": -21.0, "finale": -10.8, "roar": -22.0}
TP_MAX = 10 ** (-1.15 / 20)
C = 343.0
LISTEN = None


def rng():
    return soundlib.rng


def n_of(d):
    return int(SR * d)


def fades(x, a, b):
    """Raised-cosine fade in over `a` s and out over `b` s."""
    n = len(x)
    e = np.ones(n)
    na, nb = n_of(a), n_of(b)
    if na:
        e[:na] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, na))
    if nb:
        e[-nb:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, nb))
    return x * e


def conv(x, ir):
    m = len(x) + len(ir)
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)]


# =========================================================================================================  thunder
def channel(ground_d, az, height, run, branches, tort=0.28, step=8.0, intra=False):
    """A bolt's channel as segments (midpoint, unit direction, length, weight, main?): from the ground `ground_d` m off
    at bearing `az` up to the cloud at `height`, then `run` m on along its base; `branches` side channels off it. An
    intra-cloud flash (`intra`) is only the run, at the cloud's height, `ground_d` off."""
    segs = []

    def walk(p, d, length, w, main, up):
        out = []
        s = 0.0
        while s < length:
            d = d + rng().normal(0, tort, 3)
            if up is not None:
                d[1] = up + 0.6 * d[1] - 0.6 * up
            d /= np.linalg.norm(d) + 1e-9
            q = p + d * step
            out.append(((p + q) / 2, d.copy(), step, w, main))
            p = q
            s += step
        return out, p

    if intra:
        p0 = np.array([ground_d * np.cos(az), height, ground_d * np.sin(az)])
        h = rng().uniform(0, 2 * np.pi)
        main, _ = walk(p0, np.array([np.cos(h), 0.0, np.sin(h)]), run, 1.0, True, 0.0)
        segs += main
    else:
        p0 = np.array([ground_d * np.cos(az), 0.0, ground_d * np.sin(az)])
        up, p = walk(p0, np.array([0.0, 1.0, 0.0]), height, 1.0, True, 0.85)
        h = rng().uniform(0, 2 * np.pi)
        run_, _ = walk(p, np.array([np.cos(h), 0.0, np.sin(h)]), run, 0.7, True, 0.0)
        segs += up + run_
    for _ in range(branches):
        a = segs[rng().integers(len(segs) // 6, len(segs))]
        d = rng().normal(0, 1, 3)
        d[1] = -abs(d[1]) * 0.8 if not intra else d[1] * 0.2
        br, _ = walk(a[0], d / np.linalg.norm(d), rng().uniform(80, 500), rng().uniform(0.25, 0.5), False, None)
        segs += br
    return segs


def arrivals(segs, strokes):
    """Each segment's pulses at the listener (the origin): (time after the first arrival, amplitude, distance, pan)."""
    ts, amps, dist, pans = [], [], [], []
    r0 = min(np.linalg.norm(s[0]) for s in segs)
    for k, (s0, a0) in enumerate(strokes):
        for p, d, ln, w, main in segs:
            if k > 0 and not main:
                continue
            r = np.linalg.norm(p)
            los = p / r
            # (a straight bit radiates across its length: loudest seen side on)
            side = 0.12 + (1 - np.dot(d, los) ** 2) ** 1.5
            ts.append(s0 + (r - r0) / C)
            amps.append(a0 * w * side * ln / max(r, 25.0))
            dist.append(r)
            pans.append(np.clip(p[0] / max(np.hypot(p[0], p[2]), 1.0), -1, 1))
    return np.array(ts), np.array(amps), np.array(dist), np.array(pans)


def nwave(T_):
    """One N-wave `T_` s long (a sharp rise, a slide through zero, a sharp return), a little rounded."""
    m = max(int(T_ * SR), 4)
    w = 1.0 - 2.0 * np.arange(m) / (m - 1)
    return np.concatenate([[0.0], w, [0.0]])


def pulses(d, t0, ts, amps, dist, pans, width=0.8, fc_ref=60.0, fc_top=11000.0, bins=18):
    """The arrivals as sound: grouped by distance, each group's pulse train convolved with its N-wave (longer further
    off), through the air (a lowpass falling with distance) and panned `width` as wide as the channel is. Stereo."""
    n = n_of(d)
    L = np.zeros(n); R = np.zeros(n)
    edges = np.geomspace(dist.min() * 0.999, dist.max() * 1.001, bins + 1)
    for b in range(bins):
        sel = (dist >= edges[b]) & (dist < edges[b + 1])
        if not sel.any():
            continue
        r = np.sqrt(edges[b] * edges[b + 1])
        idx = (n_of(t0) + (ts[sel] * SR).astype(int) + rng().integers(-6, 7, sel.sum()))
        ok = (idx >= 0) & (idx < n)
        a = amps[sel][ok] * rng().uniform(0.6, 1.4, ok.sum())
        pn = pans[sel][ok] * width
        tl = np.zeros(n); tr = np.zeros(n)
        np.add.at(tl, idx[ok], a * np.sqrt(0.5 * (1 - pn)))
        np.add.at(tr, idx[ok], a * np.sqrt(0.5 * (1 + pn)))
        kern = nwave(0.0035 * (r / 60.0) ** 0.3)
        fc = float(np.clip(fc_top * (fc_ref / r) ** 0.75, 140.0, fc_top))
        for t_, out in ((tl, L), (tr, R)):
            y = np.convolve(t_, kern)[:n]
            out += band(y, 25, fc, 2)
    return L, R


def env_of(ts, amps, d, t0, smooth=0.06):
    """The arrivals' energy over time, smoothed (`smooth` s): where the booms and the rolls swell."""
    n = n_of(d)
    e = np.zeros(n)
    idx = n_of(t0) + (ts * SR).astype(int)
    ok = (idx >= 0) & (idx < n)
    np.add.at(e, idx[ok], amps[ok] ** 2)
    k = np.exp(-np.arange(n_of(smooth * 6)) / (smooth * SR))
    e = np.sqrt(np.maximum(np.convolve(e, k)[:n], 0))
    return e / (e.max() + 1e-12)


def blow(n, t0, f_hi, f_lo, f_end, drop, rise, decs, drive=3.0, octv=0.32, h3=0.18, harm=0.45):
    """A tonal boom: f_hi falling to f_lo over `drop` s and on to f_end; its octave, twelfth and driven harmonics
    stacked on it (so it is heard as weight on small speakers too)."""
    t = np.arange(n) / SR
    uu = np.maximum(t - t0, 0)
    m = t >= t0
    f = f_end + (f_lo - f_end) * np.exp(-uu / 0.6) + (f_hi - f_lo) * np.exp(-uu / drop)
    ph = 2 * np.pi * np.cumsum(f * m) / SR + rng().uniform(0, 6.28)
    env = (1 - np.exp(-uu / rise)) * sum(w * np.exp(-uu / tc) for w, tc in decs) * m
    s_ = np.sin(ph)
    hh = (np.tanh(drive * s_ + 0.3) - np.tanh(0.3)) / np.tanh(drive)
    hh = band(hh - s_ * 0.9, None, 700, 2)
    return (s_ + octv * np.sin(2 * ph + rng().uniform(0, 6.28)) + h3 * np.sin(3 * ph + rng().uniform(0, 6.28)) + harm * hh) * env


def low_rolls(d, e, lo=38.0, hi=220.0, corr=0.8):
    """Low rolls following the arrivals' energy `e`: low noise swelling with it, a little lumpy. Stereo, `corr` alike."""
    n = n_of(d)
    a = T.unit(band(white(d), lo, hi, 2))
    out = []
    for _ in range(2):
        b = T.unit(band(white(d), lo, hi, 2))
        x = (corr * a + np.sqrt(1 - corr ** 2) * b) * e * np.clip(1 + 0.5 * PB.slow_random(n, 1.0, 6.0), 0.1, None)
        out.append(x)
    return out


def echoes(L, R, d, taps, lo=40, corr=0.85, pan=0.6):
    """The land's echoes of `L`, `R`: (delay, gain, highest Hz) each, smeared a little, panned at random."""
    n = n_of(d)
    src = (L + R) / 2
    oL = np.zeros(n); oR = np.zeros(n)
    for dt, g, hi in taps:
        e = band(src, lo, hi * rng().uniform(0.85, 1.15), 2) * g
        ir_n = n_of(0.3); s_ = np.arange(ir_n) / SR
        ir = rng().standard_normal(ir_n) * np.exp(-s_ / 0.06)
        ir /= np.sqrt(np.sum(ir ** 2))
        e = conv(e, ir)
        l, r = PB.pan2(e, rng().uniform(-pan, pan))
        P.put(oL, l, dt); P.put(oR, r, dt)
    return L + oL, R + oR


def sky_verb(L, R, length, wet, darken, decay, corr):
    """A long, dark outdoor tail, its two sides `corr` alike."""
    irA = T.outdoor_ir(length, int(rng().integers(0, 999)), density=45.0, darken=darken, decay=decay)
    irB = T.outdoor_ir(length, int(rng().integers(0, 999)), density=45.0, darken=darken, decay=decay)
    irR = corr * irA + np.sqrt(1 - corr ** 2) * irB
    return L + conv(L, irA) * wet, R + conv(R, irR) * wet


def thunder(seed, d, ground_d, height, run, branches, strokes, boom, crack_db, roll_db, boom_db, verb, taps, width,
            t0=0.03, intra=False, fc_ref=60.0, rip=None, roll_corr=0.8, echo_pan=0.6, clap=None):
    """One bolt's thunder (see the module's notes), its first arrival `t0` s in. `boom`: the tonal blows as (delay after
    the first arrival, f_hi, f_lo, f_end, drop, rise, decays, gain); `verb`: (length, wet, darken, decay, corr); `clap`:
    (lo Hz, hi Hz, dB): the near channel's blast at each stroke, a short burst of air shoved (the clap the ear takes for
    the strike itself), so it stands out of the roll before it."""
    n = n_of(d)
    with PB.seeded(seed):
        az = rng().uniform(0, 2 * np.pi)
        segs = channel(ground_d, az, height, run, branches, intra=intra)
        ts, amps, dist, pans = arrivals(segs, strokes)
        L, R = pulses(d, t0, ts, amps, dist, pans, width=width, fc_ref=fc_ref)
        pk = max(np.abs(L).max(), np.abs(R).max()) + 1e-12
        L, R = L / pk * 10 ** (crack_db / 20), R / pk * 10 ** (crack_db / 20)
        if rip is not None:
            # (the strokes' tearing on the near channel: a burst of snaps, denser and harder to its end)
            lo, hi, length, count, rdb = rip
            x = np.zeros(n)
            for k in range(count):
                u = (k / max(count - 1, 1)) ** 0.6
                seg = band(rng().standard_normal(n_of(0.02)), lo * rng().uniform(0.7, 1.3), hi, 2) * np.exp(-np.arange(n_of(0.02)) / SR / rng().uniform(0.0008, 0.003))
                P.put(x, seg * rng().uniform(0.3, 1.0) * (0.35 + 0.65 * u), t0 + length * u + rng().uniform(-0.003, 0.003))
            x = x / (np.abs(x).max() + 1e-12) * 10 ** (rdb / 20)
            l, r = PB.pan2(x, rng().uniform(-0.3, 0.3))
            L += l; R += r
        if clap is not None:
            lo, hi, cdb = clap
            x = np.zeros(n)
            for s0, a0 in strokes:
                m = n_of(0.12)
                u_ = np.arange(m) / SR
                b_ = band(rng().standard_normal(m), lo, hi, 2) * np.exp(-u_ / rng().uniform(0.018, 0.032)) * np.minimum(u_ / 0.0015, 1)
                P.put(x, b_ * a0, t0 + s0)
            x = x / (np.abs(x).max() + 1e-12) * 10 ** (cdb / 20)
            l, r = PB.pan2(x, rng().uniform(-0.2, 0.2))
            L += l; R += r
        e = env_of(ts, amps, d, t0)
        rl, rr = low_rolls(d, e ** 0.8, corr=roll_corr)
        g = 10 ** (roll_db / 20) / (T.loudest((rl + rr) / 2) + 1e-12)
        L += rl * g; R += rr * g
        bm = np.zeros(n)
        for dt, f_hi, f_lo, f_end, drop, rise, decs, gain in boom:
            bm += blow(n, t0 + dt, f_hi, f_lo, f_end, drop, rise, decs) * gain
        bm = bm / (T.loudest(bm) + 1e-12) * 10 ** (boom_db / 20)
        L += bm; R += bm
        # (the lows' own harmonics, so a phone or a laptop hears the boom's weight)
        u = np.arange(n) / SR - t0
        L, R = P.alt_harmonics(L, R, u, u >= 0, -8.0, 0.0, (t0, t0 + 0.4))
        L, R = echoes(L, R, d, taps, pan=echo_pan)
        L, R = sky_verb(L, R, *verb)
        L, R = PB.causal_lowcut(L, 22.0), PB.causal_lowcut(R, 22.0)
    return L, R


def strokes_of(k, gap=(0.035, 0.09), first=1.0):
    s, out = 0.0, [(0.0, first)]
    for i in range(k - 1):
        s += rng().uniform(*gap)
        out.append((s, rng().uniform(0.35, 0.75)))
    return out


# ===========================================================================================================  writing
def true_peak(x):
    from scipy.signal import resample_poly
    return float(np.abs(resample_poly(x, 4, 1, axis=0)).max())


def decoded(path, ch):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, ch).astype(float)


def write(name, x, db, knee=None):
    """`x` (a pair: stereo; else mono) with its loudest 400 ms at `db` dB, band-limited to 15 kHz, its peaks (with
    `knee`, first rounded by a soft clip) limited until the decoded true peak is under TP_MAX. The .ogg into the mod's
    sounds; a WAV and an MP3 for listening."""
    if isinstance(x, tuple):
        m = max(len(x[0]), len(x[1]))
        y = np.zeros((m, 2))
        y[:len(x[0]), 0] = x[0]; y[:len(x[1]), 1] = x[1]
    else:
        y = np.asarray(x, float)[:, None].copy()
    y -= y.mean(axis=0)
    y = np.stack([band(y[:, k], None, 15000, 4) for k in range(y.shape[1])], axis=1)
    nf = n_of(0.03)
    y[-nf:] *= np.linspace(1, 0, nf)[:, None]
    y *= 10 ** (db / 20) / (T.loudest(y.mean(axis=1)) + 1e-12)
    path = f"{soundlib.OUT}/assets/orbital/sounds/{TH}/{name}"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ch = y.shape[1]
    c = TP_MAX * 0.97
    for _ in range(8):
        z = PB.soft_clip(y, c, knee) if knee else y
        z = PB.limit(z, c) if np.abs(z).max() > c else z
        PB.write_ogg(path, z, ch)
        dec = decoded(path + ".ogg", ch)
        tp = true_peak(dec)
        if tp <= TP_MAX:
            break
        c *= TP_MAX / tp * 0.995
    if LISTEN:
        os.makedirs(LISTEN, exist_ok=True)
        st = dec if ch == 2 else np.repeat(dec, 2, axis=1)
        N.write_wav(f"{LISTEN}/{name}.wav", st)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"{LISTEN}/{name}.wav", "-b:a", "192k", f"{LISTEN}/{name}.mp3"], check=True)
    lv = 20 * np.log10(T.loudest(dec.mean(axis=1)) + 1e-12)
    print(f"wrote {TH}/{name:12s} {len(dec) / SR:5.2f}s  {'stereo' if ch == 2 else 'mono  '}  loudest {lv:5.1f} dB  "
          f"peak {20 * np.log10(np.abs(dec).max()):5.1f} dBFS  true peak {20 * np.log10(tp):5.2f} dBTP")


# =============================================================================================================  wind
def gust_curve(d, rate=0.35, floor=0.15, sharp=1.6):
    """How hard the wind blows over time: slow swells with sharper rises (a gust comes on faster than it dies), 0..~1.3."""
    n = n_of(d)
    a = PB.slow_random(n, 0.04, rate)
    b = PB.slow_random(n, rate, rate * 4)
    g = np.clip(0.55 + 0.32 * a + 0.12 * b, 0, None)
    return floor + (1 - floor) * g ** sharp


def wind(d, gust, side=None):
    """The wind at the player for gust curve `gust`: a deep buffet, a broad rush, a howl whose pitch rises with the gust,
    leaves and grass thrashing over the top. Stereo, the rush and the top a little different in each ear."""
    n = n_of(d)
    if side is None:
        side = 0.35 * PB.slow_random(n, 0.03, 0.2)
    buffet = T.unit(band(white(d), 25, 120, 2)) * gust ** 2 * np.clip(1 + 0.6 * PB.slow_random(n, 2.0, 8.0), 0, None) * 0.35
    out = []
    shared = T.unit(band(white(d), 180, 2200, 1))
    howl_f = 340.0 + 420.0 * np.clip(gust, 0, 1.4)
    howl = P.glide_band(d, howl_f, 0.18) * np.clip(gust - 0.35, 0, None) ** 1.4 * 0.3
    howl2 = P.glide_band(d, howl_f * 1.52, 0.12) * np.clip(gust - 0.5, 0, None) ** 1.6 * 0.16
    for sgn in (-1.0, 1.0):
        own = T.unit(band(white(d), 180, 2200, 1))
        rush = (0.75 * shared + 0.66 * own) * gust ** 1.5 * 0.5
        top = T.unit(band(white(d), 1800, 7500, 2)) * gust ** 2.4 * np.clip(1 + 0.8 * PB.slow_random(n, 3.0, 14.0), 0, None) * 0.12
        x = buffet + rush + (howl + howl2) * (1 + 0.15 * sgn) + top
        out.append(x * (1 + sgn * side))
    return out


def build_gusts():
    d = 14.0
    with PB.seeded(91201):
        g = gust_curve(d)
        L, R = wind(d, g)
        L, R = fades(L, 1.8, 1.8), fades(R, 1.8, 1.8)
    write("gusts", (L, R), LEVEL["gusts"])


# =============================================================================================================  rain
def rain(d, density=1.0):
    """The rain: a wide wash of countless drops, near drops ticking and plipping (a bubble's rising chirp), heavier
    drops on the ground, a low drumming, sheets of it swelling with the wind. Stereo, wide (it is all round)."""
    n = n_of(d)
    sheet = np.exp(2.2 * PB.slow_random(n, 0.05, 0.35) / 8.686)
    L = np.zeros(n); R = np.zeros(n)
    # (the wash: pink-ish noise peaking 2-6 kHz, a darker one further off)
    for ch in (L, R):
        wash = T.unit(band(white(d), 600, 11000, 1)) * 0.5 + T.unit(band(white(d), 2000, 7000, 2)) * 0.5
        far = T.unit(band(white(d), 250, 2800, 2)) * 0.45
        drum = T.unit(band(white(d), 70, 420, 2)) * 0.22 * np.clip(1 + 0.4 * PB.slow_random(n, 0.3, 2.0), 0.2, None)
        ch += (wash * 0.32 + far + drum) * sheet
    # (near drops: ticks of many sizes, some ringing as a bubble's chirp)
    for t1 in P.poisson_times(0.0, d - 0.02, lambda v: 650.0 * density):
        a = min(rng().pareto(2.2) * 0.3 + 0.08, 2.5)
        p = rng().uniform(-1, 1)
        if rng().random() < 0.16:
            m = n_of(0.025)
            s_ = np.arange(m) / SR
            f0 = rng().uniform(1100, 3600)
            f = f0 * (1 + 0.6 * s_ / 0.025)
            x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-s_ / rng().uniform(0.004, 0.012)) * a * 0.5
        else:
            m = n_of(0.004)
            x = band(rng().standard_normal(m) * np.exp(-np.arange(m) / SR / rng().uniform(0.0002, 0.0007)), rng().uniform(900, 3000), 12000, 1) * a
        k = int(t1 * SR)
        e = min(m, n - k)
        g = sheet[k]
        L[k:k + e] += x[:e] * (1 - p) * 0.5 * g * 0.9
        R[k:k + e] += x[:e] * (1 + p) * 0.5 * g * 0.9
    # (heavier drops on the ground and on leaves, now and then)
    for t1 in P.poisson_times(0.0, d - 0.1, lambda v: 22.0 * density):
        m = n_of(0.06)
        s_ = np.arange(m) / SR
        x = T.unit(band(rng().standard_normal(m), 250, 2200, 2)) * np.exp(-s_ / rng().uniform(0.008, 0.02)) * np.minimum(s_ / 0.0008, 1)
        x *= rng().uniform(0.05, 0.22)
        p = rng().uniform(-1, 1)
        P.put(L, x * (1 - p) * 0.5, t1); P.put(R, x * (1 + p) * 0.5, t1)
    return L, R


def build_rain():
    d = 12.0
    with PB.seeded(91301):
        L, R = rain(d)
        L, R = fades(L, 1.5, 1.5), fades(R, 1.5, 1.5)
    write("rain", (L, R), LEVEL["rain"])


# ==========================================================================================================  build-up
def build_buildup():
    d = 12.0
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(91101):
        rise = np.clip(t / d, 0, 1)
        g = gust_curve(d, rate=0.3, floor=0.05) * (0.15 + 0.85 * rise ** 1.4)
        L, R = wind(d, g)
        # (a low pressure swell under it: the storm's weight gathering)
        sw = T.unit(band(white(d), 22, 70, 3)) * rise ** 2.2 * (1 + 0.3 * PB.slow_random(n, 0.1, 0.6))
        hum = blow(n, 0.0, 41.0, 39.0, 38.0, 1.0, 4.0, ((1.0, 60.0),), harm=0.3) * rise ** 2.5 * 0.5
        L += (sw * 0.5 + hum) * 0.35; R += (sw * 0.5 + hum) * 0.35
        # (the first heavy drops near the end)
        dl, dr = rain(d, 0.25)
        ramp = np.clip((t - 8.5) / 3.5, 0, 1) ** 2
        L += dl * ramp * 0.5; R += dr * ramp * 0.5
        lv = T.loudest((L + R) / 2)
        # (two far rolls of thunder, up in the cloud)
        for t1, s, db in ((5.2, 91111, -6.0), (9.4, 91112, -3.0)):
            rl, rr = rumble_one(s, d - t1)
            gg = lv * 10 ** (db / 20) / (T.loudest((rl + rr) / 2) + 1e-12)
            P.put(L, rl * gg, t1); P.put(R, rr * gg, t1)
        L, R = fades(L, 0.6, 0.8), fades(R, 0.6, 0.8)
    write("buildup", (L, R), LEVEL["buildup"])


# ==========================================================================================================  thunder
def rumble_one(seed, d):
    """Intra-cloud thunder kilometres off: no crack, a long soft roll with echoes, narrow, dark, high up."""
    with PB.seeded(seed):
        gd = rng().uniform(1800, 4000)
        h = rng().uniform(1500, 2600)
        run = rng().uniform(1500, 4000)
        f = rng().uniform(44, 56)
        boom = [(rng().uniform(0.3, 1.2), f * 1.25, f, f * 0.85, 0.25, 0.12, ((0.6, 0.8), (0.4, 2.0)), 1.0),
                (rng().uniform(1.5, 3.0), f * 1.1, f * 0.9, f * 0.8, 0.3, 0.2, ((1.0, 1.4),), 0.6)]
        st = [(0.0, 1.0), (rng().uniform(0.1, 0.3), 0.5)]
    return thunder(seed + 1, d, gd, h, run, 6, st, boom, -4.0, -14.0, -15.0,
                   (5.0, 0.7, (900, 140), 2.2, 0.85), [(0.9, 0.35, 500), (1.9, 0.25, 350), (3.2, 0.18, 260)], 0.25,
                   t0=0.25, intra=True, fc_ref=40.0, roll_corr=0.93, echo_pan=0.3)


def build_rumble(v):
    d = 9.0
    L, R = rumble_one(92000 + 17 * v, d)
    L, R = fades(L, 0.2, 1.5), fades(R, 0.2, 1.5)
    write(f"rumble{v}", (L, R), LEVEL["rumble"])


def body_drive(L, R, t0, db=3.0, hold=0.4, ease=0.9):
    """The 40-400 Hz body gently overdriven (a lopsided tanh, unity for small signals), most on the boom's first `hold`
    s and easing off after: the clap thickened as if recorded close, the sub and the crack's top left clean."""
    n = len(L)
    u = np.maximum(np.arange(n) / SR - t0, 0)
    g = 10 ** (db * np.exp(-np.maximum(u - hold, 0) / ease) / 20)
    ref = np.percentile(np.abs(band((L + R) / 2, 40, 400, 2)), 99.9) + 1e-12
    bias = 0.12
    out = []
    for x in (L, R):
        body = band(x, 40, 400, 2)
        z = g * body / ref
        sat = (np.tanh(z + bias) - np.tanh(bias)) / (1 - np.tanh(bias) ** 2)
        out.append(x - body + band(sat * ref / g, 35, 2500, 2) * g ** 0.5)
    return out


def build_crack(v):
    """A bolt close by: its strokes ripping on the near channel, a heavy boom, a short roll, the land's echoes."""
    d = 6.0
    with PB.seeded(93000 + 31 * v):
        gd = rng().uniform(25, 80)
        h = rng().uniform(900, 1600)
        k = int(rng().integers(3, 6))
        st = strokes_of(k)
        f = rng().uniform(46, 58)
        boom = [(0.004, f * 1.45, f, f * 0.7, 0.05, 0.003, ((0.55, 0.22), (0.35, 0.7), (0.1, 1.6)), 1.0),
                (st[1][0] + 0.004, f * 1.2, f * 0.92, f * 0.68, 0.06, 0.006, ((0.6, 0.3), (0.4, 0.9)), 0.5),
                (rng().uniform(0.45, 0.9), f * 0.95, f * 0.8, f * 0.64, 0.2, 0.06, ((0.5, 0.5), (0.5, 1.4)), 0.3),
                (rng().uniform(1.3, 2.2), f * 0.85, f * 0.72, f * 0.6, 0.3, 0.12, ((1.0, 1.2),), 0.15)]
        rip = (1200, 14000, st[-1][0] + rng().uniform(0.05, 0.1), int(rng().integers(40, 80)), -1.5)
        run, br = rng().uniform(400, 1500), int(rng().integers(4, 8))
    L, R = thunder(93500 + 31 * v, d, gd, h, run, br, st, boom,
                   0.0, -26.0, -12.0, (2.6, 0.16, (2400, 220), 0.8, 0.7),
                   [(0.3, 0.16, 2400), (0.7, 0.11, 1500), (1.25, 0.07, 900), (2.0, 0.05, 600)], 0.7, rip=rip,
                   clap=(250, 9000, 2.0))
    # (the boom's body driven a little and held together, as a recording too close: power, the sub kept clean)
    L, R = body_drive(L, R, 0.03, 3.0)
    L, R = N.glue(L, R)
    L, R = fades(L, 0.0, 1.0), fades(R, 0.0, 1.0)
    write(f"crack{v}", (L, R), LEVEL["crack"], knee=0.6)


def build_crack_mid(v):
    """A bolt 90-260 blocks off: a duller clap with a little tearing left in it, the boom, a longer roll, more echo."""
    d = 6.0
    with PB.seeded(93700 + 31 * v):
        gd = rng().uniform(150, 300)
        h = rng().uniform(1000, 2000)
        st = strokes_of(int(rng().integers(2, 5)))
        f = rng().uniform(44, 54)
        boom = [(0.01, f * 1.35, f, f * 0.72, 0.08, 0.01, ((0.5, 0.3), (0.5, 1.1)), 1.0),
                (rng().uniform(0.5, 1.1), f * 1.0, f * 0.84, f * 0.68, 0.22, 0.08, ((0.5, 0.6), (0.5, 1.6)), 0.3),
                (rng().uniform(1.6, 2.8), f * 0.88, f * 0.74, f * 0.64, 0.3, 0.15, ((1.0, 1.5),), 0.18)]
        rip = (900, 6000, st[-1][0] + rng().uniform(0.04, 0.08), int(rng().integers(12, 24)), -9.0)
        run, br = rng().uniform(800, 2200), int(rng().integers(4, 8))
    L, R = thunder(93900 + 31 * v, d, gd, h, run, br, st, boom,
                   -3.0, -27.0, -12.0, (3.2, 0.2, (1600, 200), 1.1, 0.78),
                   [(0.5, 0.16, 1400), (1.1, 0.11, 900), (1.9, 0.08, 600), (2.9, 0.05, 400)], 0.5, t0=0.04, fc_ref=50.0,
                   rip=rip, roll_corr=0.85, echo_pan=0.45, clap=(150, 3800, 4.0))
    L, R = body_drive(L, R, 0.04, 2.0)
    L, R = fades(L, 0.0, 1.6), fades(R, 0.0, 1.6)
    write(f"crack_mid{v}", (L, R), LEVEL["crack_mid"], knee=0.6)


def build_crack_far(v):
    """A bolt further off: mostly rumble, the clap only a soft knock under a deep, long roll, more of the land's echo,
    narrower."""
    d = 9.0
    with PB.seeded(94000 + 31 * v):
        gd = rng().uniform(450, 1100)
        h = rng().uniform(1100, 2200)
        st = strokes_of(int(rng().integers(2, 5)))
        f = rng().uniform(40, 50)
        boom = [(0.02, f * 1.25, f, f * 0.8, 0.12, 0.03, ((0.5, 0.4), (0.5, 1.4)), 0.8),
                (rng().uniform(0.6, 1.4), f * 1.05, f * 0.85, f * 0.72, 0.25, 0.1, ((0.5, 0.8), (0.5, 2.2)), 0.6),
                (rng().uniform(2.0, 3.5), f * 0.9, f * 0.75, f * 0.66, 0.3, 0.2, ((1.0, 1.8),), 0.4)]
        run, br = rng().uniform(1000, 3000), int(rng().integers(4, 8))
    L, R = thunder(94500 + 31 * v, d, gd, h, run, br, st, boom,
                   -6.0, -15.0, -11.0, (4.5, 0.45, (1300, 180), 1.6, 0.82),
                   [(0.6, 0.32, 900), (1.4, 0.24, 600), (2.4, 0.16, 400), (3.6, 0.1, 300)], 0.3, t0=0.06, fc_ref=45.0,
                   roll_corr=0.9, echo_pan=0.35, clap=(70, 700, 0.0))
    L, R = fades(L, 0.0, 1.5), fades(R, 0.0, 1.5)
    write(f"crack_far{v}", (L, R), LEVEL["crack_far"], knee=0.6)


def build_finale():
    """The colossal strike: seven bolts at once on the target, a long tearing rip of their many strokes, a huge crack,
    three tonal blows overdriven like a blast recorded too close (the sub clean), the discharge fizzing, a long roll
    off the land dying over twelve seconds."""
    d = 16.0
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(95001):
        st = [(0.0, 1.0)]
        s = 0.0
        for _ in range(9):
            s += rng().uniform(0.03, 0.075)
            st.append((s, rng().uniform(0.5, 0.95)))
        boom = [(0.004, 82.0, 52.0, 38.0, 0.05, 0.003, ((0.5, 0.3), (0.35, 1.0), (0.15, 2.6)), 1.0),
                (0.16, 70.0, 46.0, 36.0, 0.06, 0.006, ((0.6, 0.4), (0.4, 1.4)), 0.6),
                (0.55, 58.0, 42.0, 34.0, 0.15, 0.03, ((0.5, 0.8), (0.5, 2.4)), 0.5),
                (1.6, 50.0, 38.0, 33.0, 0.3, 0.12, ((1.0, 2.4),), 0.35)]
        rip = (1200, 13000, s + 0.06, 160, -1.0)
    L, R = thunder(95101, d, 40.0, 1800.0, 3500.0, 14, st, boom, 0.0, -14.0, -9.0, (6.0, 0.5, (1800, 160), 3.0, 0.75),
                   [(0.4, 0.34, 2000), (0.95, 0.26, 1300), (1.7, 0.2, 800), (2.7, 0.14, 500), (4.0, 0.1, 350),
                    (5.6, 0.07, 280), (7.4, 0.05, 240)], 0.8, rip=rip)
    # (the discharge rolling on round the sky: two long rolls high up, further off each)
    lv = T.loudest((L + R) / 2)
    for t1, sd, db in ((2.2, 95301, -9.0), (4.6, 95302, -13.0)):
        rl, rr = rumble_one(sd, d - t1)
        g = lv * 10 ** (db / 20) / (T.loudest((rl + rr) / 2) + 1e-12)
        P.put(L, rl * g, t1); P.put(R, rr * g, t1)
    with PB.seeded(95201):
        # (the discharge fizzing and crackling for a second and a half)
        fz = T.unit(band(white(d), 1500, 9000, 2)) * np.clip(N.grains(d, 500.0, (0.001, 0.003, 0.008)), 0, 8) ** 1.2
        fz *= np.exp(-np.maximum(t - 0.05, 0) / 0.6) * (t > 0.05) * (1 - np.exp(-np.maximum(t - 0.05, 0) / 0.02))
        lv = T.loudest((L + R) / 2)
        L += fz * lv * 0.12; R += np.roll(fz, 37) * lv * 0.12
    L, R = N.glue(L, R)
    L, R = N.overdrive(L, R, 0.03)
    L, R = fades(L, 0.0, 2.5), fades(R, 0.0, 2.5)
    write("finale", (L, R), LEVEL["finale"], knee=0.55)


# =============================================================================================================  roar
ROAR_D = 3.0


def build_roar(v):
    """A funnel's roar, mono (the game places it): a deep turbulent rumble, the freight-train roar boiling over it, a
    rushing top, debris rattling and thudding in it; a constant-power window (a sine rise over 1 s, 1 s flat, a sine
    fall), so the plan's copies a second apart sum to a steady roar."""
    d = ROAR_D
    n = n_of(d)
    t = np.arange(n) / SR
    with PB.seeded(96000 + 13 * v):
        boil = lambda lo, hi, db: np.exp(db * PB.slow_random(n, lo, hi) / 8.686)
        rumble = T.unit(band(white(d), 24, 110, 3)) * boil(0.5, 4.0, 3.0) * 1.1
        f = 46.0 + 5.0 * PB.slow_random(n, 0.2, 1.0)
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR + rng().uniform(0, 6.28))
        tone = (tone + 0.4 * np.sin(2 * np.pi * np.cumsum(2 * f) / SR) + 0.2 * np.sin(2 * np.pi * np.cumsum(3 * f) / SR)) * boil(0.3, 2.0, 2.0) * 0.25
        roar = (T.unit(band(white(d), 110, 900, 2)) * boil(1.5, 12.0, 4.0) * 0.8
                + T.unit(band(white(d), 350, 1600, 2)) * boil(2.0, 16.0, 5.0) * 0.45)
        top = T.unit(band(white(d), 1400, 6000, 2)) * boil(3.0, 20.0, 6.0) * 0.08
        x = rumble + tone + roar + top
        lv = np.std(x)
        # (debris in it: wood and stones clacking, things thudding, a rattle of grit)
        for t1 in P.poisson_times(0.0, d - 0.3, lambda u: 14.0):
            m = n_of(0.25)
            if rng().random() < 0.6:
                h = P.modal_hit(m, rng().uniform(500, 2400), [1.0, rng().uniform(1.4, 2.3), rng().uniform(2.6, 4.0)],
                                [rng().uniform(0.008, 0.03), 0.01, 0.005], [1.0, 0.6, 0.35], 0.4, 7000)
                h = h / (np.abs(h).max() + 1e-9) * rng().uniform(0.2, 1.0) ** 1.5 * lv * 0.5
            else:
                h = T.thud(m, rng().uniform(0.4, 1.4)) * lv * rng().uniform(0.3, 0.8)
                h = h / (np.abs(h).max() + 1e-9) * lv * 0.8
            P.put(x, h, t1)
        gr = np.clip(N.grains(d, 220.0, (0.002, 0.006)), 0, 6) ** 1.5
        x += T.unit(band(white(d), 1500, 7000, 2)) * gr * boil(1.0, 6.0, 4.0) * lv * 0.06
        x = PB.causal_lowcut(x, 20.0)
        w = np.ones(n)
        k = n_of(1.0)
        w[:k] = np.sin(0.5 * np.pi * np.arange(k) / k)
        w[-k:] = np.cos(0.5 * np.pi * np.arange(k) / k)
        x *= w
    write(f"roar{v}", x, LEVEL["roar"])


# ===========================================================================================================  listening
def game_limiter(mix, block=512, release=0.2):
    """audio.rs's output limiter: a callback's peak over 1 scales it down, the gain recovering over `release` s."""
    lp, rel = 1.0, np.exp(-1 / (release * SR))
    hits = 0
    for s0 in range(0, len(mix), block):
        blk = mix[s0:s0 + block]
        pk = max(1.0, float(np.abs(blk).max()))
        hits += pk > 1.0
        lp = max(lp, pk)
        k = np.arange(len(blk))
        blk *= (1 / np.maximum(lp * rel ** k, pk))[:, None]
        lp = max(lp * rel ** len(blk), pk)
    return hits * block / SR


def listen_mix(z, out):
    """The strike's sounds as a player `z` blocks off hears them in Horizon (their times, takes, volumes and pitches
    from the plan), mixed as the game does: each file summed to mono, 0.596 in each ear (a sound played to the
    listener), its pitch a change of speed, on its tick, then the output limiter."""
    tl = Path(out) / f"timeline_{z}.txt"
    subprocess.run(["cargo", "test", "--release", "--quiet", "--lib", "sc_write_sounds", "--", "--ignored"], cwd=ROOT / "mod",
                   env=dict(os.environ, SC_OUT=str(tl.resolve()), SC_ME=str(z)), check=True, capture_output=True)
    d = 66.0
    mix = np.zeros((n_of(d), 2))
    pick = np.random.default_rng(z)
    files = {}
    for line in tl.read_text().splitlines():
        t, ev, vol, pitch = line.split()[:4]
        if not ev.startswith(f"orbital:{TH}."):
            continue
        name = ev.split(".", 1)[1]
        f = f"{out}/{name}.wav" if os.path.exists(f"{out}/{name}.wav") else f"{out}/{name}{pick.integers(VARIANTS[name]) + 1}.wav"
        if f not in files:
            with wave.open(f) as w:
                y = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float).reshape(-1, w.getnchannels()) / 32768
            files[f] = y.mean(axis=1)
        y = files[f]
        p = float(pitch)
        if abs(p - 1) > 1e-4:
            pos = np.arange(0, len(y) - 1, p)
            i0 = pos.astype(int)
            y = y[i0] * (1 - (pos - i0)) + y[i0 + 1] * (pos - i0)
        i = n_of(np.ceil(float(t) * 20 - 1e-6) / 20)
        m = min(len(y), len(mix) - i)
        if m > 0:
            mix[i:i + m] += (y[:m] * min(float(vol), 1.0) * 0.596)[:, None]
    pre = 20 * np.log10(np.abs(mix).max() + 1e-12)
    held = game_limiter(mix)
    path = f"{out}/storm_mix_{z}"
    N.write_wav(path + ".wav", mix)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-b:a", "192k", path + ".mp3"], check=True)
    lufs, tp, _ = N.measure(path + ".wav")
    print(f"mix {z} blocks off: peak {pre:.2f} dBFS before the game's limiter ({held:.1f} s held down), true peak {tp:.2f} dBTP, "
          f"{lufs:.1f} LUFS -> {path}.wav")
    return tp


BUILD = {
    "buildup": build_buildup, "gusts": build_gusts, "rain": build_rain,
    "rumble": lambda: [build_rumble(v) for v in range(1, VARIANTS["rumble"] + 1)],
    "crack": lambda: [build_crack(v) for v in range(1, VARIANTS["crack"] + 1)],
    "crack_mid": lambda: [build_crack_mid(v) for v in range(1, VARIANTS["crack_mid"] + 1)],
    "crack_far": lambda: [build_crack_far(v) for v in range(1, VARIANTS["crack_far"] + 1)],
    "finale": build_finale,
    "roar": lambda: [build_roar(v) for v in range(1, VARIANTS["roar"] + 1)],
}


def main():
    global LISTEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also the WAV and MP3 of each, and the strike's mix, in this folder")
    a = ap.parse_args()
    soundlib.init(a.out)
    LISTEN = a.listen
    for name in a.only or NAMES:
        BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    if path.exists():
        sounds = json.loads(path.read_text())
        for name in NAMES:
            ev = f"{TH}.{name}"
            files = [f"orbital:{TH}/{name}{v + 1}" for v in range(VARIANTS[name])] if name in VARIANTS else [f"orbital:{TH}/{name}"]
            # (the roar is heard where the funnel is, out to 320 blocks; the rest follow the player)
            dist = 320 if name == "roar" else 256
            sounds[ev] = {"sounds": [{"name": f, "attenuation_distance": dist} for f in files], "subtitle": f"subtitles.orbital.{ev}"}
            if name in PICKED:
                for v in range(VARIANTS[name]):
                    sounds[f"{ev}{v + 1}"] = {"sounds": [{"name": files[v], "attenuation_distance": dist}], "subtitle": f"subtitles.orbital.{ev}"}
        path.write_text(json.dumps(sounds, indent=2))
    if LISTEN and not a.only:
        worst = max(listen_mix(z, LISTEN) for z in (60, 150, 500, 1500))
        print(f"worst true peak over the mixes: {worst:.2f} dBTP")


if __name__ == "__main__":
    main()
