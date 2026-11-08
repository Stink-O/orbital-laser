#!/usr/bin/env python3
"""The Supervolcano's satellite: how it rights itself as it comes down, flown by a control loop and written out as the
table the pass reads (mod/shaders/volcano.wgsl's VC_SAT_TAB, read by `vc_sat_att`).

    python3 tools/vc_sat_motion.py            # print the table (paste it over VC_SAT_TAB)
    python3 tools/vc_sat_motion.py --list     # and each tenth of a second: what it is held to, its tilt, rate and pushes

Why a simulation: a tilt drawn as damped sines reads as robotic. A real vehicle (a Falcon 9 booster in its landing
burn, a lander on its RCS) is a heavy body turned only by what its actuators push, through lag, with things pushing
back, so its corrections come uneven in size and time. So, a rigid body (two tilt axes) pushed by
  * its thrusters while it falls (to VC_IGN): whole pulses of a tenth of a second, bang-bang, to stop its drift and
    swing it slowly round towards the attitude the burn will want;
  * its four gimballed jets in the braking burn: a loop holding its turn to what closes on its attitude (leaning into
    the braking, then back onto the vent), its command a tenth of a second late (the jets swing first, the body
    follows), as strong as the burn; against it the ignition's kick, the thrust a little off its middle, noise and the
    propellant sloshing;
  * its thrusters again as the burn dies: trimming it onto the vent in pulses sized in quarters of a full one, with a
    dead band, while the arrays unrolling push it; then its wheels, quietly, so it is still at the lock.
The pushes change only every tenth of a second, so between the knots (tilt and rate) the tilt is near enough a
parabola: a cubic Hermite gives it back, and a slot's push is its change in rate (what the pass draws the jets and the
puffs from). Keep the times in step with volcano.wgsl's VC_IGN, VC_ARRIVE, VC_WING_OUT, VC_LOCK and `vc_sat_thr`.
"""
import argparse
import math

import numpy as np

# ---- the beats and the path (volcano.wgsl) ----
VC_IGN, VC_ARRIVE, VC_WING_OUT, VC_LOCK = 1.3, 3.4, 3.2, 4.0
DT, SLOT = 1.0 / 600.0, 0.1
LEAN = np.array([-0.07, 0.13])                 # (into its braking, about the pass's two axes: radians)
WHEELS = 3.8                                   # (the pass draws no puffs from here: volcano.wgsl's `vc_opening`)
KA, KW, W = 2.0, 5.0, 0.2                      # (the loops: attitude to rate, rate to push; the fastest it turns)
A_RCS = 0.8                                    # (a full pulse of its thrusters, rad/s^2)


def throttle(t):
    """How hard its jets burn (volcano.wgsl's `vc_sat_thr`): lit at VC_IGN, as hard as it brakes, out at VC_ARRIVE."""
    if not VC_IGN <= t < VC_ARRIVE:
        return 0.0
    x = (t - VC_IGN) / (VC_ARRIVE - VC_IGN)
    ss = lambda a, b, v: (lambda u: u * u * (3 - 2 * u))(min(max((v - a) / (b - a), 0.0), 1.0))
    return ss(VC_IGN, VC_IGN + 0.2, t) * (0.3 + 2.15 * x * x * (1 - x ** 3)) * (1 - ss(VC_ARRIVE - 0.25, VC_ARRIVE, t))


def target(t):
    """What the flight computer holds it to: leaning into its braking (LEAN, about the pass's two axes, `vc_sat_m`)
    while it burns hard, swung back onto the vent (0) as the burn dies."""
    ss = lambda a, b, v: (lambda u: u * u * (3 - 2 * u))(min(max((v - a) / (b - a), 0.0), 1.0))
    return LEAN * ss(VC_IGN - 0.6, VC_IGN + 0.4, t) * (1 - ss(VC_ARRIVE - 1.3, VC_ARRIVE - 0.5, t))


