"""The Nuke's sounds (a nuclear airburst), all synthesised here from noise, swept tones, resonators and filters. Nothing
is sampled or resynthesised from any recording: references were only ever measured (band levels, envelopes), never
copied.

Timeline the files are built for, as mod/src/strike/nuke.rs plays them (0 = the burst, the silent flash, NK_HIT = 11 s
into the strike; `dist` = the player's distance from the burst in blocks; `arrive` = dist / 343):

  fall        starts FALL_CUT s before the burst (NK_SEEN - 0.5) and is cut dead on it (FALL_CUT s into the file)
  ground      at dist / GROUND_V - GROUND_LEAD (the ground carries it five times faster than the air)
  blast       at arrive - BLAST_LEAD (BLAST_LEAD s of near-silence in the file, then the crack)
  blast_far   the same, cross-faded in by distance (`far_mix`: 300 to 900 blocks, smoothstep)
  shockwave   at arrive - SHOCK_FRONT (its front SHOCK_FRONT s into the file, on the blast's crack)
  rumble      at arrive + RUMBLE_AFTER (the blast's file RUMBLE_AFTER + BLAST_LEAD s ahead of it)
  debris      at arrive + 3.0 within 700 blocks, and again at arrive + 9.0 at pitch 0.9 closer than ~490

How each is made:

  fall        a dark roar (noise through a lowpass that opens as it comes down, its lows heavy), a falling whistle
              (two noise-excited resonances sliding down, never a pure tone), a low ominous drone under it (a narrow
              band of noise round 50 Hz with its own octave), all one source high in the sky: the same in both ears,
              darkened, in a long dark distant reverb. `nearness` keeps it far, narrow and dark until the last ~1.5 s,
              when the top opens, it widens a little and swells; cut dead on the detonation.
  blast       `explosion_live` (sounds_pk_blast.py: the roar, crack, pressure swing and debris of a very large
              explosion, synthesised to measured band levels) stretched long, and over it: a second hard crack 50-70 ms
              after the first (the airburst's wave and its reflection off the ground, the Mach stem), a boom sweeping
              from ~46 Hz down to ~31 Hz (a sine and a narrow noise band at the same pitch), a 50-120 Hz body of noise,
              a sub tail at 18-45 Hz heaving for ~15 s, the lows' own 2nd-4th harmonics (a soft-clipped copy of them,
              band-passed 70-420 Hz) so laptop and phone speakers imply the bass, the boom coming back off far land
              four times (darker each), and the fireball's crackle as distant clusters of pops with their echoes.
  blast_far   the blast through kilometres of air: everything over ~300 Hz let down (10-25 dB, more the higher), the
              crack's front smeared over ~40 ms, more low thunder rolls and a long dark outdoor reverb.
  shockwave   the blast wave going past: a low push of air, a violent roaring gust (wind noise whose octave levels
              follow a table, boiled by random surges, one side then the other), grit and debris rattling past
              (ticks and small modal hits), leaves and dust thrashing, dying away over ~4 s.
  rumble      the aftermath: deep swells of rumble rolling in from round the land (low noise bursts, each further off and
              darker), thunder-like rolls (low noise in uneven clumps of grains), a heaving sub bed; ~36 s, decaying.
  debris      rubble coming back down: heavy slabs and clods thudding, stones clacking and bouncing, crumbling grit
              (grains of band noise), near and far (the far ones darker and in the land's echo); ~6 s.
  ground      the land's answer through the ground: a falling sub thump (~40 Hz down to ~20), a sub rumble, the ground
              shuddering (low noise chopped at 9-14 Hz), a little of its harmonics so it reads on small speakers.

    python3 tools/sounds_nuke.py                     # writes orbital-sounds/assets/orbital/sounds/nuke/*.ogg, adds the
                                                     # nuke.* events to sounds.json (nothing else touched)
    python3 tools/sounds_nuke.py --only blast        # one (the blast before blast_far and the ones ducked under it)
    python3 tools/sounds_nuke.py --listen DIR        # also WAVs of each, and the whole strike heard from 200 and 600
                                                     # blocks, with their peaks, loudness and the blast's spectrum
"""
import argparse, json, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
import soundlib
from soundlib import SR, white, band
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P

TH = "nuke"
NAMES = ["fall", "ground", "blast", "blast_far", "shockwave", "rumble", "debris"]
ROOT = Path(__file__).resolve().parent.parent
PEAK = 10 ** (-1.2 / 20)                       # every file's decoded peak (dBFS), under -1 with the encoder's jitter
BLAST_PEAK = 10 ** (-2.0 / 20)                 # the blasts': a little room for what plays over them
DUCK_CEIL = 10 ** (-1.9 / 20)                  # what plays at a fixed moment against a blast is let down to keep the two
                                               # under this, leaving room for the ground's tail (its moment varies)
OCT = PB.OCT

# ---- the timeline (seconds; 0 = detonation)
FALL_CUT = 9.5
SPEED = 343.0
GROUND_V = 5 * SPEED
GROUND_LEAD = 0.02
BLAST_LEAD = 0.02
SHOCK_FRONT = 0.2
RUMBLE_AFTER = 1.5
DEBRIS_AFTER = (3.0, 9.0)


def rng():
    return soundlib.rng


def far_mix(dist):
    """How much of the blast is `blast_far` at `dist` blocks (the rest `blast`): none within 300, all past 900."""
    u = np.clip((dist - 300.0) / 600.0, 0, 1)
    return float(u * u * (3 - 2 * u))


def volumes(dist):
    """The volumes nuke.rs plays them at, `dist` blocks off (what the mixdowns use)."""
    far = far_mix(dist)
    late = dist / SPEED
    gap = late - dist / GROUND_V
    near = max(0.0, 1.0 - dist / 700.0)
    return {
        "fall": 1.0,
        "ground": float(np.clip(1.0 / (1.0 + dist / 1200.0), 0.35, 1.0) * np.clip((gap - 0.05) / 0.9, 0.3, 1.0) ** 1.2),
        "blast": 1.0 - far,
        "blast_far": far,
        "shockwave": float(np.clip(1.15 / (1.0 + dist / 450.0), 0.3, 1.0)),   # nuke.rs's nk_shock_vol
        "rumble": 1.0,
        "debris": (0.5 + 0.5 * near) if dist < 700 else 0.0,
        "debris2": (0.25 + 0.4 * near) if near > 0.3 else 0.0,
    }


