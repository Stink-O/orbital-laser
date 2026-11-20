"""The Colossi's skeleton: where each giant design's joints are, and how its display mesh is cut into rigid pieces.

A giant is a stone golem of 13 rigid pieces (BONES below) chained from the pelvis: the pass (shaders/colossi.wgsl) moves the
pieces about their joints, so a giant is animated as a whole body (legs planted by two-bone IK, pelvis, spine, head, two
arms with elbows, the hammer held in both fists: it rides the right one and the left arm reaches for its handle). Every joint of a design comes from ONE table: JOINTS_A / JOINTS_B here, in the
coordinates of the display mesh as the converter exports it (--height 50: units of 1/50 of the height), or, when
colossi.json has `"rig": {"joints": {name: [x, y, z], ...}}` for a giant, from there as fractions of the model's box (the same
fractions as `fist`), so Tripo's auto-rig joint positions can replace the measured ones without a code change. A joint that
colossi.json leaves out keeps the measured one. Names: JOINT_NAMES. `r_wrist` is the closed right fist (where the hammer is
held; colossi.json's `fist` still wins for it).

The cut: one plane a joint (`_plane`: level at the waist, the knees and the ankles, tilted under the jaw at the neck, down
through the armpit at a shoulder, a mitre at an elbow, the briefs' line at a hip). The loop the plane cuts round the joint is
split clean (`Cut.cut`: every triangle it crosses becomes three, the two sides sharing no vertex), so the mesh falls into 13
closed pieces with no overlap and no torn edge; both sides of every cut are capped (`Cut.cap`: dark stone at the rim to a
glowing core at the middle) and the joint gets a ball (an analytic sphere in the pass: the largest circle that fits in the
cut, hidden at rest) so an opened joint shows the giant's core, never a hole. A joint's pivot is that circle's middle.
"""
import numpy as np

JOINT_NAMES = ["pelvis", "spine", "neck", "r_shoulder", "r_elbow", "r_wrist", "l_shoulder", "l_elbow", "l_wrist",
               "r_hip", "r_knee", "r_ankle", "l_hip", "l_knee", "l_ankle"]
# (only for the cut, not the pose) the head's top and the toes
EXTRA_NAMES = ["head_top", "r_toe", "l_toe"]

# the bones: name, parent, pivot joint, capsule from joint to joint, radius (in 50-unit mesh units), a ball radius (0 none), and the
# horizontal planes that bound it ((joint, offset) low, high: the head is above the neck, the thighs below the hips, ...)
# (the order is the pass's: keep BONES in colossi.wgsl in step: parents and pivots)
BONES = [
    # name,    parent, pivot,        a,           b,           radius, ball, low plane,          high plane
    ("pelvis",   -1, "pelvis",     "pelvis",    "spine",     7.7, 0.0, ("r_hip", -1.0),   None),
    ("torso",     0, "spine",      "spine",     "neck",      9.0, 0.0, None,              ("neck", 0.0)),
    ("head",      1, "neck",       "neck",      "head_top",  5.0, 0.0, ("neck", 0.0),     None),
    ("r_arm",     1, "r_shoulder", "r_shoulder", "r_elbow",  3.4, 3.0, None,              None),
    ("r_fore",    3, "r_elbow",    "r_elbow",   "r_wrist",   3.4, 2.9, None,              None),
    ("l_arm",     1, "l_shoulder", "l_shoulder", "l_elbow",  3.4, 3.0, None,              None),
    ("l_fore",    5, "l_elbow",    "l_elbow",   "l_wrist",   3.3, 2.9, None,              None),
    ("r_thigh",   0, "r_hip",      "r_hip",     "r_knee",    4.6, 0.0, ("r_knee", 0.0),   ("r_hip", 1.0)),
    ("r_shin",    7, "r_knee",     "r_knee",    "r_ankle",   4.2, 0.0, ("r_ankle", 0.0),  ("r_knee", 0.0)),
    ("l_thigh",   0, "l_hip",      "l_hip",     "l_knee",    4.6, 0.0, ("l_knee", 0.0),   ("l_hip", 1.0)),
    ("l_shin",    9, "l_knee",     "l_knee",    "l_ankle",   4.2, 0.0, ("l_ankle", 0.0),  ("l_knee", 0.0)),
    ("r_foot",    8, "r_ankle",    "r_ankle",   "r_toe",     3.2, 0.0, None,              ("r_ankle", 0.0)),
    ("l_foot",   10, "l_ankle",    "l_ankle",   "l_toe",     3.2, 0.0, None,              ("l_ankle", 0.0)),
]
NBONES = len(BONES)
BALL = 0.9           # a joint's ball: this share of the least distance from the cut's middle to its rim (hidden at rest)

