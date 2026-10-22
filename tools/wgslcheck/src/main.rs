
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let src = std::fs::read_to_string(&args[1]).unwrap();
    let module = match naga::front::wgsl::parse_str(&src) {
        Ok(m) => m,
        Err(e) => { println!("PARSE ERROR:\n{}", e.emit_to_string(&src)); std::process::exit(1) }
    };
    let flags = naga::valid::ValidationFlags::all();
    let caps = naga::valid::Capabilities::all();
    let info = match naga::valid::Validator::new(flags, caps).validate(&module) {
        Ok(i) => i,
        Err(e) => { println!("VALIDATION ERROR:\n{}", e.emit_to_string(&src)); std::process::exit(1) }
    };
    let mut pc: hashbrown::HashMap<String, f64> = hashbrown::HashMap::new();
    for kv in &args[2..] {
        let (k, v) = kv.split_once('=').unwrap();
        pc.insert(k.to_string(), v.parse().unwrap());
    }
    match naga::back::pipeline_constants::process_overrides(&module, &info, None, &pc) {
        Ok(_) => println!("OK"),
        Err(e) => { println!("OVERRIDE ERROR: {e:?}"); std::process::exit(2) }
    }
}