def schedule(dist):
    """(event, file, start time against the burst, pitch) as nuke.rs plays them."""
    late = dist / SPEED
    return [("fall", "fall", -FALL_CUT, 1.0), ("ground", "ground", dist / GROUND_V - GROUND_LEAD, 1.0),
            ("blast", "blast", late - BLAST_LEAD, 1.0), ("blast_far", "blast_far", late - BLAST_LEAD, 1.0),
            ("shockwave", "shockwave", late - SHOCK_FRONT, 1.0), ("rumble", "rumble", late + RUMBLE_AFTER, 1.0),
            ("debris", "debris", late + DEBRIS_AFTER[0], 1.0), ("debris2", "debris", late + DEBRIS_AFTER[1], 0.9)]


def scaled(L, R, db):
    """`L`, `R` scaled so their loudest 400 ms is `db` dB."""
    g = 10 ** (db / 20) / (T.loudest((L + R) / 2) + 1e-12)
    return L * g, R * g


def finish(name, L, R, tail_fade=0.3):
    """Written at the level it was built to, decoded peak at most PEAK (look-ahead limiter, encoder overshoot fixed)."""
    old = P.TH
    P.TH = TH
    try:
        P.finish_abs(name, L, R, peak=PEAK, tail_fade=tail_fade)
    finally:
        P.TH = old


def finish_at(name, L, R, db, tail_fade=0.5, knee=0.5, peak=PEAK):
    """Its loudest 400 ms at `db` dB, the peaks rounded by a soft clip then held at `peak` decoded."""
    PB.finish_blast_decoded(f"{TH}/{name}", L, R, db, peak, tail_fade, knee)


def decoded(name):
    old = P.TH
    P.TH = TH
    try:
        return P.decoded(name)
    finally:
        P.TH = old


def pitched(x, pitch):
    """`x` (samples x 2) played at `pitch`, as the game does it (faster and higher, or slower and lower)."""
    if pitch == 1.0:
        return x
    m = int(len(x) / pitch)
    return np.stack([np.interp(np.arange(m) * pitch, np.arange(len(x)), x[:, k]) for k in range(x.shape[1])], axis=1)


def bed(n, parts):
    """What else plays under a sound `n` samples long: `parts` (file, start against it in seconds, volume), decoded."""
    out = np.zeros((n, 2))
    for nm, at, vol in parts:
        b = decoded(nm)
        if b is None:
            print(f"  ({nm} not built yet: not ducked under it)")
            continue
        k = int(round(at * SR))
        lo, hi = max(0, k), min(n, k + len(b))
        if hi > lo:
            out[lo:hi] += b[lo - k:hi - k] * vol
    return out


def duck_need(x, beds, ceiling=None):
    """The gain (a sample) `x` (samples x 2) needs so that, added to each of `beds`, nothing passes `ceiling`: only where
    the two meet with the same sign (or `x` alone would pass it) is it let down, and only as far as needed."""
    ceiling = DUCK_CEIL if ceiling is None else ceiling
    need = np.ones(len(x))
    for b in beds:
        for ch in range(2):
            a, c = x[:, ch], b[:, ch]
            over = np.abs(a + c) > ceiling
            if not over.any():
                continue
            same = np.sign(a) == np.sign(c)
            lim = np.where(same, ceiling - np.abs(c), ceiling + np.abs(c)) / np.maximum(np.abs(a), 1e-9)
            need = np.minimum(need, np.where(over, np.clip(lim, 0, 1), 1.0))
    return need


def smooth_gain(need, release=0.12):
    """A gain curve that dips in time (3 ms ahead) for every value in `need` and recovers over `release` seconds."""
    n = len(need)
    w = int(0.003 * SR)
    gp = np.pad(need, (w, w), constant_values=1.0)
    g = np.lib.stride_tricks.sliding_window_view(gp, 2 * w + 1).min(axis=1)[:n]
    kr = np.exp(-1.0 / (release * SR))
    out = np.empty(n)
    st = 1.0
    for i, v in enumerate(g):
        st = v if v < st else 1.0 - (1.0 - st) * kr
        out[i] = st
    return out


def duck_under(L, R, layouts, extra=()):
    """`L`, `R` eased down where, played with what `layouts` put under it, the sum would pass the ceiling. `layouts`:
    lists of (file, start against this sound, volume), one list for each way they can sound together (the near blast
    or the far one); `extra`: (pitch, start of this sound against the first's, layouts) for a repeat of this sound."""
    x = np.stack([L, R], axis=1)
    need = duck_need(x, [bed(len(x), lay) for lay in layouts])
    for pitch, at, lays in extra:
        xp = pitched(x, pitch)
        np_ = duck_need(xp, [bed(len(xp), lay) for lay in lays])
        need = np.minimum(need, np.interp(np.arange(len(x)) / pitch, np.arange(len(xp)), np_))
    g = smooth_gain(need)
    print(f"  ducked: at most {20 * np.log10(g.min() + 1e-9):.1f} dB, {np.mean(g < 0.89) * len(g) / SR:.2f} s of it over 1 dB")
    return L * g, R * g


def grains(d, rate, taus=(0.012, 0.025, 0.05)):
    """`PB.grains` (many little surges at random, averaging 1), convolved by FFT: the same curve, far quicker."""
    from scipy.signal import fftconvolve
    n = int(SR * d)
    out = np.zeros(n)
    for tau in taus:
        x = np.zeros(n)
        k = rng().poisson(rate * d / len(taus))
        np.add.at(x, rng().integers(0, n, k), np.minimum(rng().pareto(2.5, k) + 0.2, 6.0))
        s = np.arange(int(tau * SR * 6)) / SR
        kern = (1 - np.exp(-s / 0.002)) * np.exp(-s / tau)
        out += fftconvolve(x, kern)[:n] / (tau * SR)
    out = np.maximum(out, 0.0)                       # (the FFT's rounding leaves a hair under zero here and there)
    return out / (np.mean(out) + 1e-9)