JOINTS_A = {
    "pelvis": (14.2, 24.5, 6.2), "spine": (14.2, 30.0, 6.3), "neck": (14.2, 45.5, 7.2), "head_top": (14.2, 50.0, 7.5),
    "r_shoulder": (5.6, 40.5, 6.0), "r_elbow": (2.6, 33.2, 6.6), "r_wrist": (2.76, 31.95, 16.8),
    "l_shoulder": (22.8, 40.5, 6.0), "l_elbow": (26.0, 31.0, 6.4), "l_wrist": (24.5, 23.5, 6.8),
    "r_hip": (9.9, 22.5, 6.6), "r_knee": (8.8, 14.7, 6.7), "r_ankle": (8.2, 5.2, 6.2), "r_toe": (8.2, 1.0, 12.5),
    "l_hip": (18.6, 22.5, 6.6), "l_knee": (19.4, 14.7, 6.7), "l_ankle": (19.8, 5.2, 6.2), "l_toe": (20.0, 1.0, 12.5),
}
JOINTS_B = {
    "pelvis": (11.8, 27.5, 4.8), "spine": (11.8, 30.0, 4.8), "neck": (11.8, 45.5, 5.5), "head_top": (11.8, 50.0, 5.5),
    "r_shoulder": (5.0, 40.5, 4.2), "r_elbow": (2.5, 33.2, 4.9), "r_wrist": (1.8, 33.1, 14.4),
    "l_shoulder": (18.6, 40.5, 4.3), "l_elbow": (20.2, 31.0, 4.6), "l_wrist": (19.8, 24.0, 5.0),
    "r_hip": (7.6, 25.5, 4.8), "r_knee": (7.2, 16.0, 5.2), "r_ankle": (6.9, 5.0, 4.8), "r_toe": (7.0, 1.0, 10.0),
    "l_hip": (16.0, 25.5, 4.8), "l_knee": (16.0, 16.0, 5.2), "l_ankle": (16.5, 5.0, 4.8), "l_toe": (16.5, 1.0, 10.0),
}
DEFAULT = [JOINTS_A, JOINTS_B]


def joints(design, cfg_giant, lo, ext):
    """The design's joints as a dict of numpy points in mesh units: the measured table, with any joint colossi.json's
    `rig.joints` gives (fractions of the model's box) and the `fist` (the right wrist) put over it."""
    j = {k: np.array(v, float) for k, v in DEFAULT[design].items()}
    for k, v in ((cfg_giant.get("rig") or {}).get("joints") or {}).items():
        j[k] = np.array(v, float) * ext + lo
    if "fist" in cfg_giant:
        j["r_wrist"] = np.array(cfg_giant["fist"], float) * ext + lo
    return j


# ---- the cut: a plane a joint, the loop round the joint cut clean, both sides capped ---------------------------------

def _plane(j, name, side_x, tune):
    """The cut of the joint `name`: a point on its plane and the plane's unit normal, pointing to the child's side."""
    t = tune.get(name, {})
    y, x = np.array([0.0, 1.0, 0.0]), np.array([1.0, 0.0, 0.0])

    def unit(v):
        return v / np.linalg.norm(v)

    def lean(n, deg, towards):
        a = np.radians(deg)
        return unit(np.cos(a) * n + np.sin(a) * towards)

    if name == "neck":
        # (tilted under the jaw: low at the front, under the chin, rising to the joint at the back, so the jaw goes with the
        # head; a level cut at the joint left the jaw's lower half on the torso, standing still as the head turned.
        # `drop`: how far under the joint the plane passes through it, `tilt` its slope in degrees)
        z = np.array([0.0, 0.0, 1.0])
        p, n = j[name] + np.array([0.0, -t.get("drop", 1.4), 0.0]), lean(y, t.get("tilt", 20.0), z)
    elif name == "spine":
        p, n = j[name], y
    elif name.endswith("shoulder"):
        # (a plane down through the armpit, leaning in over the shoulder: the deltoid goes with the arm)
        p, n = j[name] + np.array([-side_x * t.get("in", 1.8), t.get("up", -3.5), 0.0]), lean(side_x * x, t.get("lean", 9.0), y)
    elif name.endswith("elbow"):
        # (a mitre: the plane that halves the bend)
        s, w = name[0] + "_shoulder", name[0] + "_wrist"
        p, n = j[name], unit(unit(j[name] - j[s]) + unit(j[w] - j[name]))
    elif name.endswith("hip"):
        # (the briefs' line: under the crotch, rising to the hip's outside)
        p, n = j[name] + np.array([0.0, t.get("up", -1.0), 0.0]), lean(-y, t.get("lean", 30.0), side_x * x)
    elif name.endswith("knee"):
        p, n = j[name], -y
    else:
        p, n = j[name], -y
    if "n" in t:
        n = unit(np.array(t["n"], float))
    if "p" in t:
        p = np.array(t["p"], float)
    return p, n


