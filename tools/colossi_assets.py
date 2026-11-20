#!/usr/bin/env python3
"""Builds the Colossi's data from three models (two giants and a hammer, as GLB files): the converter
(model2mc, github.com/Stink-O/model2mc) makes each model's display mesh (`.m2md`, its docs/display-mesh.md) and, for each of the
five giants, its broken statue as blocks (`--damage-seed`, its docs/damage.md); this packs them for the mod.

    tools/colossi_assets.py [--models DIR] [--converter DIR] [--out mod/colossi]

DIR holds giant_a.glb, giant_b.glb, hammer.glb and colossi.json (where the hammer arm's fist and the hammer's grip are:
fractions of each model's box, see tools/colossi_standin.py's standin.json, which is what is used when DIR is not given:
the stand-ins are made first). Writes

    view.bin      words (little-endian u32) of what the pass reads from `mod_data`: a header, the 27 meshes' headers
                  (13 bone pieces a giant design, and the hammer), the rigs, and the meshes packed with a BVH each
                  (indexed triangles; a vertex has its position, a smooth normal, baked ambient occlusion, colour and
                  glow); the five giants' table (word 640 on) is left for the mod to fill in for each strike. Layout:
                  mod/shaders/colossi.wgsl's header, tools/colossi_rig.py.
    statues.bin   the five giants as the mod places them: design, mirror, height, turn, damage, grid size, the offset that
                  puts the display mesh over the blocks, and the blocks themselves (a palette and run lengths).

The five giants' fixed choices (design, mirror, height, damage) are GIANTS below; the mod reads them back out of
statues.bin, so changing them here is all it takes.
"""
import argparse
import base64
import json
import math
import os
import pathlib
import struct
import subprocess
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import colossi_pose  # noqa: E402
import colossi_rig  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent

# design (0 = giant A, 1 = giant B), mirrored, height in blocks (about half the Planet Killer's towers: the most a block
# statue can be under the build limit), damage seed, damage spec, and the pieces that burst with its hammer (bit k bone k of
# colossi_rig.BONES: 3 and 5 the upper arms, 4 and 6 the forearms; BURST_MASK in strike/colossi.rs holds the same); they
# stand 72 degrees apart
GIANTS = [
    (0, False, 220, 4, "cuts=6,size=0.11,rough=0.65,ymin=0.38,ymax=0.97", 0x50),
    (1, True, 206, 170, "cuts=4,size=0.12,rough=0.65,ymin=0.38,ymax=0.97", 0x58),
    (0, True, 230, 214, "cuts=5,size=0.12,rough=0.65,ymin=0.38,ymax=0.97", 0x78),
    (1, False, 214, 317, "cuts=4,size=0.14,rough=0.65,ymin=0.38,ymax=0.97", 0x70),
    (0, False, 224, 401, "cuts=5,size=0.12,rough=0.65,ymin=0.38,ymax=0.97", 0x50),
]
# the kneel each giant ends in, where it struck (one knee on the ground, `colossi_pose.feet`; dy sinks it till that
# knee is down), and its statue is built in (colossi_pose.POSE_KEYS: the pelvis sunk and
# carried, its turn; the torso's; the head's: mesh units and radians, as the pass's cl_pose); the mod hands these to the pass
# (record words 48-58), which sinks each giant into it after its hammer bursts, so the blocks lie under the giant drawn
STATUE_POSE = [
    dict(dy=9.21, dz=-2.0, px=0.0, ppitch=0.12, pyaw=0.00, proll=0.00, spitch=0.48, syaw=0.06, sroll=0.03, hpitch=-0.04, hyaw=0.12, kx=0.0, ky=-2.5, kz=-10.0, side=0),
    dict(dy=10.73, dz=-1.8, px=0.0, ppitch=0.12, pyaw=-0.03, proll=0.00, spitch=0.30, syaw=-0.05, sroll=0.00, hpitch=-0.06, hyaw=-0.10, kx=0.0, ky=-2.5, kz=-10.0, side=1),
    dict(dy=9.22, dz=-2.2, px=0.0, ppitch=0.12, pyaw=0.00, proll=0.00, spitch=0.55, syaw=0.00, sroll=-0.04, hpitch=0.08, hyaw=0.05, kx=0.0, ky=-2.5, kz=-10.0, side=0),
    dict(dy=10.76, dz=-2.0, px=0.0, ppitch=0.12, pyaw=0.04, proll=0.00, spitch=0.38, syaw=0.08, sroll=0.00, hpitch=-0.05, hyaw=-0.16, kx=0.0, ky=-2.5, kz=-10.0, side=0),
    dict(dy=9.27, dz=-2.1, px=0.0, ppitch=0.12, pyaw=0.00, proll=0.02, spitch=0.45, syaw=-0.07, sroll=0.00, hpitch=-0.03, hyaw=0.08, kx=0.0, ky=-2.5, kz=-10.0, side=1),
]
RING_DEG = [-90 + 72 * g for g in range(5)]       # where each stands round the target (the mod's ring, 45 blocks out)
# triangles each model's display mesh may have (giant A, giant B, the hammer): what `mod_data` holds (262,144 words in all)
DISPLAY_TRIS = [20000, 15000, 6000]
HAMMER_HEIGHT = 38
MAGIC = 0xC0105510
LEAF = 6            # triangles a BVH leaf holds at most (more: fewer nodes, a smaller table, more tests a leaf)


