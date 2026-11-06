//! warpview WARP.wgsl OUT key=value... [-- key=value...]...: the Fold's real world_warp and world_fragment over a synthetic
//! voxel land, offscreen. Keys: t, cx cy cz (eye), lx ly lz (look at), mx my mz (player, default eye), tx ty tz (target), seed,
//! sunel sunaz, fov, w h, hills (height of the land's relief), copies (draw arm copies).
//! `noland=1` skips the mesh (for check and pts). `pts=1` warps the points in the file $WV_PTS (f32 x y z copy, from the target) and writes
//! OUT/pts_NNN.bin (x y z tint.x, from the target). `check=1` warps a polar grid and counts crossing pairs, on the land of $WV_MAP if set.
//! `post=1` puts the real post pass (the prelude, strike.wgsl up to its fs_main, what the warp shares, fold.wgsl) over the picture, on the same depth; no entities, no sky but the clear colour.
//! $WV_MAP: the real land (tools/foldview/fv.py writes it from land_from_save.py's): i32 W, then i16 ground[W*W], i16 top[W*W], u8 class[W*W], u8 ground class[W*W], and 16 colours rgb.
use std::collections::HashMap;
#[path = "../../../mod/src/passbuild.rs"] mod passbuild;
use wgpu::util::DeviceExt;
#[repr(C)] #[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct V { p: [f32; 3], uv: [f32; 2], layer: u32, c: [f32; 3] }
fn hash(x: i32, z: i32) -> f32 {
    let mut h = (x as u32).wrapping_mul(374761393) ^ (z as u32).wrapping_mul(668265263);
    h = (h ^ (h >> 13)).wrapping_mul(1274126177);
    ((h ^ (h >> 16)) & 0xFFFF) as f32 / 65535.0
}
fn land_h(x: f32, z: f32, ty: f32, hills: f32) -> f32 {
    let a = 0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin();
    let b = (x * 0.11).sin() * (z * 0.13).sin() * 0.25;
    ty + hills * (a + b)
}
fn forest(x: f32, z: f32) -> f32 { (x * 0.009 + 1.3).sin() * (z * 0.011 - 0.7).sin() }
fn quad(v: &mut Vec<V>, i: &mut Vec<u32>, a: [f32; 3], b: [f32; 3], c: [f32; 3], d: [f32; 3], layer: u32, col: [f32; 3], s: f32) {
    let n = v.len() as u32;
    let m = |p: [f32; 3], uv: [f32; 2]| V { p, uv, layer, c: col };
    v.push(m(a, [0.0, 0.0])); v.push(m(b, [s, 0.0])); v.push(m(c, [s, s])); v.push(m(d, [0.0, s]));
    i.extend_from_slice(&[n, n + 1, n + 2, n, n + 2, n + 3]);
}
fn boxy(v: &mut Vec<V>, i: &mut Vec<u32>, lo: [f32; 3], hi: [f32; 3], layer: u32, col: [f32; 3]) {
    let [x0, y0, z0] = lo; let [x1, y1, z1] = hi;
    let t = [col[0], col[1], col[2]];
    let s = [col[0] * 0.75, col[1] * 0.75, col[2] * 0.75];
    quad(v, i, [x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0], layer, t, 1.0);
    quad(v, i, [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], layer, s, 1.0);
    quad(v, i, [x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], layer, s, 1.0);
    quad(v, i, [x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], layer, s, 1.0);
    quad(v, i, [x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], layer, s, 1.0);
}
// a square of the land round (0,0): cells `st` wide out to `ext`, leaving out what is inside `hole`
fn land(v: &mut Vec<V>, i: &mut Vec<u32>, st: f32, ext: f32, hole: f32, tx: f32, tz: f32, ty: f32, hills: f32, trees: bool, c: [f32; 3]) {
    let n = (ext / st) as i32;
    for gx in -n..n { for gz in -n..n {
        let (x, z) = (gx as f32 * st + tx, gz as f32 * st + tz);
        if (x - tx).abs().max((z - tz).abs()) < hole && (x + st - tx).abs().max((z + st - tz).abs()) <= hole { continue; }
        if (x - c[0]).hypot(z - c[1]) > c[2] { continue; }
        let hf = |x: f32, z: f32| (land_h(x + 0.5 * st, z + 0.5 * st, ty, hills) / st.min(2.0)).floor() * st.min(2.0);
        let h = hf(x, z);
        let g = hash(gx, gz) * 0.1 + 0.9;
        let f = forest(x, z);
        let col = if land_h(x, z, ty, hills) < ty - 0.42 * hills { [0.58 * g, 0.55 * g, 0.42 * g] } else { [0.36 * g, 0.55 * g, 0.24 * g] };
        quad(v, i, [x, h, z], [x, h, z + st], [x + st, h, z + st], [x + st, h, z], 1, col, st.min(2.0));
        for (dx, dz) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            let o = hf(x + dx * st, z + dz * st);
            if o < h {
                let (ax, az, bx, bz) = if dx > 0.0 { (x + st, z, x + st, z + st) } else if dx < 0.0 { (x, z + st, x, z) } else if dz > 0.0 { (x + st, z + st, x, z + st) } else { (x, z, x + st, z) };
                quad(v, i, [ax, o - 2.0, az], [bx, o - 2.0, bz], [bx, h, bz], [ax, h, az], 2, [0.5, 0.45, 0.4], st);
            }
        }
        if trees && hash(gx * 7 + 3, gz * 5 - 1) < 0.02 + 0.3 * f.max(0.0) {
            let ht = 6.0 + 5.0 * hash(gx + 9, gz + 4);
            boxy(v, i, [x + 0.5, h, z + 0.5], [x + 1.5, h + ht, z + 1.5], 4, [0.4, 0.3, 0.2]);
            let w = 2.5 + hash(gx + 2, gz) * 1.5;
            boxy(v, i, [x + 1.0 - w, h + ht - 3.0, z + 1.0 - w], [x + 1.0 + w, h + ht + 2.0, z + 1.0 + w], 3, [0.18, 0.4, 0.14]);
        }
    }}
}
#[derive(Default)]
struct Map { w: usize, ground: Vec<i16>, top: Vec<i16>, cls: Vec<u8>, gcl: Vec<u8>, col: Vec<[f32; 3]> }
fn read_map(p: &str) -> Map {
    let b = std::fs::read(p).unwrap();
    let w = i32::from_le_bytes(b[0..4].try_into().unwrap()) as usize;
    let n = w * w;
    let i16s = |o: usize| -> Vec<i16> { (0..n).map(|i| i16::from_le_bytes([b[o + 2 * i], b[o + 2 * i + 1]])).collect() };
    let (o1, o2, o3, o4) = (4, 4 + 2 * n, 4 + 4 * n, 4 + 5 * n);
    let o5 = 4 + 6 * n;
    let col = (0..16).map(|i| [b[o5 + 3 * i] as f32 / 255.0, b[o5 + 3 * i + 1] as f32 / 255.0, b[o5 + 3 * i + 2] as f32 / 255.0]).collect();
    Map { w, ground: i16s(o1), top: i16s(o2), cls: b[o3..o3 + n].to_vec(), gcl: b[o4..o4 + n].to_vec(), col }
}
impl Map {
    fn at(&self, x: i32, z: i32) -> usize { let h = self.w as i32 / 2; (((z + h).clamp(0, self.w as i32 - 1)) as usize) * self.w + ((x + h).clamp(0, self.w as i32 - 1)) as usize }
    fn g(&self, x: i32, z: i32) -> f32 { self.ground[self.at(x, z)] as f32 + 1.0 }
    fn t(&self, x: i32, z: i32) -> f32 { self.top[self.at(x, z)] as f32 + 1.0 }
}
// The real land round (0,0): blocks `st` wide between the squares `hole` and `ext`. Tops, the sides down to the lowest neighbour, what stands on the ground (leaves, trunks) as boxes.
fn map_land(v: &mut Vec<V>, i: &mut Vec<u32>, m: &Map, st: i32, ext: i32, hole: i32, c: [f32; 3]) {
    let n = ext / st;
    let rch = c[2];
    for gx in -n..n { for gz in -n..n {
        let (x, z) = (gx * st, gz * st);
        if x.abs().max(z.abs()) < hole && (x + st).abs().max((z + st).abs()) <= hole { continue; }
        let (xf, zf, s) = (x as f32, z as f32, st as f32);
        if (xf - c[0]).hypot(zf - c[1]) > rch { continue; }
        let idx = m.at(x, z);
        let h = m.g(x, z);
        let k = m.gcl[idx] as usize;
        let n8 = (hash(x, z) * 0.12 + 0.88).min(1.0);
        let c = m.col[k]; let col = [c[0] * n8, c[1] * n8, c[2] * n8];
        let layer = if k == 5 { 5 } else { 1 };
        quad(v, i, [xf, h, zf], [xf, h, zf + s], [xf + s, h, zf + s], [xf + s, h, zf], layer, col, st.min(2) as f32);
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let o = m.g(x + dx * st, z + dz * st);
            if o < h {
                let (ax, az, bx, bz) = if dx > 0 { (xf + s, zf, xf + s, zf + s) } else if dx < 0 { (xf, zf + s, xf, zf) } else if dz > 0 { (xf + s, zf + s, xf, zf + s) } else { (xf, zf, xf + s, zf) };
                let side = if k == 1 { [0.45, 0.36, 0.27] } else { [col[0] * 0.75, col[1] * 0.75, col[2] * 0.75] };
                quad(v, i, [ax, o, az], [bx, o, bz], [bx, h, bz], [ax, h, az], 2, side, st.min(2) as f32);
            }
        }
        let t = m.t(x, z);
        if t > h + 1.5 && (st <= 2 || (gx + gz) % 2 == 0) {
            let tk = m.cls[idx] as usize;
            let c = m.col[tk];
            let cc = [c[0] * n8, c[1] * n8, c[2] * n8];
            let low = (t - 4.0).max(h);
            boxy(v, i, [xf, low, zf], [xf + s, t, zf + s], if tk == 6 { 3 } else { 4 }, cc);
            if hash(x / 8, z / 8) < 0.5 && st == 1 && (x % 8 == 0) && (z % 8 == 0) { boxy(v, i, [xf, h, zf], [xf + 1.0, low, zf + 1.0], 4, [0.35, 0.27, 0.17]); }
        }
    }}
}
// The far land past what the save has: the save's own land mirrored on, so that what fills the far land's ring looks like land and not a flat colour.
fn map_far(v: &mut Vec<V>, i: &mut Vec<u32>, m: &Map, st: i32, ext: i32, hole: i32, c: [f32; 3]) {
    let h = (m.w as i32 / 2 - 2).min(1400);
    let tri = |x: i32| { let p = 4 * h; let y = (x + h).rem_euclid(p); (if y < 2 * h { y } else { p - y }) - h };
    let n = ext / st;
    for gx in -n..n { for gz in -n..n {
        let (x, z) = (gx * st, gz * st);
        if x.abs().max(z.abs()) < hole && (x + st).abs().max((z + st).abs()) <= hole { continue; }
        let (xf, zf, s) = (x as f32, z as f32, st as f32);
        if (xf - c[0]).hypot(zf - c[1]) > c[2] { continue; }
        let idx = m.at(tri(x), tri(z));
        let k = m.gcl[idx] as usize;
        let tall = m.cls[idx] as usize;
        let tree = m.top[idx] as i32 > m.ground[idx] as i32 + 2;
        let col = m.col[if tree { tall } else { k }];
        let hg = m.g(tri(x), tri(z));
        quad(v, i, [xf, hg, zf], [xf, hg, zf + s], [xf + s, hg, zf + s], [xf + s, hg, zf], if k == 5 { 5 } else { 1 }, col, st.min(2) as f32);
    }}
}
fn m4(a: [[f32; 4]; 4], b: [[f32; 4]; 4]) -> [[f32; 4]; 4] {
    let mut o = [[0.0; 4]; 4];
    for c in 0..4 { for r in 0..4 { for k in 0..4 { o[c][r] += a[k][r] * b[c][k]; } } }
    o
}
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (warp, out) = (&args[1], &args[2]);
    let mut groups: Vec<HashMap<String, f32>> = vec![HashMap::new()];
    for a in &args[3..] {
        if a == "--" { groups.push(groups[0].clone()); continue; }
        let (k, v) = a.split_once('=').expect("key=value");
        let n = groups.len() - 1; groups[n].insert(k.to_string(), v.parse().expect("a number"));
    }
    if groups.len() > 1 { groups.remove(0); }
    std::fs::create_dir_all(out).unwrap();
    pollster::block_on(run(warp, out, &groups));
}
const HEAD: &str = r#"
struct G { fog_color: vec4<f32>, sky_color: vec4<f32>, sun: vec4<f32>, fog: vec4<f32>, warp: array<vec4<f32>, 6> }
@group(0) @binding(0) var<uniform> globals: G;
@group(0) @binding(1) var<uniform> vp: mat4x4<f32>;
@group(0) @binding(2) var<uniform> eye: vec4<f32>;
@group(0) @binding(3) var<uniform> shift: vec4<f32>;
struct Warped { pos: vec3<f32>, tint: vec3<f32> }
struct Fragment { home: vec3<f32>, at: vec3<f32>, uv: vec2<f32>, layer: u32, color: vec4<f32>, light: vec2<f32>, cut: f32, copy: u32, front: bool }
struct Painted { color: vec4<f32>, fog: f32 }
fn hsh(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }
fn sprite(uv: vec2<f32>, layer: u32) -> vec4<f32> {
    let c = floor(uv * 8.0);
    let n = hsh(c + f32(layer));
    let g = abs(fract(uv) - 0.5);
    return vec4<f32>(vec3<f32>(0.84 + 0.3 * n) * (1.0 - 0.14 * step(0.47, max(g.x, g.y))), 1.0);
}
"#;
const TAIL: &str = r#"
struct VO { @builtin(position) clip: vec4<f32>, @location(0) home: vec3<f32>, @location(1) at: vec3<f32>, @location(2) uv: vec2<f32>, @location(3) @interpolate(flat) layer: u32, @location(4) col: vec3<f32>, @location(5) @interpolate(flat) copy: u32, @location(6) cut: f32 }
@vertex fn vs(@location(0) p: vec3<f32>, @location(1) uv: vec2<f32>, @location(2) layer: u32, @location(3) c: vec3<f32>, @builtin(instance_index) copy: u32) -> VO {
    let home = p - eye.xyz;
    let w = world_warp(home, copy);
    var o: VO;
    o.clip = vp * vec4<f32>(w.pos - shift.xyz, 1.0);
    o.home = home; o.at = w.pos; o.uv = uv; o.layer = layer; o.col = c * max(w.tint, vec3<f32>(0.0)); o.copy = copy;
    o.cut = select(0.0, 1.0, w.tint.x < 0.0);
    return o;
}
@fragment fn fs(i: VO, @builtin(front_facing) front: bool) -> @location(0) vec4<f32> {
    let p = world_fragment(Fragment(i.home, i.at, i.uv, i.layer, vec4<f32>(i.col, 1.0), vec2<f32>(15.0, 15.0), i.cut, i.copy, front));
    if (p.color.a < 0.5) { discard; }
    let d = length(i.at);
    let fogged = mix(globals.sky_color.rgb, p.color.rgb, exp(-d / 2600.0));
    return vec4<f32>(mix(p.color.rgb, fogged, p.fog), 1.0);
}
@group(1) @binding(0) var<storage, read_write> dumpo: array<vec4<f32>>;
@group(1) @binding(1) var<uniform> dumpn: vec4<u32>;
@group(1) @binding(2) var<storage, read> dumpi: array<vec4<f32>>;
@compute @workgroup_size(64) fn dump(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= dumpn.x) { return; }
    let p = dumpi[id.x];
    let tg = (globals.warp[0].xyz - globals.warp[4].xyz) - globals.warp[5].xyz;
    let w = world_warp(tg + p.xyz, u32(p.w));
    dumpo[id.x] = vec4<f32>(w.pos - tg, w.tint.x);
}
"#;
async fn run(warp: &str, out: &str, shots: &[HashMap<String, f32>]) {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor { backends: wgpu::Backends::VULKAN, ..wgpu::InstanceDescriptor::new_without_display_handle() });
    let adapters = instance.enumerate_adapters(wgpu::Backends::VULKAN).await;
    let adapter = adapters.into_iter().find(|a| a.get_info().device_type != wgpu::DeviceType::Cpu).expect("gpu");
    let (device, queue) = adapter.request_device(&wgpu::DeviceDescriptor { required_limits: wgpu::Limits { max_buffer_size: 1 << 31, ..Default::default() }, ..Default::default() }).await.unwrap();
    let src = format!("{HEAD}\n{}\n{TAIL}", std::fs::read_to_string(warp).unwrap());
    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: None, source: wgpu::ShaderSource::Wgsl(src.into()) });
    let g = |k: &str, d: f32| *shots[0].get(k).unwrap_or(&d);
    let (w, h) = (g("w", 640.0) as u32, g("h", 360.0) as u32);
    let (tx, ty, tz) = (g("tx", 0.0), g("ty", 65.0), g("tz", 0.0));
    let hills = g("hills", 8.0);
    let mut v = Vec::new(); let mut i = Vec::new();
    // the near land, the one drawn again as the arm's copies (within FW_DISC + a bit)
    let map = std::env::var("WV_MAP").ok().map(|p| read_map(&p));
    // the far land ends in a circle round the camera, as far as the game's LOD Distance puts it (fog=blocks)
    let ec = [g("mx", g("cx", 0.0)), g("mz", g("cz", 170.0)), g("fog", 4096.0)];
    let noland = g("noland", 0.0) > 0.5;
    let mut near = 0;
    if noland {
        quad(&mut v, &mut i, [0.0; 3], [0.0; 3], [0.0; 3], [0.0; 3], 1, [0.0; 3], 1.0);
    } else if let Some(m) = &map {
        map_land(&mut v, &mut i, m, 1, 144, 0, ec);
        near = i.len() as u32;
        map_land(&mut v, &mut i, m, 1, g("fine", 280.0) as i32, 144, ec);
        map_land(&mut v, &mut i, m, 2, 640, g("fine", 280.0) as i32, ec);
        map_land(&mut v, &mut i, m, 8, 1500, 640, ec);
        map_far(&mut v, &mut i, m, 8, 2400, 1500, ec);
        map_far(&mut v, &mut i, m, 16, 20000, 2400, ec);
    } else {
        land(&mut v, &mut i, 2.0, 144.0, 0.0, tx, tz, ty, hills, true, ec);
        near = i.len() as u32;
        land(&mut v, &mut i, 2.0, 640.0, 144.0, tx, tz, ty, hills, true, ec);
        land(&mut v, &mut i, 8.0, 2400.0, 640.0, tx, tz, ty, hills, false, ec);
    }
    eprintln!("land: {} verts, {} tris", v.len(), i.len() / 3);
    let vb = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: bytemuck::cast_slice(&v), usage: wgpu::BufferUsages::VERTEX });
    let ib = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: bytemuck::cast_slice(&i), usage: wgpu::BufferUsages::INDEX });
    let uni = |n: u64| device.create_buffer(&wgpu::BufferDescriptor { label: None, size: n, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
    let (ub, vpb, eb, sb) = (uni(256), uni(64), uni(16), uni(16));
    let bgl_e = |b: u32, s: wgpu::ShaderStages| wgpu::BindGroupLayoutEntry { binding: b, visibility: s, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None };
    let all = wgpu::ShaderStages::VERTEX_FRAGMENT | wgpu::ShaderStages::COMPUTE;
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor { label: None, entries: &[bgl_e(0, all), bgl_e(1, all), bgl_e(2, all), bgl_e(3, all)] });
    let bg = device.create_bind_group(&wgpu::BindGroupDescriptor { label: None, layout: &bgl, entries: &[wgpu::BindGroupEntry { binding: 0, resource: ub.as_entire_binding() }, wgpu::BindGroupEntry { binding: 1, resource: vpb.as_entire_binding() }, wgpu::BindGroupEntry { binding: 2, resource: eb.as_entire_binding() }, wgpu::BindGroupEntry { binding: 3, resource: sb.as_entire_binding() }] });
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&bgl)], immediate_size: 0 });
    let fmt = wgpu::TextureFormat::Rgba8Unorm;
    let pipe = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None, layout: Some(&pl),
        vertex: wgpu::VertexState { module: &module, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[Some(wgpu::VertexBufferLayout { array_stride: std::mem::size_of::<V>() as u64, step_mode: wgpu::VertexStepMode::Vertex, attributes: &wgpu::vertex_attr_array![0 => Float32x3, 1 => Float32x2, 2 => Uint32, 3 => Float32x3] })] },
        primitive: wgpu::PrimitiveState { topology: wgpu::PrimitiveTopology::TriangleList, ..Default::default() },
        depth_stencil: Some(wgpu::DepthStencilState { format: wgpu::TextureFormat::Depth32Float, depth_write_enabled: Some(true), depth_compare: Some(wgpu::CompareFunction::Greater), stencil: Default::default(), bias: Default::default() }),
        multisample: Default::default(),
        fragment: Some(wgpu::FragmentState { module: &module, entry_point: Some("fs"), compilation_options: Default::default(), targets: &[Some(fmt.into())] }),
        multiview_mask: None, cache: None,
    });
    let size = wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 };
    let tex = |f: wgpu::TextureFormat| device.create_texture(&wgpu::TextureDescriptor { label: None, size, mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2, format: f, usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::TEXTURE_BINDING, view_formats: &[] });
    let (color, depth) = (tex(fmt), tex(wgpu::TextureFormat::Depth32Float));
    let (cv, dv) = (color.create_view(&Default::default()), depth.create_view(&Default::default()));
    let pad = (w * 4).div_ceil(256) * 256;
    let rb = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (pad * h) as u64, usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
    // ---- the post pass ----
    let shaders = std::path::Path::new(warp).parent().unwrap();
    let read = |f: &str| std::fs::read_to_string(shaders.join(f)).unwrap();
    let post_src = format!("{}\n{}", include_str!("../../wgslcheck/prelude.wgsl"), passbuild::own_pass(&read("strike.wgsl"), &(passbuild::warp_shared(&read("fold_warp.wgsl")) + &read("fold.wgsl"))));
    // ($WV_SUB: old=>new@@old=>new, a try at the post pass's source, no edit of it)
    let post_src = std::env::var("WV_SUB").map(|t| t.split("@@").fold(post_src.clone(), |a, r| { let (o, n) = r.split_once("=>").unwrap(); assert!(a.contains(o), "{o}"); a.replace(o, n) })).unwrap_or(post_src);
    let post_on = shots.iter().any(|k| k.get("post").copied().unwrap_or(0.0) > 0.5);
    let pmod = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: None, source: wgpu::ShaderSource::Wgsl(post_src.into()) });
    let pdepth = wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Depth, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false }, count: None };
    let pbgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor { label: None, entries: &[
        wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: true }, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false }, count: None },
        pdepth,
        wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
        wgpu::BindGroupLayoutEntry { binding: 3, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::NonFiltering), count: None },
        wgpu::BindGroupLayoutEntry { binding: 4, visibility: wgpu::ShaderStages::VERTEX_FRAGMENT, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None },
        wgpu::BindGroupLayoutEntry { binding: 5, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
    ] });
    let ppl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&pbgl)], immediate_size: 0 });
    let ppipe = post_on.then(|| device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None, layout: Some(&ppl),
        vertex: wgpu::VertexState { module: &pmod, entry_point: Some("horizon_mod_post_vertex"), compilation_options: Default::default(), buffers: &[] },
        primitive: Default::default(), depth_stencil: None, multisample: Default::default(),
        fragment: Some(wgpu::FragmentState { module: &pmod, entry_point: Some("fs_main"), compilation_options: Default::default(), targets: &[Some(fmt.into())] }),
        multiview_mask: None, cache: None,
    }));
    let pub_ = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: 1024, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
    let pdata = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: &[0u8; 16], usage: wgpu::BufferUsages::STORAGE });
    let lin = device.create_sampler(&wgpu::SamplerDescriptor { mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() });
    let near_s = device.create_sampler(&Default::default());
    let pout = tex(fmt);
    let poutv = pout.create_view(&Default::default());
    let dsv = depth.create_view(&wgpu::TextureViewDescriptor { aspect: wgpu::TextureAspect::DepthOnly, ..Default::default() });
    let pbg = device.create_bind_group(&wgpu::BindGroupDescriptor { label: None, layout: &pbgl, entries: &[
        wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&cv) },
        wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&dsv) },
        wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&lin) },
        wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::Sampler(&near_s) },
        wgpu::BindGroupEntry { binding: 4, resource: pub_.as_entire_binding() },
        wgpu::BindGroupEntry { binding: 5, resource: pdata.as_entire_binding() },
    ] });
    let bgl1_ = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor { label: None, entries: &[
        wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: false }, has_dynamic_offset: false, min_binding_size: None }, count: None },
        wgpu::BindGroupLayoutEntry { binding: 1, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None },
        wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::COMPUTE, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None }, count: None },
    ] });
    let pl2 = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&bgl), Some(&bgl1_)], immediate_size: 0 });
    let cpipe = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor { label: None, layout: Some(&pl2), module: &module, entry_point: Some("dump"), compilation_options: Default::default(), cache: None });
    // warp any points through the shader's own world_warp
    let warp_pts = |input: &[[f32; 4]]| -> Vec<[f32; 4]> {
        let count = input.len() as u64;
        let ib2 = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: bytemuck::cast_slice(input), usage: wgpu::BufferUsages::STORAGE });
        let sb2 = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: count * 16, usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC, mapped_at_creation: false });
        let ub2 = device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: bytemuck::cast_slice(&[count as u32, 0, 0, 0]), usage: wgpu::BufferUsages::UNIFORM });
        let rb2 = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: count * 16, usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let bg1 = device.create_bind_group(&wgpu::BindGroupDescriptor { label: None, layout: &bgl1_, entries: &[wgpu::BindGroupEntry { binding: 0, resource: sb2.as_entire_binding() }, wgpu::BindGroupEntry { binding: 1, resource: ub2.as_entire_binding() }, wgpu::BindGroupEntry { binding: 2, resource: ib2.as_entire_binding() }] });
        let mut enc = device.create_command_encoder(&Default::default());
        { let mut p = enc.begin_compute_pass(&Default::default()); p.set_pipeline(&cpipe); p.set_bind_group(0, &bg, &[]); p.set_bind_group(1, &bg1, &[]); p.dispatch_workgroups((count as u32).div_ceil(64), 1, 1); }
        enc.copy_buffer_to_buffer(&sb2, 0, &rb2, 0, count * 16);
        queue.submit([enc.finish()]);
        rb2.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
        let o: Vec<[f32; 4]> = { let d = rb2.slice(..).get_mapped_range().unwrap(); bytemuck::cast_slice(&d).to_vec() };
        rb2.unmap();
        o
    };
    for (n, kv) in shots.iter().enumerate() {
        let g = |k: &str, d: f32| *kv.get(k).unwrap_or(&d);
        let t = g("t", 20.0);
        let cam = [g("cx", 0.0), g("cy", ty + 34.0), g("cz", 170.0)];
        let me = [g("mx", cam[0]), g("my", cam[1]), g("mz", cam[2])];
        let look = [g("lx", tx), g("ly", ty), g("lz", tz)];
        let (el, az) = (g("sunel", 50.0).to_radians(), g("sunaz", 130.0).to_radians());
        let sun = [el.cos() * az.cos(), el.sin(), el.cos() * az.sin(), 0.0];
        let mut u = [[0.0f32; 4]; 10];
        u[0] = [0.5, 0.65, 0.9, 1.0]; u[1] = [0.5, 0.65, 0.9, 1.0]; u[2] = sun; u[3] = [0.0, g("fog", 4096.0), 0.0, g("fog", 4096.0)];
        u[4] = [tx, ty, tz, t];
        u[5] = [0.0, g("p5", 0.0), 0.0, 0.0];
        u[6] = [g("seed", 37.0), 1.0, g("level", -8.0), ty];
        u[7] = [me[0], me[1], me[2], g("flags", 0.0)];
        u[8] = [cam[0], cam[1], cam[2], 0.0];
        u[9] = [0.0, 0.0, 0.0, 1.0];
        queue.write_buffer(&ub, 0, bytemuck::cast_slice(&u));
        if g("pts", 0.0) > 0.5 {
            let b = std::fs::read(std::env::var("WV_PTS").expect("WV_PTS")).unwrap();
            let inp: Vec<[f32; 4]> = bytemuck::pod_collect_to_vec(&b);
            let o = warp_pts(&inp);
            std::fs::write(format!("{out}/pts_{n:03}.bin"), bytemuck::cast_slice(&o)).unwrap();
            continue;
        }
        if g("check", 0.0) > 0.5 {
            let (nr, nm) = (g("nr", 220.0) as u32, g("nm", 420.0) as u32);
            let rmax = g("rmax", 640.0) as u32;
            let polar = |yy: f32| -> Vec<[f32; 4]> {
                let mut o = Vec::with_capacity((nr * nm) as usize);
                for i in 0..nr { for j in 0..nm {
                    let r = (i as f32 + 0.5) / nr as f32 * rmax as f32;
                    let a = j as f32 / nm as f32 * 6.2831853;
                    let (x, z) = (r * a.cos(), r * a.sin());
                    let y = map.as_ref().map(|m| m.g(x.floor() as i32, z.floor() as i32) - ty).unwrap_or(0.0);
                    o.push([x, y + yy, z, 0.0]);
                }}
                o
            };
            let grab = |yy: f32| warp_pts(&polar(yy));
            let pts = grab(0.0);
            let top = grab(8.0);
            let (hits, worst, hitr) = check(&pts, nr as usize, nm as usize, rmax as f32);
            eprintln!("CHECK t={t}: {hits} crossing triangle pairs {worst}");
            metrics(out, t, &pts, &top, nr as usize, nm as usize, rmax as f32, &hitr);
            continue;
        }
        // the view is about the camera (positions are camera-relative)
        let f = { let d = [look[0] - cam[0], look[1] - cam[1], look[2] - cam[2]]; let l = (d[0]*d[0]+d[1]*d[1]+d[2]*d[2]).sqrt(); [d[0]/l, d[1]/l, d[2]/l] };
        let cr = |a: [f32; 3], b: [f32; 3]| [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
        let up0 = if f[1].abs() > 0.98 { [0.0, 0.0, -1.0] } else { [0.0, 1.0, 0.0] };
        let s = { let c = cr(f, up0); let l = (c[0]*c[0]+c[1]*c[1]+c[2]*c[2]).sqrt(); [c[0]/l, c[1]/l, c[2]/l] };
        let up = cr(s, f);
        let view = [[s[0], up[0], -f[0], 0.0], [s[1], up[1], -f[1], 0.0], [s[2], up[2], -f[2], 0.0], [0.0, 0.0, 0.0, 1.0]];
        let fov = g("fov", 70.0).to_radians();
        let ft = 1.0 / (fov * 0.5).tan(); let asp = w as f32 / h as f32; let (zn, zf) = (0.3, 30000.0);
        let proj = [[ft / asp, 0.0, 0.0, 0.0], [0.0, ft, 0.0, 0.0], [0.0, 0.0, zn / (zf - zn), -1.0], [0.0, 0.0, zn * zf / (zf - zn), 0.0]];
        let vpm = m4(proj, view);
        queue.write_buffer(&vpb, 0, bytemuck::cast_slice(&vpm));
        queue.write_buffer(&eb, 0, bytemuck::cast_slice(&[cam[0], cam[1], cam[2], 0.0]));
        queue.write_buffer(&sb, 0, bytemuck::cast_slice(&[g("ox", 0.0), g("oy", 0.0), g("oz", 0.0), 0.0]));
        let mut enc = device.create_command_encoder(&Default::default());
        {
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &cv, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.012, g: 0.012, b: 0.03, a: 1.0 }), store: wgpu::StoreOp::Store } })],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment { view: &dv, depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(0.0), store: wgpu::StoreOp::Store }), stencil_ops: None }),
                timestamp_writes: None, occlusion_query_set: None, multiview_mask: None,
            });
            p.set_pipeline(&pipe); p.set_bind_group(0, &bg, &[]);
            p.set_vertex_buffer(0, vb.slice(..)); p.set_index_buffer(ib.slice(..), wgpu::IndexFormat::Uint32);
            p.draw_indexed(0..i.len() as u32, 0, 0..1);
            if g("copies", 1.0) > 0.5 && (34.45..42.1).contains(&t) { p.draw_indexed(0..near, 0, 1..6); }
        }
        let bench = g("bench", 0.0) as usize;
        if bench > 0 {
            queue.submit([enc.finish()]);
            device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
            let mut ts = Vec::new();
            for _ in 0..bench {
                let t0 = std::time::Instant::now();
                let mut enc = device.create_command_encoder(&Default::default());
                { let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: None,
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &cv, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.012, g: 0.012, b: 0.03, a: 1.0 }), store: wgpu::StoreOp::Store } })],
                    depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment { view: &dv, depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(0.0), store: wgpu::StoreOp::Store }), stencil_ops: None }),
                    timestamp_writes: None, occlusion_query_set: None, multiview_mask: None,
                });
                p.set_pipeline(&pipe); p.set_bind_group(0, &bg, &[]);
                p.set_vertex_buffer(0, vb.slice(..)); p.set_index_buffer(ib.slice(..), wgpu::IndexFormat::Uint32);
                p.draw_indexed(0..i.len() as u32, 0, 0..1); }
                queue.submit([enc.finish()]);
                device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
                ts.push(t0.elapsed().as_secs_f32() * 1000.0);
            }
            ts.sort_by(|a, b| a.total_cmp(b));
            eprintln!("BENCH t={t} {w}x{h}: {:.1} ms (min {:.1})", ts[ts.len() / 2], ts[0]);
            continue;
        }
        let post = g("post", 0.0) > 0.5;
        if post {
            let tp = |m: [[f32; 4]; 4]| { let mut o = [[0.0f32; 4]; 4]; for c in 0..4 { for r in 0..4 { o[c][r] = m[r][c]; } } o };
            let inv_proj = [[asp / ft, 0.0, 0.0, 0.0], [0.0, 1.0 / ft, 0.0, 0.0], [0.0, 0.0, 0.0, (zf - zn) / (zn * zf)], [0.0, 0.0, -1.0, zn / (zf - zn) * (zf - zn) / (zn * zf)]];
            let mut f: Vec<f32> = Vec::new();
            let push = |o: &mut Vec<f32>, m: [[f32; 4]; 4]| for c in m { o.extend_from_slice(&c); };
            push(&mut f, view); push(&mut f, proj); push(&mut f, tp(view)); push(&mut f, inv_proj);
            f.extend_from_slice(&[cam[0], cam[1], cam[2], 1.0]);
            f.extend_from_slice(&[w as f32, h as f32, 1.0 / w as f32, 1.0 / h as f32]);
            f.extend_from_slice(&[0.0, 0.0, 0.25, 0.0]);
            f.extend_from_slice(&[sun[0], sun[1], sun[2], 0.0]);
            f.extend_from_slice(&[0.47, 0.65, 1.0, 1.0]);
            f.extend_from_slice(&[0.7, 0.8, 1.0, 1.0]);
            f.extend_from_slice(&[zn, zf, g("fog", 4096.0), fov]);
            f.extend_from_slice(&[tx, ty, tz, t]);
            f.extend_from_slice(&[tx.floor() + 0.5, tz.floor() + 0.5, 0.0, 14.0]);
            f.extend_from_slice(&[g("seed", 37.0), 1.0, 0.0, ty]);
            f.extend_from_slice(&[me[0], me[1], me[2], 0.0]);
            f.extend_from_slice(&[0.0; 4]);
            push(&mut f, view); push(&mut f, proj);
            f.extend_from_slice(&[cam[0], cam[1], cam[2], 1.0]);
            queue.write_buffer(&pub_, 0, bytemuck::cast_slice(&f));
            let mut p = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &poutv, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store } })],
                depth_stencil_attachment: None, timestamp_writes: None, occlusion_query_set: None, multiview_mask: None,
            });
            p.set_pipeline(ppipe.as_ref().unwrap()); p.set_bind_group(0, &pbg, &[]); p.draw(0..3, 0..1);
        }
        let pbench = g("pbench", 0.0) as usize;
        if post && pbench > 0 {
            queue.submit([std::mem::replace(&mut enc, device.create_command_encoder(&Default::default())).finish()]);
            device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
            let mut ts = Vec::new();
            for _ in 0..pbench {
                let t0 = std::time::Instant::now();
                let mut e2 = device.create_command_encoder(&Default::default());
                { let mut p = e2.begin_render_pass(&wgpu::RenderPassDescriptor { label: None, color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: &poutv, resolve_target: None, depth_slice: None, ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store } })], depth_stencil_attachment: None, timestamp_writes: None, occlusion_query_set: None, multiview_mask: None });
                  p.set_pipeline(ppipe.as_ref().unwrap()); p.set_bind_group(0, &pbg, &[]); p.draw(0..3, 0..1); }
                queue.submit([e2.finish()]);
                device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
                ts.push(t0.elapsed().as_secs_f32() * 1000.0);
            }
            ts.sort_by(|a, b| a.total_cmp(b));
            eprintln!("PBENCH t={t} {w}x{h}: {:.2} ms (min {:.2})", ts[ts.len() / 2], ts[0]);
            continue;
        }
        enc.copy_texture_to_buffer(if post { pout.as_image_copy() } else { color.as_image_copy() }, wgpu::TexelCopyBufferInfo { buffer: &rb, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(pad), rows_per_image: None } }, size);
        queue.submit([enc.finish()]);
        rb.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
        let mut img = Vec::with_capacity((w * h * 4) as usize);
        { let data = rb.slice(..).get_mapped_range().unwrap();
          for y in 0..h { img.extend_from_slice(&data[(y * pad) as usize..(y * pad + w * 4) as usize]); } }
        rb.unmap();
        let f = std::fs::File::create(format!("{out}/{n:03}.png")).unwrap();
        let mut e = png::Encoder::new(std::io::BufWriter::new(f), w, h);
        e.set_color(png::ColorType::Rgba); e.set_depth(png::BitDepth::Eight);
        e.write_header().unwrap().write_image_data(&img).unwrap();
    }
}