def simulate(seed=7):
    rng = np.random.default_rng(seed)
    ts = np.arange(0.0, VC_LOCK - DT / 2, DT)
    th = np.array([0.40, -0.22])         # (it comes in well off, ~26 degrees, still turning further off)
    om = np.array([0.07, -0.05])
    slosh, slosh_v, noise = np.zeros(2), np.zeros(2), np.zeros(2)
    cmd = np.zeros(2)
    knots, pushes = [], []
    gim, rcs = np.zeros(2), np.zeros(2)
    pre = target(VC_IGN + 0.4)
    for i, t in enumerate(ts):
        thr = throttle(t)
        if i % round(SLOT / DT) == 0:
            knots.append((t, th.copy(), om.copy()))
            tgt = target(t)
            tgt_v = (target(t + 0.05) - tgt) / 0.05
            gim, rcs = np.zeros(2), np.zeros(2)
            if VC_IGN <= t and thr > 0.2:
                # the jets: a rate held to what closes on the attitude (no faster than W), a slot late (the jets swing
                # first, the body follows), as strong as the burn
                gim = cmd
                w = np.clip(KA * (tgt - th), -W, W) + tgt_v
                cmd = np.clip(KW * (w - om), -1.4 * thr, 1.4 * thr)
            elif 0.45 <= t < VC_IGN:
                # falling: swing round towards what the burn will want, at a gentle rate, on whole pulses
                e = np.clip(0.8 * (pre - th), -0.14, 0.14) - om
                rcs = np.where(np.abs(e) > 0.03, np.sign(e) * A_RCS, 0.0)
            elif t >= VC_IGN:
                # trimming onto the vent: pulses in quarters of a full one, nothing inside a dead band
                u = np.clip(KW * (np.clip(KA * (tgt - th), -W, W) - om), -A_RCS, A_RCS)
                u = np.round(u / (A_RCS / 4)) * (A_RCS / 4)
                rcs = np.where(np.abs(tgt - th) + 0.3 * np.abs(om) > 0.005, u, 0.0)
                cmd = np.zeros(2)
            # (from WHEELS its reaction wheels hold it, quietly: the last of the tilt taken out, still by the lock)
            if t > WHEELS - 1e-6:
                rcs = 6.0 * (np.clip(2.5 * -th, -0.06, 0.06) - om)
            pushes.append((gim.copy(), rcs.copy(), thr))
        # what else pushes it: the ignition's kick, the thrust a little off its middle, the propellant sloshing,
        # the jets' noise; the arrays unrolling (one ahead of the other)
        dist = np.zeros(2)
        if thr > 0.0:
            if t < VC_IGN + 0.18:
                dist += np.array([0.5, -0.35])
            dist += np.array([0.10, -0.06]) * thr
            noise += (rng.normal(0, 1, 2) - noise) * DT * 9.0
            dist += noise * thr * 0.45
        slosh_a = -(2 * math.pi * 0.8) ** 2 * slosh - 2 * 0.12 * (2 * math.pi * 0.8) * slosh_v - 0.8 * gim
        slosh_v += slosh_a * DT
        slosh += slosh_v * DT
        dist += -0.35 * slosh
        if VC_WING_OUT + 0.1 <= t < VC_WING_OUT + 0.45:
            dist += np.array([0.05, -0.12])
        om = om + (gim + rcs + dist) * DT
        th = th + om * DT
    knots.append((VC_LOCK, th.copy(), np.zeros(2)))
    return knots, pushes


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    knots, pushes = simulate()
    rows = [f"vec4f({round(th[0] * 1000)}, {round(th[1] * 1000)}, {round(om[0] * 1000)}, {round(om[1] * 1000)})" for _, th, om in knots]
    print(f"const VC_SAT_TAB = array<vec4f, {len(rows)}>(")
    for i in range(0, len(rows), 4):
        print("    " + ", ".join(rows[i:i + 4]) + ("," if i + 4 < len(rows) else ""))
    print(");")
    if a.list:
        for (t, th, om), (g, r, thr) in zip(knots, pushes):
            h = np.degrees(target(t))
            print(f"# {t:4.1f} held {h[0]:5.1f} {h[1]:5.1f}  tilt {math.degrees(th[0]):6.1f} {math.degrees(th[1]):6.1f}"
                  f"  rate {om[0]:6.3f} {om[1]:6.3f}  jets {g[0]:5.2f} {g[1]:5.2f}  puffs {r[0]:5.2f} {r[1]:5.2f}  throttle {thr:4.2f}")


if __name__ == "__main__":
    main()
