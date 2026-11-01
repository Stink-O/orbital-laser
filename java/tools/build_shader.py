"""Build one of Orbital Laser's screen shaders for Minecraft's OpenGL 3.3 renderer.

    python tools/build_shader.py NAME --orbital-laser PATH [--converter PATH] [--glsl-version 330] [--out DIR] [--work DIR]

NAME is strike, payload or nuke. PATH is a checkout of https://github.com/Stink-O/orbital-laser (the original mod, where the
WGSL shaders live). The converter is tools/wgsl2glsl (see tools/README.md); the default is the one built beside this script.

What it does, step by step (the original's shaders are WGSL for Horizon's renderer; Minecraft wants GLSL):
  1. Assembles the pass the way the original's build does (mod/src/passbuild.rs): the fork's prelude, then strike.wgsl up to its
     fs_main (less the other lasers' own functions) and the laser's own file, at the original's QUALITY FULL (no half-size stage).
     `strike` is strike.wgsl as it is.
  2. Moves every viewing direction to a far point, so the walking bob (which shifts the camera by about a tenth of a block, the
     distance the original samples at) cannot swing the direction.
  3. Replaces the half-float packing of the Payload's billows (not in OpenGL 3.3) with plain floats.
  4. Replaces `mod_data` (a storage buffer) with an unsigned-integer texture, and textureLoad on the depth texture (not
     expressible in GLSL) with a lookup through depth_at.
  5. Converts with naga, then makes the result Minecraft's format: its header, the fragment input location, a plain depth read
     in place of naga's shadow sampler, and the vertical flip between the shader's uv (0 at the top) and Minecraft's textures.
The output is written to src/client/resources/assets/orbital/shaders/post/NAME.fsh. Those files are generated: do not edit them.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

NL = chr(10)
HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent


def own_pass(shader, own):
    """strike.wgsl up to its fs_main, less the regions marked `[lasers pass only]`, then the laser's own file."""
    out, skip = [], False
    for line in shader.splitlines():
        if line.startswith("@fragment"):
            break
        if line.startswith("// [lasers pass only]"):
            skip = True
        if not skip:
            out.append(line)
        if line.startswith("// [end lasers pass only]"):
            skip = False
    return NL.join(out) + NL + own


def without_half_stage(text):
    """The laser's own file without its half-size stage (the original's QUALITY FAST), which needs bindings 6 and 7."""
    out, skip = [], False
    for line in text.splitlines():
        if line.startswith("// [half stage]"):
            skip = True
        if not skip:
            out.append(line)
        if line.startswith("// [end half stage]"):
            skip = False
    return NL.join(out) + NL


def assemble(name, original):
    prelude = (original / "tools/wgslcheck/prelude.wgsl").read_text(encoding="utf-8")
    strike = (original / "mod/shaders/strike.wgsl").read_text(encoding="utf-8")
    if name == "strike":
        return prelude + NL + strike
    own = (original / ("mod/shaders/" + name + ".wgsl")).read_text(encoding="utf-8")
    return prelude + NL + own_pass(strike, without_half_stage(own))


def patch_wgsl(name, wgsl):
    # (2) far viewing directions
    wgsl = "const RAY_DEPTH: f32 = 0.00002;" + NL + wgsl
    wgsl, n_rays = re.subn(r"normalize\(world_offset\(([^,()]+), 0\.5\)\)",
                           lambda m: "normalize(world_offset(" + m.group(1) + ", RAY_DEPTH))", wgsl)
    print(name + ": " + str(n_rays) + " viewing directions moved to a far point")

    # (3) no half-float packing
    packed_decl = "    q: array<vec2<u32>, 18>,"
    packed_store = "        o.q[i] = vec2<u32>(pack2x16float(q.xy - C.xy), pack2x16float(vec2<f32>(q.z - C.z, q.w)));"
    packed_load = NL.join([
        "        let qp = (*col).q[i];",
        "        let qa = unpack2x16float(qp.x);",
        "        let qb = unpack2x16float(qp.y);",
        "        let q = vec4<f32>(qa, qb);",
    ])
    if packed_decl in wgsl:
        assert packed_store in wgsl and packed_load in wgsl, "the packed billows' code is not as expected"
        wgsl = wgsl.replace(packed_decl, "    q: array<vec4<f32>, 18>,")
        wgsl = wgsl.replace(packed_store, "        o.q[i] = vec4<f32>(q.xy - C.xy, q.z - C.z, q.w);")
        wgsl = wgsl.replace(packed_load, "        let q = (*col).q[i];")
        print(name + ": half-float packing replaced with plain floats")
    assert "pack2x16float" not in wgsl and "unpack2x16float" not in wgsl, "a half-float pack is left"

    # (4) mod_data as a texture; depth loads through depth_at
    decl = "@group(0) @binding(5) var<storage, read> mod_data: array<u32>;"
    assert decl in wgsl, "mod_data declaration not found"
    wgsl = wgsl.replace(decl, NL.join([
        "@group(0) @binding(5) var mod_data_tex: texture_2d<u32>;",
        "fn md_len() -> u32 { let d = textureDimensions(mod_data_tex); return d.x * d.y; }",
        "fn md_at(i: u32) -> u32 { return textureLoad(mod_data_tex, vec2<i32>(i32(i & 4095u), i32(i >> 12u)), 0).r; }",
        "fn depth_px(q: vec2<i32>) -> f32 { return depth_at((vec2<f32>(q) + vec2<f32>(0.5)) * frame.resolution.zw); }",
    ]))
    wgsl, n_dpx = re.subn(r"textureLoad\(scene_depth, (.+?), 0\)", lambda m: "depth_px(" + m.group(1) + ")", wgsl)
    n_len = wgsl.count("arrayLength(&mod_data)")
    wgsl = wgsl.replace("arrayLength(&mod_data)", "md_len()")
    wgsl, n_at = re.subn(r"mod_data\[([^\]]+)\]", lambda m: "md_at(" + m.group(1) + ")", wgsl)
    assert "mod_data[" not in wgsl and "&mod_data" not in wgsl, "a mod_data use was left"
    print(name + ": " + str(n_dpx) + " depth loads, " + str(n_len) + " lengths and " + str(n_at) + " reads of mod_data patched")
    return wgsl


