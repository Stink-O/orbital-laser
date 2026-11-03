//! Each pass (prelude + source) through naga to SPIR-V, MSL and HLSL, as wgpu would for Vulkan, Metal and DX12:
//! xshader PRELUDE PASS... prints, per pass and backend, ok with the output's size, or the error.
use naga::back::{hlsl, msl, spv};
use naga::valid::{Capabilities, ValidationFlags, Validator};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let prelude = std::fs::read_to_string(&args[0]).expect("prelude");
    let mut failed = false;
    for path in &args[1..] {
        let src = std::fs::read_to_string(path).expect("pass");
        let full = format!("{prelude}\n{src}");
        let name = std::path::Path::new(path).file_name().unwrap().to_string_lossy().to_string();
        let module = match naga::front::wgsl::parse_str(&full) {
            Ok(m) => m,
            Err(e) => {
                println!("{name}: WGSL parse FAILED: {}", e.emit_to_string(&full));
                failed = true;
                continue;
            }
        };
        let info = match Validator::new(ValidationFlags::all(), Capabilities::all()).validate(&module) {
            Ok(i) => i,
            Err(e) => {
                println!("{name}: validation FAILED: {e:?}");
                failed = true;
                continue;
            }
        };
        let entries: Vec<String> = module.entry_points.iter().map(|e| e.name.clone()).collect();
        let fns = module.functions.len();
        let mut line = format!("{name}: {} KiB wgsl, {fns} functions, entries {entries:?}", full.len() >> 10);
        // SPIR-V (Vulkan)
        match spv::write_vec(&module, &info, &spv::Options::default(), None) {
            Ok(words) => line += &format!(" | spv ok {} KiB", words.len() * 4 >> 10),
            Err(e) => { line += &format!(" | spv FAILED {e}"); failed = true; }
        }
        // MSL (Metal): Metal 2.4, as wgpu asks on Apple Silicon
        let mut mo = msl::Options::default();
        mo.lang_version = (2, 4);
        mo.fake_missing_bindings = true;
        let po = msl::PipelineOptions::default();
        match msl::write_string(&module, &info, &mo, &po) {
            Ok((s, _)) => line += &format!(" | msl ok {} KiB", s.len() >> 10),
            Err(e) => { line += &format!(" | msl FAILED {e}"); failed = true; }
        }
        // HLSL (DX12): shader model 6.0
        let mut ho = hlsl::Options::default();
        ho.shader_model = hlsl::ShaderModel::V6_0;
        ho.fake_missing_bindings = true;
        let mut out = String::new();
        let hpo = hlsl::PipelineOptions::default();
        let mut w = hlsl::Writer::new(&mut out, &ho, &hpo);
        let r = w.write(&module, &info, None).map(|_| ());
        drop(w);
        match r {
            Ok(_) => line += &format!(" | hlsl ok {} KiB", out.len() >> 10),
            Err(e) => { line += &format!(" | hlsl FAILED {e}"); failed = true; }
        }
        let dir = std::path::Path::new("out");
        let _ = std::fs::create_dir_all(dir);
        if let Ok((s, _)) = msl::write_string(&module, &info, &mo, &po) {
            let _ = std::fs::write(dir.join(format!("{name}.metal")), s);
        }
        let _ = std::fs::write(dir.join(format!("{name}.hlsl")), &out);
        println!("{line}");
    }
    if failed {
        std::process::exit(1);
    }
}
