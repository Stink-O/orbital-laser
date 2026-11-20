"""The Colossi's statue pose, worked out as the pass works it out, and a statue's blocks moved into it.

The pass (mod/shaders/colossi.wgsl) ends each giant crouched where it struck, in a pose read from its record (words 48-58,
`STATUE_POSE` in tools/colossi_assets.py): `rig` below is `cl_rig` for that still pose (no hammer in its hands, its feet
in the stance its stamps left them, the pelvis sunk back onto its legs where they would not reach), line for line, so the
blocks `pose_blocks` moves lie under the giant drawn over them. Keep the two in step: cl_rig, cl_leg, cl_arm, cl_about,
cl_arc, cl_rx/ry/rz, cl_rest_pole and the stance in cl_pose.
"""
import numpy as np

# the stance the stamps leave the feet in (cl_pose: o.lf, o.rf with s1 = s2 = 1)
LF = np.array([2.5, 0.0, 3.4])
RF = np.array([-2.9, 0.0, -2.4])
# (and the kneel: where the kneeling foot goes from its ankle at rest, kx ky kz, and which foot kneels, side: 0 the right, 1
# the left; the other stays where its stamp put it)
# (the foot that does not kneel is put here from its ankle at rest, the right's (the left's x the other way): a little in
# front and in under the body, so its shin stands upright over it and its knee is up in front, the thigh rising to it from
# the hip; the pass's CL_FRONT)
FRONT = np.array([1.0, 0.0, 5.3])
POSE_KEYS = ["dy", "dz", "px", "ppitch", "pyaw", "proll", "spitch", "syaw", "sroll", "hpitch", "hyaw", "kx", "ky", "kz", "side"]


def feet(p):
    """The two feet's places from their ankles at rest (right, left) in pose p: the stance, one swapped for the kneel."""
    k = np.array([p["kx"], p["ky"], p["kz"]])
    return (k, FRONT * np.array([-1.0, 1.0, 1.0])) if p["side"] < 0.5 else (FRONT, k)


def _cols(*c):
    return np.column_stack(c).astype(np.float64)


def rx(a):
    c, s = np.cos(a), np.sin(a)
    return _cols([1, 0, 0], [0, c, s], [0, -s, c])


def ry(a):
    c, s = np.cos(a), np.sin(a)
    return _cols([c, 0, -s], [0, 1, 0], [s, 0, c])


def rz(a):
    c, s = np.cos(a), np.sin(a)
    return _cols([c, s, 0], [-s, c, 0], [0, 0, 1])


def unit(v):
    return v / np.linalg.norm(v)


def arc(a, b):
    c = a @ b
    v = np.cross(a, b)
    k = 1.0 / max(1.0 + c, 1.0e-3)
    vx = _cols([0, v[2], -v[1]], [-v[2], 0, v[0]], [v[1], -v[0], 0])
    return np.eye(3) + vx + (vx @ vx) * k


class Xf:
    def __init__(self, r, t):
        self.r, self.t = r, t

    def pos(self, p):
        return self.r @ p + self.t


def about(pr, c, rl):
    return Xf(pr.r @ rl, pr.r @ (c - rl @ c) + pr.t)


def frame(ax, n):
    nn = unit(n - ax * (n @ ax))
    return np.column_stack([ax, nn, np.cross(ax, nn)])


def leg(pel, h0, k0, a0, goal, kn=0.0, up=0.0, sx=1.0):
    hw = pel.pos(h0)
    l1, l2 = np.linalg.norm(k0 - h0), np.linalg.norm(a0 - k0)
    e0 = goal - hw
    d = np.clip(np.linalg.norm(e0), 0.35 * (l1 + l2), l1 + l2)
    e = unit(e0)
    a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
    h = np.sqrt(max(l1 * l1 - a * a, 0.0))
    fwd = pel.r @ np.array([0.0, 0.0, 1.0]) + np.array([0.0, up, 0.0])
    so = pel.r @ np.array([sx, 0.0, 0.0])
    es = e @ so
    l0 = fwd @ so - es * (fwd @ e)
    fwd = fwd + so * (max(-l0, 0.0) / max(1.0 - es * es, 0.2))
    pv = unit(fwd - e * (fwd @ e))
    kw = hw + e * a + pv * h
    aw = hw + e * d
    n = np.cross(e, pv)
    n0 = np.cross(unit(a0 - h0), np.array([0.0, 0.0, 1.0]))
    rt = frame(unit(kw - hw), n) @ frame(unit(k0 - h0), n0).T
    rs = frame(unit(aw - kw), n) @ frame(unit(a0 - k0), n0).T
    s0 = unit(a0 - k0)
    rf = frame(unit(s0 + (unit(aw - kw) - s0) * (0.35 + 0.65 * kn)), n) @ frame(s0, n0).T @ rx(1.2 * kn)
    return Xf(rt, hw - rt @ h0), Xf(rs, kw - rs @ k0), Xf(rf, aw - rf @ a0)


