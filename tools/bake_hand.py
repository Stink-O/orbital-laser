#!/usr/bin/env python3
"""Bake the Sky Breaks' hand and arm from a sculpted mesh into small distance grids, one a bone.

    python3 -I tools/bake_hand.py ~/.cache/orbital-handmesh/src [--look DIR]

reads MakeHuman's base mesh (base.obj, default.mhskel, default_weights.mhw: CC0), takes its right arm, subdivides it
twice (Catmull-Clark), fits it to the skeleton `hd_set` poses in mod/shaders/skybreak.wgsl (its knuckles, its fingers'
lengths), cuts it into 18 rigid pieces at the joints and writes

    mod/assets/sb_hand.bin              the grids, 10 bits a sample, three samples a word (little-endian u32 words)
    mod/shaders/skybreak.wgsl           the block between `// [bake table]` and `// [end bake table]`

Run offline (numpy only; `-I` because the mesh folder is data, not code). Nothing here runs at build time.
The pieces: 0-11 the fingers' bones (finger * 3 + bone, index to little, as `hd_fb`), 12-14 the thumb's, 15 the palm
(in the hand's frame), 16 the forearm (in the wrist's frame), 17 the upper arm (in the elbow's).
"""
import json, os, struct, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARM = ['upperarm01.R', 'upperarm02.R', 'lowerarm01.R', 'lowerarm02.R', 'wrist.R'] + \
      ['metacarpal%d.R' % i for i in range(1, 5)] + \
      ['finger%d-%d.R' % (f, k) for f in range(1, 6) for k in range(1, 4)]

# ---- the skeleton the shader poses (hd_knuckle, hd_digit_dims, hd_set in skybreak.wgsl: keep in step) ----
KN = np.array([[10.9, 0.9, 7.0], [3.5, 1.6, 7.7], [-3.9, 1.1, 4.8], [-11.0, -0.3, 1.6]])
DM = np.array([[29.5, 3.8, 0.07], [33.1, 3.9, 0.012], [31.7, 3.65, -0.05], [25.2, 3.25, -0.14]])   # length, width, splay
LENS = np.array([0.48, 0.29, 0.23])
TP = np.array([8.6, -3.4, -16.5])            # the thumb's root
TL = np.array([15.6, 10.8, 8.6])             # its bones' lengths
THUMB_SLEEVE = (7.6, 7.2, 5.6, 5.4, 5.3)     # (the sleeve round the thumb that parts it from the palm: its radius along it)
TUP = np.array([0.8, 0.55, -0.2])            # its back's way, open
WRIST = np.array([0.0, 0.0, -24.0])
THUMB_BALL = 0.62                            # (how far along the thumb's first bone the palm goes on, round its root)
PALM_MOUND = (0.45, 0.55, 0.4, 0.3)          # (how high a knuckle's mound stands on the bend of the palm's end, index to little)
FINGER_MOUND = (0.5, 0.3, 0.2)               # (and on the back end of a finger's three bones)
MOUND_W = 3.4                                # (how wide those mounds are, across the finger)
SADDLE = 0.7                                 # (how far the bend of a knuckle sinks between two fingers: the saddles of the row)
SADDLE_W = 2.9
WEB_FLOOR = -2.4                             # (the palm keeps the back of the web by the thumb down to here: thick, not a shell)
LO, HI = -5.0, 7.0                           # the range a sample holds (units), in 10 bits


# ---- the mesh ----
def load(src):
    V = []; F = []; G = []; g = ''
    for line in open(os.path.join(src, 'base.obj')):
        if line.startswith('v '):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('g '):
            g = line.split()[1]
        elif line.startswith('f '):
            F.append([int(t.split('/')[0]) - 1 for t in line.split()[1:]]); G.append(g)
    V = np.array(V); F = np.array(F); G = np.array(G)
    sk = json.load(open(os.path.join(src, 'default.mhskel')))
    J = {n: V[np.array(ix)].mean(0) for n, ix in sk['joints'].items()}
    B = {n: (J[b['head']], J[b['tail']]) for n, b in sk['bones'].items()}
    W = json.load(open(os.path.join(src, 'default_weights.mhw')))['weights']
    return V, F, G, B, W


def arm_faces(V, F, G, W):
    w = np.zeros(len(V))
    for b in ARM:
        for i, x in W.get(b, []):
            w[i] += x
    return F[(G == 'body') & (w[F].min(1) > 0.5)]