def minecraft_format(name, glsl):
    # (5) Minecraft's header, input location, depth read and vertical flip
    first, rest = glsl.split(NL, 1)
    assert first.startswith("#version"), first
    glsl = "#version 330" + NL + "#extension GL_ARB_separate_shader_objects : require" + NL + rest
    glsl = glsl.replace("smooth in vec2 _vs2fs_location0;", "layout(location = 0) in vec2 _vs2fs_location0;")
    glsl = glsl.replace("uniform sampler2DShadow _group_0_binding_1_fs;", "uniform sampler2D _group_0_binding_1_fs;")
    depth_call = "float _e4 = textureLod(_group_0_binding_1_fs, vec2(uv), 0);"
    assert depth_call in glsl, "depth read not found"
    glsl = glsl.replace(depth_call, "float _e4 = textureLod(_group_0_binding_1_fs, vec2(uv.x, 1.0 - uv.y), 0.0).r;")
    flips = len(re.findall(r"textureLod\(_group_0_binding_0_fs, ", glsl))
    glsl = glsl.replace("textureLod(_group_0_binding_0_fs, ", "orbitalSceneLod(_group_0_binding_0_fs, ")
    helper = NL + "vec4 orbitalSceneLod(sampler2D s, vec2 uv, float lod) {" + NL
    helper += "    return textureLod(s, vec2(uv.x, 1.0 - uv.y), lod);" + NL + "}" + NL
    marker = "layout(std140) uniform Frame_block_0Fragment"
    assert marker in glsl, "frame block not found"
    glsl = glsl.replace(marker, helper + NL + marker, 1)
    print(name + ": " + str(flips) + " scene reads flipped")
    return glsl


def default_converter():
    for kind in ("release", "debug"):
        for exe in ("wgsl2glsl.exe", "wgsl2glsl"):
            p = HERE / "wgsl2glsl" / "target" / kind / exe
            if p.exists():
                return p
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", choices=["strike", "payload", "nuke"])
    ap.add_argument("--orbital-laser", required=True, type=Path, help="a checkout of github.com/Stink-O/orbital-laser")
    ap.add_argument("--converter", type=Path, default=default_converter(), help="the built tools/wgsl2glsl")
    ap.add_argument("--glsl-version", default="330")
    ap.add_argument("--out", type=Path, default=PROJECT / "src/client/resources/assets/orbital/shaders/post")
    ap.add_argument("--work", type=Path, default=HERE / "work", help="scratch folder (git-ignored)")
    a = ap.parse_args()
    if a.converter is None or not a.converter.exists():
        sys.exit("The converter is not built: run `cargo build --release` in tools/wgsl2glsl, or pass --converter PATH.")

    wgsl = patch_wgsl(a.name, assemble(a.name, a.orbital_laser))
    a.work.mkdir(parents=True, exist_ok=True)
    wgsl_path = a.work / (a.name + "_full.wgsl")
    glsl_path = a.work / (a.name + a.glsl_version + ".glsl")
    wgsl_path.write_text(wgsl, encoding="utf-8", newline=NL)
    r = subprocess.run([str(a.converter), str(wgsl_path), str(glsl_path), "fs_main", a.glsl_version], capture_output=True, text=True)
    print(r.stderr.strip())
    if r.returncode != 0:
        sys.exit(1)

    glsl = minecraft_format(a.name, glsl_path.read_text(encoding="utf-8"))
    a.out.mkdir(parents=True, exist_ok=True)
    target = a.out / (a.name + ".fsh")
    target.write_text(glsl, encoding="utf-8", newline=NL)
    print("wrote " + str(target) + " (" + str(len(glsl)) + " bytes)")


if __name__ == "__main__":
    main()