def env_ar(n, t0, att, dec, sustain=0.0, dec2=None):
    """0 before t0, rising over `att`, decaying with `dec` (plus `sustain` of a second, slower decay `dec2`)."""
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    e = (1 - np.exp(-u / max(att, 1e-4))) * ((1 - sustain) * np.exp(-u / dec) + (sustain * np.exp(-u / dec2) if dec2 else 0))
    return e * (t >= t0)


def distant_verb(x, length=3.5, wet=0.6, darken=(2200, 300), decay=1.4, corr=0.85, seed_shift=0):
    """`x` (mono) in a distant outdoor reverb: the dry sound centred, the wet two tails `corr` alike (narrow)."""
    irA = T.outdoor_ir(length, seed_shift, density=50.0, darken=darken, decay=decay)
    irB = T.outdoor_ir(length, seed_shift + 1, density=50.0, darken=darken, decay=decay)
    irR = corr * irA + np.sqrt(1 - corr ** 2) * irB
    out = []
    for ir in (irA, irR):
        m = len(x) + len(ir)
        y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)]
        out.append(x + y * wet)
    return out


# ============================================================================================================  the fall
def nearness(t):
    """0 while the bomb is far up, 1 at the detonation: only its last ~1.5 s close in."""
    return np.clip((t - (FALL_CUT - 1.5)) / 1.3, 0, 1) ** 1.3


def fall():
    d = FALL_CUT + 1.0
    n = int(SR * d)
    t = np.arange(n) / SR
    prog = np.clip(t / FALL_CUT, 0, 1)
    near = nearness(t)
    with PB.seeded(77101):
        # ---- the roar: dark noise, a lowpass opening as it comes down; its lows heavy, wavering slowly
        x = white(d)
        lows = T.unit(band(x, 35, 160, 2))
        mids = T.unit(band(x, 120, 6000, 1))
        fc = 380 + 900 * prog ** 1.6 + 4200 * near ** 1.5
        mids = T.unit(PB.lowpass_track(mids, fc))
        wav = np.exp(2.2 * PB.slow_random(n, 0.2, 1.5) / 8.686)
        roar = (lows * 10 ** ((-36 + 14 * prog ** 1.4 + 5 * near) / 20)
                + mids * 10 ** ((-39 + 15 * prog ** 1.4 + 9 * near) / 20)) * wav
        # ---- the whistle: two resonances sliding down (1500 -> 620 Hz), the upper one coming up as it nears
        f0 = 620 + 880 * np.exp(-2.1 * prog) - 60 * near
        f0 = f0 * (1 + 0.004 * PB.slow_random(n, 0.3, 1.5) + 0.004 * near * PB.slow_random(n, 3.0, 7.0))
        wh = (P.glide_band(d, f0, 0.07) + 0.45 * P.glide_band(d, f0 * 1.52, 0.09) * (0.4 + 0.6 * near)
              + 0.2 * P.glide_band(d, f0 * 2.06, 0.1) * near)
        wh_air = 1400 + 1500 * prog + 6000 * near ** 1.5
        wh = PB.lowpass_track(wh, wh_air)
        wh *= 10 ** ((-37 + 17 * prog ** 1.2 + 6 * near) / 20) * np.exp(1.8 * PB.slow_random(n, 0.4, 2.5) / 8.686)
        # ---- the drone: a narrow band round ~52 Hz (falling a little) and its octave, swelling: weight bearing down
        fd = 54 - 6 * prog
        dr = P.glide_band(d, fd, 0.35) + 0.5 * P.glide_band(d, fd * 2.0, 0.3) + 0.25 * P.glide_band(d, fd * 3.0, 0.3)
        dr *= 10 ** ((-44 + 16 * prog ** 1.5 + 6 * near) / 20) * np.exp(1.5 * PB.slow_random(n, 0.1, 0.8) / 8.686)
        dry = roar + wh + dr
        # ---- far up: in a long, dark, distant reverb, narrow; drier and a little wider in its last moment
        wet_amt = 0.85 - 0.45 * near
        L, R = distant_verb(dry, 4.0, 1.0, darken=(1800, 260), decay=1.5, corr=0.9)
        L = dry + (L - dry) * wet_amt; R = dry + (R - dry) * wet_amt
        side = P.glide_band(d, f0 * 1.003, 0.08) * 10 ** ((-37 + 17 * prog ** 1.2 + 6 * near) / 20) * 0.25 * near
        side += T.unit(PB.lowpass_track(band(white(d), 300, 8000, 1), fc)) * 10 ** ((-42 + 15 * prog ** 1.4 + 9 * near) / 20) * 0.3 * near
        L, R = L + side, R - side
        # ---- fade in from nothing; cut dead on the detonation, a breath of dark air after (0.12 s)
        g = np.clip(t / 2.5, 0, 1) ** 2
        kc = int(FALL_CUT * SR)
        k6 = int(0.005 * SR)
        g[kc - k6:kc] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k6))
        g[kc:] = 0
        last = band((L + R)[kc - int(0.04 * SR):kc] * 0.5, 60, 900, 2)
        m = int(0.3 * SR)
        s = np.arange(m) / SR
        ir = band(rng().standard_normal(m), 60, 800, 2) * np.exp(-s / 0.05) * (1 - np.exp(-s / 0.003))
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        tl = np.convolve(last, ir)[: int(0.3 * SR)] * 0.25
        L, R = L * g, R * g
        P.put(L, tl, FALL_CUT - 0.04); P.put(R, tl, FALL_CUT - 0.04)
        L, R = PB.causal_lowcut(L, 22.0), PB.causal_lowcut(R, 22.0)
    L, R = scaled(L[:int((FALL_CUT + 0.5) * SR)], R[:int((FALL_CUT + 0.5) * SR)], -16.5)
    finish("fall", L, R, tail_fade=0.2)