def catmull_clark(V, F, extra=None):
    """One level; `extra` (per-vertex values, e.g. weights) is carried along by plain averaging."""
    nv = len(V); nf = len(F)
    fp = V[F].mean(1)
    e = np.stack([F, np.roll(F, -1, 1)], 2).reshape(-1, 2)
    ue, inv, cnt = np.unique(np.sort(e, 1), axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1); ne = len(ue)
    fsum = np.zeros((ne, 3)); np.add.at(fsum, inv, np.repeat(fp, 4, 0))
    mid = V[ue].mean(1)
    bnd = cnt == 1
    ep = np.where(bnd[:, None], mid, (V[ue].sum(1) + fsum) / 4.0)
    n = np.zeros(nv); np.add.at(n, F.reshape(-1), 1)
    Fs = np.zeros((nv, 3)); np.add.at(Fs, F.reshape(-1), np.repeat(fp, 4, 0))
    val = np.zeros(nv); np.add.at(val, ue.reshape(-1), 1)
    Rs = np.zeros((nv, 3)); np.add.at(Rs, ue[:, 0], mid); np.add.at(Rs, ue[:, 1], mid)
    vp = (Fs / n[:, None] + 2 * Rs / val[:, None] + (val[:, None] - 3) * V) / val[:, None]
    vb = np.zeros(nv, bool); vb[ue[bnd].reshape(-1)] = True
    bs = np.zeros((nv, 3)); be = ue[bnd]
    np.add.at(bs, be[:, 0], V[be[:, 1]]); np.add.at(bs, be[:, 1], V[be[:, 0]])
    vp[vb] = 0.75 * V[vb] + 0.125 * bs[vb]
    NV = np.concatenate([vp, ep, fp])
    ei = inv.reshape(nf, 4) + nv
    fi = np.arange(nf) + nv + ne
    NF = np.stack([np.stack([F[:, i], ei[:, i], fi, ei[:, (i - 1) % 4]], 1) for i in range(4)], 1).reshape(-1, 4)
    if extra is None:
        return NV, NF
    return NV, NF, np.concatenate([extra, extra[ue].mean(1), extra[F].mean(1)])


# ---- how far a point is from the mesh, less than none inside it ----
def closest_bary(p, a, b, c):
    """Barycentric weights of the point of triangle abc nearest p (Ericson); arrays broadcast on the last axis."""
    ab = b - a; ac = c - a; ap = p - a
    d1 = (ab * ap).sum(-1); d2 = (ac * ap).sum(-1)
    bp = p - b; d3 = (ab * bp).sum(-1); d4 = (ac * bp).sum(-1)
    cp = p - c; d5 = (ab * cp).sum(-1); d6 = (ac * cp).sum(-1)
    va = d3 * d6 - d5 * d4; vb = d5 * d2 - d1 * d6; vc = d1 * d4 - d3 * d2
    den = va + vb + vc
    den = np.where(np.abs(den) < 1e-30, 1e-30, den)
    v = vb / den; w = vc / den
    def div(x, y):
        return x / np.where(np.abs(y) < 1e-30, 1e-30, y)
    m = (vc <= 0) & (d1 >= 0) & (d3 <= 0); v = np.where(m, div(d1, d1 - d3), v); w = np.where(m, 0.0, w)
    m = (vb <= 0) & (d2 >= 0) & (d6 <= 0); w = np.where(m, div(d2, d2 - d6), w); v = np.where(m, 0.0, v)
    m = (va <= 0) & (d4 - d3 >= 0) & (d5 - d6 >= 0)
    t = div(d4 - d3, (d4 - d3) + (d5 - d6)); w = np.where(m, t, w); v = np.where(m, 1.0 - t, v)
    m = (d1 <= 0) & (d2 <= 0); v = np.where(m, 0.0, v); w = np.where(m, 0.0, w)
    m = (d3 >= 0) & (d4 <= d3); v = np.where(m, 1.0, v); w = np.where(m, 0.0, w)
    m = (d6 >= 0) & (d5 <= d6); v = np.where(m, 0.0, v); w = np.where(m, 1.0, w)
    return v, w


class Sdf:
    """The signed distance to a smooth triangle mesh: the nearest vertex (brute force), then the exact nearest point
    on the triangles round it; inside or out by the mesh's own (interpolated) normal there."""

    def __init__(self, V, T):
        self.V = V; self.T = T
        fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
        N = np.zeros_like(V)
        for k in range(3):
            np.add.at(N, T[:, k], fn)
        self.N = N / (np.linalg.norm(N, axis=1)[:, None] + 1e-20)
        cnt = np.zeros(len(V), int); np.add.at(cnt, T.reshape(-1), 1)
        K = cnt.max()
        vt = np.zeros((len(V), K), int); fill = np.zeros(len(V), int)
        order = np.argsort(T.reshape(-1), kind='stable')
        tv = T.reshape(-1)[order]; tt = (np.arange(T.size) // 3)[order]
        start = np.concatenate([[0], np.cumsum(cnt)[:-1]])
        slot = np.arange(T.size) - start[tv]
        vt[tv, slot] = tt
        first = vt[:, :1]
        pad = np.arange(K)[None, :] >= cnt[:, None]
        self.vt = np.where(pad, first, vt)

    def near(self, lo, hi, margin=10.0):
        """The same, of only the mesh within `margin` of a box: quicker for a piece's grid."""
        keep = np.all((self.V[self.T] > lo - margin) & (self.V[self.T] < hi + margin), axis=2).any(1)
        T = self.T[keep]
        used = np.unique(T)
        m = -np.ones(len(self.V), int); m[used] = np.arange(len(used))
        s = Sdf(self.V[used], m[T]); s.N = self.N[used]
        return s

    def __call__(self, P, chunk=4096):
        P = np.asarray(P, np.float64).reshape(-1, 3)
        out = np.empty(len(P))
        V32 = self.V.astype(np.float32); vv = (V32 * V32).sum(1)
        A = self.V[self.T[:, 0]]; B = self.V[self.T[:, 1]]; C = self.V[self.T[:, 2]]
        for s in range(0, len(P), chunk):
            p = P[s:s + chunk]
            i = (vv[None, :] - 2.0 * (p.astype(np.float32) @ V32.T)).argmin(1)
            tri = self.vt[i]
            a = A[tri]; b = B[tri]; c = C[tri]
            v, w = closest_bary(p[:, None, :], a, b, c)
            cp = a + (b - a) * v[..., None] + (c - a) * w[..., None]
            dd = ((cp - p[:, None, :]) ** 2).sum(2)
            j = dd.argmin(1); r = np.arange(len(p))
            t = self.T[tri[r, j]]
            vj = v[r, j][:, None]; wj = w[r, j][:, None]
            n = self.N[t[:, 0]] * (1 - vj - wj) + self.N[t[:, 1]] * vj + self.N[t[:, 2]] * wj
            sg = np.where(((p - cp[r, j]) * n).sum(1) < 0, -1.0, 1.0)
            out[s:s + chunk] = sg * np.sqrt(dd[r, j])
        return out


def norm(v):
    return v / np.linalg.norm(v)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# (the arm's ends at the elbow: each one's middle off its bone's line and its radius there, in its own frame)
ELBOW_F = (2.0, -0.5, 13.0)
ELBOW_U = (1.2, -1.4, 14.0)


def smax(a, b, r):
    """max with its corner rounded to radius r."""
    u = np.maximum(a + r, 0); v = np.maximum(b + r, 0)
    return np.where((a > -r) & (b > -r), np.sqrt(u * u + v * v) - r, np.maximum(a, b))


# ---- the mesh fitted to the shader's skeleton: everything after this is in the hand's own frame and units ----
def walk(pts, dists):
    """Points at the given distances along a polyline from its start."""
    out = []
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1); cum = np.concatenate([[0], np.cumsum(seg)])
    for d in dists:
        k = min(np.searchsorted(cum, d, side='right') - 1, len(seg) - 1)
        out.append(pts[k] + (pts[k + 1] - pts[k]) * (d - cum[k]) / seg[k])
    return np.array(out)