def f32(x):
    return struct.unpack("<I", struct.pack("<f", float(x)))[0]


def read_m2md(path):
    """The converter's display mesh (docs/display-mesh.md, version 3): vertices (v,3), colours and glow (v,4) bytes,
    triangles (t,3), unit normals (v,3), the voxel grid."""
    w = np.frombuffer(pathlib.Path(path).read_bytes(), "<u4")
    assert w[0] == int.from_bytes(b"M2MD", "little") and w[1] == 3, "not a version 3 display mesh (the converter with normals)"
    v, t, hs, vw = int(w[2]), int(w[3]), int(w[14]), int(w[15])
    vert = w[hs:hs + vw * v].reshape(v, vw)
    pos = vert[:, :3].copy().view("<f4").astype(np.float64)
    col = np.stack([(vert[:, 3] >> s) & 255 for s in (0, 8, 16, 24)], 1).astype(np.uint8)   # (r, g, b, glow)
    nrm = (np.stack([(vert[:, 4] >> s) & 1023 for s in (0, 10, 20)], 1).astype(np.float64) - 511.0) / 511.0
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    idx = w[hs + vw * v:hs + vw * v + (3 * t + 1) // 2].view("<u2")[:3 * t].reshape(t, 3).astype(np.int64)
    return pos, col, idx, nrm, tuple(int(x) for x in w[10:13])


def bvh(q, leaf=LEAF):
    """Median-split BVH over quantised triangles q (n,3,3 ints): (nodes (m,3) words, the triangle order). A node is its
    box's low and high corners (10 bits a coordinate) and a word: a leaf's triangle count (1-15) in its top four bits over
    its first triangle, or 0 over its left child (the right is the next node)."""
    n = len(q)
    mn, mx = q.min(1), q.max(1)
    cen = (mn + mx) / 2.0
    order = np.arange(n)
    nodes = [None]
    work = [(0, 0, n)]

    def pack(v):
        return int(v[0]) | int(v[1]) << 10 | int(v[2]) << 20

    while work:
        i, a, b = work.pop()
        ids = order[a:b]
        lo, hi = mn[ids].min(0), mx[ids].max(0)
        if b - a <= leaf:
            nodes[i] = [pack(lo), pack(hi), (b - a) << 28 | a]
            continue
        ax = int(np.argmax(hi - lo))
        order[a:b] = ids[np.argsort(cen[ids, ax], kind="stable")]
        m = (a + b) // 2
        left = len(nodes)
        nodes += [None, None]
        nodes[i] = [pack(lo), pack(hi), left]
        work += [(left, a, m), (left + 1, m, b)]
    return np.array(nodes, dtype=np.uint64), order


def _hemisphere(n):
    """n directions over +z, cosine-weighted (a Fibonacci spiral)."""
    k = np.arange(n) + 0.5
    r = np.sqrt(k / n)
    th = k * 2.399963229728653
    return np.stack([r * np.cos(th), r * np.sin(th), np.sqrt(np.maximum(1.0 - r * r, 0.0))], 1)


def ambient(pos, nrm, idx, cell=0.3, reach=4.5, ndir=40):
    """How open each vertex is to the sky around it (1 open, towards 0 in a crevice): the mesh's own triangles rastered into
    a grid of `cell`, and from every vertex `ndir` rays over its normal's hemisphere marched `reach` through the grid, a
    near blocker counting more than a far one. Only this mesh shades itself (a bone piece: what it bakes moves with it)."""
    lo = pos.min(0) - reach - 2 * cell
    dims = np.ceil((pos.max(0) + reach + 2 * cell - lo) / cell).astype(int) + 1
    occ = np.zeros(dims, bool)
    tv = pos[idx]
    edge = np.maximum(np.linalg.norm(tv[:, 1] - tv[:, 0], axis=1), np.maximum(np.linalg.norm(tv[:, 2] - tv[:, 1], axis=1), np.linalg.norm(tv[:, 0] - tv[:, 2], axis=1)))
    sub = np.clip(np.ceil(edge / (0.5 * cell)).astype(int), 1, 64)
    for n in np.unique(sub):
        t = tv[sub == n]
        i, j = np.meshgrid(np.arange(n + 1), np.arange(n + 1), indexing="ij")
        keep = i + j <= n
        u, v = i[keep] / n, j[keep] / n
        pts = t[:, None, 0] * (1 - u - v)[None, :, None] + t[:, None, 1] * u[None, :, None] + t[:, None, 2] * v[None, :, None]
        c = np.floor((pts.reshape(-1, 3) - lo) / cell).astype(int)
        occ[c[:, 0], c[:, 1], c[:, 2]] = True
    # a frame about each normal
    up = np.where(np.abs(nrm[:, 1:2]) < 0.9, np.array([[0.0, 1.0, 0.0]]), np.array([[1.0, 0.0, 0.0]]))
    tx = np.cross(up, nrm)
    tx /= np.maximum(np.linalg.norm(tx, axis=1, keepdims=True), 1e-9)
    ty = np.cross(nrm, tx)
    hs = _hemisphere(ndir)
    start = pos + nrm * (1.6 * cell)
    steps = np.arange(0.0, reach, 0.8 * cell)
    shade = np.zeros(len(pos))
    for d in hs:
        dr = tx * d[0] + ty * d[1] + nrm * d[2]
        hit = np.zeros(len(pos))
        free = np.ones(len(pos), bool)
        for s in steps:
            c = np.floor((start + dr * s - lo) / cell).astype(int)
            o = occ[c[:, 0], c[:, 1], c[:, 2]] & free
            hit[o] = (1.0 - s / reach) ** 1.5
            free &= ~o
        shade += hit
    return 1.0 - shade / ndir


def _oct(n):
    """Unit normals to octahedral coordinates in 0..1."""
    n = n / np.maximum(np.abs(n).sum(1, keepdims=True), 1e-9)
    x, y = n[:, 0].copy(), n[:, 1].copy()
    neg = n[:, 2] < 0
    ox = (1.0 - np.abs(y)) * np.where(x >= 0, 1.0, -1.0)
    oy = (1.0 - np.abs(x)) * np.where(y >= 0, 1.0, -1.0)
    x[neg], y[neg] = ox[neg], oy[neg]
    return x * 0.5 + 0.5, y * 0.5 + 0.5


def pack_mesh(pos, col, idx, nrm):
    """One mesh (a bone's piece, or the hammer) as words: BVH nodes (3 words, see `bvh`), triangles (2 words: three vertex
    numbers, 16 bits each, in the BVH's order) and vertices (3 words: the position as three 10-bit coordinates in the
    piece's own box; the normal, octahedral, 12 bits each, under how open the vertex is (`ambient`), 8 bits; then its colour
    and the converter's glow byte, how much greener than stone it is: the glowing cracks). Returns nodes, triangles,
    vertices, the box's corner and size."""
    used, inv = np.unique(idx, return_inverse=True)
    pos, col, nrm, idx = pos[used], col[used], nrm[used], inv.reshape(-1, 3)
    lo, hi = pos.min(0), pos.max(0)
    ext = np.maximum(hi - lo, 1e-3)
    qv = np.rint((pos - lo) / ext * 1023.0).astype(np.int64)
    nodes, order = bvh(qv[idx])
    idx = idx[order]
    # vertices in the order the triangles first use them (what a leaf reads lies together)
    flat = idx.reshape(-1)
    _, first = np.unique(flat, return_index=True)
    vorder = flat[np.sort(first)]
    rank = np.empty(len(pos), np.int64)
    rank[vorder] = np.arange(len(vorder))
    idx = rank[idx]
    assert len(vorder) <= 65536, "a piece has more vertices than a triangle's 16-bit numbers reach"
    ao = ambient(pos, nrm, inv.reshape(-1, 3))
    ox, oy = _oct(nrm)
    vert = np.zeros((len(pos), 3), np.uint64)
    vert[:, 0] = qv[:, 0] | (qv[:, 1] << 10) | (qv[:, 2] << 20)
    vert[:, 1] = np.rint(ox * 4095).astype(np.uint64) | (np.rint(oy * 4095).astype(np.uint64) << 12) | (np.rint(np.clip(ao, 0, 1) * 255).astype(np.uint64) << 24)
    c = col.astype(np.uint64)
    vert[:, 2] = c[:, 0] | (c[:, 1] << 8) | (c[:, 2] << 16) | (c[:, 3] << 24)
    vert = vert[vorder]
    tri = np.zeros((len(idx), 2), np.uint64)
    tri[:, 0] = idx[:, 0].astype(np.uint64) | (idx[:, 1].astype(np.uint64) << 16)
    tri[:, 1] = idx[:, 2].astype(np.uint64)
    return nodes, tri, vert, lo, ext


def run_converter(conv, args):
    py = conv / ".venv" / "bin" / "python"
    if not py.exists():
        py = pathlib.Path(sys.executable)
    r = subprocess.run([str(py), "-m", "model2mc", *map(str, args), "-q", "--no-promo"], cwd=conv, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"model2mc failed: {r.stderr}")


def statue(path):
    """The converter's voxel dump as (X,Y,Z, palette states, blocks in x + z*X + y*X*Z order as bytes)."""
    d = json.loads(pathlib.Path(path).read_text())
    assert d["format"] == "model2mc-voxels" and d["encoding"] == "u8", "a statue needs 255 block types at most"
    pal = [p["state"] for p in d["palette"]]
    return d["size"], pal, base64.b64decode(d["blocks"])


def burst(raw, size, mask, tree, bone, back):
    """A statue without the pieces that burst (the blocks nearest those bones of the display mesh; `back` takes a block's
    middle to the mesh's space), and without anything that is then not joined to the ground (by a face or an edge: the
    statues are shells a block thick). Returns the blocks and how many went each way."""
    from scipy import ndimage
    X, Y, Z = size
    a = np.frombuffer(raw, np.uint8).reshape(Y, Z, X).copy()
    y, z, x = np.nonzero(a)
    _, near = tree.query(back(np.stack([x, y, z], 1) + 0.5))
    gone = ((mask >> bone[near]) & 1) == 1
    a[y[gone], z[gone], x[gone]] = 0
    lab, _ = ndimage.label(a > 0, ndimage.generate_binary_structure(3, 2))
    ground = np.unique(lab[0:3])
    floating = (a > 0) & ~np.isin(lab, ground[ground > 0])
    a[floating] = 0
    return a.tobytes(), int(gone.sum()), int(floating.sum())


def rle(raw):
    a = np.frombuffer(raw, np.uint8)
    cut = np.flatnonzero(np.diff(a)) + 1
    starts = np.r_[0, cut]
    lens = np.diff(np.r_[starts, len(a)])
    return a[starts], lens


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models", type=pathlib.Path, help="folder with giant_a.glb, giant_b.glb, hammer.glb, colossi.json")
    ap.add_argument("--converter", type=pathlib.Path, default=pathlib.Path.home() / "Downloads" / "model-to-minecraft")
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "mod" / "colossi")
    ap.add_argument("--work", type=pathlib.Path, default=ROOT / "dist" / "colossi")
    ap.add_argument("--view-only", action="store_true", help="only view.bin, from the display meshes already in --work (a second)")
    ap.add_argument("--reuse", action="store_true", help="use the converter's output already in --work (display meshes and statues): only the packing and the statues' pose run")
    a = ap.parse_args()
    work = a.work
    work.mkdir(parents=True, exist_ok=True)
    models = a.models
    if models is None:
        models = work / "standin"
        py = a.converter / ".venv" / "bin" / "python"
        subprocess.run([str(py if py.exists() else sys.executable), str(ROOT / "tools" / "colossi_standin.py"), str(models)], check=True)
        cfg = json.loads((models / "standin.json").read_text())
    else:
        cfg = json.loads((models / "colossi.json").read_text())
    names = [cfg["giants"][0]["model"], cfg["giants"][1]["model"]]
    fists = [np.array(g["fist"]) for g in cfg["giants"]]
    grip = np.array(cfg["hammer"]["grip"])

    # display meshes: giants at 50 blocks and the hammer, as they come out of the converter, no yaw, no mirror
    meshes = []
    for i, n in enumerate(names):
        if not a.view_only and not a.reuse:
            run_converter(a.converter, [models / n, "--height", 50, "--display-mesh", work / f"g{i}.m2md", "--display-tris", DISPLAY_TRIS[i], "-o", work / f"g{i}.json"])
        meshes.append(read_m2md(work / f"g{i}.m2md"))
    if not a.view_only and not a.reuse:
        run_converter(a.converter, [models / cfg["hammer"]["model"], "--height", HAMMER_HEIGHT, "--display-mesh", work / "h.m2md", "--display-tris", DISPLAY_TRIS[2], "-o", work / "h.json"])
    meshes.append(read_m2md(work / "h.m2md"))

    words = {0: MAGIC, 1: colossi_rig.NMESH, 2: 5, 3: 3}
    off, (ntri, nvert), info = colossi_rig.build_view(meshes, cfg, pack_mesh, f32, words, grip)
    for d, tris, balls, loose in info:
        print(f"design {d}: pieces of {tris} triangles, balls {balls}" + (f", loose bits {loose}" if loose else ""), file=sys.stderr)
    print(f"{colossi_rig.NMESH} meshes (13 bones a design and the hammer), {ntri:,} triangles, {nvert:,} vertices", file=sys.stderr)
    arr = np.zeros(off, np.uint32)
    for i, v in words.items():
        arr[i] = v
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "view.bin").write_bytes(arr.astype("<u4").tobytes())
    print(f"view.bin: {off:,} words of the 262,144 a call takes ({100 * off / 262144:.0f}%)", file=sys.stderr)
    assert off <= 262144, "view.bin is over what one render.set-data call takes"
    if a.view_only:
        return

    # the five statues: voxelised at their own height, turned to face the ring's middle, broken by their seed
    out = bytearray(b"CLST")
    out += struct.pack("<I", len(GIANTS))
    from scipy.spatial import cKDTree
    trees = []
    for d in (0, 1):        # (every design's display mesh, its points marked with their bone)
        pos, col, idx, nrm, _ = meshes[d]
        lo, ext = pos.min(0), pos.max(0) - pos.min(0)
        pos, _, _, parts, _, _, _ = colossi_rig.segment(pos, col, idx, nrm, colossi_rig.joints(d, cfg["giants"][d], lo, ext), d)
        pts = np.concatenate([np.concatenate([pos[t].mean(1), pos[t].reshape(-1, 3)]) for t in parts])
        trees.append((cKDTree(pts), np.concatenate([np.full(4 * len(t), b) for b, t in enumerate(parts)])))
    for g, (design, mirror, height, seed, spec, mask) in enumerate(GIANTS):
        theta = math.radians(RING_DEG[g])
        yaw = math.degrees(math.atan2(-math.cos(theta), -math.sin(theta)))     # its front (+z) turned to the middle
        if mirror:
            yaw = -yaw        # (the converter mirrors after it turns the model: the mirror turns the front the other way too)
        args = [models / names[design], "--height", height, "--yaw", f"{yaw:.4f}", "--damage-seed", seed, "--damage", spec, "-o", work / f"s{g}.json"]
        if mirror:
            args.append("--mirror")
        if not a.reuse:
            run_converter(a.converter, args)
        (X, Y, Z), pal, raw = statue(work / f"s{g}.json")
        # (where the display mesh lies over the blocks: the mesh as the pass draws it, scaled by height / 50, turned by yaw and
        # mirrored, has its x and z minimum at the grid's edge, its y minimum at 0)
        pos = meshes[design][0] * (height / 50.0)   # (the display meshes are exported at 50 blocks)
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        rot = np.stack([c * pos[:, 0] + s * pos[:, 2], pos[:, 1], -s * pos[:, 0] + c * pos[:, 2]], 1)
        if mirror:
            rot[:, 0] = -rot[:, 0]
        b = -rot.min(0)
        b[1] = 0.0

        def back(p, b=b, c=c, s=s, mirror=mirror, height=height):
            q = p - b
            if mirror:
                q[:, 0] = -q[:, 0]
            return np.stack([c * q[:, 0] - s * q[:, 2], q[:, 1], s * q[:, 0] + c * q[:, 2]], 1) * (50.0 / height)

        raw, gone, floating = burst(raw, (X, Y, Z), mask, *trees[design], back)

        # (then moved into the crouch it ends in: each block with the bone nearest it, by the pass's own rig)
        def fwd(u, b=b, c=c, s=s, mirror=mirror, height=height):
            p = u * (height / 50.0)
            q = np.stack([c * p[:, 0] + s * p[:, 2], p[:, 1], -s * p[:, 0] + c * p[:, 2]], 1)
            if mirror:
                q[:, 0] = -q[:, 0]
            return q + b

        arr = np.frombuffer(raw, np.uint8).reshape(Y, Z, X)
        yy, zz, xx = np.nonzero(arr)
        _, near = trees[design][0].query(back(np.stack([xx, yy, zz], 1) + 0.5))
        bone = np.full(arr.shape, -1, np.int16)
        bone[yy, zz, xx] = trees[design][1][near]
        jw = np.frombuffer((a.out / "view.bin").read_bytes(), "<f4")
        joints = jw[448 + 96 * design: 448 + 96 * design + 45].astype(np.float64).reshape(15, 3)
        posed, shift = colossi_pose.pose_blocks(arr, bone, colossi_pose.rig(joints, STATUE_POSE[g]), back, fwd)
        from scipy import ndimage
        lab, _ = ndimage.label(posed > 0, ndimage.generate_binary_structure(3, 2))
        g0 = max(0, min(posed.shape[0], 3 - int(shift[1])))
        ground = np.unique(lab[0:g0])
        loose = (posed > 0) & ~np.isin(lab, ground[ground > 0])
        posed[loose] = 0
        PY, PZ, PX = posed.shape
        print(f"statue {g} posed: {PX}x{PY}x{PZ}, shift {shift.tolist()}, {int((posed > 0).sum()):,} blocks, {int(loose.sum()):,} loose", file=sys.stderr)
        vals, lens = rle(posed.tobytes())
        sp = {k: float(v) for k, v in (kv.split("=") for kv in spec.split(","))}
        out += struct.pack("<BBHIfH", design, int(mirror), height, seed, yaw, len(pal))
        out += struct.pack("<HHH", X, Y, Z)
        out += struct.pack("<H5f", int(sp["cuts"]), sp["size"], sp["rough"], sp["ymin"], sp["ymax"], 0.0)
        out += struct.pack("<3f", *b)
        out += struct.pack("<HHHhhh", PX, PY, PZ, *[int(v) for v in shift])
        out += struct.pack("<15f", *[STATUE_POSE[g][k] for k in colossi_pose.POSE_KEYS])
        for p in pal:
            e = p.encode()
            out += struct.pack("<B", len(e)) + e
        out += struct.pack("<I", len(vals))
        for v, n in zip(vals, lens):
            out += struct.pack("<BI", int(v), int(n))
        print(f"statue {g}: design {design}{' mirrored' if mirror else ''}, {X}x{Y}x{Z}, {int((np.frombuffer(raw, np.uint8) != 0).sum()):,} blocks, {len(pal)} types, yaw {yaw:.1f}; {gone:,} burst, {floating:,} more not joined to the ground", file=sys.stderr)
    (a.out / "statues.bin").write_bytes(bytes(out))
    print(f"statues.bin: {len(out):,} bytes", file=sys.stderr)


if __name__ == "__main__":
    main()