# ===========================================================================================================  the blast
def pop_clusters(d, t_lo, t_hi, rate, level_db, decay):
    """The fireball crackling, far off: clusters of 3-8 pops within a few tenths of a second, each pop a short band of
    noise dulled by distance, each cluster echoed once or twice off the land, later and darker. Stereo, narrow."""
    n = int(SR * d)
    L = np.zeros(n); R = np.zeros(n)
    for tc in P.poisson_times(t_lo, t_hi, lambda v: rate * np.exp(-(v - t_lo) / decay)):
        p = rng().uniform(-0.3, 0.3)
        cl = np.zeros(int(0.6 * SR))
        tp = 0.0
        for _ in range(rng().integers(3, 9)):
            m = int(0.03 * SR)
            s = np.arange(m) / SR
            fc = np.exp(rng().uniform(np.log(700), np.log(2600)))
            x = band(rng().standard_normal(m), fc / 2.5, fc * 2, 2) * (1 - np.exp(-s / 0.0006)) * np.exp(-s / rng().uniform(0.003, 0.008))
            x = x / (np.sqrt(np.mean(x[:int(0.01 * SR)] ** 2)) + 1e-9) * min(rng().pareto(2.0) * 0.4 + 0.4, 2.5)
            P.put(cl, x, tp)
            tp += rng().exponential(0.05)
            if tp > 0.45:
                break
        cl = P.air(cl, 3200)
        a = 10 ** ((level_db - (tc - t_lo) / decay * 4.3) / 20)
        l, r = PB.pan2(cl * a, p)
        P.put(L, l, tc); P.put(R, r, tc)
        for e in range(rng().integers(1, 3)):
            dt = rng().uniform(0.35, 1.3) * (1 + e)
            ech = P.air(cl, 1400) * a * rng().uniform(0.25, 0.45) / (1 + e)
            l, r = PB.pan2(ech, rng().uniform(-0.6, 0.6))
            P.put(L, l, tc + dt); P.put(R, r, tc + dt)
    return L, R


def blast():
    d = 26.0
    n = int(SR * d)
    t = np.arange(n) / SR
    t0 = BLAST_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(77301):
        EL, ER = PB.explosion_live(d, t0, stretch=1.8, debris=1.1, whump=1.5, live=1.2)
        ref = T.loudest((EL + ER) / 2)                      # (every layer below is set against the roar's loudest)
        L, R = EL.copy(), ER.copy()
        # ---- the second crack: the wave off the ground (Mach stem), 50-70 ms after the first, a little duller
        gap = rng().uniform(0.05, 0.07)
        for tc, g, hi in ((t0, 0.7, 12000), (t0 + gap, 1.0, 7000)):
            m = int(0.12 * SR)
            s = np.arange(m) / SR
            cr = band(rng().standard_normal(m), 180, hi, 2) * (1 - np.exp(-s / 0.0003)) * np.exp(-s / 0.009)
            cr += band(rng().standard_normal(m), 60, 600, 2) * (1 - np.exp(-s / 0.001)) * np.exp(-s / 0.025) * 1.2
            cr = cr / (np.abs(cr).max() + 1e-9) * ref * 7.0 * g
            P.put(L, cr, tc); P.put(R, cr, tc)
        # ---- the boom: ~46 Hz sweeping down to ~31, a sine and a narrow band of noise at that pitch; rising in 30 ms
        f = 30.0 + 13.0 * np.exp(-u / 1.1)
        ph = 2 * np.pi * np.cumsum(f * on) / SR
        benv = (1 - np.exp(-u / 0.03)) * (0.55 * np.exp(-u / 0.8) + 0.45 * np.exp(-u / 3.2)) * on
        boom = (np.sin(ph) * 0.8 + 0.6 * P.glide_band(d, np.maximum(f, 20), 0.3)) * benv
        boom *= np.exp(1.5 * PB.slow_random(n, 0.3, 2.0) / 8.686)
        # ---- the body: 50-120 Hz noise, heavy for the first seconds
        body = T.unit(band(white(d), 50, 120, 3)) * (1 - np.exp(-u / 0.05)) * (0.6 * np.exp(-u / 1.2) + 0.4 * np.exp(-u / 4.5)) * on
        body *= np.exp(2.5 * PB.slow_random(n, 0.5, 4.0) / 8.686)
        # ---- the sub tail: 18-45 Hz, swelling in over a third of a second, heaving, gone by ~18 s
        sub = T.unit(band(white(d), 18, 45, 3)) * (1 - np.exp(-u / 0.3)) ** 2 * np.exp(-u / 5.0) * on
        sub *= np.exp(3.0 * PB.slow_random(n, 0.15, 1.2) / 8.686)
        low = boom * 1.25 + body * 0.6 + sub * 0.8
        # (the roar's low mids and mids lifted: the crack and the roar have to carry it on any speaker)
        for ch in (L, R):
            ch += band(ch, 250, 4000, 1) * 1.4
        L += low * ref; R += low * ref
        # ---- the boom off far land: four returns, each later, darker and from elsewhere
        src = band((L + R) / 2, None, 900, 2)
        for dt, gn, hi in ((0.75, 0.35, 700), (1.6, 0.28, 450), (2.7, 0.22, 300), (4.3, 0.16, 220)):
            ech = band(src, 25, hi * rng().uniform(0.85, 1.15), 2)
            ir_n = int(0.5 * SR); s = np.arange(ir_n) / SR
            ir = rng().standard_normal(ir_n) * np.exp(-s / 0.12)
            ir /= np.sqrt(np.sum(ir ** 2))
            ech = np.fft.irfft(np.fft.rfft(ech, n + ir_n) * np.fft.rfft(ir, n + ir_n), n + ir_n)[:n]
            l, r = PB.pan2(ech * gn, rng().uniform(-0.6, 0.6))
            P.put(L, l, dt); P.put(R, r, dt)
        # ---- the fireball crackling, far off and in clusters
        cl, cr_ = pop_clusters(d, t0 + 0.6, t0 + 9.0, 2.2, 20 * np.log10(ref) - 9.0, 3.5)
        L += cl; R += cr_
        # ---- the lows' own harmonics (2nd-4th), for small speakers: a soft-clipped copy of the lows, 70-420 Hz of it
        lo = band((L + R) / 2, None, 90, 3)
        c = np.percentile(np.abs(lo), 99.0) * 0.35 + 1e-9
        h = np.tanh(lo / c) * c - lo * 0.0
        h = band(h, 70, 420, 2)
        h = h / (T.loudest(h) + 1e-9) * T.loudest(lo) * 10 ** (-5.0 / 20)
        L += h; R += h
        L, R = PB.causal_lowcut(L * on, 15.0), PB.causal_lowcut(R * on, 15.0)
    finish_at("blast", L, R, -6.5, tail_fade=3.0, knee=0.5, peak=BLAST_PEAK)


