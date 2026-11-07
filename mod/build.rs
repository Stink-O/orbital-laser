//! Builds every post pass ahead of time (src/passbuild.rs) into OUT_DIR, and `passes.rs` there naming them, for lib.rs
//! to `include!`: the game is handed a ready-made `&'static str`, so switching QUALITY costs the mod nothing.
#[path = "src/passbuild.rs"]
mod passbuild;

use std::fmt::Write as _;
use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let shaders = root.join("shaders");
    println!("cargo:rerun-if-changed=src/passbuild.rs");
    println!("cargo:rerun-if-changed=shaders");
    let read = |name: &str| {
        let p = shaders.join(name);
        println!("cargo:rerun-if-changed={}", p.display());
        std::fs::read_to_string(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
    };
    let shader = read("strike.wgsl");
    let mut rs = String::new();
    let write = |name: String, text: String| -> String {
        let p = out.join(&name);
        std::fs::write(&p, text).unwrap();
        format!("include_str!({:?})", p.display().to_string())
    };
    // 0 the other lasers' (strike.wgsl itself), then the downfall's, the planet killer's, the crystal bloom's, the
    // sinkhole's
    let mut others = vec![format!("include_str!({:?})", shaders.join("strike.wgsl").display().to_string())];
    for own in ["downfall", "planetkiller", "crystalbloom", "sinkhole"] {
        others.push(write(format!("pass_{own}.wgsl"), passbuild::own_pass(&shader, &read(&format!("{own}.wgsl")))));
    }
    writeln!(rs, "/// The other lasers' pass, then the downfall's, the planet killer's, the crystal bloom's and the sinkhole's.").unwrap();
    writeln!(rs, "const PASS_OWN: [&str; 5] = [{}];", others.join(", ")).unwrap();
    let payload = read("payload.wgsl");
    let p: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_payload_{f}.wgsl"), passbuild::split_pass(&shader, &payload, f))).collect();
    writeln!(rs, "/// The Payload's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_PAYLOAD: [&str; 2] = [{}];", p.join(", ")).unwrap();
    let nuke = read("nuke.wgsl");
    let n: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_nuke_{f}.wgsl"), passbuild::split_pass(&shader, &nuke, f))).collect();
    writeln!(rs, "/// The Nuke's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_NUKE: [&str; 2] = [{}];", n.join(", ")).unwrap();
    let rod = read("rod.wgsl");
    let r: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_rod_{f}.wgsl"), passbuild::split_pass(&shader, &rod, f))).collect();
    writeln!(rs, "/// The Rod from God's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_ROD: [&str; 2] = [{}];", r.join(", ")).unwrap();
    let sc = read("supercell.wgsl");
    let c: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_supercell_{f}.wgsl"), passbuild::split_pass(&shader, &sc, f))).collect();
    writeln!(rs, "/// The Supercell's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_SUPERCELL: [&str; 2] = [{}];", c.join(", ")).unwrap();
    let hu = read("hurricane.wgsl");
    let h: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_hurricane_{f}.wgsl"), passbuild::split_pass(&shader, &hu, f))).collect();
    writeln!(rs, "/// The Hurricane's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_HURRICANE: [&str; 2] = [{}];", h.join(", ")).unwrap();
    let ts = read("tsunami.wgsl");
    let t: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_tsunami_{f}.wgsl"), passbuild::split_pass(&shader, &ts, f))).collect();
    writeln!(rs, "/// The Tsunami's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_TSUNAMI: [&str; 2] = [{}];", t.join(", ")).unwrap();
    let fold = write("pass_fold.wgsl".into(), passbuild::own_pass(&shader, &(passbuild::warp_shared(&read("fold_warp.wgsl")) + &read("fold.wgsl"))));
    writeln!(rs, "/// The Fold's (no half-size stage: its cost is the warp, drawn whole).").unwrap();
    writeln!(rs, "const PASS_FOLD: &str = {fold};").unwrap();
    std::fs::write(out.join("passes.rs"), rs).unwrap();
}
