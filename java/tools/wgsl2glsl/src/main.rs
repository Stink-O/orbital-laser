use naga::back::glsl;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: wgsl2glsl <in.wgsl> <out.glsl> <entry> [version]");
        std::process::exit(2);
    }
    let src = std::fs::read_to_string(&args[1]).expect("read input");
    let version: u16 = args.get(4).and_then(|v| v.parse().ok()).unwrap_or(450);
    let module = match naga::front::wgsl::parse_str(&src) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("{}", e.emit_to_string(&src));
            std::process::exit(1);
        }
    };
    let info = match naga::valid::Validator::new(naga::valid::ValidationFlags::all(), naga::valid::Capabilities::all()).validate(&module) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("{}", e.emit_to_string(&src));
            std::process::exit(1);
        }
    };
    let opts = glsl::Options {
        version: glsl::Version::Desktop(version),
        writer_flags: glsl::WriterFlags::empty(),
        binding_map: Default::default(),
        zero_initialize_workgroup_memory: true,
    };
    let pipe = glsl::PipelineOptions { shader_stage: naga::ShaderStage::Fragment, entry_point: args[3].clone(), multiview: None };
    let mut out = String::new();
    let mut writer = glsl::Writer::new(&mut out, &module, &info, &opts, &pipe, naga::proc::BoundsCheckPolicies::default()).expect("writer");
    let reflection = writer.write().expect("write glsl");
    std::fs::write(&args[2], &out).expect("write output");
    eprintln!("ok: {} bytes of GLSL; textures {:?}", out.len(), reflection.texture_mapping.keys().collect::<Vec<_>>());
    eprintln!("uniforms {:?}", reflection.uniforms);
}