def blast_far():
    x = decoded("blast")
    if x is None:
        raise SystemExit("blast is not built yet: build it before blast_far")
    d = 32.0
    n = int(SR * d)
    with PB.seeded(77401):
        out = []
        tt_ = np.arange(n) / SR - BLAST_LEAD
        soft_on = np.clip(tt_ / 0.07, 0, 1) ** 2                 # (the crack's front softened: its top rising over 70 ms)
        for ch in range(2):
            y = np.zeros(n); y[:len(x)] = x[:, ch]
            lo = band(y, None, 300, 2)
            mid = band(y, 300, 1500, 2)
            hi = band(y, 1500, None, 2)
            hi = hi * soft_on
            mid = mid * np.sqrt(soft_on)
            out.append(lo * 1.1 + mid * 0.45 + P.air(hi, 5000) * 0.14)
        L, R = out
        # (more of the low thunder rolling off the land)
        rl, rr = PB.thunder_rolls(d, BLAST_LEAD + 0.8, count=14, length=14.0)
        g = T.loudest((L + R) / 2) * 0.5 / (T.loudest((rl + rr) / 2) + 1e-9)
        L += rl * g; R += rr * g
        # (and a long dark outdoor reverb: the land and the sky it came over)
        for i, ch in enumerate((L, R)):
            ir = T.outdoor_ir(7.0, 30 + i, density=30.0, darken=(1200, 150), decay=3.0)
            m = n + len(ir)
            wet = np.fft.irfft(np.fft.rfft(ch, m) * np.fft.rfft(ir, m), m)[:n]
            ch += wet * 0.55
        f = T.fade(n, 0.002, 4.0)
        L, R = PB.causal_lowcut(L * f, 15.0), PB.causal_lowcut(R * f, 15.0)
    finish_at("blast_far", L, R, -12.5, tail_fade=3.0, knee=0.5, peak=BLAST_PEAK)


# =======================================================================================================  the shockwave
def shockwave():
    d = 6.0
    F = SHOCK_FRONT
    n = int(SR * d)
    t = np.arange(n) / SR
    tau = t - F
    on = np.clip((tau + 0.005) / 0.05, 0, 1) * (tau > -0.005)
    E = on * (0.55 * np.exp(-np.maximum(tau, 0) / 0.7) + 0.45 * np.exp(-np.maximum(tau, 0) / 2.2))
    with PB.seeded(77501):
        L = np.zeros(n); R = np.zeros(n)
        # ---- the roaring gust: wind noise, each ear its own gusts over a shared swell, buffeting side to side
        gt = P.poisson_times(F + 0.02, d - 0.8, lambda v: 9.0 * np.exp(-(v - F) / 0.9) + 1.5)
        common = P.bumps(n, gt, rng().uniform(0.03, 0.12, len(gt)), rng().uniform(0.1, 0.35, len(gt)),
                         np.minimum(rng().pareto(2.5, len(gt)) * 0.5 + 0.4, 2.5))
        tabT = np.array([0.0, 1.0, 3.0, 6.0])
        tab = np.array([[-44, -32, -26, -25, -27, -30, -35, -41, -49, -60],
                        [-46, -34, -27, -26, -28, -31, -37, -43, -52, -64],
                        [-50, -38, -30, -29, -31, -35, -41, -48, -58, -70],
                        [-54, -42, -34, -33, -35, -39, -46, -54, -64, -76]], dtype=float)
        wl, wr = P.snoise(d, tabT, tab, 2048, 512, corr=np.array([1.0, 0.95, 0.8, 0.6, 0.45, 0.35, 0.3, 0.25, 0.2, 0.2]))
        for ch, w in ((L, wl), (R, wr)):
            own = P.bumps(n, gt + rng().uniform(-0.05, 0.05, len(gt)), rng().uniform(0.03, 0.12, len(gt)),
                          rng().uniform(0.1, 0.3, len(gt)), np.minimum(rng().pareto(2.5, len(gt)) * 0.5 + 0.3, 2.5))
            gust = 0.4 + 0.5 * common / (common.mean() + 1e-9) * 0.5 + 0.5 * own / (own.mean() + 1e-9) * 0.5
            hi_part = band(w, 900, None, 2)
            ch += ((w - hi_part) + hi_part * np.clip(gust / 1.4, 0.4, 1.8)) * gust * E
        # ---- the roar in it: 150-1500 Hz, boiling in grains
        for ch in (L, R):
            r = T.unit(band(rng().standard_normal(n), 150, 1500, 2)) * grains(d, 50.0, (0.01, 0.03, 0.08)) ** 0.8
            ch += r * E * 10 ** (-30.0 / 20)
        # ---- dust, leaves, grass thrashing
        for ch in (L, R):
            fol = T.unit(band(rng().standard_normal(n), 2000, 10000, 2))
            g = np.clip(grains(d, 90.0, (0.004, 0.009, 0.02)), 0, 8.0) ** 1.3
            g /= np.sqrt(np.mean(g ** 2)) + 1e-9
            ch += fol * g * on * (0.7 * np.exp(-np.maximum(tau, 0) / 0.8) + 0.3 * np.exp(-np.maximum(tau, 0) / 2.5)) * 10 ** (-40.0 / 20)
        # ---- grit and debris rattling past
        for t1 in P.poisson_times(F + 0.01, d - 0.5, lambda v: 120.0 * np.exp(-(v - F) / 0.5) + 6.0 * np.exp(-(v - F) / 2.5)):
            a = min(rng().pareto(1.8) * 0.4 + 0.25, 4.0) * 10 ** (-30.0 / 20) * np.exp(-max(t1 - F, 0) / 2.0)
            tk = band(PB.tick(int(0.01 * SR), 0, a, rng().uniform(0.00015, 0.0006), rng().choice([-1.0, 1.0])), 1500, 11000, 2)
            p = rng().uniform(-0.9, 0.9)
            P.put(L, tk * (1 - p) * 1.2, t1); P.put(R, tk * (1 + p) * 1.2, t1)
        for t1 in P.poisson_times(F + 0.05, F + 3.0, lambda v: 14.0 * np.exp(-(v - F) / 0.9)):
            m = int(0.1 * SR)
            hit = P.modal_hit(m, rng().uniform(700, 3200), [1.0, rng().uniform(1.5, 2.1), rng().uniform(2.6, 3.7)],
                              [rng().uniform(0.004, 0.015), 0.005, 0.003], [1.0, 0.6, 0.35], 0.7)
            hit *= 10 ** ((-32.0 + rng().uniform(-6, 3)) / 20) / (np.abs(hit).max() + 1e-9) * 3.0
            p = rng().uniform(-0.9, 0.9)
            P.put(L, hit * (1 - p), t1); P.put(R, hit * (1 + p), t1)
        # ---- the pressure of it: one big low push at the front, then uneven shoves, the same in both ears
        pt = np.concatenate([[F + 0.01], P.poisson_times(F + 0.15, F + 2.5, lambda v: 4.0 * np.exp(-(v - F) / 0.9))])
        amps = np.concatenate([[3.0], np.minimum(rng().pareto(2.2, len(pt) - 1) * 0.5 + 0.4, 2.0) * rng().choice([-1.0, 1.0], len(pt) - 1)])
        push = P.bumps(n, pt, np.r_[0.02, rng().uniform(0.03, 0.08, len(pt) - 1)], np.r_[0.12, rng().uniform(0.06, 0.18, len(pt) - 1)], amps)
        push = band(push, 10, 70, 2)
        push = push / (np.abs(push).max() + 1e-9) * 10 ** (-14.0 / 20)
        L += push; R += push
        g0 = np.clip((tau + 0.005) / 0.015, 0, 1)
        L, R = PB.causal_lowcut(L * g0, 14.0), PB.causal_lowcut(R * g0, 14.0)
        L, R = scaled(L, R, -14.0)
        a = SHOCK_FRONT - BLAST_LEAD
        L, R = duck_under(L, R, [[("blast", a, 1.0)], [("blast_far", a, 1.0)]])
    finish("shockwave", L, R, tail_fade=0.8)


