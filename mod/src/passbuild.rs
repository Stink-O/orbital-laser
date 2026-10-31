//! Building the post passes' sources from the shader files: run by build.rs, so the mod holds every pass ready-made
//! (`passes.rs` in OUT_DIR) and a switch (QUALITY, the Nuke's cloud) only picks one: none of this runs in the game, where
//! building a pass of some 200 KB in one call took the mod past its fuel. Also compiled into the tests.
#![allow(dead_code)]

/// The Nuke's clouds (`wheel::CLOUDS`): files in shaders/nuke_cloud (v1.wgsl ..., written by tools/nuke_cloud.py
/// extract; v10.wgsl by hand, v3's with today's look), but for `CLOUD_CURRENT`, today's (nuke.wgsl itself).
pub const CLOUD_COUNT: usize = 10;
pub const CLOUD_CURRENT: usize = 8;

/// A laser's own pass: strike.wgsl (`shader`) up to its fs_main, less the other lasers' own functions (marked
/// `[lasers pass only]`), then `own` (see shaders/downfall.wgsl, shaders/planetkiller.wgsl ...).
pub fn own_pass(shader: &str, own: &str) -> String {
    let mut out = String::with_capacity(shader.len() + own.len());
    let mut skip = false;
    for line in shader.lines() {
        if line.starts_with("@fragment") {
            break;
        }
        if line.starts_with("// [lasers pass only]") {
            skip = true;
        }
        if !skip {
            out.push_str(line);
            out.push('\n');
        }
        if line.starts_with("// [end lasers pass only]") {
            skip = false;
        }
    }
    out.push_str(own);
    out
}

/// A pass with a half-size stage (payload.wgsl, nuke.wgsl), at QUALITY FAST (its `[half stage]` kept: the smoke drawn
/// at half the width and height, on a game with mod passes' half-size stage; a game without it draws the pass's
/// `fs_main`, at full size) or FULL (left out).
pub fn split_pass(shader: &str, src: &str, fast: bool) -> String {
    if fast {
        return own_pass(shader, src);
    }
    let mut own = String::with_capacity(src.len());
    let mut skip = false;
    for line in src.lines() {
        if line.starts_with("// [half stage]") {
            skip = true;
        }
        if !skip {
            own.push_str(line);
            own.push('\n');
        }
        if line.starts_with("// [end half stage]") {
            skip = false;
        }
    }
    own_pass(shader, &own)
}

/// nuke.wgsl `src` with an earlier cloud in it: the version's functions at `// [cloud fns]`, its block in place of the
/// lines between `// [cloud]` and `// [end cloud]`; the rest of the pass (the fall, the flash, the shockwave, the dust,
/// the debris, the shadow on the land) today's. Keep in step with tools/nuke_cloud.py's `splice`.
pub fn nuke_cloud_pass(src: &str, version: &str) -> String {
    let (fns, block) = version.split_once("\n// [cloud]\n").unwrap_or((version, ""));
    let fns = fns.split_once("// [cloud fns]\n").map_or(fns, |(_, f)| f);
    let mut out = String::with_capacity(src.len() + version.len());
    let mut skip = false;
    for line in src.lines() {
        if line.starts_with("    // [end cloud]") {
            skip = false;
        }
        if skip {
            continue;
        }
        out.push_str(line);
        out.push('\n');
        if line.starts_with("// [cloud fns]") {
            out.push_str(fns.trim_end_matches('\n'));
            out.push('\n');
        } else if line.starts_with("    // [cloud]") {
            out.push_str(block.trim_end_matches('\n'));
            out.push('\n');
            skip = true;
        }
    }
    out
}