def rest_pole(s0, e0, w0):
    d = unit(w0 - s0)
    v = e0 - s0
    return unit(v - d * (v @ d) + np.array([0.0, 0.0, -1.0e-3]))


def arm(xt, s0, e0, w0, goal, pole):
    """cl_arm with no hammer to hold (w = 0: no twist)."""
    sw = xt.pos(s0)
    l1, l2 = np.linalg.norm(e0 - s0), np.linalg.norm(w0 - e0)
    e = goal - sw
    d = np.clip(np.linalg.norm(e), 0.3 * (l1 + l2), 0.999 * (l1 + l2))
    dr = unit(e)
    a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
    h = np.sqrt(max(l1 * l1 - a * a, 0.0))
    pv = unit(pole - dr * (pole @ dr))
    kw = sw + dr * a + pv * h
    ww = sw + dr * d
    f = unit(ww - kw)
    ru = arc(unit(e0 - s0), unit(kw - sw))
    rf = arc(unit(w0 - e0), f)
    return Xf(ru, sw - ru @ s0), Xf(rf, kw - rf @ e0)


def rig(j, pose):
    """The 13 pieces' transforms (mesh units, 50 a giant) for joints `j` (15 x 3: pelvis, spine, neck, r_shoulder, r_elbow,
    r_wrist, l_shoulder, l_elbow, l_wrist, r_hip, r_knee, r_ankle, l_hip, l_knee, l_ankle) in the still pose `pose`."""
    p = pose
    xp = about(Xf(np.eye(3), np.zeros(3)), j[0], rz(p["proll"]) @ rx(p["ppitch"]) @ ry(p["pyaw"]))
    xp.t = xp.t + np.array([p["px"], -p["dy"], p["dz"]])
    xt = about(xp, j[1], rz(p["sroll"]) @ rx(p["spitch"]) @ ry(p["syaw"]))
    rf_, lf_ = feet(p)
    for _ in range(3):
        drop = 0.0
        for h0, k0, a0, f in ((j[9], j[10], j[11], rf_), (j[12], j[13], j[14], lf_)):
            a = a0 + f
            drop = max(drop, np.linalg.norm(a - xp.pos(h0)) - 0.995 * (np.linalg.norm(k0 - h0) + np.linalg.norm(a0 - k0)))
        dd = 1.1 * max(drop, 0.0)
        xp.t = xp.t - np.array([0.0, dd, 0.0])
        xt.t = xt.t - np.array([0.0, dd, 0.0])
    xh = about(xt, j[2], rx(p["hpitch"]) @ ry(p["hyaw"]))
    fl0 = j[8] + unit(j[8] - j[7]) * 2.5
    ru, rfa = arm(xt, j[3], j[4], j[5], xt.pos(j[5]), xt.r @ rest_pole(j[3], j[4], j[5]))
    lu, lfa = arm(xt, j[6], j[7], fl0, xt.pos(fl0), xt.r @ rest_pole(j[6], j[7], fl0))
    rth, rsh, rft = leg(xp, j[9], j[10], j[11], j[11] + rf_, 1.0 if p["side"] < 0.5 else 0.0, 0.0 if p["side"] < 0.5 else 1.0, -1.0)
    lth, lsh, lft = leg(xp, j[12], j[13], j[14], j[14] + lf_, 0.0 if p["side"] < 0.5 else 1.0, 1.0 if p["side"] < 0.5 else 0.0, 1.0)
    return [xp, xt, xh, ru, rfa, lu, lfa, rth, rsh, lth, lsh, rft, lft]


def pose_blocks(a, bone, xfs, back, fwd):
    """Blocks `a` (Y, Z, X palette indices, rest pose) whose bones are `bone` (same shape, -1 for air) moved by each bone's
    transform: every block sampled 2 x 2 x 2 and splatted, so a turned shell a block thick keeps no holes. Returns the posed
    blocks (Y, Z, X) and the shift (x, y, z) of their grid from the rest one's."""
    y, z, x = np.nonzero(a)
    ids = a[y, z, x]
    bn = bone[y, z, x]
    sub = np.array([[dx, dy, dz] for dx in (0.36, 0.64) for dy in (0.36, 0.64) for dz in (0.36, 0.64)])
    pts, vals = [], []
    base = np.stack([x, y, z], 1).astype(np.float64)
    for k, xf in enumerate(xfs):
        m = bn == k
        if not m.any():
            continue
        p = (base[m][:, None, :] + sub[None]).reshape(-1, 3)
        u = back(p)
        q = fwd(u @ xf.r.T + xf.t)
        pts.append(np.floor(q).astype(np.int64))
        vals.append(np.repeat(ids[m], len(sub)))
    pts = np.concatenate(pts)
    vals = np.concatenate(vals)
    lo = pts.min(0)
    hi = pts.max(0)
    X, Y, Z = (hi - lo + 1).tolist()
    out = np.zeros((Y, Z, X), np.uint8)
    q = pts - lo
    out[q[:, 1], q[:, 2], q[:, 0]] = vals
    return out, lo