# ==========================================================================================================  the rumble
def rumble():
    d = 38.0
    n = int(SR * d)
    t = np.arange(n) / SR
    with PB.seeded(77601):
        L = np.zeros(n); R = np.zeros(n)
        # ---- swells rolling in off the land, unevenly, each further off and darker
        tr = rng().uniform(0.3, 1.0)
        k = 0
        while tr < d - 8.0:
            far = min(tr / 26.0, 1.0)
            ln = rng().uniform(2.0, 4.0) + 3.0 * far
            m = int(ln * SR)
            s = np.arange(m) / SR
            env = (1 - np.exp(-s / (rng().uniform(0.12, 0.4) + 0.4 * far))) ** 2 * np.exp(-s / (rng().uniform(0.6, 1.2) + 1.2 * far))
            env /= env.max() + 1e-9
            hi = 300 - 190 * far
            lvl = 10 ** ((-20.0 - 14.0 * far + rng().uniform(-3, 2)) / 20)
            # (the nearer ones with a dull boom at their front, a slope sending it back; the thunder's clumpy grain)
            boom = T.unit(band(rng().standard_normal(m), 60, 500 - 280 * far, 2)) * np.exp(-s / 0.2) * (1 - np.exp(-s / 0.02)) * (1 - far) * 0.5
            clump = grains(ln, rng().uniform(8, 18), (0.04, 0.09, 0.2)) ** 0.7
            a_ = T.unit(band(rng().standard_normal(m), 25, hi, 2))
            corr = 0.9 - 0.5 * far
            p = rng().uniform(-0.55, 0.55)
            for ch, sgn in ((L, 1.0), (R, -1.0)):
                own = T.unit(band(rng().standard_normal(m), 25, hi, 2))
                x = (corr * a_ + np.sqrt(1 - corr ** 2) * own) * env * clump[:m] + boom
                P.put(ch, x * lvl * (1 + p * sgn), tr)
            tr += rng().gamma(1.7, 0.9 + 0.22 * k)
            k += 1
        # ---- thunder-like rolls low down
        rl, rr = PB.thunder_rolls(d, 0.0, count=22, length=26.0)
        g = 10 ** (-24.0 / 20) / (T.loudest((rl + rr) / 2) + 1e-9)
        L += rl * g; R += rr * g
        # ---- the sub bed under it all, heaving, decaying over the whole length
        bed = T.unit(band(white(d), 18, 70, 3))
        bed2 = T.unit(band(white(d), 18, 70, 3))
        benv = 10 ** (np.interp(t, [0, 2, 8, 16, 26, 34, 38], [-22, -18, -21, -26, -33, -42, -60]) / 20)
        heave = np.exp(3.0 * PB.slow_random(n, 0.1, 0.9) / 8.686)
        L += (0.92 * bed + 0.39 * bed2) * benv * heave
        R += (0.92 * bed - 0.39 * bed2) * benv * heave
        f = T.fade(n, 1.5, 4.0)
        L, R = PB.causal_lowcut(L * f, 15.0), PB.causal_lowcut(R * f, 15.0)
        L, R = scaled(L, R, -16.0)
        a, b = -(RUMBLE_AFTER + BLAST_LEAD), -(RUMBLE_AFTER + SHOCK_FRONT)
        L, R = duck_under(L, R, [[("blast", a, 1.0), ("shockwave", b, 1.0)], [("blast_far", a, 1.0), ("shockwave", b, 1.0)]])
    finish("rumble", L, R, tail_fade=2.0)