type P3 = [f32; 3];
fn sub(a: P3, b: P3) -> P3 { [a[0]-b[0], a[1]-b[1], a[2]-b[2]] }
fn cross(a: P3, b: P3) -> P3 { [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]] }
fn dot(a: P3, b: P3) -> f32 { a[0]*b[0]+a[1]*b[1]+a[2]*b[2] }
// does segment p-q go through triangle a,b,c (Moller-Trumbore), strictly inside
fn seg_tri(p: P3, q: P3, a: P3, b: P3, c: P3) -> bool {
    let d = sub(q, p); let e1 = sub(b, a); let e2 = sub(c, a);
    let h = cross(d, e2); let det = dot(e1, h);
    if det.abs() < 1e-5 { return false; }
    let f = 1.0 / det; let s = sub(p, a);
    let u = f * dot(s, h); if !(0.001..=0.999).contains(&u) { return false; }
    let qv = cross(s, e1); let v = f * dot(d, qv); if v < 0.001 || u + v > 0.999 { return false; }
    let tt = f * dot(e2, qv); (0.001..=0.999).contains(&tt)
}
fn check(pts: &[[f32; 4]], nr: usize, nm: usize, rmax: f32) -> (usize, String, Vec<u32>) {
    let mut hitr = vec![0u32; 32];
    let at = |i: usize, j: usize| { let p = pts[i * nm + (j % nm)]; [p[0], p[1], p[2]] };
    // triangles as (i, j, kind)
    let mut tris = Vec::with_capacity(nr * nm * 2);
    for i in 0..nr - 1 { for j in 0..nm { tris.push((i, j, 0u8)); tris.push((i, j, 1u8)); } }
    let cell = 18.0f32;
    let mut grid: HashMap<(i32, i32, i32), Vec<u32>> = HashMap::new();
    let tv = |t: (usize, usize, u8)| -> [P3; 3] { let (i, j, k) = t; if k == 0 { [at(i, j), at(i + 1, j), at(i + 1, j + 1)] } else { [at(i, j), at(i + 1, j + 1), at(i, j + 1)] } };
    for (n, t) in tris.iter().enumerate() {
        let v = tv(*t);
        let lo = [0, 1, 2].map(|c| v[0][c].min(v[1][c]).min(v[2][c]));
        let hi = [0, 1, 2].map(|c| v[0][c].max(v[1][c]).max(v[2][c]));
        // (a stretched triangle over many cells: only its bounds' first few)
        if (hi[0]-lo[0]).max(hi[1]-lo[1]).max(hi[2]-lo[2]) > 200.0 { continue; }
        for x in (lo[0] / cell).floor() as i32..=(hi[0] / cell).floor() as i32 { for y in (lo[1] / cell).floor() as i32..=(hi[1] / cell).floor() as i32 { for z in (lo[2] / cell).floor() as i32..=(hi[2] / cell).floor() as i32 {
            grid.entry((x, y, z)).or_default().push(n as u32);
        }}}
    }
    let mut seen = std::collections::HashSet::new();
    let mut worst = String::new();
    let mut hits = 0;
    for l in grid.values() {
        for a in 0..l.len() { for b in a + 1..l.len() {
            let (ta, tb) = (l[a], l[b]);
            let (x, y) = (tris[ta as usize], tris[tb as usize]);
            let dj = (x.1 as i32 - y.1 as i32).abs().min(nm as i32 - (x.1 as i32 - y.1 as i32).abs());
            if (x.0 as i32 - y.0 as i32).abs() <= 2 && dj <= 2 { continue; }
            if !seen.insert((ta.min(tb), ta.max(tb))) { continue; }
            let (va, vb) = (tv(x), tv(y));
            let mut cross_ = false;
            for e in 0..3 { if seg_tri(va[e], va[(e + 1) % 3], vb[0], vb[1], vb[2]) || seg_tri(vb[e], vb[(e + 1) % 3], va[0], va[1], va[2]) { cross_ = true; break; } }
            if cross_ {
                hits += 1;
                hitr[((x.0 as f32 + 0.5) / nr as f32 * rmax / rmax * 32.0) as usize % 32] += 1;
                hitr[((y.0 as f32 + 0.5) / nr as f32 * 32.0) as usize % 32] += 1;
                if worst.is_empty() { worst = format!("e.g. r {:.0} a {:.2} with r {:.0} a {:.2}", (x.0 as f32 + 0.5) / nr as f32 * rmax, x.1 as f32 / nm as f32 * 6.283, (y.0 as f32 + 0.5) / nr as f32 * rmax, y.1 as f32 / nm as f32 * 6.283); }
            }
        }}
    }
    (hits, worst, hitr)
}
// One line per radial bin: t, r, relief (how much of 8 blocks of height survive, median, p10, p90), stretch (median, p95 of the worse of the two ways
// a cell is stretched against the other), flipped (share of the cells inside out against their own up), lean (median degrees off the sheet's normal),
// kink (p95 turn between neighbouring cells, degrees), crossings.
fn metrics(out: &str, t: f32, a: &[[f32; 4]], b: &[[f32; 4]], nr: usize, nm: usize, rmax: f32, hitr: &[u32]) {
    use std::io::Write;
    let path = format!("{out}/metrics.csv");
    let fresh = !std::path::Path::new(&path).exists();
    let mut f = std::fs::OpenOptions::new().create(true).append(true).open(&path).unwrap();
    if fresh { writeln!(f, "t,r,relief50,relief10,relief90,stretch50,stretch95,flip,lean50,kink95,cross").unwrap(); }
    let p = |g: &[[f32; 4]], i: usize, j: usize| { let q = g[i * nm + (j % nm)]; [q[0], q[1], q[2]] };
    let len = |v: P3| dot(v, v).sqrt();
    let bins = 32;
    let mut rows: Vec<[Vec<f32>; 5]> = (0..bins).map(|_| [vec![], vec![], vec![], vec![], vec![]]).collect();
    let dr = rmax / nr as f32;
    for i in 1..nr - 1 {
        let r = (i as f32 + 0.5) * dr;
        let k = ((r / rmax * bins as f32) as usize).min(bins - 1);
        let da = 6.2831853 * r / nm as f32;
        for j in 0..nm {
            let (c, e, n) = (p(a, i, j), p(a, i + 1, j), p(a, i, j + 1));
            let (ur, ua) = (sub(e, c), sub(n, c));
            let (sr, sa) = (len(ur) / dr, len(ua) / da);
            let nrm = cross(ua, ur); // up on the flat land
            let up = sub(p(b, i, j), c);
            let rel = len(up) / 8.0;
            let ln = len(nrm).max(1e-6);
            let cosv = dot(up, nrm) / (ln * len(up).max(1e-6));
            let w = p(a, i - 1, j);
            let u0 = sub(c, w);
            let turn = (dot(ur, u0) / (len(ur) * len(u0)).max(1e-6)).clamp(-1.0, 1.0).acos().to_degrees();
            let row = &mut rows[k];
            row[0].push(rel);
            row[1].push(sr.max(sa).max(1e-3) / sr.min(sa).max(1e-3));
            row[2].push(if cosv < -0.05 { 1.0 } else { 0.0 });
            row[3].push(cosv.clamp(-1.0, 1.0).acos().to_degrees());
            row[4].push(turn);
        }
    }
    for k in 0..bins {
        let row = &mut rows[k];
        if row[0].is_empty() { continue; }
        let q = |v: &mut Vec<f32>, f: f32| { v.sort_by(|a, b| a.total_cmp(b)); v[((v.len() - 1) as f32 * f) as usize] };
        let (r50, r10, r90) = (q(&mut row[0], 0.5), q(&mut row[0], 0.1), q(&mut row[0], 0.9));
        let (s50, s95) = (q(&mut row[1], 0.5), q(&mut row[1], 0.95));
        let flip = row[2].iter().sum::<f32>() / row[2].len() as f32;
        let (l50, k95) = (q(&mut row[3], 0.5), q(&mut row[4], 0.95));
        writeln!(f, "{t},{},{r50:.3},{r10:.3},{r90:.3},{s50:.2},{s95:.2},{flip:.4},{l50:.1},{k95:.1},{}", (k as f32 + 0.5) * rmax / bins as f32, hitr[k]).unwrap();
    }
}