def umeyama(X, Y):
    """The scale, turn and shift taking X nearest Y."""
    mx = X.mean(0); my = Y.mean(0)
    H = (Y - my).T @ (X - mx) / len(X)
    U, D, Vt = np.linalg.svd(H)
    S = np.eye(3); S[2, 2] = np.sign(np.linalg.det(U) * np.linalg.det(Vt))
    R = U @ S @ Vt
    s = (D * np.diag(S)).sum() / ((X - mx) ** 2).sum() * len(X)
    return s, R, my - s * R @ mx


class Fit:
    def __init__(self, src):
        V, F, G, B, W = load(src)
        Fa = arm_faces(V, F, G, W)
        used = np.unique(Fa); m = -np.ones(len(V), int); m[used] = np.arange(len(used))
        lab = np.zeros((len(V), 5))
        for f in range(1, 6):
            for i, x in W.get('finger%d-3.R' % f, []):
                lab[i, f - 1] += x
        V1, F1, l1 = catmull_clark(V[used], m[Fa], lab[used])
        V2, F2, l2 = catmull_clark(V1, F1, l1)
        T = np.concatenate([F2[:, [0, 1, 2]], F2[:, [0, 2, 3]]])
        wr = B['wrist.R'][0]; mi = B['metacarpal2.R'][1]
        az = norm(mi - wr); ax = B['metacarpal1.R'][1] - B['metacarpal4.R'][1]
        ax = norm(ax - az * (ax @ az)); ay = np.cross(az, ax)
        A = 36.0 * np.stack([ax, ay, az]); t = WRIST.copy()
        marks = {'wrist': wr, 'elbow': B['lowerarm01.R'][0], 'shoulder': B['upperarm01.R'][0]}
        for f in range(1, 6):
            marks['d%d' % f] = np.array([B['finger%d-1.R' % f][0], B['finger%d-2.R' % f][0], B['finger%d-3.R' % f][0], B['finger%d-3.R' % f][1]])
        tgt = np.concatenate([[WRIST], KN, [TP]])
        for it in range(4):
            L = lambda v: (v - wr) @ A.T + t
            J = self.joints(L, marks, L(V2), l2)
            src_pts = np.concatenate([[L(wr)], J[1:, 0], [J[0, 0]]])
            s, R, sh = umeyama(src_pts, tgt)
            A = s * R @ A; t = s * R @ t + sh
        L = lambda v: (v - wr) @ A.T + t
        self.scale = np.linalg.norm(A[0])
        J = self.joints(L, marks, L(V2), l2)
        ctl = np.concatenate([[L(wr)], J[1:, 0], [J[0, 0]]])
        self.residual = np.linalg.norm(tgt - ctl, axis=1)
        sig = 9.0
        K = np.exp(-((ctl[:, None] - ctl[None]) ** 2).sum(2) / (2 * sig * sig))
        wts = np.linalg.solve(K, tgt - ctl)
        warp = lambda p: p + np.exp(-((p[..., None, :] - ctl) ** 2).sum(-1) / (2 * sig * sig)) @ wts
        self.V = warp(L(V2)); self.T = T; self.lab = l2
        self.J = warp(J)                       # [digit 0 thumb .. 4 little][joint 0..3] (3 the tip)
        self.elbow = warp(L(marks['elbow'])); self.shoulder = warp(L(marks['shoulder']))
        self.mcp_marks = warp(L(np.array([marks['d%d' % f][0] for f in range(2, 6)])))
        self.sdf = Sdf(self.V, T)
        # (the thumb's back: the way its last bone is thinnest)
        tv = self.V[l2[:, 0] > 0.5]
        f = norm(self.J[0, 3] - self.J[0, 2])
        q = tv - tv.mean(0); q = q - np.outer(q @ f, f)
        ev, evec = np.linalg.eigh(q.T @ q)
        up = evec[:, 1]                         # (0 is along f, none; 1 the thin way)
        self.thumb_up = up if up @ TUP > 0 else -up

    @staticmethod
    def joints(L, marks, VL, lab):
        J = np.zeros((5, 4, 3))
        for d in range(5):
            M = L(marks['d%d' % (d + 1)])
            dr = norm(M[3] - M[2])
            tip = M[2] + dr * ((VL[lab[:, d] > 0.5] - M[2]) @ dr).max()
            back = M[0] + 40.0 * norm(M[0] - M[1])
            ln = TL[::-1] if d == 0 else LENS[::-1] * DM[d - 1, 0]
            J[d, 3] = tip
            J[d, 2::-1] = walk(np.array([tip, M[2], M[1], M[0], back]), np.cumsum(ln))
        return J