# ==========================================================================================================  the debris
def debris():
    d = 6.5
    n = int(SR * d)
    with PB.seeded(77701):
        L = np.zeros(n); R = np.zeros(n)
        fL = np.zeros(n); fR = np.zeros(n)

        def place(x, t1, near, p):
            gl, gr = (1 - p) * 0.5 + 0.5 * near * (1 - p), (1 + p) * 0.5 + 0.5 * near * (1 + p)
            P.put(L, x * gl * near, t1); P.put(R, x * gr * near, t1)
            P.put(fL, x * (1 - near) * (1 - p * 0.5), t1); P.put(fR, x * (1 - near) * (1 + p * 0.5), t1)

        rate = lambda v: 12.0 * np.clip(v / 0.3, 0, 1) * np.exp(-max(v - 0.5, 0) / 1.8) + 0.8 * np.exp(-v / 4.0)
        for t1 in P.poisson_times(0.05, d - 1.2, rate):
            near = rng().random() ** 1.5
            kind = rng().random()
            if kind < 0.4:                                    # a clod: a dull thud and a spray of dirt
                size = min(rng().pareto(2.0) * 0.4 + 0.3, 2.2)
                m = int((0.2 + 0.3 * size) * SR)
                s = np.arange(m) / SR
                x = T.thud(m, size) * size * 0.12
                x += T.unit(band(rng().standard_normal(m), 600, 5000, 2)) * np.exp(-s / rng().uniform(0.012, 0.035)) * np.minimum(s / 0.002, 1) * 0.035 * (0.4 + 0.6 * near)
            elif kind < 0.7:                                  # a stone clacking, sometimes bouncing
                size = rng().uniform(0.3, 1.0)
                m = int(0.35 * SR)
                x = P.modal_hit(m, rng().uniform(800, 2800) / (0.6 + size), [1.0, rng().uniform(1.45, 2.2), rng().uniform(2.4, 3.9), rng().uniform(4.1, 5.6)],
                                [rng().uniform(0.004, 0.02), rng().uniform(0.003, 0.01), 0.004, 0.002], [1.0, 0.7, 0.45, 0.25], 0.5)
                x = x / (np.abs(x).max() + 1e-9) * 0.08 * size + T.thud(m, 0.3 * size) * 0.03 * size
                if rng().random() < 0.35:
                    P.put(x, x * rng().uniform(0.25, 0.5), rng().uniform(0.07, 0.22))
            elif kind < 0.85:                                 # crumbling: a short run of grit and small stones
                m = int(rng().uniform(0.3, 0.8) * SR)
                s = np.arange(m) / SR
                gr = np.clip(grains(m / SR, 120.0, (0.003, 0.008)), 0, 6) ** 1.4
                x = T.unit(band(rng().standard_normal(m), 400, 4500, 2)) * gr[:m] * np.sin(np.pi * s / s[-1]) * 0.02
                x += T.unit(band(rng().standard_normal(m), 80, 400, 2)) * np.sin(np.pi * s / s[-1]) * 0.012
            else:                                             # a slab of concrete or rock, landing heavily off
                m = int(1.0 * SR)
                x = T.thud(m, rng().uniform(1.8, 2.8)) * 0.2
                near = near * 0.5
            x = P.air(x, 1600 + 9000 * near)
            place(x, t1, 0.25 + 0.75 * near, rng().uniform(-0.85, 0.85))
        for t1 in P.poisson_times(0.1, d - 1.0, lambda v: 130.0 * np.clip(v / 0.4, 0, 1) * np.exp(-max(v - 0.4, 0) / 1.4)):
            a = min(rng().pareto(2.4) * 0.35 + 0.15, 2.0) * 0.02
            tk = band(PB.tick(int(0.006 * SR), 0, a, rng().uniform(0.0002, 0.0008), rng().choice([-1.0, 1.0])), 1200, 9000, 2)
            p = rng().uniform(-1, 1)
            P.put(L, tk * (1 - p * 0.8), t1); P.put(R, tk * (1 + p * 0.8), t1)
        for src, dst, sh in ((fL, L, 0), (fR, R, 1)):
            ir = T.outdoor_ir(1.8, 50 + sh, density=40.0, darken=(2200, 280), decay=0.7)
            m_ = n + len(ir)
            wet = np.fft.irfft(np.fft.rfft(src, m_) * np.fft.rfft(ir, m_), m_)[:n]
            dst += src * 0.55 + wet * 0.55
        f = T.fade(n, 0.002, 1.8)
        L, R = PB.causal_lowcut(L * f, 22.0), PB.causal_lowcut(R * f, 22.0)
        L, R = scaled(L, R, -20.0)
        # (it lands on the blast, the shockwave and the rumble at moments fixed against them: room made under them, for
        # its first play and for the repeat at pitch 0.9)
        def lay(t1, v):
            return [[(bl, -(t1 + BLAST_LEAD), 1.0), ("shockwave", -(t1 + SHOCK_FRONT), 1.0), ("rumble", -(t1 - RUMBLE_AFTER), 1.0)]
                    for bl in ("blast", "blast_far")]
        t1, t2 = DEBRIS_AFTER
        L, R = duck_under(L, R, lay(t1, 1.0), extra=[(0.9, 0.0, lay(t2, 1.0))])
    finish("debris", L, R, tail_fade=0.5)