def _loops(pos, idx, s):
    """The loops a plane (signed distances `s` of the vertices) cuts the surface in: for each, its triangles and where
    its middle is."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    side = s > 0
    ts = side[idx]
    cross = np.flatnonzero(ts.any(1) & ~ts.all(1))
    if len(cross) == 0:
        return []
    tc = idx[cross]
    eu, ev = tc, tc[:, [1, 2, 0]]
    m = side[eu] != side[ev]
    key = np.minimum(eu, ev) * len(pos) + np.maximum(eu, ev)
    tr = np.repeat(np.arange(len(cross)), 3).reshape(-1, 3)[m]
    uk, first, inv = np.unique(key[m], return_index=True, return_inverse=True)
    n = len(cross)
    g = coo_matrix((np.ones(len(tr)), (tr, n + inv.ravel())), shape=(n + len(uk), n + len(uk)))
    nc, lab = connected_components(g, directed=False)
    u, v = eu[m][first], ev[m][first]
    w = (s[u] / (s[u] - s[v]))[:, None]
    pts = pos[u] + (pos[v] - pos[u]) * w
    out = []
    for c in range(nc):
        tri = cross[lab[:n] == c]
        if len(tri):
            out.append((tri, pts[lab[n:] == c].mean(0)))
    return out


def _rim(pos, segs, n):
    """The cut's rim as one loop of vertices in order, from its segments (pairs of vertices). A clean surface gives one
    ring, every vertex with two neighbours. A model's small faults (a vertex on another triangle's edge, a sliver, a fin
    inside the body) give gaps closed by a vertex at the same place, spurs and chords: vertices at one place count as
    one, spurs are trimmed, and of what is left the outline (the outer face, traced in the plane) is the rim."""
    key, rep, at = {}, [], []
    for v in {v for e in segs for v in e}:
        k = tuple(np.rint(pos[v] * 2000.0).astype(np.int64))
        if k not in key:
            key[k] = len(rep)
            rep.append(v)
        at.append((v, key[k]))
    node = dict(at)
    nb = {}
    for u, v in segs:
        a, b = node[u], node[v]
        if a != b:
            nb.setdefault(a, set()).add(b)
            nb.setdefault(b, set()).add(a)
    spur = [a for a, v in nb.items() if len(v) < 2]
    while spur:
        a = spur.pop()
        if a not in nb:
            continue
        for b in nb.pop(a):
            nb[b].discard(a)
            if len(nb[b]) < 2:
                spur.append(b)
    assert nb, "a cut's rim has no loop in it"
    ax = np.cross(n, [0.0, 0.0, 1.0] if abs(n[2]) < 0.9 else [1.0, 0.0, 0.0])
    ax /= np.linalg.norm(ax)
    ay = np.cross(n, ax)
    q = {a: np.array([pos[rep[a]] @ ax, pos[rep[a]] @ ay]) for a in nb}
    if all(len(v) == 2 for v in nb.values()):
        loops, left = [], set(nb)
        while left:
            a = next(iter(left))
            loop, prev = [a], None
            while True:
                u = loop[-1]
                w = next((x for x in nb[u] if x != prev), prev)
                if w == loop[0]:
                    break
                loop.append(w)
                prev = u
            left -= set(loop)
            loops.append(loop)
    else:
        # (every face of the planar graph, each directed edge once: at a vertex turn to the next edge clockwise)
        order = {a: sorted(v, key=lambda b: np.arctan2(*(q[b] - q[a])[::-1])) for a, v in nb.items()}
        seen, loops = set(), []
        for a in nb:
            for b in nb[a]:
                if (a, b) in seen:
                    continue
                loop, u, v = [], a, b
                while (u, v) not in seen:
                    seen.add((u, v))
                    loop.append(u)
                    o = order[v]
                    u, v = v, o[(o.index(u) - 1) % len(o)]
                loops.append(loop)

    def area(loop):
        c = np.array([q[a] for a in loop])
        d = np.roll(c, -1, 0)
        return abs(float((c[:, 0] * d[:, 1] - c[:, 1] * d[:, 0]).sum())) * 0.5

    return [rep[a] for a in max(loops, key=area)]


class Cut:
    """A mesh being cut: vertex arrays that grow, triangles that are replaced."""

    def __init__(self, pos, col, idx, nrm):
        self.pos, self.col, self.nrm, self.idx = pos.copy(), col.astype(float), nrm.copy(), idx.copy()
        self.rims = []          # for every cut: (the + side's new vertices, the - side's, point, normal)

    def cut(self, p, n, near):
        """Cuts the loop of the plane (p, n) whose middle is nearest `near`: its triangles are split along the plane, the
        two sides sharing no vertex."""
        s = (self.pos - p) @ n
        s[s == 0.0] = 1e-9
        loops = _loops(self.pos, self.idx, s)
        assert loops, "a cut's plane misses the mesh"
        tri, _mid = min(loops, key=lambda l: np.linalg.norm(l[1] - near))
        side = s > 0
        new = {}        # edge -> (vertex on the + side, on the - side)
        add_pos, add_col, add_nrm = [], [], []
        base = len(self.pos)

        def point(u, v):
            k = (min(u, v), max(u, v))
            if k not in new:
                w = s[u] / (s[u] - s[v])
                q = self.pos[u] + (self.pos[v] - self.pos[u]) * w
                c = self.col[u] + (self.col[v] - self.col[u]) * w
                m = self.nrm[u] + (self.nrm[v] - self.nrm[u]) * w
                m = m / max(np.linalg.norm(m), 1e-9)
                i = base + len(add_pos)
                add_pos.extend([q, q]); add_col.extend([c, c]); add_nrm.extend([m, m])
                new[k] = (i, i + 1)
            return new[k]

        tris, segs = [], []
        for t in tri:
            a, b, c = self.idx[t]
            sa, sb, sc = side[a], side[b], side[c]
            if sb != sa and sb != sc:
                a, b, c = b, c, a
            elif sc != sa and sc != sb:
                a, b, c = c, a, b
            # (a is alone on its side)
            pab, pac = point(a, b), point(a, c)
            ka = 0 if side[a] else 1
            segs.append((pab[0], pac[0]))
            tris.append((a, pab[ka], pac[ka]))
            tris.append((pab[1 - ka], b, c))
            tris.append((pab[1 - ka], c, pac[1 - ka]))
        keep = np.ones(len(self.idx), bool)
        keep[tri] = False
        self.idx = np.concatenate([self.idx[keep], np.array(tris, np.int64)])
        self.pos = np.concatenate([self.pos, np.array(add_pos)])
        self.col = np.concatenate([self.col, np.array(add_col)])
        self.nrm = np.concatenate([self.nrm, np.array(add_nrm)])
        # (the rim in order, walked along the cut's own segments: a loop need not be star-shaped about its middle)
        plus = np.array(_rim(self.pos, segs, n))
        self.rims.append((plus, plus + 1, p, n))

    def parts(self):
        """Which piece every vertex is in (pieces numbered by nothing in particular)."""
        from scipy.sparse import coo_matrix
        from scipy.sparse.csgraph import connected_components
        e = np.concatenate([self.idx[:, [0, 1]], self.idx[:, [1, 2]], self.idx[:, [2, 0]]])
        v = len(self.pos)
        return connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(v, v)), directed=False)

    def cap(self, k):
        """Closes both sides of cut k with a fan about the loop's middle: dark stone at the rim to a glowing core (the glow
        byte) at the middle. The middle is where the largest circle fits in the loop (so a pinched or notched loop still
        fans without folding, and the joint's ball fits inside the limb). Returns the middle, that circle's radius, and the
        two caps' triangles (+ side, - side)."""
        plus, minus, p, n = self.rims[k]
        pts = self.pos[plus]
        ax = np.cross(n, [0.0, 0.0, 1.0] if abs(n[2]) < 0.9 else [1.0, 0.0, 0.0])
        ax /= np.linalg.norm(ax)
        ay = np.cross(n, ax)
        o0 = pts.mean(0)
        q = np.stack([(pts - o0) @ ax, (pts - o0) @ ay], 1)
        q1 = np.roll(q, -1, 0)

        def clear(g):           # how far inside the loop each point of g is (negative outside)
            d = q1 - q
            w = g[:, None, :] - q[None]
            tt = np.clip((w * d[None]).sum(2) / np.maximum((d * d).sum(1), 1e-12)[None], 0.0, 1.0)
            dist = np.linalg.norm(w - tt[:, :, None] * d[None], axis=2).min(1)
            yi, yj = q[None, :, 1], q1[None, :, 1]
            hit = ((yi > g[:, None, 1]) != (yj > g[:, None, 1])) & \
                  (g[:, None, 0] < (q1[None, :, 0] - q[None, :, 0]) * (g[:, None, 1] - yi) / (yj - yi + 1e-30) + q[None, :, 0])
            return np.where(hit.sum(1) % 2 == 1, dist, -dist)

        lo, hi = q.min(0), q.max(0)
        best, r = None, -1.0
        for _ in range(3):
            gx, gy = np.meshgrid(np.linspace(lo[0], hi[0], 41), np.linspace(lo[1], hi[1], 41))
            g = np.stack([gx.ravel(), gy.ravel()], 1)
            c = clear(g)
            i = int(c.argmax())
            best, r = g[i], float(c[i])
            step = (hi - lo) / 40.0
            lo, hi = best - step, best + step
        mid = o0 + best[0] * ax + best[1] * ay
        # (which way the loop runs about the middle: the fan follows the loop, so it can only fold where the loop is not
        # star-shaped about the middle)
        e0, e1 = q - best, q1 - best
        turn = e0[:, 0] * e1[:, 1] - e0[:, 1] * e1[:, 0]
        ccw = turn.sum() > 0
        folded = int((turn < 0).sum() if ccw else (turn > 0).sum())
        m = len(plus)
        stone = self.col[plus].copy()
        stone[:, :3] *= 0.5
        stone[:, 3] = CAP_RIM_GLOW
        core = np.array([[*(stone[:, :3].mean(0) * 0.7), 255.0]])
        out = []
        for sign in (1.0, -1.0):          # (the + side's cap looks back along the normal, the - side's along it)
            b = len(self.pos)
            self.pos = np.concatenate([self.pos, pts, mid[None]])
            self.col = np.concatenate([self.col, stone, core])
            self.nrm = np.concatenate([self.nrm, np.tile(-sign * n, (m + 1, 1))])
            i = np.arange(m)
            ring = np.stack([np.full(m, b + m), b + i, b + (i + 1) % m], 1)
            # (ax, ay, n is right-handed: a loop running counter-clockwise in (ax, ay) faces along n)
            out.append(ring if (sign < 0) == ccw else ring[:, ::-1])
        return mid, r, out, folded


CAP_RIM_GLOW = 40.0
# the joints that are cut, in the order they are cut: the joint, the bone on its far side
CUTS = [("spine", 1), ("neck", 2), ("r_shoulder", 3), ("r_elbow", 4), ("l_shoulder", 5), ("l_elbow", 6),
        ("r_hip", 7), ("r_knee", 8), ("l_hip", 9), ("l_knee", 10), ("r_ankle", 11), ("l_ankle", 12)]
# per design, what a cut's plane is moved by (see _plane)
# (the neck's: each design's throat, measured off its mesh's profile, is at y 43.3 (A) and 44.0 (B), its chin just over it)
TUNE = [{"neck": {"drop": 1.45, "tilt": 20.0}}, {"neck": {"drop": 1.3, "tilt": 20.0}}]


def segment(pos, col, idx, nrm, j, design):
    """Cuts a giant's display mesh into its 13 pieces. Returns the vertex arrays (grown by the cuts' and the caps' vertices),
    every bone's triangles, and for every cut joint its middle (the pivot) and its ball's radius."""
    c = Cut(pos, col, idx, nrm)
    for name, _bone in CUTS:
        side_x = -1.0 if name[0] == "r" else 1.0
        p, n = _plane(j, name, side_x, TUNE[design])
        c.cut(p, n, j[name])
    nc, lab = c.parts()
    bone_of = {}
    for k, (name, bone) in enumerate(CUTS):
        ls = np.unique(lab[c.rims[k][0]])
        assert len(ls) == 1, f"the cut at {name} left its far side in {len(ls)} pieces"
        assert ls[0] not in bone_of, f"the cut at {name} did not part the mesh (its far side is still {BONES[bone_of[ls[0]]][0]})"
        bone_of[ls[0]] = bone
    rest = [l for l in range(nc) if l not in bone_of]
    sizes = np.bincount(lab[c.idx[:, 0]], minlength=nc)
    root = max(rest, key=lambda l: sizes[l])
    for l in rest:          # (anything loose goes with the pelvis)
        bone_of[l] = 0
    tri_bone = np.array([bone_of[l] for l in range(nc)])[lab[c.idx[:, 0]]]
    tris = [c.idx[tri_bone == b] for b in range(NBONES)]
    pivots, balls, folds = {}, {}, {}
    for k, (name, bone) in enumerate(CUTS):
        mid, inner, (cap_far, cap_near), bad = c.cap(k)
        folds[name] = bad
        tris[bone] = np.concatenate([tris[bone], cap_far])
        parent = BONES[bone][1]
        tris[parent] = np.concatenate([tris[parent], cap_near])
        pivots[name], balls[bone] = mid, inner
    loose = [int(sizes[l]) for l in rest if l != root] + [f"{k} cap folds {v}" for k, v in folds.items() if v]
    return c.pos, np.clip(np.rint(c.col), 0, 255).astype(np.uint8), c.nrm, tris, pivots, balls, loose


# ---- the layout of `mod_data` (colossi.wgsl's header, strike/colossi.rs's table_words: keep the three in step) ----
MESH_HEAD = 16          # mesh m's header (16 words): giant design d's bone b is mesh 13 d + b; the hammer is mesh 26:
                        # node_off, tri_off, triangles, vert_off, box corner xyz, box size xyz, pivot xyz, radius, ball radius, ball rgb
NMESH = 2 * NBONES + 1
RIG = 448               # design d's rig (96 words): its 15 joints (xyz), then word 45: how far any vertex is from the pelvis
RIG_STRIDE = 96
CL_INST = 640           # the five giants' records (64 words each)
CL_REC = 64
MESH_DATA = 1024        # where the packed meshes start


def build_view(meshes, cfg, pack_mesh, f32, words, hammer_grip):
    """Packs the giants as bone pieces and the hammer into `words` (a dict word -> value), returns the end offset and the
    triangle and vertex counts. meshes: (pos, col, idx, normals, grid) for design A, B and the hammer."""
    off = MESH_DATA
    total = [0, 0]
    info = []

    def put(m, pos, col, idx, nrm, pivot, ball):
        nonlocal off
        nodes, tri, vert, lo, ext = pack_mesh(pos, col, idx, nrm)
        hdr = MESH_HEAD + 16 * m
        node_off = off
        tri_off = node_off + nodes.size
        vert_off = tri_off + tri.size
        for k, v in enumerate([node_off, tri_off, len(tri), vert_off]):
            words[hdr + k] = v
        for k in range(3):
            words[hdr + 4 + k] = f32(lo[k])
            words[hdr + 7 + k] = f32(ext[k])
            words[hdr + 10 + k] = f32(pivot[k])
        words[hdr + 13] = f32(np.linalg.norm(ext) / 2)
        words[hdr + 14] = f32(ball[0])
        words[hdr + 15] = ball[1]
        for base, a in ((node_off, nodes), (tri_off, tri), (vert_off, vert)):
            for i, v in enumerate(a.reshape(-1)):
                words[base + i] = int(v)
        off = vert_off + vert.size
        total[0] += len(tri)
        total[1] += len(vert)

    for d in (0, 1):
        pos, col, idx, nrm, _ = meshes[d]
        lo, ext = pos.min(0), pos.max(0) - pos.min(0)
        j = joints(d, cfg["giants"][d], lo, ext)
        pos, col, nrm, parts, pivots, balls, loose = segment(pos, col, idx, nrm, j, d)
        j.update(pivots)
        info.append((d, [len(t) for t in parts], {BONES[b][0]: round(r, 2) for b, r in balls.items()}, loose))
        rig = RIG + RIG_STRIDE * d
        for n, name in enumerate(JOINT_NAMES):
            for k in range(3):
                words[rig + 3 * n + k] = f32(j[name][k])
        words[rig + 45] = f32(np.linalg.norm(pos - j["pelvis"], axis=1).max())
        for b, tris in enumerate(parts):
            put(NBONES * d + b, pos, col, tris, nrm, j[BONES[b][2]], (BALL * balls.get(b, 0.0), 0))
    pos, col, idx, nrm, _ = meshes[2]
    lo, ext = pos.min(0), pos.max(0) - pos.min(0)
    # (the hammer's header keeps the whole model's box in words 4-9: the plan and the pass place its grip and head by it)
    put(2 * NBONES, pos, col, idx, nrm, np.array(hammer_grip) * ext + lo, (0.0, 0))
    return off, total, info
