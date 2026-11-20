#!/usr/bin/env python3
"""The Colossi's stand-in models: two blocky stone giants and a hammer as GLB files, for building and testing the laser
until the Tripo models arrive (tools/colossi_assets.py takes either through the converter).

    tools/colossi_standin.py OUTDIR [--cell 1.5]

Writes giant_a.glb, giant_b.glb and hammer.glb (rocky triangle meshes, one colour a triangle, the glowing cracks bright
green) and standin.json, which says where the hammer arm's fist and the hammer's grip are (as fractions of each model's
box). Needs trimesh (the converter's venv has it).

"""
import argparse
import math
import json
import pathlib
import sys

import numpy as np


def vnoise(p, seed=0.0):
    """Smooth 3D value-ish noise from sines (the generator's own; the shader's cuts use its own noise)."""
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    return (0.5 + 0.25 * np.sin(x * 1.31 + seed) * np.cos(z * 1.17 - y * 0.83)
            + 0.15 * np.sin(y * 2.07 + z * 1.71 + seed * 2.0) * np.cos(x * 2.31)
            + 0.10 * np.sin((x + y + z) * 3.9 + seed * 3.0))


def patch(origin, u, v, nrm, nu, nv, amp, seed):
    """A grid of nu x nv cells over a box face (corner `origin`, spans u and v), roughened along its normal."""
    tris = []
    gu = np.linspace(0, 1, nu + 1)
    gv = np.linspace(0, 1, nv + 1)
    pts = origin + gu[:, None, None] * u + gv[None, :, None] * v
    pts = pts + (vnoise(pts * 0.35, seed) - 0.5)[..., None] * amp * nrm
    for i in range(nu):
        for j in range(nv):
            a, b, c, d = pts[i, j], pts[i + 1, j], pts[i + 1, j + 1], pts[i, j + 1]
            if (i + j) & 1:
                tris += [(a, b, c), (a, c, d)]
            else:
                tris += [(a, b, d), (b, c, d)]
    return tris


def obox(centre, axes, half, cell, amp, seed):
    """An oriented box: `axes` three unit vectors, `half` half-sizes along them, faces cut in cells of about `cell`."""
    tris = []
    centre = np.asarray(centre, float)
    for k in range(3):
        for s in (-1, 1):
            n = axes[k] * s
            i, j = (k + 1) % 3, (k + 2) % 3
            u, v = axes[i] * 2 * half[i], axes[j] * 2 * half[j]
            o = centre + n * half[k] - u / 2 - v / 2
            nu = max(1, round(2 * half[i] / cell))
            nv = max(1, round(2 * half[j] / cell))
            tris += patch(o, u, v, n, nu, nv, amp, seed + k * 3 + s)
    return tris


