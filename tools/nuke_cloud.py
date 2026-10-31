#!/usr/bin/env python3
"""The Nuke's earlier clouds, for comparing them in the game (`/orbital nukecloud`, the wheel's CLOUD row).

    tools/nuke_cloud.py extract          # (re)write mod/shaders/nuke_cloud/vN.wgsl from the commits in VERSIONS
    tools/nuke_cloud.py splice N [--fast] # print the Nuke's own pass (nuke.wgsl) with version N's cloud in it
                                          # (N = 0 or `current`: nuke.wgsl as it is), as mod/src/lib.rs builds it

Each version file holds, from that commit's nuke.wgsl, the cloud's own functions (from `struct PlCol` up to
`fn pl_gref`, with whatever else they call that has changed since) and the cloud's block in `nuke()` (from "the
mushroom cloud" up to "the bomb"), every name they define prefixed `vN_` so they sit beside today's. The pass is
today's nuke.wgsl with those functions at its `// [cloud fns]` line and the block in place of the lines between
`// [cloud]` and `// [end cloud]`: so only the cloud is the old one; the fall, the flash, the shockwave, the dust, the
debris and the shadow on the land are today's. Keep the splice in step with `nuke_cloud_pass` in mod/src/lib.rs.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NUKE = ROOT / "mod/shaders/nuke.wgsl"
OUT = ROOT / "mod/shaders/nuke_cloud"
# (number, commit, the wheel's label) oldest first; keep in step with NUKE_CLOUDS in mod/src/lib.rs
VERSIONS = [
    (1, "f7212de", "FIRST CLOUD"),
    (2, "59f7989", "ROUND CROWN"),
    (3, "12c9f80", "FOLDING"),
    (4, "3570696", "CARRIED LUMPS"),
    (5, "6cb04f9", "BOIL-UP"),
    (6, "c969abe", "FIZEAU"),
    (7, "73fe7bf", "BILLOWS"),
    (8, "1ba6527", "BOIL ON BILLOWS"),
]
CLOUD_A = "    // ---- the mushroom cloud:"
CLOUD_B = "    // ---- the bomb:"


def items(lines):
    """The file's top-level definitions: {name: (kind, first line, end line (exclusive))}, comments above included."""
    out = {}
    i = 0
    while i < len(lines):
        m = re.match(r"^(fn|struct|const) (\w+)", lines[i])
        if not m:
            i += 1
            continue
        start = i
        while start > 0 and lines[start - 1].startswith("//") and not lines[start - 1].startswith("// ["):
            start -= 1
        if m.group(1) == "const":
            end = i + 1
        else:
            end = i + 1
            while end < len(lines) and lines[end] != "}":
                end += 1
            end += 1
        out[m.group(2)] = (m.group(1), start, end)
        i = end
    return out


def body(lines, span):
    """A definition's text without its comments (for telling whether it changed)."""
    return "\n".join(l.split("//")[0].rstrip() for l in lines[span[1]:span[2]] if not l.startswith("//")).strip()


def idents(text):
    return set(re.findall(r"\b[A-Za-z_]\w*\b", re.sub(r"//.*", "", text)))


def rename(text, names, pre):
    if not names:
        return text
    pat = re.compile(r"(?<![\.\w])(" + "|".join(sorted(map(re.escape, names), key=len, reverse=True)) + r")\b")
    out = []
    for line in text.split("\n"):
        code, sep, comment = line.partition("//")
        out.append(pat.sub(lambda m: pre + m.group(1), code) + sep + comment)
    return "\n".join(out)


def extract(n, commit, label):
    old = subprocess.run(["git", "show", f"{commit}:mod/shaders/nuke.wgsl"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.split("\n")
    cur = NUKE.read_text().split("\n")
    oi, ci = items(old), items(cur)
    lo, hi = oi["PlCol"][1], oi["pl_gref"][1]
    fns = old[lo:hi]
    a = next(i for i, l in enumerate(old) if l.startswith(CLOUD_A))
    b = next(i for i, l in enumerate(old) if l.startswith(CLOUD_B))
    block = old[a:b]
    while block and not block[-1].strip():
        block.pop()
    names = {k for k, v in oi.items() if lo <= v[1] < hi}
    # whatever else they call that is not today's (missing or changed), carried along under its own new name
    extra = []
    todo = idents("\n".join(fns + block))
    seen = set()
    while todo:
        k = todo.pop()
        if k in seen or k in names or k not in oi:
            continue
        seen.add(k)
        if k in ci and body(old, oi[k]) == body(cur, ci[k]):
            continue
        names.add(k)
        span = oi[k]
        extra.append((span[1], old[span[1]:span[2]]))
        todo |= idents("\n".join(old[span[1]:span[2]]))
    pre = f"v{n}_"
    head = subprocess.run(["git", "log", "-1", "--format=%h %ad %s", "--date=format:%Y-%m-%d %H:%M", commit], cwd=ROOT,
                          check=True, capture_output=True, text=True).stdout.strip()
    text = [f"// v{n} {label}: the Nuke's cloud as it was at {head[:150]}",
            "// Written by tools/nuke_cloud.py extract (don't edit by hand); spliced into nuke.wgsl by mod/src/lib.rs's",
            "// nuke_cloud_pass for /orbital nukecloud " + str(n) + ".",
            "// [cloud fns]"]
    for _, lines in sorted(extra):
        text += lines
    text += fns
    text += ["// [cloud]"] + block
    out = rename("\n".join(text), names, pre)
    OUT.mkdir(exist_ok=True)
    (OUT / f"v{n}.wgsl").write_text(out.rstrip() + "\n")
    print(f"v{n} {commit}: {len(names)} names, {len(extra)} carried along: {sorted(k for k in names if k not in {x for x in oi if lo <= oi[x][1] < hi})}")


def splice(src, version):
    """nuke.wgsl `src` with `version` (a version file's text, or None) in it."""
    if version is None:
        return src
    fns, _, block = version.partition("\n// [cloud]\n")
    fns = fns.split("// [cloud fns]\n", 1)[1]
    out = []
    skip = False
    for line in src.split("\n"):
        if line.startswith("// [cloud fns]"):
            out.append(line)
            out.append(fns.rstrip("\n"))
            continue
        if line.startswith("    // [cloud]"):
            out.append(line)
            out.append(block.rstrip("\n"))
            skip = True
            continue
        if line.startswith("    // [end cloud]"):
            skip = False
        if not skip:
            out.append(line)
    return "\n".join(out)


def main():
    if sys.argv[1:2] == ["extract"]:
        for v in VERSIONS:
            extract(*v)
        return
    if sys.argv[1:2] == ["splice"]:
        n = sys.argv[2]
        version = None if n in ("0", "current", str(len(VERSIONS) + 1)) else (OUT / f"v{int(n)}.wgsl").read_text()
        src = splice(NUKE.read_text(), version)
        if "--fast" not in sys.argv:
            src = re.sub(r"(?ms)^// \[half stage\].*?^// \[end half stage\]\n?", "", src)
        sys.stdout.write(src)
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