# ==========================================================================================================  the ground
def ground():
    d = 3.2
    n = int(SR * d)
    t = np.arange(n) / SR
    t1 = GROUND_LEAD
    u = np.maximum(t - t1, 0)
    on = t >= t1
    with PB.seeded(77801):
        th = soundlib.thump(n, t1, rng().uniform(40, 44), 20.0, 0.32, 4.5) * (1 - np.exp(-u / 0.03)) * on
        th += T.unit(band(white(d), 18, 90, 2)) * (1 - np.exp(-u / 0.025)) * np.exp(-u / 0.12) * on * 0.5
        rum = T.unit(band(white(d), 16, 48, 3)) * (1 - np.exp(-u / 0.1)) * np.exp(-u / 0.5) * on * 0.45
        rum *= np.exp(2.5 * PB.slow_random(n, 0.8, 4.0) / 8.686)
        chop = np.clip(1 + 0.9 * PB.slow_random(n, 9.0, 14.0), 0.05, None)
        sh = T.unit(band(white(d), 30, 110, 2)) * chop * (1 - np.exp(-u / 0.06)) * np.exp(-u / 0.5) * on * 0.3
        rat = T.unit(band(white(d), 900, 3200, 2)) * np.clip(PB.slow_random(n, 25.0, 70.0), 0, None) ** 2 * np.exp(-u / 0.35) * on * 0.012
        x = th + rum + sh
        lo = band(x, None, 70, 3)
        c = np.percentile(np.abs(lo), 99.5) * 0.4 + 1e-9
        harm = band(np.tanh(lo / c) * c, 70, 260, 2)
        x = x + harm * 0.6
        L = x + rat; R = x * 0.98 + band(rat, 1000, None, 1) * 0.8
        L, R = PB.causal_lowcut(L, 15.0), PB.causal_lowcut(R, 15.0)
    finish_at("ground", L, R, -14.5, tail_fade=0.6, knee=0.55)


BUILD = {"fall": fall, "ground": ground, "blast": blast, "blast_far": blast_far, "shockwave": shockwave,
         "rumble": rumble, "debris": debris}


# ============================================================================================================  listening
def measure(path):
    """(integrated LUFS, true peak dBTP, sample peak dBFS) by ffmpeg's ebur128."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true+sample", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    tail = r[r.rfind("Summary:"):]
    def grab(key):
        i = tail.find(key)
        return float(tail[i:].split(":")[1].split()[0]) if i >= 0 else float("nan")
    return grab("I:"), grab("Peak:"), None


def write_wav(path, x):
    import wave
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def mixdown(dist):
    """The whole strike at `dist` blocks: (stereo array, the burst's time in it). Starts at the strike's 0 (fire)."""
    vol = volumes(dist)
    ev = [e for e in schedule(dist) if vol[e[0]] > 0]
    start = -(11.0)
    clips = {}
    for nm, f, at, pitch in ev:
        c = decoded(f)
        if pitch != 1.0:                              # (the game plays a pitch as a change of speed)
            m = int(len(c) / pitch)
            c = np.stack([np.interp(np.arange(m) * pitch, np.arange(len(c)), c[:, k]) for k in range(2)], axis=1)
        clips[nm] = c
    end = max(at + len(clips[nm]) / SR for nm, _, at, _ in ev) + 0.5
    out = np.zeros((int((end - start) * SR), 2))
    for nm, _, at, _ in ev:
        k = int(round((at - start) * SR))
        c = clips[nm] * vol[nm]
        out[k:k + len(c)] += c[:len(out) - k]
    return out, start


def spectrum_report(x):
    """Where the blast's energy sits, over its first 3 s: octave levels and the share in a few bands."""
    m = x.mean(axis=1)[: int(3.0 * SR)]
    X = np.abs(np.fft.rfft(m * np.hanning(len(m)))) ** 2
    f = np.fft.rfftfreq(len(m), 1 / SR)
    tot = X.sum()
    bands = [(0, 30), (30, 60), (60, 120), (120, 250), (250, 500), (500, 2000), (2000, 6000), (6000, 22050)]
    share = ", ".join(f"{a}-{b} Hz {100 * X[(f >= a) & (f < b)].sum() / tot:4.1f}%" for a, b in bands)
    lowf = f[(f > 15) & (f < 150)][np.argmax(X[(f > 15) & (f < 150)])]
    octs = P.oct_levels(m, 0.0, 3.0)
    return share, lowf, octs


def listen(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for nm in NAMES:
        x = decoded(nm)
        p = out / f"nuke_{nm}.wav"
        write_wav(p, x)
        lufs, tp, _ = measure(p)
        rows.append((p.name, len(x) / SR, 20 * np.log10(np.abs(x).max()), tp, lufs))
    for dist in (60, 100, 150, 250, 300, 450, 750, 900, 1500):
        x, _ = mixdown(dist)
        print(f"  the whole strike {dist:4d} blocks off peaks at {20 * np.log10(np.abs(x).max()):.2f} dBFS")
    for dist in (200, 600):
        x, start = mixdown(dist)
        pk = np.abs(x).max()
        p = out / f"nuke_full_{dist}blocks.wav"
        write_wav(p, x)
        lufs, tp, _ = measure(p)
        rows.append((p.name + f"  (detonation at {-start:.1f} s)", len(x) / SR, 20 * np.log10(pk), tp, lufs))
    print(f"\n{'file':52s} {'len':>6s} {'peak':>7s} {'TP':>7s} {'LUFS':>7s}")
    for r in rows:
        print(f"{r[0]:52s} {r[1]:6.1f} {r[2]:7.2f} {r[3]:7.2f} {r[4]:7.1f}")
    share, lowf, octs = spectrum_report(decoded("blast"))
    print("\nblast, first 3 s: " + share)
    print(f"  strongest low frequency {lowf:.1f} Hz; octaves (dB) " + " ".join(f"{int(fc)}:{v:.1f}" for fc, v in zip(OCT, octs)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write listening WAVs and the full-strike mixdowns here")
    a = ap.parse_args()
    soundlib.init(a.out)
    for name in a.only if a.only is not None else NAMES:
        BUILD[name]()
    path = Path(a.out) / "assets" / "orbital" / "sounds.json"
    if path.exists():
        sounds = json.loads(path.read_text())
        for name in NAMES:
            ev = f"{TH}.{name}"
            sounds[ev] = {"sounds": [{"name": f"orbital:{TH}/{name}", "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"}
        path.write_text(json.dumps(sounds, indent=2))
    if a.listen:
        listen(a.listen)


if __name__ == "__main__":
    main()
