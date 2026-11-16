"""The Convergence's explosions (tools/sounds_convergence.py), in its two takes (take 2 ships).

Take 2, this laser's own (`own_blast`, OWN): each kind of explosion (the Nether's surges, the Aether's surges, the hit
in the air, the eruption, the blast, the land's tear) built the way the Payload's were: one explosion of a reference
was measured (its octave levels over time, the first half second in 20 ms windows; its low blows' times, levels and
pitches; how high its start peaks), the numbers put here as tables, and the sound synthesised from noise, swept sines
and narrow noise until, measured with the same code, it measures like the table (`calibrated_own`). Nothing of the
reference is in it: only those measurements.

Take 1, built only to level the layers by: `sounds_payload.py`'s `blast_alt`, `ground_alt`, `rush` and `tail` lifted
whole (every stage in the same order, drawing the same random numbers) with what was fixed made an argument; at the
Payload's own arguments each returns exactly the arrays the original hands to its finishing (`same_as_payload`).
Arguments added: `seed` (the random stream), `d` (the file's length, s), `stretch` (the table's times after its start
scaled), `f` (the pitch of the low blows and the bed), `tilt` (dB per octave about 500 Hz on the roar's rows from its
first second), `crackle` (the roar's crackle: its rate times this, its level 20 log10 of it more).
The finishing (`finish`) is `PB.finish_blast_decoded`'s level and limiter without its encoding: the caller writes the
file.
"""
import numpy as np

import soundlib
from soundlib import SR, white, band
import sounds_themes as T
import sounds_pk_blast as PB
import sounds_payload as P

OCT = PB.OCT
PEAK = P.PEAK


def rng():
    return soundlib.rng


def warp(times, k, keep):
    """`times` after `keep` scaled by k about it."""
    times = np.asarray(times, dtype=float)
    return np.where(times <= keep, times, keep + (times - keep) * k)


def tilted(table, rows, tilt):
    """`table` with `tilt` dB per octave about 500 Hz added to rows `rows` on."""
    out = np.array(table, dtype=float)
    if tilt:
        out[rows:] += tilt * (np.log2(OCT) - np.log2(500.0))
    return out


# ===========================================================================================  sounds_payload.blast_alt
ALT = dict(seed=91311, d=11.5)