# ---- the pieces: each a field over its bone's own frame (x across, y to the back of the hand, z along) ----
def seg_dist(P, a, b):
    ab = b - a
    h = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
    return np.linalg.norm(P - a - np.outer(h, ab), axis=1)


class Pieces:
    def __init__(self, fit):
        self.fit = fit; J = fit.J
        ay = np.array([0.0, 1.0, 0.0])
        self.fr = {}
        for i in range(4):
            for s in range(3):
                a, b = J[i + 1, s], J[i + 1, s + 1]
                f = norm(b - a); u = norm(ay - f * (ay @ f))
                self.fr[i * 3 + s] = (a, np.cross(u, f), u, f, np.linalg.norm(b - a), LENS[s] * DM[i, 0])
        for k in range(3):
            a, b = J[0, k], J[0, k + 1]
            f = norm(b - a); u = norm(fit.thumb_up - f * (fit.thumb_up @ f))
            self.fr[12 + k] = (a, np.cross(u, f), u, f, np.linalg.norm(b - a), TL[k])
        # (between two fingers: a plane through their web, along the way between them and the hand's back)
        self.web = []
        for i in range(3):
            wp = 0.5 * (fit.mcp_marks[i] + fit.mcp_marks[i + 1])
            b = norm(self.fr[i * 3][3] + self.fr[i * 3 + 3][3])
            n = norm(np.cross(ay, b))
            self.web.append((wp, n if n @ (J[i + 1, 1] - wp) > 0 else -n, b))
        # (the palm's ends at the knuckles: the shader's fingers' frames, open and unspread)
        self.kf = []
        for i in range(4):
            f = np.array([np.sin(DM[i, 2]), 0.0, np.cos(DM[i, 2])])
            self.kf.append((KN[i], np.cross(ay, f), ay, f))
        # (the forearm's frame at the wrist, the upper arm's at the elbow: as hd_set makes them)
        ad = norm(fit.elbow - WRIST); x0 = np.array([1.0, 0.0, 0.0]); x0 = norm(x0 - ad * (x0 @ ad)); y0 = np.cross(x0, ad)
        self.fore = (WRIST, x0, y0, ad, np.linalg.norm(fit.elbow - WRIST))
        sd = norm(fit.shoulder - fit.elbow)
        rot = lambda v: v - (ad + sd) * ((ad + sd) @ v) / (1.0 + ad @ sd) + 2.0 * sd * (ad @ v)
        self.upper = (fit.elbow, rot(x0), rot(y0), sd)
        self.D = fit.sdf

    # -- the whole mesh, cut down to one finger's column / without the thumb / to the thumb's own parts --
    def column(self, i, P):
        c = np.full(len(P), -1e9)
        for j, sg in ((i - 1, 1.0), (i, -1.0)):
            if 0 <= j < 3:
                wp, n, b = self.web[j]
                c = np.maximum(c, sg * ((P - wp) @ n) - 0.8 * smoothstep(1.0, -1.0, (P - wp) @ b))
        a, r, u, f, _, _ = self.fr[i * 3]
        x = (P - a) @ r
        # (the outer two no wider than themselves, and round at the knuckle: what is past that there is the palm's
        # edge, the palm's own)
        if i == 0 or i == 3:
            y = (P - a) @ u
            c = np.maximum(c, np.hypot(np.maximum(x if i == 0 else -x, 0.0), 0.75 * y) - DM[i, 1] - 0.9)
        return c

    def d_finger(self, i, D, P):
        return smax(D(P), self.column(i, P), 0.7)

    def thumb_sleeve(self, P, first=0, last=4, back=0.4):
        """How far outside a sleeve round the thumb, from 40% along its first bone to past its tip: fat round the ball
        of the thumb and the web, close round the thumb itself from just past its second joint. The palm is what is
        outside it, the thumb's pieces what is inside (`first`, `last`: a part of its length only)."""
        J = self.fit.J[0]
        pts = [J[0] + back * (J[1] - J[0]), J[1], J[1] + 2.5 * norm(J[2] - J[1]), J[2], J[3] + 3.0 * norm(J[3] - J[2])]
        rad = THUMB_SLEEVE
        d = np.full(len(P), 1e9)
        for k in range(first, last):
            ab = pts[k + 1] - pts[k]
            h = np.clip(((P - pts[k]) @ ab) / (ab @ ab), 0.0, 1.0)
            d = np.minimum(d, np.linalg.norm(P - pts[k] - np.outer(h, ab), axis=1) - (rad[k] + (rad[k + 1] - rad[k]) * h))
        return d

    def thumb_cut(self, P):
        """Where the palm ends and the thumb goes on alone: inside the sleeve round the thumb, further than 62% of its
        first bone from its root (a ball round the root: the thumb swings and turns about there, so the palm's end is
        the one shape that stays under the thumb's first piece as it does). So the palm keeps the ball of the thumb,
        and the thumb's first piece holds it too: at rest one surface, and as the thumb swings in no gap opens behind
        it."""
        J = self.fit.J[0]
        return np.maximum(self.thumb_sleeve(P, back=0.3), THUMB_BALL * np.linalg.norm(J[1] - J[0]) - np.linalg.norm(P - J[0], axis=1))

    def d_palm(self, D, P):
        # (over the thumb's sleeve the palm keeps the back of the web down to WEB_FLOOR: without it what is left there
        # is a shell of skin, a fin once the thumb has swung away into a fist)
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        # (all of it from the wrist up, and out to the hand's edge: where the palm's share of the back ended, across the
        # back of the hand and along it, the two pieces' rounded ends left a groove, a square line on the skin)
        floor = WEB_FLOOR + 14.0 * (1.0 - smoothstep(4.0, 0.0, z)) + 14.0 * smoothstep(17.5, 19.5, x)
        return smax(D(P), -smax(self.thumb_cut(P), y - floor, 1.5), 2.0)

    def d_thumb(self, k, D, P):
        J = self.fit.J[0]
        if k == 0:
            return smax(D(P), np.minimum(seg_dist(P, J[0], J[1]) - 7.2, self.thumb_sleeve(P, 0, 2) - 0.8), 1.5)
        return smax(D(P), self.thumb_sleeve(P, 2, 4) - 0.6, 0.7)

    # -- a piece's field at its grid's points --
    def hinged(self, dfun, frame, G, back, front, bump, saddle=0.0):
        """`dfun` in the bone's frame, closed past its ends by its own section there swept round the joint's axis:
        the back of the section round the back of the joint, the pad's under it; `bump` a low mound on the bend."""
        a0, r, u, f, lm, ls = frame
        x, y, z = G[:, 0], G[:, 1], G[:, 2]
        zc = z.copy()
        if back:
            zc = np.maximum(zc, 0.0)
        if front:
            zc = np.minimum(zc, ls)
        a = z - zc
        world = lambda x, y, z: a0 + np.outer(x, r) + np.outer(y, u) + np.outer(z * lm / ls, f)
        d = np.empty(len(G))
        cap = a != 0
        d[~cap] = dfun(world(x[~cap], y[~cap], z[~cap]))
        if cap.any():
            rho = np.hypot(a[cap], y[cap]); th = np.arctan2(np.abs(a[cap]), y[cap])
            # (the back end keeps its back's height further round: bent a right angle, what is behind the joint is the
            # back of the hand, and a cap any fatter there stands out of it as a ball)
            t = smoothstep(np.where(a[cap] < 0, 0.62, 0.5) * np.pi, 0.97 * np.pi, th)
            dd = dfun(world(x[cap], rho, zc[cap])); dp = dfun(world(x[cap], -rho, zc[cap]))
            d[cap] = dd * (1 - t) + dp * t - bump * np.sin(2.0 * np.clip(th, 0, 0.5 * np.pi)) * np.exp(-(x[cap] / MOUND_W) ** 2) \
                + np.where(a[cap] < 0, saddle, 0.0) * smoothstep(0.0, 0.6, th) * (1.0 - smoothstep(0.6 * np.pi, 0.9 * np.pi, th)) * (1.0 - np.exp(-(x[cap] / SADDLE_W) ** 2))
        return d

    def domed(self, dfun, world, G, zlo, zhi, about=None):
        """`dfun` closed past z = zlo and z = zhi by its section there swept round the joint's middle (a dome)."""
        x, y, z = G[:, 0], G[:, 1], G[:, 2]
        zc = np.clip(z, -1e9 if zlo is None else zlo, 1e9 if zhi is None else zhi)
        a = z - zc
        # (round the middle of the section itself, which need not be on the bone's line; or round `about`)
        mid = {}
        for e in (zlo, zhi):
            if e is not None and about is not None:
                mid[e] = about
            elif e is not None:
                gx, gy = np.meshgrid(np.linspace(x.min(), x.max(), 48), np.linspace(y.min(), y.max(), 48), indexing='ij')
                gx = gx.ravel(); gy = gy.ravel()
                ins = dfun(world(gx, gy, np.full(len(gx), float(e)))) < 0
                mid[e] = (gx[ins].mean(), gy[ins].mean()) if ins.any() else (0.0, 0.0)
        mx = np.zeros(len(G)); my = np.zeros(len(G))
        for e, (cx, cy) in mid.items():
            m = (a != 0) & (zc == e)
            mx[m] = cx; my[m] = cy
        rxy = np.hypot(x - mx, y - my)
        rho = np.where(a != 0, np.hypot(rxy, a), rxy)
        on = rxy > 1e-6                      # (on the axis itself any way out will do)
        cx = np.where(on, (x - mx) / np.maximum(rxy, 1e-6), 1.0); cy = np.where(on, (y - my) / np.maximum(rxy, 1e-6), 0.0)
        return dfun(world(mx + cx * rho, my + cy * rho, zc))

    def finger(self, pid, G):
        i, s = divmod(pid, 3)
        D = self.near(pid, G)
        d = self.hinged(lambda P: self.d_finger(i, D, P), self.fr[pid], G, True, s < 2, FINGER_MOUND[s], SADDLE if s == 0 else 0.0)
        if s == 0:
            # (a finger's root no deeper round its knuckle than a finger is: under it at the knuckle the mesh is the
            # palm's pad, and swept round the joint that is a ball out of the hand's edge)
            y, z = G[:, 1], G[:, 2]
            d = smax(d, np.hypot(np.minimum(z, 0.0), np.minimum(y, 0.0)) - 1.3 * DM[i, 1] - 2.5 * smoothstep(0.0, 3.0, z), 0.8)
            # (nor fatter along it: the mesh's finger carries the palm's pad and edge a third of the way up it, and bent
            # that stands out of the fist as a block; the palm's own end holds the pad)
            d = smax(d, np.hypot(G[:, 0], y) - DM[i, 1] - 1.1, 0.8)
            # (and behind its knuckle no more than a ball round it: swept round the joint its broad root is a barrel, and
            # with the finger turned or sunk as it shuts, the barrel's end stands out of the hand's edge as a claw)
            d = smax(d, np.sqrt(G[:, 0] ** 2 + y ** 2 + np.minimum(z, 0.0) ** 2) - DM[i, 1] - 0.5, 0.6)
        return d

    def thumb(self, pid, G):
        k = pid - 12
        a0, r, u, f, lm, ls = self.fr[pid]
        D = self.near(pid, G)
        world = lambda x, y, z: a0 + np.outer(x, r) + np.outer(y, u) + np.outer(z * lm / ls, f)
        return self.domed(lambda P: self.d_thumb(k, D, P), world, G, None if k == 0 else 0.0, ls if k < 2 else None)

    def palm(self, pid, G):
        D = self.near(pid, G)
        dfun = lambda P: self.d_palm(D, P)
        base = dfun(G)                       # (past the wrist it runs on as the arm: the shader fades it into the forearm)
        s = [smoothstep(-1.2, 1.2, (G - wp) @ n) for wp, n, b in self.web]
        w = [s[0], (1 - s[0]) * s[1], (1 - s[0]) * (1 - s[1]) * s[2], (1 - s[0]) * (1 - s[1]) * (1 - s[2])]
        out = np.zeros(len(G))
        for i in range(4):
            kn, r, u, f = self.kf[i]
            v = G - kn
            x, y, a = v @ r, v @ u, v @ f
            ci = base.copy()
            m = (w[i] > 1e-4) & (a > 0)
            if m.any():
                rho = np.hypot(a[m], y[m]); th = np.arctan2(a[m], y[m])
                t = smoothstep(0.5 * np.pi, 0.95 * np.pi, th)
                at = lambda yy: kn + np.outer(x[m], r) + np.outer(yy, u)
                ci[m] = dfun(at(rho)) * (1 - t) + dfun(at(-rho)) * t \
                    - PALM_MOUND[i] * np.sin(2.0 * np.clip(th, 0, 0.5 * np.pi)) * np.exp(-(x[m] / MOUND_W) ** 2) \
                    + SADDLE * smoothstep(0.0, 0.6, th) * (1.0 - smoothstep(0.6 * np.pi, 0.9 * np.pi, th)) * (1.0 - np.exp(-(x[m] / SADDLE_W) ** 2))
            out += w[i] * ci
        return out

    def forearm(self, pid, G):
        w0, x0, y0, ad, lm = self.fore
        D = self.near(pid, G)
        world = lambda x, y, z: w0 + np.outer(x, x0) + np.outer(y, y0) - np.outer(z * lm / 96.0, ad)
        # (at the elbow the mesh's forearm carries the start of its upper arm, bent as the mesh's arm is; turned to
        # any other bend that stands out of the elbow as a knob. So near the elbow it is no fatter than a forearm is
        # just before it, and its end is a ball round that middle: two such ends make an elbow at any bend)
        cx, cy, rj = ELBOW_F
        own = lambda P: smax(D(world(P[:, 0], P[:, 1], P[:, 2])), np.hypot(P[:, 0] - cx, P[:, 1] - cy) - rj - 0.25 * np.maximum(P[:, 2] + 84.0, 0.0), 1.5)
        here = lambda x, y, z: np.stack([x, y, z], -1)
        return self.domed(own, here, G, -96.0, None, (cx, cy))   # (open at the wrist: the shader holds z there)

    def upperarm(self, pid, G):
        e, x1, y1, sd = self.upper
        D = self.near(pid, G)
        world = lambda x, y, z: e + np.outer(x, x1) + np.outer(y, y1) - np.outer(z, sd)
        cx, cy, rj = ELBOW_U                 # (as the forearm's end: the mesh's upper arm carries its forearm's start)
        own = lambda P: smax(D(world(P[:, 0], P[:, 1], P[:, 2])), np.hypot(P[:, 0] - cx, P[:, 1] - cy) - rj - 0.12 * np.maximum(-P[:, 2] - 12.0, 0.0), 1.5)
        here = lambda x, y, z: np.stack([x, y, z], -1)
        return self.domed(own, here, G, None, 0.0, (cx, cy))

    def near(self, pid, G):
        """The mesh near this piece's grid only."""
        lo, hi = G.min(0), G.max(0)
        c = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        if pid < 15:
            a0, r, u, f, lm, ls = self.fr[pid]
            W = a0 + np.outer(c[:, 0], r) + np.outer(c[:, 1], u) + np.outer(c[:, 2] * lm / ls, f)
        elif pid == 15:
            W = c
        elif pid == 16:
            w0, x0, y0, ad, lm = self.fore
            W = w0 + np.outer(c[:, 0], x0) + np.outer(c[:, 1], y0) - np.outer(c[:, 2] * lm / 96.0, ad)
        else:
            e, x1, y1, sd = self.upper
            W = e + np.outer(c[:, 0], x1) + np.outer(c[:, 1], y1) - np.outer(c[:, 2], sd)
        return self.D.near(W.min(0), W.max(0), 12.0)


