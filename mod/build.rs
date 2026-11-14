//! Builds every post pass ahead of time (src/passbuild.rs) into OUT_DIR, and `passes.rs` there naming them, for lib.rs
//! to `include!`: the game is handed a ready-made `&'static str`, so switching QUALITY costs the mod nothing.
#[path = "src/passbuild.rs"]
mod passbuild;
#[path = "src/strike/we_path.rs"]
mod we_path;

use std::fmt::Write as _;
use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let shaders = root.join("shaders");
    println!("cargo:rerun-if-changed=src/passbuild.rs");
    println!("cargo:rerun-if-changed=src/strike/we_path.rs");
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
    let vc = read("volcano.wgsl") + &read("volcano_mount.wgsl");
    let v: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_volcano_{f}.wgsl"), passbuild::split_pass(&shader, &vc, f))).collect();
    writeln!(rs, "/// The Supervolcano's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_VOLCANO: [&str; 2] = [{}];", v.join(", ")).unwrap();
    let ts = read("tsunami.wgsl");
    let t: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_tsunami_{f}.wgsl"), passbuild::split_pass(&shader, &ts, f))).collect();
    writeln!(rs, "/// The Tsunami's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_TSUNAMI: [&str; 2] = [{}];", t.join(", ")).unwrap();
    let sb = read("skybreak.wgsl");
    let k: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_skybreak_{f}.wgsl"), passbuild::split_pass(&shader, &sb, f))).collect();
    writeln!(rs, "/// The Sky Breaks' at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_SKYBREAK: [&str; 2] = [{}];", k.join(", ")).unwrap();
    let cp = read("carpetbomb.wgsl");
    let c: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_carpet_{f}.wgsl"), passbuild::split_pass(&shader, &cp, f))).collect();
    writeln!(rs, "/// The Carpet Bomb's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_CARPET: [&str; 2] = [{}];", c.join(", ")).unwrap();
    // the World Eater's: its path (its constants spliced in from strike/we_path.rs), its body, its own; and its world warp
    // (what of the path is marked `[warp too]`, then worldeater_warp.wgsl)
    let we_path_src = we_path::we_splice_consts(&read("worldeater_path.wgsl"));
    // (the fx's stand-in mound is for the preview, which has no world warp: in the game the warp lifts the land itself)
    let we_own = read("worldeater.wgsl");
    const STANDIN: &str = "const WE_STANDIN_MOUND: bool = true;";
    if !we_own.contains(STANDIN) {
        println!("cargo:warning=worldeater.wgsl has no `{STANDIN}` line to turn off for the game");
    }
    let we = we_path_src.clone() + &read("worldeater_body.wgsl") + &we_own.replace(STANDIN, "const WE_STANDIN_MOUND: bool = false;");
    let w: Vec<String> = [false, true].iter().map(|&f| write(format!("pass_worldeater_{f}.wgsl"), passbuild::split_pass(&shader, &we, f))).collect();
    writeln!(rs, "/// The World Eater's at QUALITY FULL and FAST.").unwrap();
    writeln!(rs, "const PASS_WORLDEATER: [&str; 2] = [{}];", w.join(", ")).unwrap();
    let warp = write("we_warp.wgsl".into(), passbuild::marked(&we_path_src, "warp too") + &read("worldeater_warp.wgsl"));
    writeln!(rs, "/// The World Eater's world warp (the wormsign and the dome).").unwrap();
    writeln!(rs, "const PASS_WE_WARP: &str = {warp};").unwrap();
    let fold = write("pass_fold.wgsl".into(), passbuild::own_pass(&shader, &(passbuild::warp_shared(&read("fold_warp.wgsl")) + &read("fold.wgsl"))));
    writeln!(rs, "/// The Fold's (no half-size stage: its cost is the warp, drawn whole).").unwrap();
    writeln!(rs, "const PASS_FOLD: &str = {fold};").unwrap();
    std::fs::write(out.join("passes.rs"), rs).unwrap();
}