def blast_alt(seed, d, stretch=1.0, f=1.0, tilt=0.0, crackle=1.0, t0=0.02):
    """`P.blast_alt` before its finishing: the air out of the hush, the low boom 0.15 s in (`f` times its pitch, as
    the sub pushes, the second blow and the bed of 34-66 Hz), a gap, the crack inside it at 0.232 s and a second blow,
    then the wide roar (its table's times after 0.43 s, the ears' likeness after 0.65 s and the bed's after 0.8 s
    scaled by `stretch`; tilted by `tilt` from its first second on), crackling (`crackle`) over the heaving bed, the
    lows' harmonics, the low clip and the start's soft clip. (L, R)."""
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(seed):
        times = np.concatenate([[0.2, 0.27], warp(P.ALT_T, stretch, 0.43) + 0.04]) + t0
        tab = np.vstack([P.ALT_DB[0] - 40.0, P.ALT_DB[0] - 12.0, tilted(P.ALT_DB + P.ALT_TRIM, 3, tilt)])
        bl, br = PB.shaped_noise_tv(d, times, tab, warp(P.ALT_CORR_T, stretch, 0.65) + t0, P.ALT_CORR, 4096, 1024, wander=1.6, wander_from=t0 + 0.3)
        bl, br = bl * P.SN_GAIN, br * P.SN_GAIN
        boil = [np.exp((2.6 * PB.slow_random(n, 1.5, 10.0) + 1.2 * PB.slow_random(n, 12.0, 40.0)) / 8.686) for _ in range(2)]
        ramp = np.clip((u - 0.3) / 0.4, 0, 1)
        outs = []
        for ch, bo in ((bl, boil[0]), (br, boil[1])):
            hi = band(ch, 250, None, 2)
            outs.append(ch - hi + hi * (1 + (bo - 1) * ramp))
        L, R = outs
        wash = []
        for _ in range(2):
            w_ = T.unit(band(rng().standard_normal(n), 300, 9000, 2))
            w_ = band(w_, None, 2000, 1) * 0.9 + w_ * 0.06
            wash.append(w_ * np.clip(u / 0.13, 0, 1) ** 2.5 * np.exp(-np.maximum(u - 0.13, 0) / 0.03) * on * 10 ** (-28.0 / 20))
        roar63 = P.oct_levels((L + R) / 2, t0 + 0.5, t0 + 1.0)[1]
        roar1k = P.oct_levels((L + R) / 2, t0 + 0.5, t0 + 1.0)[5]

        def blow_env(tp, rise, fall):
            uu = u - tp
            return np.where(uu < 0, np.exp(-0.5 * (uu / rise) ** 2), np.exp(-uu / fall)) * on

        def blow_at(tp, f0, rise, fall, a, sweep=0.12, body=0.0):
            uu = u - tp
            env = blow_env(tp, rise, fall)
            ph = 2 * np.pi * np.cumsum(f0 * f * (1 + sweep * np.exp(-np.maximum(uu, 0) / 0.05)) * on) / SR
            x = np.sin(ph + rng().uniform(0, 6.28)) * env
            if body:
                x = x + T.unit(band(rng().standard_normal(n), 38 * f, 150 * f, 3)) * env * body
            return x * a
        sub = blow_at(0.11, 30.0, 0.02, 0.035, 1.0) + blow_at(0.31, 33.0, 0.02, 0.06, 1.2)
        boom = (blow_at(0.15, 50.0, 0.022, P.ALT_BOOM_FALL, 1.0, sweep=0.24, body=P.ALT_BODY)
                + blow_at(0.355, 45.0, 0.02, 0.045, 0.6, sweep=0.15, body=P.ALT_BODY * 0.7) + blow_at(0.32, 53.0, 0.012, 0.025, 0.4))
        punch = (T.unit(band(rng().standard_normal(n), 80, 200, 3)) * np.exp(-0.5 * ((u - 0.158) / 0.007) ** 2)
                 + T.unit(band(rng().standard_normal(n), 80, 200, 3)) * np.exp(-0.5 * ((u - 0.285) / 0.012) ** 2) * 0.8) * on

        def peak10(x, lo, hi):
            y = band(x, lo, hi, 2)
            w = int(0.01 * SR)
            return 20 * np.log10(max(np.sqrt(np.mean(y[i:i + w] ** 2)) for i in range(0, int(0.6 * SR), w // 2)) + 1e-12)
        sub *= 10 ** ((roar63 + 4.5 - peak10(sub, 20 * f, 45 * f)) / 20)
        boom *= 10 ** ((roar63 + P.ALT_BOOM_DB - peak10(boom, 35 * f, 90 * f)) / 20)
        punch *= 10 ** ((roar63 + 1.5 - peak10(punch, 90, 250)) / 20) * P.ALT_PUNCH
        blow = sub + boom + punch
        crack = [np.zeros(n), np.zeros(n)]
        for tc, a, top_lag, w in ((0.232, 1.0, 0.012, 0.022), (0.322, 0.35, 0.004, 0.012), (0.342, 0.3, 0.004, 0.01)):
            for k in range(2):
                uu = u - tc
                m_env = np.where(uu < 0, 0.0, (1 - np.exp(-uu / 0.002)) * np.exp(-uu / w)) * on
                h_env = np.where(uu < top_lag, 0.0, (1 - np.exp(-(uu - top_lag) / 0.002)) * np.exp(-(uu - top_lag) / (w * 1.1))) * on
                mid = T.unit(band(rng().standard_normal(n), 380, 3500, 2))
                top = T.unit(band(rng().standard_normal(n), 3500, 18000, 2))
                crack[k] += (mid * m_env + top * h_env * 10 ** (-6.0 / 20)) * a
        cg = 10 ** ((roar1k + 10.0 - peak10((crack[0] + crack[1]) / 2, 1000, 4000)) / 20)
        crack = [c * cg for c in crack]
        wg = 10 ** ((roar1k - 4.0 - peak10((wash[0] + wash[1]) / 2, 250, 1000)) / 20)
        wash = [w_ * wg for w_ in wash]
        # (the crackle: its rate times `crackle`, its level 20 log10 of it more, its thinning out as long as the roar)
        cdb = 20 * np.log10(crackle)
        cl, cr = P.crackle(d, 0.0, lambda v: 0.0 if v < t0 + 0.35 else crackle * (14.0 * np.exp(-(v - t0 - 0.35) / (1.2 * stretch)) + 2.0),
                           lambda v: -40.0 + cdb - 4.0 * max(v - t0 - 0.35, 0) / stretch, lo=1800, hi=12000)
        bed = []
        bl0 = T.unit(band(rng().standard_normal(n), 34 * f, 66 * f, 3))
        for k in range(2):
            b_ = 0.94 * bl0 + 0.34 * T.unit(band(rng().standard_normal(n), 34 * f, 66 * f, 3))
            bed.append(b_)
        heave = np.exp((3.0 * PB.slow_random(n, 0.4, 2.5) + 1.5 * PB.slow_random(n, 3.0, 9.0)) / 8.686)
        benv = (np.clip((u - 0.24) / 0.12, 0, 1) ** 2 * 10 ** (np.interp(u, warp(P.ALT_BED_T, stretch, 0.8), P.ALT_BED_DB) / 20) * heave * on)
        mid0 = (L + R) / 2
        bref = np.sqrt(np.mean(band(mid0, 40 * f, 63 * f, 3)[int((t0 + 0.4) * SR):int((t0 + 1.4) * SR)] ** 2))
        bgot = np.sqrt(np.mean(band(bl0 * benv, 40 * f, 63 * f, 3)[int((t0 + 0.4) * SR):int((t0 + 1.4) * SR)] ** 2))
        bed = [b_ * benv * bref / (bgot + 1e-12) * 10 ** (P.ALT_BED_UP / 20) for b_ in bed]
        L = L + wash[0] + blow + crack[0] + cl + bed[0]
        R = R + wash[1] + blow + crack[1] + cr + bed[1]
        L, R = P.alt_harmonics(L, R, u, on)
        L, R = PB.causal_lowcut(L * on, 24.0), PB.causal_lowcut(R * on, 24.0)
        lows = [band(ch, None, 110, 4) for ch in (L, R)]
        c_lo = T.loudest((lows[0] + lows[1]) / 2) * 10 ** (P.ALT_LOW_CLIP / 20)
        L = L - lows[0] + PB.soft_clip(lows[0], c_lo, 0.5)
        R = R - lows[1] + PB.soft_clip(lows[1], c_lo, 0.5)
        free = 1 + 1e3 * np.clip((u - 0.6) / 0.1, 0, 1) ** 2
        L0, R0 = L, R
        lv = T.loudest((L + R) / 2)
        for _ in range(4):
            c = lv * 10 ** (7.5 / 20) * free
            L = PB.soft_clip(L0, c, 0.5); R = PB.soft_clip(R0, c, 0.5)
            lv = T.loudest((L + R) / 2)
    return L, R


def ground_alt(seed=92311, f=1.0):
    """`P.ground_alt` (one boom swelling up out of the ground and sliding down, the rumble, its harmonics) on `seed`,
    the boom `f` times its pitch. (L, R), 2.6 s, its start 0.02 s in, at the Payload's level."""
    d = 2.6
    n = int(SR * d)
    t = np.arange(n) / SR
    t1 = P.GROUND_LEAD
    u = np.maximum(t - t1, 0)
    on = t >= t1
    up = P.GROUND_UP
    at_octave, oct_levels = P.at_octave, P.oct_levels
    with PB.seeded(seed):
        tp = rng().uniform(0.12, 0.15)
        fb = (47.0 + rng().uniform(29, 34) * np.exp(-u / 0.22)) * f
        ph = 2 * np.pi * np.cumsum(fb * on) / SR
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
        L, R = P.alt_harmonics(L, R, u, on, P.GROUND_ALT_HARM_DB, -1.0, (t1 + 0.04, t1 + 0.4))
        L, R = PB.causal_lowcut(L, 24.0), PB.causal_lowcut(R, 24.0)
        L, R = L * P.GROUND_ALT_UP, R * P.GROUND_ALT_UP
    return L, R


# ========================================================================================  sounds_payload.rush and tail
def duck_under(L, R, blasts, at, ceiling=0.92, release=0.08):
    """`P.duck_under_blasts` against the given blasts ([(L, R)], each starting `at` s into this sound) rather than the
    Payload's own files: eased down where the two would add up past `ceiling`, down 2 ms ahead, back over `release`."""
    n = len(L)
    need = np.ones(n)
    for bL, bR in blasts:
        b = np.stack([bL, bR], axis=1)
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
    return L * out, R * out


RUSH_FRONT = 0.15   # (the rush's front this far into its file)


def rush(seed=92401, blasts=(), at=RUSH_FRONT - 0.02):
    """`P.rush` (the shockwave's front and its dust over the player: gusts from side to side, the leaves thrashing,
    grit and twigs thrown past, low pushes of air, wind dying away) on `seed`, eased under `blasts` (starting `at` s
    in, as the Payload's blast starts 0.13 s after it). (L, R), 9 s, its front RUSH_FRONT in."""
    d = 9.0
    FRONT = RUSH_FRONT
    n = int(SR * d)
    t = np.arange(n) / SR
    tau = t - FRONT
    on = np.clip((tau + 0.01) / 0.12, 0, 1) ** 1.5 * (tau > -0.01)
    E = on * (0.6 * np.exp(-np.maximum(tau, 0) / 0.8) + 0.4 * np.exp(-np.maximum(tau, 0) / 3.5))
    poisson_times, bumps, snoise, put, modal_hit = P.poisson_times, P.bumps, P.snoise, P.put, P.modal_hit
    with PB.seeded(seed):
        L = np.zeros(n); R = np.zeros(n)
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
            hi_part = band(w, 900, None, 2)
            bright = np.clip(gust / 1.5, 0.4, 1.6)
            ch += ((w - hi_part) + hi_part * bright) * gust * E * (1 + 0.4 * np.clip((tau - 0.5) / 0.7, 0, 1))
        for ch in (L, R):
            fol = T.unit(band(rng().standard_normal(n), 2200, 9500, 2))
            g = PB.grains(d, 70.0, (0.004, 0.009, 0.02))
            g = np.clip(g, 0, 8.0) ** 1.3
            g /= np.sqrt(np.mean(g ** 2)) + 1e-9
            env = on * (0.75 * np.exp(-np.maximum(tau, 0) / 0.9) + 0.25 * np.exp(-np.maximum(tau, 0) / 3.0))
            ch += fol * g * env * 10 ** (-46.0 / 20)
        for t1 in poisson_times(FRONT + 0.02, d - 0.5, lambda v: 70.0 * np.exp(-(v - FRONT) / 0.6) + 4.0 * np.exp(-(v - FRONT) / 3.0)):
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
        pt = poisson_times(FRONT + 0.05, FRONT + 2.2, lambda v: 4.0 * np.exp(-(v - FRONT) / 0.9))
        push = bumps(n, pt, rng().uniform(0.03, 0.08, len(pt)), rng().uniform(0.06, 0.18, len(pt)),
                     np.minimum(rng().pareto(2.2, len(pt)) * 0.5 + 0.4, 2.5) * rng().choice([-1.0, 1.0], len(pt)))
        push = band(push, 12, 70, 2) * 10 ** (-31.0 / 20) / (np.sqrt(np.mean(band(push, 12, 70, 2)[int(FRONT * SR):int((FRONT + 2) * SR)] ** 2)) + 1e-9)
        L += push; R += push
        g0 = np.clip((tau + 0.005) / 0.02, 0, 1)
        L, R = L * g0, R * g0
        L, R = PB.causal_lowcut(L, 14.0), PB.causal_lowcut(R, 14.0)
        L, R = duck_under(L, R, blasts, at, ceiling=0.95)
    return L, R


TAIL_AFTER = 2.4    # (the tail starts this long after the blast arrives)


def tail(seed=92601, blasts=(), at=-2.42):
    """`P.tail` (the roar rolling back off the land in uneven swells, each further off and darker, the low roar
    outlasting the blast's own) on `seed`, eased under `blasts` (starting `at` s into it). (L, R), 22 s."""
    d = 22.0
    n = int(SR * d)
    t = np.arange(n) / SR
    put = P.put
    with PB.seeded(seed):
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
        bed_env = 10 ** (np.interp(t + 2.4, [10.0, 13.5, 16.0, 18.0, 20.0, 22.0, 24.4], [-60, -24, -21, -23, -28, -36, -60]) / 20)
        bl, br = PB.shaped_noise(d, np.array([0.0, d]), np.array([[-12, -6, -6, -12, -20, -28, -36, -46, -56, -70],
                                                                  [-14, -6, -8, -15, -24, -33, -42, -52, -62, -76]], dtype=float),
                                 corr=np.array([1.0, 0.99, 0.95, 0.85, 0.7, 0.5, 0.4, 0.3, 0.2, 0.2]))
        unit_ = 1.0 / (np.sqrt(np.mean(((bl + br) / 2) ** 2)) + 1e-12)
        heave = np.exp(1.6 * PB.slow_random(n, 0.15, 1.2) / 8.686)
        L += bl * unit_ * bed_env * heave
        R += br * unit_ * bed_env * heave
        f = T.fade(n, 0.6, 3.0)
        L, R = PB.causal_lowcut(L * f, 16.0), PB.causal_lowcut(R * f, 16.0)
        L, R = duck_under(L, R, blasts, at)
    return L, R


# ============================================================================================================  finish
def loudest(L, R):
    """The loudest 400 ms of the mid (RMS, 100 ms steps), as `PB.finish_blast_decoded` measures it."""
    y = (L + R) / 2
    n = len(y)
    w, h = int(0.4 * SR), int(0.1 * SR)
    return max(np.sqrt(np.mean(y[i:i + w] ** 2)) for i in range(0, max(n - w, 1), h))


def finish(L, R, db, peak=PEAK, tail_fade=0.8, knee=None):
    """`PB.finish_blast_decoded`'s level and limiter: the loudest 400 ms at `db`, the peaks under `peak` (its ceiling
    0.985 of it) by `PB.limit` (after `PB.soft_clip` with `knee`), the last `tail_fade` s faded; not encoded. (L, R)."""
    n = max(len(L), len(R))
    x = np.stack([np.pad(L - L.mean(), (0, n - len(L))), np.pad(R - R.mean(), (0, n - len(R)))], axis=1)
    target = 10 ** (db / 20)
    c = peak * 0.985
    lv = lambda y: loudest(y[:, 0], y[:, 1])
    gain = target / lv(x)
    shape = (lambda z: PB.soft_clip(z, c, knee)) if knee else (lambda z: z)
    for _ in range(6):
        y = PB.limit(shape(x * gain), c)
        got = lv(y)
        gain *= target / got
        if abs(20 * np.log10(target / got)) < 0.05:
            break
    y = PB.limit(shape(x * gain), c)
    nf = int(tail_fade * SR)
    if nf:
        y[-nf:] *= np.linspace(1, 0, nf)[:, None]
    return y[:, 0], y[:, 1]


# =================================================================  this laser's own explosions (take 2: OWN, own_blast)
# Each kind of explosion in this laser is built to the measurements of one explosion of a reference, as the Payload's
# were: its octave levels over time (dB, `P.oct_levels`'s octaves and filters (`oct_windows`), its loudest 400 ms set to REF_DB; the first half
# second in 20 ms windows (FINE), then the windows COARSE), its low blows (s after its onset, Hz, their 10 ms level in
# 30-120 Hz at REF_DB), how high its first 0.6 s peaks over its loudest 400 ms. `own_blast` synthesises one from them
# (a roar of noise shaped to the table, the blows as swept sines with a broad body, or as punches of low-mid noise
# where the blow sits over 105 Hz, the lows' own harmonics, the soft clips) and `calibrated_own` trims the roar's
# table until the result, measured with the same code in the same windows, measures like the table.
REF_DB = -8.0
FINE = 0.02
COARSE = ((0.5, 0.8), (0.8, 1.2), (1.2, 1.8), (1.8, 2.5), (2.5, 3.5), (3.5, 5.0), (5.0, 7.0))

# (nether: measured to 3.37 s after its onset; its first 0.6 s peaks +4.1 dB over its loudest 400 ms)
NETHER_T = np.array([0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.27, 0.29, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.45, 0.47, 0.49, 0.65, 1.00, 1.50, 2.15])
NETHER_DB = np.array([
    [-21.0, -26.4, -29.4, -29.1, -29.8, -30.6, -33.0, -34.4, -33.7, -36.7],
    [-22.4, -26.1, -16.1, -26.5, -30.1, -28.1, -30.6, -33.2, -33.7, -36.4],
    [-26.4, -30.5, -19.2, -20.1, -25.9, -30.2, -29.3, -29.8, -29.2, -33.4],
    [-26.6, -18.6, -25.4, -24.9, -25.2, -28.1, -31.2, -34.4, -32.9, -39.7],
    [-23.5, -22.4, -24.2, -23.5, -24.3, -27.7, -29.4, -29.3, -32.7, -38.8],
    [-25.8, -24.9, -19.5, -22.7, -21.0, -24.9, -29.3, -32.1, -38.0, -46.5],
    [-23.9, -24.1, -18.6, -18.2, -18.8, -25.9, -31.6, -33.8, -38.7, -46.1],
    [-21.5, -20.3, -15.0, -19.8, -23.1, -30.1, -34.6, -36.3, -40.7, -48.8],
    [-19.2, -23.3, -21.1, -29.3, -27.9, -32.2, -38.1, -42.6, -47.5, -53.9],
    [-21.0, -24.7, -23.6, -27.5, -21.9, -28.7, -37.6, -39.7, -44.6, -52.1],
    [-19.5, -22.8, -23.6, -27.9, -28.4, -35.1, -39.1, -41.5, -45.1, -52.2],
    [-21.6, -18.7, -22.8, -32.6, -32.0, -36.7, -40.4, -42.3, -44.9, -53.3],
    [-22.5, -21.4, -18.6, -28.2, -33.0, -37.7, -39.0, -41.4, -44.2, -53.2],
    [-28.8, -23.3, -23.2, -30.8, -30.6, -35.8, -39.4, -42.0, -44.2, -53.6],
    [-27.5, -18.3, -19.9, -28.7, -34.4, -35.6, -39.6, -41.9, -44.8, -53.4],
    [-21.2, -21.6, -20.2, -30.3, -32.4, -36.9, -40.8, -41.6, -44.1, -53.2],
    [-15.4, -18.3, -15.2, -27.3, -34.9, -38.6, -41.2, -44.4, -46.6, -55.8],
    [-13.4, -14.7, -24.5, -33.1, -33.7, -41.5, -42.3, -44.3, -46.2, -55.2],
    [-14.6, -16.5, -29.2, -28.2, -36.9, -38.6, -38.9, -41.0, -42.2, -52.4],
    [-17.7, -19.3, -23.2, -24.5, -33.3, -36.6, -34.8, -38.6, -39.5, -48.0],
    [-22.0, -18.6, -17.8, -27.1, -32.8, -35.4, -32.2, -36.2, -37.0, -46.2],
    [-20.4, -24.7, -20.4, -27.8, -30.0, -33.8, -30.5, -29.9, -30.9, -38.7],
    [-18.3, -21.5, -22.6, -25.5, -29.6, -31.2, -28.9, -29.3, -29.1, -39.0],
    [-19.5, -14.9, -23.4, -27.6, -27.4, -29.8, -29.9, -28.6, -27.3, -36.8],
    [-20.8, -24.0, -21.9, -24.5, -23.4, -27.2, -25.4, -24.0, -22.5, -32.6],
    [-17.8, -17.3, -23.8, -26.0, -24.4, -24.8, -23.3, -20.6, -21.5, -27.9],
    [-18.7, -15.3, -19.7, -24.0, -27.2, -29.8, -29.7, -26.3, -26.4, -31.6],
    [-17.5, -13.5, -20.5, -25.3, -30.0, -30.0, -33.9, -33.9, -31.8, -35.7],
    [-20.2, -23.2, -29.3, -31.8, -34.4, -36.7, -34.0, -31.8, -29.8, -37.2],
])
NETHER_BLOWS = ((0.020, 124.0, -16.4), (0.075, 61.9, -12.9), (0.160, 149.7, -12.8), (0.225, 43.8, -13.2), (0.360, 42.6, -7.7), (0.470, 44.1, -8.9), (0.530, 37.1, -12.1), (0.650, 62.9, -10.0))
# (aether: measured to 7.0 s after its onset; its first 0.6 s peaks +1.6 dB over its loudest 400 ms)
AETHER_T = np.array([0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.27, 0.29, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.45, 0.47, 0.49, 0.65, 1.00, 1.50, 2.15, 3.00, 4.25, 6.00])
AETHER_DB = np.array([
    [-37.0, -21.4, -11.9, -17.2, -21.2, -25.3, -29.9, -38.0, -49.5, -59.5],
    [-29.2, -11.7, -16.9, -20.3, -24.2, -29.3, -35.8, -45.5, -52.1, -61.6],
    [-27.3, -9.8, -23.1, -21.5, -28.3, -36.8, -45.0, -49.2, -53.1, -59.0],
    [-26.0, -10.4, -23.2, -21.5, -27.6, -35.9, -43.7, -47.4, -53.4, -57.6],
    [-25.1, -9.5, -23.1, -21.8, -29.0, -40.4, -46.3, -52.6, -55.6, -60.2],
    [-27.3, -10.5, -23.6, -22.4, -30.4, -40.3, -43.3, -47.6, -53.2, -56.5],
    [-24.5, -10.0, -22.8, -22.4, -29.6, -35.5, -43.4, -51.4, -52.8, -57.3],
    [-24.9, -9.9, -23.1, -22.1, -29.2, -37.9, -42.3, -49.0, -52.0, -55.5],
    [-27.5, -10.2, -22.8, -22.1, -29.5, -38.0, -45.5, -48.1, -49.0, -52.8],
    [-23.8, -10.2, -22.7, -22.7, -31.2, -36.2, -43.3, -50.4, -50.1, -53.6],
    [-25.4, -10.7, -23.4, -23.5, -28.7, -35.5, -41.1, -48.0, -49.8, -50.0],
    [-26.3, -9.5, -22.8, -23.1, -32.6, -37.3, -43.1, -50.9, -56.1, -61.2],
    [-26.6, -10.8, -21.9, -22.1, -28.5, -33.6, -40.8, -49.3, -53.2, -60.2],
    [-26.9, -10.2, -23.2, -22.9, -26.4, -37.5, -42.7, -48.1, -53.0, -57.5],
    [-28.6, -12.3, -19.4, -22.4, -28.9, -35.1, -41.8, -48.3, -51.5, -57.8],
    [-23.4, -14.4, -24.2, -23.8, -28.5, -31.5, -39.0, -45.6, -48.9, -55.4],
    [-28.8, -15.6, -19.0, -25.0, -26.2, -32.1, -41.1, -47.6, -48.3, -56.5],
    [-26.1, -14.2, -19.8, -23.8, -24.7, -31.7, -40.6, -44.0, -49.4, -55.9],
    [-28.2, -11.0, -23.9, -24.0, -24.9, -33.2, -42.7, -45.0, -51.0, -58.4],
    [-29.2, -12.5, -22.2, -24.3, -29.3, -33.8, -42.1, -47.2, -52.6, -58.2],
    [-32.4, -14.3, -21.6, -24.6, -27.4, -35.2, -43.2, -49.2, -53.1, -59.5],
    [-31.9, -17.2, -20.4, -22.9, -24.2, -31.1, -40.9, -49.1, -52.9, -58.7],
    [-32.9, -18.1, -21.2, -21.9, -22.2, -30.1, -37.5, -48.3, -53.5, -60.1],
    [-33.6, -17.6, -23.1, -23.0, -25.3, -32.1, -37.8, -46.9, -52.6, -59.3],
    [-40.5, -22.3, -22.8, -22.8, -25.4, -29.2, -37.5, -45.7, -52.9, -58.7],
    [-30.9, -23.7, -22.5, -23.8, -25.9, -31.0, -37.9, -46.1, -53.8, -62.6],
    [-24.4, -18.9, -19.9, -20.8, -25.1, -30.6, -38.4, -45.8, -53.1, -62.7],
    [-23.2, -19.9, -18.5, -19.4, -25.2, -30.1, -34.6, -34.7, -35.6, -37.8],
    [-20.4, -20.2, -18.3, -21.5, -26.4, -31.6, -38.4, -43.5, -40.4, -41.9],
    [-16.6, -21.0, -19.6, -26.0, -28.9, -31.5, -36.2, -39.8, -44.5, -51.3],
    [-18.3, -17.6, -21.0, -26.0, -27.8, -28.3, -30.2, -32.4, -33.3, -38.0],
    [-12.9, -20.5, -23.3, -26.0, -31.2, -31.9, -33.9, -37.8, -37.8, -41.9],
])
AETHER_BLOWS = ((0.040, 67.3, -7.2), (0.095, 62.6, -7.0), (0.145, 62.1, -7.2), (0.200, 60.3, -7.2), (0.375, 63.6, -8.7), (0.470, 66.2, -14.2), (0.680, 102.5, -16.0))
# (impact: measured to 1.72 s after its onset; its first 0.6 s peaks +2.6 dB over its loudest 400 ms)
IMPACT_T = np.array([0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.27, 0.29, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.45, 0.47, 0.49, 0.65, 1.00])
IMPACT_DB = np.array([
    [-25.6, -22.9, -17.4, -20.3, -18.4, -30.2, -40.0, -44.2, -43.3, -48.3],
    [-25.7, -21.1, -24.9, -19.1, -20.7, -31.9, -40.0, -46.4, -37.4, -39.6],
    [-22.7, -19.5, -19.1, -16.9, -22.9, -30.8, -35.2, -36.9, -33.0, -32.2],
    [-25.1, -18.9, -18.9, -18.6, -22.0, -31.6, -37.0, -39.6, -32.1, -31.3],
    [-29.7, -29.7, -22.1, -20.9, -23.3, -27.1, -30.6, -29.8, -31.0, -31.1],
    [-44.4, -21.9, -25.1, -20.1, -21.9, -21.6, -25.2, -29.7, -30.6, -33.4],
    [-37.3, -22.8, -18.9, -17.9, -20.2, -24.3, -27.6, -33.3, -34.0, -34.3],
    [-30.0, -28.9, -25.6, -27.4, -23.5, -27.7, -33.9, -35.9, -32.8, -33.7],
    [-32.1, -25.9, -33.8, -25.0, -20.4, -23.4, -30.0, -31.9, -29.4, -31.6],
    [-32.1, -27.4, -30.2, -22.9, -19.6, -21.5, -23.9, -26.0, -29.3, -34.6],
    [-38.0, -28.8, -29.0, -22.5, -19.6, -18.5, -22.5, -28.0, -29.8, -40.4],
    [-46.3, -30.2, -27.8, -26.0, -18.1, -18.4, -17.1, -28.6, -32.3, -42.5],
    [-43.0, -31.5, -27.3, -18.8, -16.1, -18.1, -20.6, -27.5, -34.3, -44.2],
    [-38.9, -27.0, -30.9, -19.1, -16.6, -20.4, -18.7, -26.0, -35.2, -44.6],
    [-42.6, -28.7, -26.0, -30.1, -18.8, -17.6, -17.1, -25.6, -35.2, -45.4],
    [-37.5, -24.0, -22.3, -24.8, -21.9, -17.1, -16.9, -26.4, -36.5, -47.0],
    [-37.1, -30.4, -27.5, -27.0, -23.0, -19.4, -15.5, -24.2, -33.8, -45.9],
    [-45.2, -31.7, -26.5, -25.9, -24.5, -23.0, -17.2, -26.1, -37.1, -48.7],
    [-46.4, -28.3, -27.5, -26.3, -21.1, -19.7, -18.2, -25.3, -37.6, -49.0],
    [-38.4, -27.7, -32.2, -35.5, -20.0, -15.7, -21.4, -24.0, -36.9, -48.6],
    [-42.6, -29.2, -30.8, -32.7, -21.6, -13.5, -24.7, -26.7, -37.6, -48.6],
    [-41.5, -32.1, -29.6, -32.5, -20.6, -13.9, -23.6, -24.8, -36.9, -47.6],
    [-34.8, -28.4, -29.6, -33.4, -25.7, -25.0, -20.6, -20.6, -35.4, -49.1],
    [-39.2, -26.3, -27.7, -33.7, -23.8, -28.4, -24.0, -27.6, -39.3, -49.1],
    [-31.5, -25.9, -33.8, -30.4, -24.5, -24.9, -27.1, -30.2, -34.5, -42.4],
    [-25.9, -20.4, -25.6, -29.1, -29.1, -29.8, -28.9, -29.8, -32.5, -39.5],
    [-13.8, -17.4, -19.9, -23.6, -26.9, -29.7, -27.9, -26.5, -29.2, -36.5],
])
IMPACT_BLOWS = ((0.070, 86.9, -12.7), (0.125, 95.0, -15.6), (0.200, 354.2, -20.3), (0.310, 98.2, -18.0), (0.380, 78.9, -21.0), (0.575, 51.3, -19.8), (0.630, 79.2, -13.1), (0.690, 61.7, -13.0))
# (erupt: measured to 7.0 s after its onset; its first 0.6 s peaks +2.7 dB over its loudest 400 ms)
ERUPT_T = np.array([0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.27, 0.29, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.45, 0.47, 0.49, 0.65, 1.00, 1.50, 2.15, 3.00, 4.25, 6.00])
ERUPT_DB = np.array([
    [-14.5, -21.3, -28.5, -27.3, -24.6, -26.6, -26.4, -23.2, -25.5, -36.2],
    [-11.6, -18.7, -20.5, -27.5, -30.4, -32.5, -29.5, -25.6, -28.2, -38.7],
    [-13.0, -15.5, -23.1, -27.4, -31.8, -35.1, -28.9, -25.6, -30.7, -42.0],
    [-11.8, -27.3, -24.6, -26.5, -29.8, -30.6, -29.5, -24.8, -27.9, -38.8],
    [-12.9, -21.9, -19.9, -26.9, -31.3, -32.3, -27.7, -23.1, -26.6, -36.9],
    [-16.4, -20.9, -20.1, -30.0, -29.8, -30.1, -26.5, -20.7, -24.4, -35.3],
    [-20.4, -19.8, -22.3, -32.5, -31.1, -29.0, -25.3, -19.7, -24.2, -35.4],
    [-12.7, -22.3, -29.6, -36.7, -31.8, -33.9, -29.7, -23.2, -27.7, -38.3],
    [-11.9, -23.9, -27.4, -34.3, -34.7, -37.4, -30.0, -22.4, -26.1, -36.1],
    [-9.8, -18.6, -25.4, -40.1, -36.6, -35.8, -32.5, -25.4, -28.7, -37.7],
    [-11.2, -21.1, -21.7, -31.3, -38.4, -37.8, -32.5, -27.4, -30.7, -40.6],
    [-9.8, -20.4, -22.7, -35.4, -41.8, -39.5, -35.3, -29.4, -32.1, -41.2],
    [-11.2, -19.8, -27.5, -38.2, -36.7, -37.6, -30.0, -25.6, -28.7, -37.7],
    [-12.4, -20.4, -32.0, -36.0, -37.0, -34.8, -29.5, -23.6, -27.1, -35.9],
    [-12.9, -19.6, -29.4, -39.1, -37.9, -33.9, -28.9, -23.6, -26.9, -36.0],
    [-12.8, -21.5, -28.5, -35.6, -31.4, -29.2, -27.2, -23.0, -25.8, -34.7],
    [-14.9, -24.0, -32.5, -33.1, -28.8, -21.6, -23.3, -21.3, -21.9, -29.1],
    [-17.9, -28.8, -30.3, -33.3, -29.2, -24.3, -23.8, -22.3, -21.5, -27.8],
    [-15.2, -22.9, -20.9, -37.2, -31.3, -25.9, -25.7, -22.8, -23.7, -29.8],
    [-14.9, -23.2, -21.8, -31.6, -32.0, -27.2, -24.7, -23.2, -26.0, -32.9],
    [-14.1, -20.0, -27.6, -34.5, -32.3, -28.4, -27.5, -24.4, -26.4, -33.1],
    [-21.8, -26.3, -27.0, -29.4, -30.1, -26.6, -24.2, -22.3, -22.9, -29.8],
    [-21.6, -17.8, -25.4, -30.9, -35.1, -31.1, -27.4, -24.6, -23.6, -29.7],
    [-19.7, -17.4, -21.7, -30.5, -36.1, -32.0, -28.8, -23.4, -24.4, -30.9],
    [-17.3, -15.1, -26.7, -28.1, -37.5, -36.7, -28.7, -24.9, -25.8, -31.5],
    [-13.4, -18.5, -21.9, -31.9, -39.2, -38.2, -29.9, -26.4, -27.4, -33.8],
    [-19.3, -19.9, -21.9, -24.5, -26.7, -27.6, -24.8, -26.5, -31.4, -40.9],
    [-14.6, -16.9, -20.6, -23.7, -25.4, -26.3, -26.9, -30.8, -41.2, -55.1],
    [-14.0, -17.4, -23.0, -24.3, -25.8, -26.8, -27.5, -30.2, -41.0, -55.6],
    [-13.6, -16.7, -21.8, -24.5, -26.5, -29.4, -30.1, -34.2, -44.0, -59.9],
    [-11.7, -17.7, -21.3, -26.7, -28.7, -31.2, -36.4, -41.3, -45.9, -55.5],
    [-14.2, -19.9, -22.7, -23.7, -25.4, -28.8, -33.7, -39.5, -47.2, -54.6],
])
ERUPT_BLOWS = ((0.050, 35.1, -7.4), (0.200, 36.0, -8.4), (0.390, 36.3, -11.6), (0.490, 44.5, -9.2), (0.560, 64.9, -10.9), (0.680, 32.6, -10.4))
# (blast: measured to 6.97 s after its onset; its first 0.6 s peaks +2.8 dB over its loudest 400 ms)
BLAST_T = np.array([0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.27, 0.29, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.45, 0.47, 0.49, 0.65, 1.00, 1.50, 2.15, 3.00, 4.25])
BLAST_DB = np.array([
    [-39.4, -29.0, -32.9, -29.2, -36.1, -45.8, -46.1, -46.7, -49.0, -62.4],
    [-37.1, -25.6, -24.6, -20.0, -29.7, -40.7, -40.3, -39.9, -41.9, -55.2],
    [-29.6, -20.9, -25.4, -22.3, -25.7, -23.5, -22.4, -23.8, -26.9, -34.1],
    [-30.6, -23.5, -18.6, -20.3, -24.5, -22.7, -23.3, -23.0, -25.4, -32.6],
    [-34.4, -18.4, -16.0, -23.2, -23.1, -24.4, -25.1, -25.4, -31.8, -38.0],
    [-24.2, -17.6, -17.7, -21.7, -25.8, -25.9, -27.0, -27.5, -33.3, -42.9],
    [-25.6, -14.0, -17.2, -22.2, -24.9, -26.7, -27.2, -28.4, -33.1, -42.3],
    [-34.4, -17.1, -22.3, -20.5, -23.3, -22.6, -23.2, -24.5, -27.8, -37.1],
    [-33.2, -15.6, -22.9, -20.9, -20.5, -24.5, -24.0, -23.5, -27.9, -37.5],
    [-26.1, -16.6, -24.5, -17.5, -19.0, -24.6, -24.5, -24.1, -30.1, -39.1],
    [-28.8, -19.6, -26.0, -20.0, -17.9, -22.0, -23.0, -24.3, -29.0, -36.4],
    [-26.9, -16.8, -17.8, -22.7, -20.1, -27.4, -25.0, -26.3, -30.4, -38.1],
    [-25.8, -14.1, -16.9, -22.2, -21.1, -24.7, -26.4, -27.6, -32.8, -43.8],
    [-28.4, -15.8, -14.7, -22.9, -20.1, -23.8, -25.2, -26.6, -33.7, -44.5],
    [-33.0, -14.7, -20.6, -22.4, -23.6, -23.9, -26.0, -27.5, -32.2, -43.4],
    [-30.2, -24.1, -16.9, -22.6, -19.9, -23.3, -26.1, -26.4, -31.4, -42.0],
    [-33.6, -16.3, -19.6, -21.7, -22.5, -26.3, -27.7, -29.3, -34.6, -43.7],
    [-25.5, -18.6, -22.0, -21.3, -22.6, -25.5, -24.8, -27.9, -34.3, -45.1],
    [-18.8, -16.4, -20.8, -20.9, -26.5, -26.3, -27.8, -28.4, -36.4, -47.1],
    [-22.5, -13.9, -20.2, -22.0, -26.7, -25.8, -27.8, -29.1, -35.4, -47.8],
    [-20.3, -14.4, -19.8, -23.1, -26.5, -23.9, -25.8, -30.4, -35.4, -47.9],
    [-24.1, -13.5, -21.8, -21.7, -26.3, -26.5, -27.6, -30.6, -37.1, -47.9],
    [-27.4, -15.5, -19.4, -22.4, -25.9, -23.7, -26.3, -28.9, -35.1, -48.1],
    [-21.2, -12.2, -23.7, -27.1, -26.7, -25.5, -29.1, -31.5, -37.7, -49.6],
    [-20.1, -14.2, -17.1, -22.6, -26.3, -25.9, -28.8, -33.7, -39.4, -51.1],
    [-20.7, -16.3, -21.2, -23.2, -25.1, -24.9, -26.7, -29.5, -36.2, -48.2],
    [-20.0, -16.6, -20.7, -23.1, -24.1, -24.4, -26.9, -29.0, -35.7, -47.6],
    [-25.6, -22.0, -23.1, -21.0, -22.1, -21.7, -25.3, -27.9, -34.4, -45.3],
    [-14.9, -19.7, -19.3, -20.4, -22.6, -23.8, -27.4, -29.4, -34.3, -43.1],
    [-15.1, -22.7, -23.3, -27.8, -17.9, -20.2, -24.4, -24.4, -27.7, -37.8],
    [-15.6, -15.0, -24.6, -29.1, -23.9, -25.8, -25.3, -26.5, -31.2, -41.2],
])
BLAST_BLOWS = ((0.130, 78.7, -8.3), (0.260, 74.8, -7.4), (0.460, 56.1, -7.2), (0.555, 53.1, -9.0), (0.630, 83.2, -9.5), (0.685, 48.2, -9.8))
# (tear: measured to 4.3 s after its onset; its first 0.6 s peaks +3.0 dB over its loudest 400 ms)
TEAR_T = np.array([0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15, 0.17, 0.19, 0.21, 0.23, 0.25, 0.27, 0.29, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.45, 0.47, 0.49, 0.65, 1.00, 1.50, 2.15, 3.00])
TEAR_DB = np.array([
    [-40.4, -37.9, -31.0, -25.5, -26.0, -24.7, -24.2, -22.4, -22.5, -23.5],
    [-44.2, -32.0, -19.5, -24.6, -22.3, -23.2, -22.9, -20.0, -22.1, -25.6],
    [-33.6, -14.8, -19.2, -21.8, -25.8, -26.4, -23.4, -23.1, -25.5, -30.0],
    [-30.8, -13.5, -24.0, -25.7, -30.2, -25.5, -22.3, -20.3, -22.8, -30.2],
    [-25.9, -20.6, -16.5, -23.7, -24.9, -24.2, -20.9, -19.8, -23.3, -29.6],
    [-25.7, -16.3, -18.0, -24.4, -29.1, -25.6, -20.1, -19.7, -23.6, -29.3],
    [-17.0, -15.8, -25.9, -27.3, -28.1, -28.6, -21.0, -20.7, -24.6, -30.2],
    [-15.2, -20.6, -26.0, -26.5, -29.0, -26.1, -20.8, -20.0, -23.8, -29.7],
    [-12.6, -17.8, -23.4, -27.0, -32.7, -29.8, -23.4, -24.8, -27.5, -33.3],
    [-16.1, -16.5, -22.7, -27.6, -28.9, -24.4, -22.5, -22.8, -24.7, -32.4],
    [-15.7, -21.5, -16.4, -24.4, -26.5, -26.1, -26.2, -24.8, -26.7, -31.7],
    [-14.6, -20.6, -15.3, -20.7, -28.0, -28.4, -28.3, -26.4, -25.7, -30.7],
    [-14.1, -21.4, -17.7, -30.0, -28.0, -27.5, -28.7, -28.9, -28.9, -35.5],
    [-14.6, -16.2, -17.3, -21.8, -28.5, -31.7, -28.5, -26.7, -28.2, -35.6],
    [-18.4, -12.4, -19.4, -23.2, -27.3, -29.2, -28.1, -26.1, -26.7, -34.3],
    [-26.0, -11.1, -22.9, -23.0, -31.4, -33.7, -31.5, -29.1, -30.4, -38.9],
    [-21.5, -11.0, -23.3, -27.5, -30.5, -25.3, -28.7, -27.1, -28.5, -36.8],
    [-17.1, -12.8, -21.0, -23.4, -31.5, -30.8, -31.3, -29.8, -33.5, -40.8],
    [-16.8, -14.6, -22.6, -26.8, -30.0, -26.8, -28.0, -27.0, -30.0, -37.6],
    [-13.9, -18.4, -18.6, -21.2, -28.6, -29.6, -31.9, -31.2, -31.4, -41.5],
    [-12.5, -21.7, -19.9, -21.1, -26.1, -28.9, -32.4, -30.5, -31.5, -41.0],
    [-10.9, -24.4, -19.1, -27.2, -26.6, -27.4, -31.7, -30.9, -33.5, -43.1],
    [-11.9, -22.4, -23.3, -29.5, -30.4, -30.8, -34.7, -33.3, -33.5, -44.7],
    [-12.9, -15.6, -20.2, -23.8, -29.3, -31.8, -36.1, -35.1, -37.9, -46.8],
    [-19.2, -20.2, -23.5, -22.9, -29.4, -27.8, -31.9, -31.8, -34.7, -44.3],
    [-18.2, -15.5, -18.5, -23.0, -28.6, -26.6, -30.8, -30.9, -35.7, -47.3],
    [-19.0, -17.1, -17.4, -23.2, -28.4, -30.6, -36.1, -38.7, -47.0, -62.3],
    [-18.3, -15.1, -20.4, -25.8, -32.2, -38.5, -45.3, -51.4, -63.5, -79.1],
    [-16.9, -14.0, -21.0, -26.0, -35.3, -45.3, -54.9, -63.8, -74.6, -89.7],
    [-12.1, -18.7, -21.4, -28.5, -40.5, -49.9, -60.2, -69.6, -79.1, -92.1],
])
TEAR_BLOWS = ((0.060, 69.9, -9.5), (0.130, 63.6, -10.3), (0.180, 39.6, -9.2), (0.310, 65.4, -7.3), (0.365, 47.7, -7.5), (0.465, 33.9, -9.4), (0.535, 92.5, -8.7), (0.680, 50.2, -8.9))

# Per kind: its table and blows, how high its start peaks (`crest`, dB over its loudest 400 ms), and the last row it is
# built to (`own`, s: past it the reference's rows hold other sound, or for the impact its lows swelling again into a
# second hit, which here would land on the first surge; past it the roar falls away at the rates the build gives).
OWN = {"nether": dict(T=NETHER_T, DB=NETHER_DB, blows=NETHER_BLOWS, crest=4.1, own=1.5),
       "aether": dict(T=AETHER_T, DB=AETHER_DB, blows=AETHER_BLOWS, crest=1.6, own=1.0),
       "impact": dict(T=IMPACT_T, DB=IMPACT_DB, blows=IMPACT_BLOWS, crest=2.6, own=0.65),
       "erupt": dict(T=ERUPT_T, DB=ERUPT_DB, blows=ERUPT_BLOWS, crest=2.7, own=6.0),
       "blast": dict(T=BLAST_T, DB=BLAST_DB, blows=BLAST_BLOWS, crest=2.8, own=4.25),
       "tear": dict(T=TEAR_T, DB=TEAR_DB, blows=TEAR_BLOWS, crest=3.0, own=3.0)}
KEEP = 0.5          # (the first half second keeps its own timing; what comes after is scaled by `k`)
TOP_IN = 0.04       # (the octaves from 1 kHz up rise in over the first 40 ms: nothing bright on the front)
TOP_IN_DB = 15.0
ONSET = 0.012       # (the whole eased in over this from its onset)
BLOW_MAX = 160.0    # (a "blow" measured over this is a mid peak, not a blow: left to the roar)
CLIP_TOP = 300.0    # (the start's soft clip kept under this, Hz)
LOWS = 105.0        # (blows under this are swept sines with a body; over it, punches of noise)


def windows(T_):
    """The measuring window of each row time: 20 ms about a fine row, the COARSE window a coarse row is the middle of."""
    out = []
    for tc in T_:
        if tc < KEEP:
            out.append((tc - FINE / 2, tc + FINE / 2))
        else:
            out.append(min(COARSE, key=lambda w: abs((w[0] + w[1]) / 2 - tc)))
    return out


def shift_oct(rows, f):
    """Each row's spectrum moved up log2(f) octaves (along the octaves, the ends held)."""
    if f == 1.0:
        return np.array(rows, dtype=float)
    lo = np.log2(OCT)
    return np.array([np.interp(lo - np.log2(f), lo, r) for r in rows])


def table_of(kind, k=1.0, f=1.0):
    """Kind `kind`'s table as it is built and measured: (row times (s after the onset, scaled by `k` after KEEP), the
    rows (shifted by `f`), their windows (scaled alike)). Its own rows only; the fine rows' octaves from 1 kHz up are
    averaged (power) over three windows: the reference's 25 Hz flutter up there is left out."""
    o = OWN[kind]
    m = o["T"] <= o["own"] + 1e-9
    T_, rows = o["T"][m], np.array(o["DB"][m], dtype=float)
    fine = np.where(T_ < KEEP)[0]
    hi = OCT >= 1000
    p = 10 ** (rows[fine][:, hi] / 10)
    sm = p.copy()
    sm[1:-1] = (p[:-2] + p[1:-1] + p[2:]) / 3
    rows[fine[:, None], np.where(hi)[0][None, :]] = 10 * np.log10(sm)
    rows = shift_oct(rows, f)
    w = [(float(warp(a, k, KEEP)), float(warp(b, k, KEEP))) for a, b in windows(T_)]
    return warp(T_, k, KEEP), rows, w


def fall_rows(T_, rows, d, fall):
    """Rows past the table's last, every 0.25 s to `d`: each octave falling from the last row at its own rate (dB a
    second: `fall` = (at 31.5 Hz, at 16 kHz), between them along the octaves)."""
    rate = np.interp(np.log2(OCT), [np.log2(OCT[0]), np.log2(OCT[-1])], fall)
    ts = np.arange(T_[-1] + 0.25, d + 0.25, 0.25)
    return ts, np.array([rows[-1] - rate * (tc - T_[-1]) for tc in ts]).reshape(-1, len(OCT))


def blow(n, u, on, tb, hz, rng_, body=P.ALT_BODY):
    """One low blow at `tb` s: under LOWS a sine swept down 12 % onto `hz` (rising over 12 ms, falling over 35) with a
    broad body of noise (38-150 Hz scaled with it, as the Payload alternative's boom); over it a punch of noise round
    `hz` (an octave and a bit wide, 8 ms)."""
    uu = u - tb
    if hz <= LOWS:
        env = np.where(uu < 0, np.exp(-0.5 * (uu / 0.012) ** 2), np.exp(-uu / 0.035)) * on
        f0 = hz * (1 + 0.12 * np.exp(-np.maximum(uu, 0) / 0.05))
        x = np.sin(2 * np.pi * np.cumsum(f0 * on) / SR + rng_.uniform(0, 6.28)) * env
        return x + T.unit(band(rng_.standard_normal(n), 38 * hz / 50, 150 * hz / 50, 3)) * env * body
    return T.unit(band(rng_.standard_normal(n), hz / 1.5, hz * 1.5, 3)) * np.exp(-0.5 * (uu / 0.008) ** 2) * on


def lev10(x, at, lo=30.0, hi=120.0):
    """The 10 ms level of x's lo-hi Hz at `at` s (dB)."""
    y = band(x[max(N(at) - N(0.3), 0):N(at) + N(0.3)], lo, hi, 4)
    c = min(N(0.3), N(at))
    s = y[c - N(0.005):c + N(0.005)]
    return 10 * np.log10(np.mean(s * s) + 1e-14)


def N(s):
    return int(round(s * SR))


def own_blast(kind, seed, d, k=1.0, f=1.0, fall=(8.0, 20.0), trim=None, t0=0.02, extra=None, btrim=None, mid=0.0,
              roar=None, clips=True):
    """Kind `kind`'s explosion (OWN), mono, `d` s, its onset `t0` in: the roar from its table (`table_of`, times after
    KEEP scaled by `k`, `f` times its pitch; then falling away by `fall`), its octaves from 1 kHz up let in over
    TOP_IN; the blows at their times (scaled alike) and pitches (times `f`), each at its measured level; the lows'
    harmonics (`P.alt_harmonics`); the lows rounded off P.ALT_LOW_CLIP dB over their loudest 400 ms and the first
    0.6 s at the kind's `crest`. `trim` (dB, per row) moves the table's rows and `btrim` (dB, per blow) the blows;
    `extra(x, u, on, rng)` adds to it before the clips; `mid` (dB) moves the blows' body and the harmonics together;
    `roar(x, u)` reshapes the roar alone (before the blows are laid in); `clips` False leaves out the two soft clips.
    At about the table's level."""
    n = int(SR * d)
    t = np.arange(n) / SR
    u = np.maximum(t - t0, 0.0)
    on = t >= t0
    T_, rows, _ = table_of(kind, k, f)
    if trim is not None:
        rows = rows + trim
    ft, fr = fall_rows(T_, rows, d, fall)
    times = np.concatenate([[-0.006], T_, ft]) + t0
    tab = np.vstack([rows[0] - 40.0, rows, fr])
    with PB.seeded(seed):
        rg = rng()
        x = PB.shaped_noise_tv(d, times, tab, np.array([0.0, d]), np.ones((2, len(OCT))), 2048, 256)[0] * SN2
        # (eased in over ONSET from the onset: the noise's frames reach back over it, and a cut there would click)
        ease = np.where(on, np.sin(0.5 * np.pi * np.clip(u / ONSET, 0, 1)) ** 2, 0.0)
        x = x * ease
        hi = band(x, 1000, None, 2)
        x = x - hi + hi * 10 ** (-TOP_IN_DB * (1 - np.clip(u / TOP_IN, 0, 1)) ** 2 / 20)
        if roar is not None:
            x = roar(x, u)
        for j, (tb, hz, lv) in enumerate(blows_of(kind)):
            tb_, hz_ = float(warp(tb, k, KEEP)), hz * f
            b = blow(n, u, on, tb_, hz_, rg, P.ALT_BODY * 10 ** (mid / 20))
            x = x + b * 10 ** ((lv - 1.0 + (0.0 if btrim is None else btrim[j]) - lev10(b, t0 + tb_)) / 20)
        x = P.alt_harmonics(x, x, u, on, P.ALT_HARM_DB + mid, 0.0, (t0, t0 + 0.4))[0]
        x = PB.causal_lowcut(x * ease, 24.0)
        if extra is not None:
            x = extra(x, u, on, rg)
        if not clips:
            return x * ease
        lo = band(x, None, 110, 4)
        x = x - lo + PB.soft_clip(lo, T.loudest(lo) * 10 ** (P.ALT_LOW_CLIP / 20), 0.5)
        # (the start as dense as the reference's: its peaks rounded off `crest` dB over its loudest 400 ms; only what the
        # rounding takes off under CLIP_TOP Hz is kept, so the lows are squashed and nothing new is sprayed up top)
        free = 1 + 1e3 * np.clip((u - 0.6) / 0.1, 0, 1) ** 2
        x0, lv = x, T.loudest(x)
        for _ in range(4):
            x = x0 + band(PB.soft_clip(x0, lv * 10 ** (OWN[kind]["crest"] / 20) * free, 0.5) - x0, None, CLIP_TOP, 4)
            lv = T.loudest(x)
    return x * ease


def oct_windows(x, t0, wins, pad=0.5):
    """`P.oct_levels`' octave filters run over the whole stretch round the windows (s after t0; a short window is not
    cut out before it is filtered, where the lows' edges would spray into the top), then each window's RMS: [window,
    octave] dB. The tables were measured with it."""
    a0 = min(a for a, _ in wins) - pad
    b0 = max(b for _, b in wins) + pad
    k0 = N(t0 + a0)
    seg = x[max(k0, 0):N(t0 + b0)]
    if k0 < 0:
        seg = np.r_[np.zeros(-k0), seg]
    out = np.zeros((len(wins), len(OCT)))
    for j, fc in enumerate(OCT):
        y = band(seg, fc / 2 ** 0.5, min(fc * 2 ** 0.5, SR * 0.47), 3)
        for i, (a, b) in enumerate(wins):
            s = y[N(a - a0):N(b - a0)]
            out[i, j] = 20 * np.log10(np.sqrt(np.mean(s ** 2)) + 1e-12)
    return out


def blows_of(kind):
    """Kind `kind`'s low blows (its measured peaks under BLOW_MAX)."""
    return [b for b in OWN[kind]["blows"] if b[1] <= BLOW_MAX]


def residuals(x, kind, k=1.0, f=1.0, t0=0.02, fit=False):
    """What x measures in the table's windows less the table ([row, octave] dB), each blow's 10 ms 30-120 Hz level
    less its measured one, and the gain (dB) x was taken by: none, or with `fit` the one that fits it best (the mean
    over 63 Hz-8 kHz)."""
    T_, rows, w = table_of(kind, k, f)
    got = oct_windows(x, t0, w)
    g = float(np.mean((rows - got)[:, 1:9])) if fit else 0.0
    bl = [lev10(x, t0 + float(warp(tb, k, KEEP))) + g - lv for tb, _, lv in blows_of(kind)]
    return got + g - rows, np.array(bl), g


def calibrated_own(kind, seed, d, k=1.0, f=1.0, fall=(8.0, 20.0), rounds=10, t0=0.02, extra=None):
    """`own_blast` with its table and blows trimmed, `rounds` times, by what it measures against the table
    (`residuals`; the same noise every round: only the levels move), the front's top left where TOP_IN put it.
    (the sound at the table's level, with `extra`; the residuals without it; with it; the trim)."""
    T_, rows, _ = table_of(kind, k, f)
    trim = np.zeros_like(rows)
    btrim = np.zeros(len(blows_of(kind)))
    front = (T_ < TOP_IN)[:, None] & (OCT >= 1000)[None, :]
    mid = 0.0
    fine = T_ < KEEP
    for _ in range(rounds):
        r, rb, _ = residuals(own_blast(kind, seed, d, k, f, fall, trim, t0, None, btrim, mid), kind, k, f, t0)
        trim = trim - np.where(front, 0.0, np.clip(r, -6.0, 6.0)) * 0.85
        btrim = btrim - np.clip(rb, -6.0, 6.0) * 0.7
        # (where the roar is already taken far down and 125-250 Hz still measure over the table, it is the blows' body
        # and the harmonics that are too much for this reference: taken down together)
        over = np.mean(np.maximum(r[fine][:, 2:4], 0.0)[trim[fine][:, 2:4] < -20.0]) if np.any(trim[fine][:, 2:4] < -20.0) else 0.0
        mid = max(mid - 0.7 * over, -24.0)
    x0 = own_blast(kind, seed, d, k, f, fall, trim, t0, None, btrim, mid)
    base = residuals(x0, kind, k, f, t0)
    x = own_blast(kind, seed, d, k, f, fall, trim, t0, extra, btrim, mid) if extra is not None else x0
    got = residuals(x, kind, k, f, t0) if extra is not None else base
    return x, base, got, (trim, btrim, mid)


# What the Nether's and the Aether's hits have on top of their references' (inside the roar, never on its front):
def boil(db=3.0, start=0.15):
    """The Nether's: its fire boiling in the roar, the 250 Hz-4 kHz swelling and sinking by about `db` dB at 1.5-10 Hz
    (the Payload alternative's boil without its faster part), coming in over 0.25 s from `start` s after the onset."""
    def add(x, u, on, rng_):
        mid = band(x, 250, 4000, 2)
        bo = np.exp(db * PB.slow_random(len(x), 1.5, 10.0) / 8.686)
        return x + mid * (bo - 1) * np.clip((u - start) / 0.25, 0, 1) * on
    return add


def ring(f0, db=-9.0, life=0.7, at=0.06, partials=(2, 3, 4, 5)):
    """The Aether's: a clean ringing weight in the roar, noise gathered narrowly (a sixth of an octave) round the
    partials of its blows' pitch `f0` (2-5: 100-400 Hz), each gliding down 3 % as it dies (over `life` s, the higher
    sooner), rising over 30 ms from `at` s after the onset; set `db` under the roar's 100-400 Hz over 0.1-0.5 s."""
    def add(x, u, on, rng_):
        n = len(x)
        uu = np.maximum(u - at, 0.0)
        y = np.zeros(n)
        for j, p in enumerate(partials):
            fc = p * f0 * (1 - 0.03 * np.clip(uu / (2 * life), 0, 1))
            env = (1 - np.exp(-uu / 0.03)) * np.exp(-uu / (life * (1 - 0.15 * j))) * (u >= at)
            y += glide(n, fc, rng_) * env * 10 ** (-3.0 * j / 20)
        k0, k1 = int(np.argmax(u >= 0.1)), int(np.argmax(u >= 0.5))
        have = np.sqrt(np.mean(band(x, 100, 400, 3)[k0:k1] ** 2))
        got = np.sqrt(np.mean(band(y, 100, 400, 3)[k0:k1] ** 2)) + 1e-12
        return x + y * have / got * 10 ** (db / 20)
    return add


def glide(n, fc, rng_, width=1 / 6, size=2048, hop=512):
    """Noise in a band `width` octaves wide round a centre that moves (`fc`, Hz, one value a sample)."""
    f = np.fft.rfftfreq(size, 1 / SR)
    win = np.hanning(size)
    out = np.zeros(n + 2 * size)
    for s in range(-size, n, hop):
        c = fc[min(max(s + size // 2, 0), n - 1)]
        g = np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / c) / (width / 2)) ** 2)
        z = (rng_.standard_normal(len(f)) + 1j * rng_.standard_normal(len(f)))
        out[s + size:s + 2 * size] += np.fft.irfft(g * z, size) * win
    y = out[size:size + n]
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-12)


# `PB.shaped_noise_tv`'s levels at this frame size (2048, hop 256) come out this much under the table's, as `oct_windows`
# measures them (pink noise at -30 dB in every octave measures -50.5 dB)
SN2 = 10 ** (20.5 / 20)


# ===========================================================================================  checked against the Payload
def same_as_payload():
    """Each lifted builder at the Payload's arguments against the Payload's own builder (its finishing and its ducking
    caught before they write anything): [(name, the largest difference)]."""
    got = {}
    keep = (PB.finish_blast_decoded, P.finish_abs, P.duck_under_blasts)
    PB.finish_blast_decoded = lambda name, L, R, *a, **k: got.__setitem__(name.split("/")[-1], (L, R))
    P.finish_abs = lambda name, L, R, *a, **k: got.__setitem__(name, (L, R))
    P.duck_under_blasts = lambda L, R, *a, **k: (L, R)
    try:
        for nm in ("blast_alt", "ground_alt", "rush", "tail"):
            P.BUILD[nm]()
    finally:
        PB.finish_blast_decoded, P.finish_abs, P.duck_under_blasts = keep
    ours = {"blast_alt": blast_alt(**ALT), "ground_alt": ground_alt(), "rush": rush(), "tail": tail()}
    return [(nm, max(float(np.max(np.abs(a - b))) for a, b in zip(got[nm], ours[nm]))) for nm in ours]


if __name__ == "__main__":
    import sys
    soundlib.init(sys.argv[1] if len(sys.argv) > 1 else "orbital-sounds")
    for nm, err in same_as_payload():
        print(f"{nm:11s} largest difference against sounds_payload's own: {err:.3g}")