# ---- the grids ----
def specs():
    """piece, its roomy box (lo, hi), its samples' spacing, how far out of its surface its grid must reach."""
    out = []
    for i in range(4):
        for s in range(3):
            ls = LENS[s] * DM[i, 0]
            if s == 0:
                out.append((i * 3, (-7.5, -12.0, -9.0), (7.5, 8.0, ls + 7.0), (0.6,) * 3, 0.8))
            else:
                out.append((i * 3 + s, (-6.0, -6.5, -6.5), (6.0, 6.5, ls + (6.5 if s == 1 else 3.5)), ((0.55,) * 3, (0.45,) * 3)[s - 1], 0.8))
    out.append((12, (-12.0, -12.0, -12.0), (12.0, 12.0, TL[0] + 10.0), (0.75,) * 3, 1.7))
    out.append((13, (-9.5, -9.5, -9.0), (9.5, 9.5, TL[1] + 8.0), (0.6,) * 3, 0.8))
    out.append((14, (-7.5, -7.5, -8.0), (7.5, 7.5, TL[2] + 4.5), (0.5,) * 3, 0.8))
    out.append((15, (-20.0, -19.0, -37.2), (26.0, 10.0, 20.0), (0.9,) * 3, 1.7))
    out.append((16, (-26.0, -26.0, -122.0), (31.0, 26.0, 8.0), (1.6, 1.6, 2.4), 1.5))
    out.append((17, (-28.0, -28.0, -60.0), (28.0, 28.0, 27.0), (2.0, 2.0, 3.0), 1.5))
    return out


