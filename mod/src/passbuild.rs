//! Building the post passes' sources from the shader files: run by build.rs, so the mod holds every pass ready-made
//! (`passes.rs` in OUT_DIR) and a switch (QUALITY) only picks one: none of this runs in the game, where
//! building a pass of some 200 KB in one call took the mod past its fuel. Also compiled into the tests.
#![allow(dead_code)]

/// A laser's own pass: strike.wgsl (`shader`) up to its fs_main, less the other lasers' own functions (marked
/// `[lasers pass only]`) and the Mothership's ship (`[mothership]`, kept for an `own` that says `// [uses the mothership]`),
/// then `own` (see shaders/downfall.wgsl, shaders/planetkiller.wgsl ...).
pub fn own_pass(shader: &str, own: &str) -> String {
    let mut out = String::with_capacity(shader.len() + own.len());
    let ship = own.contains("// [uses the mothership]");
    let mut skip = false;
    for line in shader.lines() {
        if line.starts_with("@fragment") {
            break;
        }
        if line.starts_with("// [lasers pass only]") || (!ship && line.starts_with("// [mothership]")) {
            skip = true;
        }
        if !skip {
            out.push_str(line);
            out.push('\n');
        }
        if line.starts_with("// [end lasers pass only]") || line.starts_with("// [end mothership]") {
            skip = false;
        }
    }
    out.push_str(own);
    out
}

/// What of the Fold's world warp its post pass has too: what lies between fold_warp.wgsl's `[post pass too]` marks.
pub fn warp_shared(warp: &str) -> String {
    let mut out = String::new();
    let mut on = false;
    for line in warp.lines() {
        if line.starts_with("// [end post pass too]") {
            on = false;
        }
        if on {
            out.push_str(line);
            out.push('\n');
        }
        if line.starts_with("// [post pass too]") {
            on = true;
        }
    }
    out
}

/// What lies between the lines starting `// [<mark>]` and `// [end <mark>]` of `src` (worldeater_path.wgsl's `[warp
/// too]`: what of it the World Eater's world warp has too).
pub fn marked(src: &str, mark: &str) -> String {
    let (open, close) = (format!("// [{mark}]"), format!("// [end {mark}]"));
    let mut out = String::new();
    let mut on = false;
    for line in src.lines() {
        if line.starts_with(&close) {
            on = false;
        }
        if on {
            out.push_str(line);
            out.push('\n');
        }
        if line.starts_with(&open) {
            on = true;
        }
    }
    out
}

/// A pass with a half-size stage (payload.wgsl, nuke.wgsl), at QUALITY FAST (its `[half stage]` kept: the smoke drawn
/// at half the width and height, on a game with mod passes' half-size stage; a game without it draws the pass's
/// `fs_main`, at full size) or FULL (left out).
pub fn split_pass(shader: &str, src: &str, fast: bool) -> String {
    let lean = src.contains("// [lean pass]");
    let pass = split_pass_full(shader, src, fast);
    if lean { lean_pass(&pass) } else { pass }
}

/// The pass less its comment lines and blank lines (a source saying `// [lean pass]`, the World Eater's: its
/// sections already cut, so the marks are no longer wanted), for the game's 256 KiB limit.
pub fn lean_pass(src: &str) -> String {
    let mut out = String::with_capacity(src.len());
    for line in src.lines() {
        let l = line.trim_start();
        if l.is_empty() || l.starts_with("//") {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

fn split_pass_full(shader: &str, src: &str, fast: bool) -> String {
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