def basis(d):
    w = np.asarray(d, float)
    w = w / np.linalg.norm(w)
    t = np.array([0.0, 1.0, 0.0]) if abs(w[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(t, w)
    u /= np.linalg.norm(u)
    v = np.cross(w, u)
    return [u, v, w]


def seg(p0, p1, wid, dep, cell, amp, seed):
    """A limb: a box from p0 to p1, wid x dep across."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    ax = basis(p1 - p0)
    return obox((p0 + p1) / 2, ax, [wid / 2, dep / 2, np.linalg.norm(p1 - p0) / 2], cell, amp, seed)


E = np.eye(3)


def giant(design, cell):
    """A ~50 block giant, feet at the origin, facing +z. Design 0 lean and long, design 1 bulky with a heavy brow."""
    t = []
    if design == 0:
        legs, torso, head, sh = 22, 17, 9, 11
    else:
        legs, torso, head, sh = 19, 20, 10, 13
    s = 11 * design
    for side in (-1, 1):
        t += obox((side * 5.5, legs / 2, 0), E, [3.6, legs / 2, 4.2], cell, 0.9, 1 + s + side)
        t += obox((side * 5.5, 1.2, 1.6), E, [3.9, 1.2, 6.0], cell, 0.7, 5 + s + side)       # feet
    t += obox((0, legs + torso / 2, 0), E, [sh - 1, torso / 2, 6.0 + design], cell, 1.1, 3 + s)
    t += obox((0, legs + torso + 0.8, -0.5), E, [sh + 1.5, 2.2, 6.5], cell, 1.0, 4 + s)         # shoulders
    t += obox((0, legs + torso + head / 2 + 2, 1.0), E, [head / 2 + 0.6 * design, head / 2, head / 2], cell, 0.9, 7 + s)
    if design == 1:
        t += obox((0, legs + torso + head + 0.5, 2.5), E, [head / 2 + 2, 1.8, head / 2 + 1], cell, 0.8, 9)  # brow / helm
    sy = legs + torso + 0.8
    # the hammer arm (+x side): shoulder, down and out to an elbow, the forearm forward and up, a closed fist upright
    sx = sh + 1
    elbow = (sx + 4, sy - 11, 3.0)
    fist = (sx + 4.5, sy - 5.5, 14.0)
    t += seg((sx, sy, 0), elbow, 6.2, 6.2, cell, 0.9, 13 + s)
    t += seg(elbow, fist, 5.4, 5.4, cell, 0.8, 14 + s)
    t += obox((fist[0], fist[1] + 0.5, fist[2] + 0.5), E, [3.1, 3.4, 3.1], cell, 0.7, 15 + s)  # the fist, closed, vertical
    # the relaxed arm (-x side): hangs down, a little forward, a hand open at the end
    hand = (-sx - 2, sy - 22, 4.0)
    el2 = (-sx - 1.5, sy - 11, 1.5)
    t += seg((-sx, sy, 0), el2, 5.8, 5.8, cell, 0.9, 17 + s)
    t += seg(el2, hand, 5.0, 5.0, cell, 0.8, 18 + s)
    t += obox((hand[0], hand[1] - 2, hand[2]), E, [2.8, 3.2, 2.4], cell, 0.6, 19 + s)
    return t, np.array(fist)


def hammer(cell):
    """The hammer, upright with its grip at the origin: a long handle up y, a mallet head across it at the top."""
    t = []
    t += obox((0, 10, 0), E, [1.5, 17, 1.5], cell, 0.5, 21)
    t += obox((0, 24, 0), E, [8.5, 5.5, 5.0], cell, 0.9, 22)
    t += obox((0, 24, 0), E, [9.2, 4.2, 4.2], cell, 0.7, 23)       # the head's collars
    t += obox((0, -6.5, 0), E, [2.2, 1.5, 2.2], cell, 0.5, 24)    # the pommel
    return t


def colour(tris, seed):
    """One baked colour a triangle: stone, lichen and soot by position; the green cracks as the emissive byte."""
    out = []
    for a, b, c in tris:
        p = (a + b + c) / 3.0
        n = vnoise(p * 0.5, seed)
        grain = vnoise(p * 2.3, seed + 4.0)
        base = np.array([0.50, 0.48, 0.44]) * (0.62 + 0.55 * n + 0.18 * grain)
        if vnoise(p * 0.8, seed + 9.0)[()] > 0.74:
            base = base * np.array([0.8, 1.0, 0.7])             # a little lichen
        # cracks: thin ridges where a noise passes through 0.5
        ridge = abs(vnoise(p * 0.42, seed + 2.0) - 0.5) + 0.35 * abs(vnoise(p * 0.9, seed + 5.0) - 0.5)
        e = 255 if ridge < 0.045 else 0
        r, g, bl = (np.clip(base, 0, 1) * 255).astype(int)
        if e:
            r, g, bl = 40, 255, 110
        out.append((r, g, bl))
    return out


def write_glb(path, tris, cols):
    import trimesh
    t = np.array(tris, float).reshape(-1, 3)
    c = np.repeat(np.array(cols, np.uint8), 3, axis=0)
    c = np.concatenate([c, np.full((len(c), 1), 255, np.uint8)], 1)
    m = trimesh.Trimesh(vertices=t, faces=np.arange(len(t)).reshape(-1, 3), vertex_colors=c, process=False)
    m.export(path)
    return t.min(0), t.max(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--cell", type=float, default=1.5, help="face cell size in blocks (smaller: more triangles)")
    a = ap.parse_args()
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    info = {"giants": [], "hammer": {}}
    for d in (0, 1):
        tris, fist = giant(d, a.cell)
        lo, hi = write_glb(out / f"giant_{'ab'[d]}.glb", tris, colour(tris, 1.0 + 7 * d))
        info["giants"].append({"model": f"giant_{'ab'[d]}.glb", "fist": ((fist - lo) / (hi - lo)).round(4).tolist()})
    h = hammer(a.cell * 0.8)
    lo, hi = write_glb(out / "hammer.glb", h, colour(h, 33.0))
    info["hammer"] = {"model": "hammer.glb", "grip": ((np.zeros(3) - lo) / (hi - lo)).round(4).tolist()}
    (out / "standin.json").write_text(json.dumps(info, indent=1))
    print(f"wrote {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