def build(pc, spec):
    pid, lo, hi, h, pad = spec
    lo = np.array(lo); hi = np.array(hi); h = np.array(h)
    n = np.ceil((hi - lo) / h).astype(int) + 1
    ax = [lo[k] + h[k] * np.arange(n[k]) for k in range(3)]
    G = np.stack(np.meshgrid(*ax, indexing='ij'), -1).reshape(-1, 3)
    fn = pc.finger if pid < 12 else pc.thumb if pid < 15 else (pc.palm, pc.forearm, pc.upperarm)[pid - 15]
    d = fn(pid, G).reshape(n)
    near = np.argwhere(d < pad + 0.3)
    i0 = np.maximum(near.min(0) - 1, 0); i1 = np.minimum(near.max(0) + 2, n)
    open_lo = pid in (15, 17)                # (the palm and the upper arm run on out of their grids' low ends, the forearm
    open_hi = pid == 16                      # out of its high one: the shader does not read them there)
    for k in range(3):
        if i0[k] == 0 and not (open_lo and k == 2):
            print('  piece %d: its surface reaches the roomy box at the low end of axis %d' % (pid, k))
        if i1[k] == n[k] and not (open_hi and k == 2):
            print('  piece %d: its surface reaches the roomy box at the high end of axis %d' % (pid, k))
    d = d[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]]
    faces = [d[0], d[-1], d[:, 0], d[:, -1]] + ([] if open_hi else [d[:, :, -1]]) + ([] if open_lo else [d[:, :, 0]])
    mrg = max(min(f.min() for f in faces) - 0.05, 0.0)
    # (how far its surface reaches: its box, and how far from its bone's line: for the shader's bounds)
    bmin = lo + i0 * h
    S = bmin + np.argwhere(d < 0.3) * h
    zlen = LENS[pid % 3] * DM[pid // 3, 0] if pid < 12 else TL[pid - 12] if pid < 15 else 0.0
    zc = np.clip(S[:, 2], -96.0 if pid == 16 else -1e9 if pid == 17 else 0.0, zlen)
    reach = np.sqrt(S[:, 0] ** 2 + S[:, 1] ** 2 + (S[:, 2] - zc) ** 2).max() + 0.3
    return dict(pid=pid, d=d, bmin=bmin, h=h, mrg=mrg, slo=S.min(0) - 0.3, shi=S.max(0) + 0.3, reach=reach)


def pack(g):
    d = g['d']
    nx, ny, nz = d.shape
    q = np.round((np.clip(d, LO, HI) - LO) / (HI - LO) * 1023.0).astype(np.uint32)
    nxw = (nx + 2) // 3
    w = np.zeros((nz, ny, nxw), np.uint32)
    for ix in range(nx):
        w[:, :, ix // 3] |= q[ix].T << np.uint32(10 * (ix % 3))
    return w.reshape(-1)


def main():
    src = sys.argv[1]
    fit = Fit(src)
    print('fit: %.2f units to a mesh unit; knuckles, wrist, thumb root off by %s before the warp' % (fit.scale, np.round(fit.residual, 2)))
    pc = Pieces(fit)
    if os.environ.get('BAKE_INFO'):
        # (how far the mesh's own bones are from the shader's open hand's: the turn each piece is drawn with there)
        rest = {}
        for i in range(4):
            f = np.array([np.sin(DM[i, 2]), 0.0, np.cos(DM[i, 2])])
            for s_ in range(3):
                rest[i * 3 + s_] = (f, np.array([0.0, 1.0, 0.0]))
        for k, f in enumerate(([0.7, -0.33, 0.63], [0.54, -0.28, 0.78], [0.5, -0.24, 0.83])):
            f = norm(np.array(f)); rest[12 + k] = (f, norm(TUP - f * (TUP @ f)))
        for pid in range(15):
            a, r, u, f, lm, ls = pc.fr[pid]
            sf, su = rest[pid]
            print('bone %2d: mesh length %.2f (shader %.2f), its way %.1f deg from the open hand\'s, its back %.1f deg' % (
                pid, lm, ls, np.degrees(np.arccos(np.clip(f @ sf, -1, 1))), np.degrees(np.arccos(np.clip(u @ su, -1, 1)))))
        print('thumb joints', np.round(fit.J[0], 2).tolist())
        return
    only = [int(x) for x in os.environ.get('BAKE_ONLY', '').split(',') if x]
    grids = []
    for sp in specs():
        if only and sp[0] not in only:
            continue
        g = build(pc, sp)
        grids.append(g)
        print('piece %2d: %s samples, from %s, spacing %s, margin %.2f, reach %.2f, %d words' % (g['pid'], g['d'].shape, np.round(g['bmin'], 2), g['h'], g['mrg'], g['reach'], len(pack(g))))
    if os.environ.get('BAKE_NPZ'):
        np.savez(os.environ['BAKE_NPZ'], **{'d%d' % g['pid']: g['d'] for g in grids})
    if only:
        return
    words = [np.zeros(4, np.uint32)]
    off = 4
    cases = []
    # (the pass is close to the game's 256 KiB: numbers without their trailing zeros)
    num = lambda v: ('%.4f' % v).rstrip('0').rstrip('.') + ('.0' if float('%.4f' % v) == int(v) else '')
    for g in grids:
        w = pack(g); n = g['d'].shape; b = g['bmin']; iv = 1.0 / g['h']
        cases.append('        case %d { return hb_grid(p, %du, vec3<i32>(%d, %d, %d), vec3<f32>(%s, %s, %s), vec3<f32>(%.6f, %.6f, %.6f), %.3f); }'
                     % (g['pid'], off, n[0], n[1], n[2], num(b[0]), num(b[1]), num(b[2]), iv[0], iv[1], iv[2], g['mrg']))
        words.append(w); off += len(w)
    words = np.concatenate(words)
    words[:4] = [0x53424844, 1, len(grids), len(words)]
    os.makedirs(os.path.join(ROOT, 'mod/assets'), exist_ok=True)
    open(os.path.join(ROOT, 'mod/assets/sb_hand.bin'), 'wb').write(words.astype('<u4').tobytes())
    up = grids[-1]
    block = ['// [bake table] (written by tools/bake_hand.py from the sculpted mesh: run it again rather than edit this)',
             'const HB_WORDS: u32 = %du;' % len(words),
             'const HB_LO: f32 = %.1f;' % LO,
             'const HB_STEP: f32 = %.8f;' % ((HI - LO) / 1023.0),
             'const HB_UZ: f32 = %.3f; // (the upper arm\'s grid ends here: past it the arm runs on as it is there)' % (up['bmin'][2] + up['h'][2]),
             'const HB_FZ: f32 = %.3f; // (and the forearm\'s, past the wrist)' % (grids[16]['bmin'][2] + grids[16]['h'][2] * (grids[16]['d'].shape[2] - 2)),
             'const HB_RAD: array<f32, 15> = array<f32, 15>(%s); // (how far each bone\'s piece reaches from its line)' % ', '.join('%.2f' % g['reach'] for g in grids[:15]),
             'const HB_PLO: vec3<f32> = vec3<f32>(%.2f, %.2f, %.2f); // (the box round the palm)' % tuple(grids[15]['slo']),
             'const HB_PHI: vec3<f32> = vec3<f32>(%.2f, %.2f, %.2f);' % tuple(grids[15]['shi']),
             'const HB_RF: f32 = %.2f; // (how far the forearm reaches from its line, and the upper arm)' % grids[16]['reach'],
             'const HB_RU: f32 = %.2f;' % grids[17]['reach'],
             'fn hb_piece(id: i32, p: vec3<f32>) -> f32 {', '    switch id {'] + cases + \
            ['        default { return 1.0e9; }', '    }', '}', '// [end bake table]']
    path = os.path.join(ROOT, 'mod/shaders/skybreak.wgsl')
    s = open(path).read()
    a = s.find('// [bake table]'); b = s.find('// [end bake table]')
    if a < 0 or b < 0:
        print('no // [bake table] block in skybreak.wgsl: table not written'); print('\n'.join(block))
    else:
        open(path, 'w').write(s[:a] + '\n'.join(block) + s[b + len('// [end bake table]'):])
    print('%d words in all (%d bytes)' % (len(words), len(words) * 4))


if __name__ == '__main__':
    main()
