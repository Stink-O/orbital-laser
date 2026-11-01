"""The Rod from God's sounds (a tungsten rod dropped from orbit: kinetic, no explosive), all synthesised here from
noise, swept tones, resonators and filters, nothing sampled. Its drama is silence, then one enormous impact.

Timeline the files are built for, as mod/src/strike/rod.rs plays them (strike seconds; RD_HIT = 7.0 the impact;
`dist` = the player's distance from the impact point in blocks; `arrive` = dist / 343):

  hiss        at RD_HIT - HISS_CUT, cut dead on the impact (HISS_CUT s into the file); volume 1 at any distance
  ground      at RD_HIT + dist / GROUND_V - GROUND_LEAD (the ground carries it five times faster than the air)
  blast       at RD_HIT + arrive - BLAST_LEAD (BLAST_LEAD s of near-silence in the file, then the double crack)
  blast_far   the same moment, cross-faded in by distance (`far_mix`: 250 to 800 blocks, smoothstep)
  rumble      at RD_HIT + arrive + RUMBLE_AFTER
  debris      at RD_HIT + arrive + 2.5 within 500 blocks, and again at arrive + 7.0 at pitch 0.9 closer than 350

How each is made:

  hiss        the rod tearing down the last stretch: a thin sizzle of 3-9 kHz noise in fine crackling grains and a faint
              whine gliding up from ~5 to ~8 kHz, rising over 1.6 s, the same in both ears (high overhead), cut dead.
  blast       the impact. A supersonic double crack (the rod's bow shock, then 85 ms on its tail shock and the impact
              itself, the second heavier), at once the impact's tonal boom (~60 Hz dropping to ~45 in a tenth of a
              second, on to ~40; its octave, twelfth and driven harmonics stacked on it), a sub push under it and the
              ground's rebound 0.24 s on; a 40-110 Hz noise texture riding the boom and a short dark roar under it; a
              short dry tail (a few seconds of thunder roll, three echoes off far land, a small outdoor space); the
              lows' harmonics for small speakers, glue and the Nuke's overdrive, the sub clean; room made in it for the
              ground's thump wherever that lands.
  blast_far   the blast through a kilometre of air (the Nuke's `far_of`): highs let down, the cracks' front smeared,
              more low rolls, a long dark outdoor reverb, the mids kept and the lows' harmonics so it carries on a laptop.
  ground      the land's answer through the ground: a sharp falling sub thump (~46 Hz to ~22), a sub rumble, a shudder
              (low noise chopped at 9-14 Hz), a little of its harmonics for small speakers.
  rumble      the ground rumbling on: low swells rolling in off the land, low thunder rolls, a heaving sub bed; ~20 s.
  debris      the ejecta coming back down: clods thudding, stones clacking and bouncing, grit, slabs landing off, near
              and far (the far ones darker, in the land's echo); ~6.5 s.

    python3 tools/sounds_rod.py                      # writes orbital-sounds/assets/orbital/sounds/rod/*.ogg and the
                                                     # rod.* events in sounds.json (nothing else touched)
    python3 tools/sounds_rod.py --only blast         # one (blast before blast_far, rumble and debris)
    python3 tools/sounds_rod.py --listen DIR         # also WAVs (and MP3s) of each, and the whole strike heard from
                                                     # 200 and 600 blocks, with every mixdown's true peak
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
import sounds_nuke as N

TH = "rod"
N.TH = TH                      # (the Nuke's helpers, finish_at, decoded, duck_under, far_of, write to rod/ now)
NAMES = ["hiss", "ground", "blast", "blast_far", "rumble", "debris"]
ROOT = Path(__file__).resolve().parent.parent
PEAK = N.PEAK
BLAST_PEAK = 10 ** (-1.6 / 20)
CEIL = 10 ** (-1.45 / 20)       # what plays with the blasts is kept under this with them (decoded: under -1 dBTP)
N.DUCK_CEIL = CEIL             # (and what is ducked under them, `N.duck_under`, the same)

# ---- the timeline (seconds; 0 = the impact)
RD_HIT = 7.0
HISS_CUT = 1.6
SPEED = 343.0
GROUND_V = 5 * SPEED
GROUND_LEAD = 0.02
BLAST_LEAD = 0.02
RUMBLE_AFTER = 1.0
DEBRIS_AFTER = (2.5, 7.0)
DEBRIS_REACH = 500.0
BLASTS = ("blast", "blast_far")


def rng():
    return soundlib.rng


def far_mix(dist):
    """How much of the blast is `blast_far` at `dist` blocks: none within 250, all past 800."""
    u = np.clip((dist - 250.0) / 550.0, 0, 1)
    return float(u * u * (3 - 2 * u))


def volumes(dist):
    """The volumes rod.rs plays them at, `dist` blocks off."""
    far = far_mix(dist)
    gap = dist / SPEED - dist / GROUND_V
    near = max(0.0, 1.0 - dist / DEBRIS_REACH)
    return {
        "hiss": 1.0,
        "ground": float(np.clip(1.0 / (1.0 + dist / 1200.0), 0.35, 1.0) * np.clip((gap - 0.05) / 0.9, 0.3, 1.0) ** 1.2),
        "blast": 1.0 - far,
        "blast_far": far * min(1.25 / (1.0 + dist / 2000.0), 1.0),
        "rumble": 1.0,
        "debris": (0.5 + 0.5 * near) if dist < DEBRIS_REACH else 0.0,
        "debris2": (0.25 + 0.4 * near) if near > 0.3 else 0.0,
    }


def schedule(dist):
    """(event, file, start against the impact, pitch) as rod.rs plays them."""
    late = dist / SPEED
    return [("hiss", "hiss", -HISS_CUT, 1.0), ("ground", "ground", dist / GROUND_V - GROUND_LEAD, 1.0),
            ("blast", "blast", late - BLAST_LEAD, 1.0), ("blast_far", "blast_far", late - BLAST_LEAD, 1.0),
            ("rumble", "rumble", late + RUMBLE_AFTER, 1.0),
            ("debris", "debris", late + DEBRIS_AFTER[0], 1.0), ("debris2", "debris", late + DEBRIS_AFTER[1], 0.9)]


# ================================================================================================================  hiss
def hiss():
    d = HISS_CUT + 0.02
    n = int(SR * d)
    t = np.arange(n) / SR
    with PB.seeded(88101):
        rise = np.clip(t / HISS_CUT, 0, 1)
        env = 10 ** ((-34.0 + 30.0 * rise ** 1.6) / 20)                 # (from nothing to its loudest at the impact)
        gr = np.clip(N.grains(d, 900.0, (0.0008, 0.002, 0.004)), 0, 8) ** 0.8
        siz = T.unit(band(white(d), 3000, 9000, 2)) * (0.35 + 0.65 * gr / (gr.mean() + 1e-9))
        f = 5000.0 + 3000.0 * rise ** 1.4
        wh = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.12 + 0.25 * P.glide_band(d, f, 0.15)
        x = (siz * 0.5 + wh) * env
        x = P.air(x, 9500)
        # (high overhead: one narrow source, a touch of its echo off the land, darker)
        L, R = N.distant_verb(x, length=1.2, wet=0.25, darken=(5000, 600), decay=0.4, corr=0.9)
        cut = int(HISS_CUT * SR)
        for ch in (L, R):
            ch[cut:] = 0.0
            ch[cut - int(0.004 * SR):cut] *= np.linspace(1, 0, int(0.004 * SR))
            ch[:int(0.05 * SR)] *= np.linspace(0, 1, int(0.05 * SR))
        g = 10 ** (-14.0 / 20) / (max(np.abs(L).max(), np.abs(R).max()) + 1e-12)
    N.finish("hiss", L * g, R * g, tail_fade=0.01)


# ===============================================================================================================  blast
ROD_D = 14.0
ROD_LEVEL = -5.8          # its loudest 400 ms
CRACK_GAP = 0.085         # the bow shock, then the tail shock and the impact
CRACK_DB = 3.0           # the cracks' peak against the blows' 30-120 Hz RMS over their first 0.4 s (sharper than the Nuke's)
ROAR_DB = -20.0
TAIL_DB = -17.0
HARM_DB = -9.0
FAR_LEVEL = -11.5


def blow(u, on, tp, f_hi, f_lo, f_end, drop, rise, decs, a, drive=3.5, octv=0.28, h3=0.16, harm=0.42):
    """One tonal blow (as the Nuke's ALT): f_hi to f_lo over `drop` s, on down to f_end; its harmonics stacked on it."""
    uu = np.maximum(u - tp, 0)
    m = (u >= tp) & on
    f = f_end + (f_lo - f_end) * np.exp(-uu / 0.7) + (f_hi - f_lo) * np.exp(-uu / drop)
    ph = 2 * np.pi * np.cumsum(f * m) / SR + rng().uniform(0, 6.28)
    env = (1 - np.exp(-uu / rise)) * sum(w * np.exp(-uu / tc) for w, tc in decs) * m
    s_ = np.sin(ph)
    hh = (np.tanh(drive * s_ + 0.3) - np.tanh(0.3)) / np.tanh(drive)
    hh = band(hh - s_ * 0.9, None, 700, 2)
    return (s_ + octv * np.sin(2 * ph + rng().uniform(0, 6.28)) + h3 * np.sin(3 * ph + rng().uniform(0, 6.28)) + harm * hh) * env * a


def blast():
    d = ROD_D
    n = int(SR * d)
    t = np.arange(n) / SR
    t0 = BLAST_LEAD
    u = np.maximum(t - t0, 0)
    on = t >= t0
    with PB.seeded(88301):
        L = np.zeros(n); R = np.zeros(n)
        ti = CRACK_GAP                                                   # (the impact, against the first crack)
        # ---- the blows: a sub push, the impact's boom, the ground's rebound
        sub = blow(u, on, ti, 46.0, 38.0, 35.0, 0.04, 0.003, ((0.75, 0.15), (0.25, 0.6)), 0.85, drive=1.0, octv=0.0, h3=0.0, harm=0.0)
        boom = blow(u, on, ti + 0.004, 60.0, 45.0, 40.0, 0.05, 0.004, ((0.55, 0.18), (0.35, 0.7), (0.1, 1.8)), 1.0)
        boom += blow(u, on, ti + 0.24, 50.0, 41.0, 37.0, 0.05, 0.01, ((0.65, 0.18), (0.35, 0.7)), 0.5)
        benv = band(np.abs(boom), None, 12, 1)
        body = T.unit(band(white(d), 40, 110, 3)) * np.maximum(benv, 0) * 0.5
        low = sub + boom + body
        # ---- the double crack: the bow shock (bright, hard), then the tail shock and the impact (heavier); dry
        crack = [np.zeros(n), np.zeros(n)]
        for tc, a, w, kn in ((0.0, 0.85, 0.008, 0.5), (0.004, 0.35, 0.004, 0.2), (ti, 1.0, 0.014, 1.1), (ti + 0.005, 0.45, 0.008, 0.4)):
            for k in range(2):
                uu = u - tc
                e = np.where(uu < 0, 0.0, (1 - np.exp(-np.maximum(uu, 0) / 0.0002)) * np.exp(-np.maximum(uu, 0) / w)) * on
                ek = np.where(uu < 0, 0.0, (1 - np.exp(-np.maximum(uu, 0) / 0.001)) * np.exp(-np.maximum(uu, 0) / (w * 2.5))) * on
                knock = T.unit(band(rng().standard_normal(n), 120, 450, 2)) * ek * kn
                mid = T.unit(band(rng().standard_normal(n), 450, 5000, 2)) * e
                top = T.unit(band(rng().standard_normal(n), 5000, 15000, 2)) * e * 0.45
                crack[k] += (knock + mid + top) * a
        # ---- the roar under it, a texture: short and dark, rock and dust thrown up
        renv = (1 - np.exp(-np.maximum(u - ti - 0.03, 0) / 0.05)) * (0.6 * np.exp(-u / 0.6) + 0.4 * np.exp(-u / 2.0)) * (u > ti + 0.03) * on
        shared = band(white(d), 60, 2200, 1)
        roar = []
        for _ in range(2):
            x = band(0.7 * shared + 0.7 * band(white(d), 60, 2200, 1), None, 1300, 1)
            boil = np.exp((2.4 * PB.slow_random(n, 1.5, 10.0) + 1.2 * PB.slow_random(n, 12.0, 40.0)) / 8.686)
            roar.append(T.unit(x) * boil * renv)
        pk = lambda x, a, b: np.sqrt(np.mean(band(x, a, b, 2)[int((t0 + ti) * SR):int((t0 + ti + 0.4) * SR)] ** 2)) + 1e-12
        lref = pk(low, 30, 120)
        rg = lref * 10 ** (ROAR_DB / 20) / pk((roar[0] + roar[1]) / 2, 30, 4000)
        cg = lref * 10 ** (CRACK_DB / 20) / (np.abs((crack[0] + crack[1]) / 2).max() + 1e-12)
        L += low + roar[0] * rg + crack[0] * cg
        R += low + roar[1] * rg + crack[1] * cg
        # ---- the short dry tail: a few seconds of thunder roll, three echoes off far land
        rl, rr = PB.thunder_rolls(d, t0 + ti + 0.6, count=10, length=9.0)
        g = lref * 10 ** (TAIL_DB / 20) / (T.loudest((rl + rr) / 2) + 1e-9)
        L += rl * g; R += rr * g
        src = band((L + R) / 2, None, 900, 2) * 10 ** ((TAIL_DB + 10.0) / 20)
        for dt, gn, hi in ((0.7, 0.22, 700), (1.6, 0.15, 450), (2.9, 0.1, 280)):
            ech = band(src, 25, hi * rng().uniform(0.85, 1.15), 2)
            ir_n = int(0.4 * SR); s = np.arange(ir_n) / SR
            ir = rng().standard_normal(ir_n) * np.exp(-s / 0.1)
            ir /= np.sqrt(np.sum(ir ** 2))
            ech = np.fft.irfft(np.fft.rfft(ech, n + ir_n) * np.fft.rfft(ir, n + ir_n), n + ir_n)[:n]
            l, r = PB.pan2(ech * gn, rng().uniform(-0.7, 0.7))
            P.put(L, l, dt); P.put(R, r, dt)
        # ---- a small outdoor space round it (drier than the Nuke's)
        for i, ch in enumerate((L, R)):
            ir = T.outdoor_ir(2.5, 60 + i, density=40.0, darken=(2600, 220), decay=1.0)
            mm = n + len(ir)
            ch += np.fft.irfft(np.fft.rfft(ch, mm) * np.fft.rfft(ir, mm), mm)[:n] * 0.16
        # ---- the lows' harmonics, glue, the Nuke's overdrive (on the impact), the sub clean
        L, R = P.alt_harmonics(L, R, u, on, HARM_DB, ti - 0.01, (t0 + ti + 0.02, t0 + ti + 0.4))
        L, R = N.glue(L, R)
        L, R = N.overdrive(L * on, R * on, t0 + ti)
        f_ = T.fade(n, 0.0005, 3.0)
        L, R = PB.causal_lowcut(L * on * f_, 18.0), PB.causal_lowcut(R * on * f_, 18.0)
        # (the lows rounded off a little over their loudest, then the first 0.5 s into a soft clip, as the ALT blasts)
        lows = [band(ch, None, 110, 4) for ch in (L, R)]
        c_lo = T.loudest((lows[0] + lows[1]) / 2) * 10 ** (2.5 / 20)
        L = L - lows[0] + PB.soft_clip(lows[0], c_lo, 0.5)
        R = R - lows[1] + PB.soft_clip(lows[1], c_lo, 0.5)
        free = 1 + 1e3 * np.clip((u - 0.5) / 0.1, 0, 1) ** 2
        L0, R0 = L, R
        lv = T.loudest((L + R) / 2)
        for _ in range(4):
            c = lv * 10 ** (7.0 / 20) * free
            L = PB.soft_clip(L0, c, 0.5); R = PB.soft_clip(R0, c, 0.5)
            lv = T.loudest((L + R) / 2)
    N.finish_at("blast", L, R, ROD_LEVEL, tail_fade=2.0, knee=0.5, peak=BLAST_PEAK)
    room("blast")


def blast_far():
    L, R = N.far_of("blast", 88401, ROD_D + 6.0)
    N.finish_at("blast_far", L, R, FAR_LEVEL, tail_fade=2.5, knee=0.5, peak=BLAST_PEAK)
    room("blast_far")


def room(name):
    """A blast (as written) eased down where the ground's thump (which lands earlier the further off the player is, at
    the volume rod.rs gives it there) would take the sum past CEIL."""
    x = N.decoded(name)
    gr = N.decoded("ground")
    if gr is None:
        print("  (ground not built yet: no room made for it)")
        return
    n = len(x)
    need = np.ones(n)
    for dist in (20, 40, 60, 100, 150, 200, 250, 300, 450, 600, 800, 1000, 1500):
        v = volumes(dist)
        own = v[name]
        if own <= 0:
            continue
        b = np.zeros((n, 2))
        k = -int(round(dist * (1 / SPEED - 1 / GROUND_V) * SR))
        lo, hi = max(0, k), min(n, k + len(gr))
        if hi > lo:
            b[lo:hi] += gr[lo - k:hi - k] * v["ground"]
        need = np.minimum(need, N.duck_need(x * own, [b], CEIL))
    g = N.smooth_gain(need)
    print(f"  room made: at most {20 * np.log10(g.min() + 1e-9):.1f} dB")
    old = P.TH
    P.TH = TH
    try:
        P.finish_abs(name, x[:, 0] * g, x[:, 1] * g, peak=BLAST_PEAK, tail_fade=0.05)
    finally:
        P.TH = old


# ==============================================================================================================  ground
def ground():
    d = 3.0
    n = int(SR * d)
    t = np.arange(n) / SR
    t1 = GROUND_LEAD
    u = np.maximum(t - t1, 0)
    on = t >= t1
    with PB.seeded(88501):
        th = soundlib.thump(n, t1, rng().uniform(44, 48), 22.0, 0.26, 6.0) * (1 - np.exp(-u / 0.015)) * on
        th += T.unit(band(white(d), 20, 100, 2)) * (1 - np.exp(-u / 0.01)) * np.exp(-u / 0.08) * on * 0.5
        rum = T.unit(band(white(d), 16, 48, 3)) * (1 - np.exp(-u / 0.08)) * np.exp(-u / 0.45) * on * 0.45
        rum *= np.exp(2.5 * PB.slow_random(n, 0.8, 4.0) / 8.686)
        chop = np.clip(1 + 0.9 * PB.slow_random(n, 9.0, 14.0), 0.05, None)
        sh = T.unit(band(white(d), 30, 110, 2)) * chop * (1 - np.exp(-u / 0.05)) * np.exp(-u / 0.45) * on * 0.3
        rat = T.unit(band(white(d), 900, 3200, 2)) * np.clip(PB.slow_random(n, 25.0, 70.0), 0, None) ** 2 * np.exp(-u / 0.3) * on * 0.012
        x = th + rum + sh
        lo = band(x, None, 70, 3)
        c = np.percentile(np.abs(lo), 99.5) * 0.4 + 1e-9
        x = x + band(np.tanh(lo / c) * c, 70, 260, 2) * 0.6
        L = x + rat; R = x * 0.98 + band(rat, 1000, None, 1) * 0.8
        L, R = PB.causal_lowcut(L, 15.0), PB.causal_lowcut(R, 15.0)
    N.finish_at("ground", L, R, -14.5, tail_fade=0.6, knee=0.55)


# ==============================================================================================================  rumble
def rumble():
    d = 20.0
    n = int(SR * d)
    t = np.arange(n) / SR
    with PB.seeded(88601):
        L = np.zeros(n); R = np.zeros(n)
        tr = rng().uniform(0.9, 1.3)                                 # (the first after the blast's own boom has let go)
        k = 0
        while tr < d - 5.0:
            far = min(tr / 14.0, 1.0)
            ln = rng().uniform(1.5, 3.0) + 2.0 * far
            m = int(ln * SR)
            s = np.arange(m) / SR
            env = (1 - np.exp(-s / (rng().uniform(0.1, 0.3) + 0.3 * far))) ** 2 * np.exp(-s / (rng().uniform(0.5, 1.0) + 0.8 * far))
            env /= env.max() + 1e-9
            hi = 280 - 170 * far
            lvl = 10 ** ((-20.0 - 14.0 * far + rng().uniform(-3, 2)) / 20)
            boom = T.unit(band(rng().standard_normal(m), 60, 450 - 250 * far, 2)) * np.exp(-s / 0.18) * (1 - np.exp(-s / 0.02)) * (1 - far) * 0.5
            clump = N.grains(ln, rng().uniform(8, 18), (0.04, 0.09, 0.2)) ** 0.7
            a_ = T.unit(band(rng().standard_normal(m), 25, hi, 2))
            corr = 0.9 - 0.5 * far
            p = rng().uniform(-0.55, 0.55)
            for ch, sgn in ((L, 1.0), (R, -1.0)):
                own = T.unit(band(rng().standard_normal(m), 25, hi, 2))
                x = (corr * a_ + np.sqrt(1 - corr ** 2) * own) * env * clump[:m] + boom
                P.put(ch, x * lvl * (1 + p * sgn), tr)
            tr += rng().gamma(1.7, 0.7 + 0.2 * k)
            k += 1
        rl, rr = PB.thunder_rolls(d, 0.0, count=12, length=14.0)
        g = 10 ** (-25.0 / 20) / (T.loudest((rl + rr) / 2) + 1e-9)
        L += rl * g; R += rr * g
        bed = T.unit(band(white(d), 18, 70, 3))
        bed2 = T.unit(band(white(d), 18, 70, 3))
        benv = 10 ** (np.interp(t, [0, 1.5, 5, 10, 15, 18, 20], [-22, -19, -23, -29, -37, -46, -60]) / 20)
        heave = np.exp(3.0 * PB.slow_random(n, 0.1, 0.9) / 8.686)
        L += (0.92 * bed + 0.39 * bed2) * benv * heave
        R += (0.92 * bed - 0.39 * bed2) * benv * heave
        f = T.fade(n, 1.8, 3.0)
        L, R = PB.causal_lowcut(L * f, 15.0), PB.causal_lowcut(R * f, 15.0)
        L, R = N.scaled(L, R, -17.0)
        a = -(RUMBLE_AFTER + BLAST_LEAD)
        L, R = N.duck_under(L, R, [[(bl, a, 1.0)] for bl in BLASTS])
    N.finish("rumble", L, R, tail_fade=2.0)


# ==============================================================================================================  debris
def debris():
    d = 6.5
    n = int(SR * d)
    with PB.seeded(88701):
        L = np.zeros(n); R = np.zeros(n)
        fL = np.zeros(n); fR = np.zeros(n)

        def place(x, t1, near, p):
            gl, gr = (1 - p) * 0.5 + 0.5 * near * (1 - p), (1 + p) * 0.5 + 0.5 * near * (1 + p)
            P.put(L, x * gl * near, t1); P.put(R, x * gr * near, t1)
            P.put(fL, x * (1 - near) * (1 - p * 0.5), t1); P.put(fR, x * (1 - near) * (1 + p * 0.5), t1)

        rate = lambda v: 14.0 * np.clip((v - 0.25) / 0.5, 0, 1) * np.exp(-max(v - 0.5, 0) / 1.8) + 0.8 * np.exp(-v / 4.0)
        for t1 in P.poisson_times(0.05, d - 1.2, rate):
            near = rng().random() ** 1.5
            kind = rng().random()
            if kind < 0.35:                                   # a clod: a dull thud and a spray of dirt
                size = min(rng().pareto(2.0) * 0.4 + 0.3, 2.2)
                m = int((0.2 + 0.3 * size) * SR)
                s = np.arange(m) / SR
                x = T.thud(m, size) * size * 0.12
                x += T.unit(band(rng().standard_normal(m), 600, 5000, 2)) * np.exp(-s / rng().uniform(0.012, 0.035)) * np.minimum(s / 0.002, 1) * 0.035 * (0.4 + 0.6 * near)
            elif kind < 0.72:                                 # a stone clacking, sometimes bouncing (more rock: it is the bedrock thrown up)
                size = rng().uniform(0.3, 1.0)
                m = int(0.35 * SR)
                x = P.modal_hit(m, rng().uniform(800, 2800) / (0.6 + size), [1.0, rng().uniform(1.45, 2.2), rng().uniform(2.4, 3.9), rng().uniform(4.1, 5.6)],
                                [rng().uniform(0.004, 0.02), rng().uniform(0.003, 0.01), 0.004, 0.002], [1.0, 0.7, 0.45, 0.25], 0.5)
                x = x / (np.abs(x).max() + 1e-9) * 0.08 * size + T.thud(m, 0.3 * size) * 0.03 * size
                if rng().random() < 0.35:
                    P.put(x, x * rng().uniform(0.25, 0.5), rng().uniform(0.07, 0.22))
            elif kind < 0.87:                                 # crumbling: a short run of grit and small stones
                m = int(rng().uniform(0.3, 0.8) * SR)
                s = np.arange(m) / SR
                gr = np.clip(N.grains(m / SR, 120.0, (0.003, 0.008)), 0, 6) ** 1.4
                x = T.unit(band(rng().standard_normal(m), 400, 4500, 2)) * gr[:m] * np.sin(np.pi * s / s[-1]) * 0.02
                x += T.unit(band(rng().standard_normal(m), 80, 400, 2)) * np.sin(np.pi * s / s[-1]) * 0.012
            else:                                             # a slab of rock landing heavily off
                m = int(1.0 * SR)
                x = T.thud(m, rng().uniform(1.8, 2.8)) * 0.2
                near = near * 0.5
            x = P.air(x, 1600 + 9000 * near)
            place(x, t1, 0.25 + 0.75 * near, rng().uniform(-0.85, 0.85))
        for t1 in P.poisson_times(0.1, d - 1.0, lambda v: 120.0 * np.clip(v / 0.4, 0, 1) * np.exp(-max(v - 0.4, 0) / 1.4)):
            a = min(rng().pareto(2.4) * 0.35 + 0.15, 2.0) * 0.02
            tk = band(PB.tick(int(0.006 * SR), 0, a, rng().uniform(0.0002, 0.0008), rng().choice([-1.0, 1.0])), 1200, 9000, 2)
            p = rng().uniform(-1, 1)
            P.put(L, tk * (1 - p * 0.8), t1); P.put(R, tk * (1 + p * 0.8), t1)
        for src, dst, sh in ((fL, L, 0), (fR, R, 1)):
            ir = T.outdoor_ir(1.8, 70 + sh, density=40.0, darken=(2200, 280), decay=0.7)
            m_ = n + len(ir)
            wet = np.fft.irfft(np.fft.rfft(src, m_) * np.fft.rfft(ir, m_), m_)[:n]
            dst += src * 0.55 + wet * 0.55
        f = T.fade(n, 0.002, 1.8)
        L, R = PB.causal_lowcut(L * f, 22.0), PB.causal_lowcut(R * f, 22.0)
        L, R = N.scaled(L, R, -20.0)

        # (debris plays only within DEBRIS_REACH, where the far blast is at most 0.45 of its volume)
        def lay(t1):
            return [[(bl, -(t1 + BLAST_LEAD), v), ("rumble", -(t1 - RUMBLE_AFTER), 1.0)] for bl, v in (("blast", 1.0), ("blast_far", 0.45))]
        t1, t2 = DEBRIS_AFTER
        L, R = N.duck_under(L, R, lay(t1), extra=[(0.9, 0.0, lay(t2))])
    N.finish("debris", L, R, tail_fade=0.5)


BUILD = {"hiss": hiss, "ground": ground, "blast": blast, "blast_far": blast_far, "rumble": rumble, "debris": debris}


# ===========================================================================================================  listening
def mixdown(dist, start=-RD_HIT):
    """The whole strike at `dist` blocks from strike time 0 (the impact RD_HIT s in): (stereo array, its start)."""
    vol = volumes(dist)
    ev = [e for e in schedule(dist) if vol[e[0]] > 0]
    clips = {nm: N.pitched(N.decoded(f), pitch) for nm, f, _, pitch in ev}
    end = max(at + len(clips[nm]) / SR for nm, _, at, _ in ev) + 0.5
    out = np.zeros((int((end - start) * SR), 2))
    for nm, _, at, _ in ev:
        k = int(round((at - start) * SR))
        c = clips[nm] * vol[nm]
        out[k:k + len(c)] += c[:len(out) - k]
    return out, start


def mp3(wav):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libmp3lame", "-b:a", "160k", str(wav.with_suffix(".mp3"))], check=True)


def listen(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for nm in NAMES:
        x = N.decoded(nm)
        p = out / f"rod_{nm}.wav"
        N.write_wav(p, x)
        lufs, tp, _ = N.measure(p)
        rows.append((p.name, len(x) / SR, 20 * np.log10(np.abs(x).max()), tp, lufs))
        if nm == "blast":
            mp3(p)
    tmp = out / "_check.wav"
    worst = -99.0
    for dist in (30, 60, 100, 150, 200, 250, 300, 450, 600, 800, 1000, 1500):
        x, _ = mixdown(dist)
        N.write_wav(tmp, x)
        _, tp, _ = N.measure(tmp)
        worst = max(worst, tp)
        print(f"  the whole strike {dist:4d} blocks off: sample peak {20 * np.log10(np.abs(x).max()):.2f} dBFS, true peak {tp:.2f} dBTP")
    tmp.unlink()
    print(f"  worst true peak over every distance: {worst:.2f} dBTP")
    for dist in (200, 600):
        x, start = mixdown(dist)
        p = out / f"rod_full_{dist}blocks.wav"
        N.write_wav(p, x)
        mp3(p)
        lufs, tp, _ = N.measure(p)
        rows.append((p.name + f"  (impact at {-start:.1f} s)", len(x) / SR, 20 * np.log10(np.abs(x).max()), tp, lufs))
    print(f"\n{'file':52s} {'len':>6s} {'peak':>7s} {'TP':>7s} {'LUFS':>7s}")
    for r in rows:
        print(f"{r[0]:52s} {r[1]:6.1f} {r[2]:7.2f} {r[3]:7.2f} {r[4]:7.1f}")
    share, lowf, octs = N.spectrum_report(N.decoded("blast"))
    print("\nblast, first 3 s: " + share)
    print(f"  strongest low frequency {lowf:.1f} Hz; octaves (dB) " + " ".join(f"{int(fc)}:{v:.1f}" for fc, v in zip(N.OCT, octs)))
    b = N.decoded("blast").mean(axis=1)
    print(f"  loudest 400 ms {20 * np.log10(T.loudest(b)):.1f} dB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=NAMES)
    ap.add_argument("--out", default=str(ROOT / "orbital-sounds"))
    ap.add_argument("--listen", help="also write listening WAVs and MP3s and the full-strike mixdowns here")
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
