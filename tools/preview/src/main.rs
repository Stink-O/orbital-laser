//! Renders Orbital Laser's post pass offscreen over a synthetic scene (sky, gently rolling ground, a cloud layer at
//! y 192), so a strike's look can be checked in seconds without the game. Not part of the mod: tools/preview.py runs it.
//!   preview SHADER OUTDIR key=value... [-- key=value...]...
//! The pass (the game's prelude goes before it) is compiled once, then each shot (the keys before the first `--`, then
//! each `--` group's over them) is drawn to OUTDIR/NN.png. Keys: t, laser, cx cy cz (the eye), yaw pitch fov, tx ty tz
//! (the target), lx ly lz (a point to look at, in place of yaw and pitch), mx mz (the player, by default the eye), seed,
//! mode, style, colour, night, clouds, w h (the first shot's for all), frames (timed, the median printed),
//! gpu (part of the adapter's name), flat, hills (the land rolling that high round the target, `hills_h`), vox (blocks
//! from $PREVIEW_VOXELS), crater.
//! The pass's `mod_data` (the mod's `render.set-data`) is read from $PREVIEW_DATA if set: a line `index value` a word,
//! the value a float (its bits) or, with a trailing `u`, a word as it is; one word, 0, otherwise, as in the game.
use std::collections::HashMap;

fn hash(x: i32, z: i32) -> f32 {
    let mut h = (x as u32).wrapping_mul(374761393) ^ (z as u32).wrapping_mul(668265263);
    h = (h ^ (h >> 13)).wrapping_mul(1274126177);
    ((h ^ (h >> 16)) & 0xFFFF) as f32 / 65535.0
}
fn ground_h(x: f32, z: f32) -> f32 {
    64.0 + 3.0 * (x * 0.031).sin() * (z * 0.027).cos() + 6.0 * (x * 0.009 + 1.0).sin() * (z * 0.011).sin()
}
/// With `hills=H`: rolling hills and valleys round the target, H high, the target's ground at `ty` (the Crystal Bloom's
/// pieces come down on slopes; strike/crystal.rs's tests rest them on the same land).
pub fn hills_h(x: f32, z: f32, ty: f32, h: f32) -> f32 {
    ty + h * (0.5 * (x * 0.045 + 0.7).sin() * (z * 0.038).cos() + 0.5 * (x * 0.013 - z * 0.017).sin())
}
/// With `crater=1`, the planet killer's crater dug into it round the target (strike.rs's pk_depth0, smoothly, with the
/// rim thrown up round it), to look at its aftermath against the shape the strike leaves.
fn crater_h(x: f32, z: f32, on: bool) -> f32 {
    let g = ground_h(x, z);
    if !on {
        return g;
    }
    let r = (x - 0.5).hypot(z - 0.5);
    let d = if r < 40.0 {
        123.0
    } else if r < 145.0 {
        60.0 + 20.0 * (145.0 - r) / 105.0
    } else if r < 240.0 {
        let u = (r - 145.0) / 95.0;
        60.0 * (1.0 - u * u)
    } else {
        -15.0 * (240.0 / r).powi(3) * ((340.0 - r) / 70.0).clamp(0.0, 1.0)
    };
    if r < 240.0 { 64.0 - d } else { g - d }
}

/// With `pit=1`, the sinkhole's pit dug into the land where its collapse has reached by time `t` (strike/sinkhole.rs's
/// rim and sh_front, roughly: its phases are not the strike's), 25 deep until it is dug on to bedrock from 16 s.
fn pit_h(x: f32, z: f32, ty: f32, t: f32) -> Option<f32> {
    let (dx, dz) = (x - 0.5, z - 0.5);
    let r = dx.hypot(dz);
    let a = dz.atan2(dx);
    let rim = 112.0 * (1.0 + 0.07 * (3.0 * a + 1.0).sin() + 0.04 * (5.0 * a + 2.0).sin() + 0.025 * (11.0 * a + 3.0).sin());
    let front = if r < 30.0 { 8.6 + 0.9 * r / 30.0 } else { 10.6 + 4.4 * ((r - 30.0) / 82.0).clamp(0.0, 1.4).powf(0.75) };
    if r >= rim || t < front + 0.3 {
        return None;
    }
    let deep = if t < 16.5 { 25.0 } else { 123.0 };
    // (the walls stepped in a few ledges, the floor heaped with rubble)
    let wall = ((rim - r) / 3.0).floor() * 9.0;
    let rub = if deep > 30.0 { 3.0 + 6.0 * hash((x / 5.0).floor() as i32, (z / 5.0).floor() as i32) + 8.0 * (1.0 - r / rim) } else { 0.0 };
    Some(ty - wall.min(deep) .max(6.0).min(deep) + if wall >= deep { rub } else { 0.0 })
}

struct Shot {
    w: u32,
    h: u32,
    color: Vec<u8>,
    depth: Vec<f32>,
    u: Vec<f32>,
    frames: u32,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let shader_path = &args[1];
    let out = &args[2];
    let mut gpu = String::new();
    let mut groups: Vec<HashMap<String, f32>> = vec![HashMap::new()];
    for a in &args[3..] {
        if a == "--" {
            groups.push(groups[0].clone());
            continue;
        }
        let (k, v) = a.split_once('=').expect("key=value");
        if k == "gpu" {
            gpu = v.to_string();
        } else {
            let n = groups.len() - 1;
            groups[n].insert(k.to_string(), v.parse().expect("a number"));
        }
    }
    if groups.len() > 1 {
        groups.remove(0);
    }
    // (the scenes are marched on the CPU: each shot's on a thread of its own)
    let shots: Vec<Shot> = std::thread::scope(|sc| {
        let hs: Vec<_> = groups.iter().map(|g| sc.spawn(move || shot(g))).collect();
        hs.into_iter().map(|h| h.join().unwrap()).collect()
    });
    std::fs::create_dir_all(out).unwrap();
    pollster::block_on(run(shader_path, out, &shots, &gpu));
}

fn shot(kv: &HashMap<String, f32>) -> Shot {
    let g = |k: &str, d: f32| *kv.get(k).unwrap_or(&d);
    let (w, h) = (g("w", 960.0) as u32, g("h", 540.0) as u32);
    let cam = [g("cx", 0.0), g("cy", 70.0), g("cz", 60.0)];
    let (mut yaw, mut pitch) = (g("yaw", -90.0).to_radians(), g("pitch", 20.0).to_radians());
    // (or looking at lx ly lz)
    if kv.contains_key("lx") {
        let d = [g("lx", 0.0) - cam[0], g("ly", 0.0) - cam[1], g("lz", 0.0) - cam[2]];
        yaw = d[2].atan2(d[0]);
        pitch = d[1].atan2((d[0] * d[0] + d[2] * d[2]).sqrt());
    }
    let tgt = [g("tx", 0.5), g("ty", 65.0), g("tz", 0.5)];
    let me = [g("mx", cam[0]), g("mz", cam[2])];
    let time = g("t", 10.0);
    let laser = g("laser", 4.0);
    let frames = g("frames", 1.0) as u32;
    let fov = g("fov", 70.0).to_radians();

    // the camera: forward from yaw (0 = +x, -90 = -z) and pitch (up positive)
    let fwd = [pitch.cos() * yaw.cos(), pitch.sin(), pitch.cos() * yaw.sin()];
    let norm = |v: [f32; 3]| {
        let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
        [v[0] / l, v[1] / l, v[2] / l]
    };
    let cross = |a: [f32; 3], b: [f32; 3]| [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    let right = norm(cross(fwd, [0.0, 1.0, 0.0]));
    let up = cross(right, fwd);
    // view: rows right, up, -forward (column-major for WGSL)
    let view = [
        right[0], up[0], -fwd[0], 0.0, right[1], up[1], -fwd[1], 0.0, right[2], up[2], -fwd[2], 0.0, 0.0, 0.0, 0.0, 1.0,
    ];
    let inv_view = [
        right[0], right[1], right[2], 0.0, up[0], up[1], up[2], 0.0, -fwd[0], -fwd[1], -fwd[2], 0.0, 0.0, 0.0, 0.0, 1.0,
    ];
    let (near, far) = (0.05f32, 4096.0f32);
    let aspect = w as f32 / h as f32;
    let fy = 1.0 / (fov / 2.0).tan();
    let fx = fy / aspect;
    let a = near / (far - near);
    let b = near * far / (far - near);
    // reversed z: depth 1 at the near plane, 0 at the far
    let proj = [fx, 0.0, 0.0, 0.0, 0.0, fy, 0.0, 0.0, 0.0, 0.0, a, -1.0, 0.0, 0.0, b, 0.0];
    let inv_proj = [1.0 / fx, 0.0, 0.0, 0.0, 0.0, 1.0 / fy, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0 / b, 0.0, 0.0, -1.0, a / b];

    // ---- the synthetic scene ----
    // (`flat=1`: the ground level at the target's height; `vox=1`: blocks standing on it, read from the file
    // $PREVIEW_VOXELS, a line `x y z r g b` a block, colours 0-1: what a strike builds, to put beside what its pass draws)
    let flat = g("flat", 0.0) > 0.5;
    let mut vox: std::collections::HashMap<(i32, i32, i32), [f32; 3]> = Default::default();
    if g("vox", 0.0) > 0.5 {
        let text = std::fs::read_to_string(std::env::var("PREVIEW_VOXELS").expect("PREVIEW_VOXELS")).unwrap();
        for l in text.lines() {
            let v: Vec<f32> = l.split_whitespace().map(|x| x.parse().unwrap()).collect();
            if v.len() == 6 {
                vox.insert((v[0] as i32, v[1] as i32, v[2] as i32), [v[3], v[4], v[5]]);
            }
        }
    }
    let (mut vlo, mut vhi) = ([i32::MAX; 3], [i32::MIN; 3]);
    for k in vox.keys() {
        let k = [k.0, k.1, k.2];
        for j in 0..3 {
            vlo[j] = vlo[j].min(k[j]);
            vhi[j] = vhi[j].max(k[j] + 1);
        }
    }
    let hills = g("hills", 0.0);
    let pit = g("pit", 0.0) > 0.5;
    let ground = |x: f32, z: f32, crater: bool| {
        if let Some(h) = pit.then(|| pit_h(x, z, tgt[1], time)).flatten() {
            h
        } else if flat {
            tgt[1]
        } else if hills != 0.0 {
            hills_h(x, z, tgt[1], hills)
        } else {
            crater_h(x, z, crater)
        }
    };
    let night = g("night", 0.0) > 0.5;
    let sun = if night { norm([0.35, -0.6, 0.25]) } else { norm([0.35, 0.8, 0.25]) };
    let nk = if night { 0.08 } else { 1.0 };
    let mut color = vec![0u8; (w * h * 4) as usize];
    let mut depth = vec![0f32; (w * h) as usize];
    let srgb = |c: f32| (c.clamp(0.0, 1.0).powf(1.0 / 2.2) * 255.0) as u8;
    for py in 0..h {
        for px in 0..w {
            let nx = (px as f32 + 0.5) / w as f32 * 2.0 - 1.0;
            let ny = 1.0 - (py as f32 + 0.5) / h as f32 * 2.0;
            let d = norm([
                fwd[0] + right[0] * nx / fx + up[0] * ny / fy,
                fwd[1] + right[1] * nx / fx + up[1] * ny / fy,
                fwd[2] + right[2] * nx / fx + up[2] * ny / fy,
            ]);
            let mut c = {
                let hz = (1.0 - d[1].max(0.0)).powf(3.0);
                [0.25 + 0.45 * hz, 0.42 + 0.4 * hz, 0.85 + 0.12 * hz]
            };
            let mut hit_t = -1.0f32;
            // the ground: march
            if d[1] < 0.2 {
                let mut t = 0.5;
                let crater = g("crater", 0.0) > 0.5;
                let mut prev = cam[1] - ground(cam[0], cam[2], crater);
                while t < 3500.0 {
                    let p = [cam[0] + d[0] * t, cam[1] + d[1] * t, cam[2] + d[2] * t];
                    let s = p[1] - ground(p[0], p[2], crater);
                    if s < 0.0 {
                        let tt = t - s / (s - prev) * -1.0 * 0.0;
                        hit_t = tt;
                        let bx = p[0].floor() as i32;
                        let bz = p[2].floor() as i32;
                        let n = hash(bx, bz);
                        let lit = 0.55 + 0.45 * sun[1];
                        c = [(0.18 + 0.06 * n) * lit, (0.36 + 0.1 * n) * lit, (0.12 + 0.04 * n) * lit];
                        if p[1] < tgt[1] - 1.5 {
                            // (rock laid open: dirt near the top, stone in bands, deepslate deep down)
                            let band = hash((p[1] / 3.0).floor() as i32, 7);
                            let dep = tgt[1] - p[1];
                            let k = if dep < 4.0 { [0.27, 0.19, 0.13] } else if dep > 70.0 { [0.2, 0.2, 0.22] } else { [0.4, 0.39, 0.38] };
                            c = [k[0] * (0.85 + 0.3 * band) * lit, k[1] * (0.85 + 0.3 * band) * lit, k[2] * (0.85 + 0.3 * band) * lit];
                        }
                        let fog = 1.0 - (-t / 1800.0).exp();
                        c = [c[0] + (0.6 - c[0]) * fog, c[1] + (0.72 - c[1]) * fog, c[2] + (0.95 - c[2]) * fog];
                        break;
                    }
                    prev = s;
                    t += (s * 0.5).max(0.2).min(4.0);
                }
            }
            // the blocks: through the grid of them (a DDA), the nearest in front of the ground
            if !vox.is_empty() {
                // (into their box)
                let (mut t0, mut t1) = (0.0f32, 1.0e9f32);
                for j in 0..3 {
                    if d[j].abs() < 1e-9 {
                        if cam[j] < vlo[j] as f32 || cam[j] > vhi[j] as f32 { t1 = -1.0; }
                        continue;
                    }
                    let (a0, a1) = ((vlo[j] as f32 - cam[j]) / d[j], (vhi[j] as f32 - cam[j]) / d[j]);
                    t0 = t0.max(a0.min(a1));
                    t1 = t1.min(a0.max(a1));
                }
                if t0 <= t1 {
                    let t = t0 + 1e-4;
                    let p = [cam[0] + d[0] * t, cam[1] + d[1] * t, cam[2] + d[2] * t];
                    let mut cell = [p[0].floor() as i32, p[1].floor() as i32, p[2].floor() as i32];
                    let step = [d[0].signum() as i32, d[1].signum() as i32, d[2].signum() as i32];
                    let mut tmax = [0.0f32; 3];
                    let mut tdel = [0.0f32; 3];
                    for j in 0..3 {
                        tdel[j] = if d[j].abs() < 1e-9 { 1e30 } else { 1.0 / d[j].abs() };
                        let edge = if step[j] > 0 { cell[j] as f32 + 1.0 } else { cell[j] as f32 };
                        tmax[j] = if d[j].abs() < 1e-9 { 1e30 } else { t + (edge - p[j]) / d[j] };
                    }
                    let mut tc = t;
                    let mut face = 1usize;
                    for _ in 0..600 {
                        if tc > t1 + 1.0 || (hit_t > 0.0 && tc > hit_t) {
                            break;
                        }
                        if let Some(col) = vox.get(&(cell[0], cell[1], cell[2])) {
                            hit_t = tc;
                            // (lit by its face: the top brightest, then the sides)
                            let k = [0.75, 1.0, 0.6][face] * (0.55 + 0.45 * sun[1].max(0.2));
                            c = [col[0] * k, col[1] * k, col[2] * k];
                            break;
                        }
                        let j = if tmax[0] < tmax[1] { if tmax[0] < tmax[2] { 0 } else { 2 } } else if tmax[1] < tmax[2] { 1 } else { 2 };
                        tc = tmax[j];
                        tmax[j] += tdel[j];
                        cell[j] += step[j];
                        face = j;
                    }
                }
            }
            // the clouds: a layer of 12-block cells at 192
            if hit_t < 0.0 && d[1].abs() > 1e-4 && *kv.get("clouds").unwrap_or(&1.0) > 0.5 {
                let t = (192.0 - cam[1]) / d[1];
                if t > 0.0 && t < 2000.0 {
                    let p = [cam[0] + d[0] * t, cam[2] + d[2] * t];
                    let cx = (p[0] / 12.0).floor() as i32;
                    let cz = (p[1] / 12.0).floor() as i32;
                    if hash(cx, cz) > 0.62 {
                        hit_t = t;
                        c = [0.92, 0.93, 0.95];
                    }
                }
            }
            let i = (py * w + px) as usize;
            color[i * 4] = srgb(c[0] * nk);
            color[i * 4 + 1] = srgb(c[1] * nk);
            color[i * 4 + 2] = srgb(c[2] * nk * 1.3);
            color[i * 4 + 3] = 255;
            if hit_t > 0.0 {
                // view-space z of the point is -hit_t * dot(d, fwd)
                let zv = -hit_t * (d[0] * fwd[0] + d[1] * fwd[1] + d[2] * fwd[2]);
                depth[i] = (a * zv + b) / -zv;
            }
        }
    }

    // ---- the frame uniform (the prelude's Frame) ----
    let wing = (me[1] - tgt[2]).atan2(me[0] - tgt[0]);
    let mut u: Vec<f32> = Vec::new();
    u.extend_from_slice(&view);
    u.extend_from_slice(&proj);
    u.extend_from_slice(&inv_view);
    u.extend_from_slice(&inv_proj);
    u.extend_from_slice(&[cam[0], cam[1], cam[2], 1.0]);
    u.extend_from_slice(&[w as f32, h as f32, 1.0 / w as f32, 1.0 / h as f32]);
    u.extend_from_slice(&[time, if night { 0.6 } else { 0.25 }, 0.0, 0.0]);
    u.extend_from_slice(&[sun[0], sun[1], sun[2], 0.0]);
    if night { u.extend_from_slice(&[0.03, 0.04, 0.08, 1.0]); } else { u.extend_from_slice(&[0.47, 0.65, 1.0, 1.0]); }
    u.extend_from_slice(&[0.7, 0.8, 1.0, 1.0]);
    u.extend_from_slice(&[near, far, 512.0, fov]);
    u.extend_from_slice(&[tgt[0], tgt[1], tgt[2], time]);
    u.extend_from_slice(&[tgt[0].floor() + 0.5, tgt[2].floor() + 0.5, wing, laser]);
    u.extend_from_slice(&[g("seed", 37.0), 1.0, 0.0, tgt[1].floor()]);
    // (strike.rs's df_reach)
    let reach = (360.0 - ((me[0] - tgt[0]).powi(2) + (me[1] - tgt[2]).powi(2)).sqrt()).max(40.0);
    u.extend_from_slice(&[g("mode", 0.0), g("style", 0.0), g("reach", reach), g("colour", 0.0)]);

    let _ = nk;
    Shot { w, h, color, depth, u, frames }
}

async fn run(shader_path: &str, out: &str, shots: &[Shot], gpu: &str) {
    let (w, h) = (shots[0].w, shots[0].h);
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor { backends: wgpu::Backends::VULKAN, ..wgpu::InstanceDescriptor::new_without_display_handle() });
    let adapters = instance.enumerate_adapters(wgpu::Backends::VULKAN).await;
    let adapter = adapters.into_iter().find(|a| a.get_info().name.contains(gpu) && a.get_info().device_type != wgpu::DeviceType::Cpu).expect("no such gpu");
    eprintln!("adapter: {}", adapter.get_info().name);
    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor { required_features: wgpu::Features::TIMESTAMP_QUERY, ..Default::default() })
        .await
        .unwrap();
    let prelude = include_str!("../../wgslcheck/prelude.wgsl");
    let src = format!("{prelude}\n{}", std::fs::read_to_string(shader_path).unwrap());
    let t_compile = std::time::Instant::now();
    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: None, source: wgpu::ShaderSource::Wgsl(src.into()) });
    let size = wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 };
    let mk = |format, usage| {
        device.create_texture(&wgpu::TextureDescriptor { label: None, size, mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2, format, usage, view_formats: &[] })
    };
    let scene = mk(wgpu::TextureFormat::Rgba8Unorm, wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST);
    let dsrc = mk(wgpu::TextureFormat::R32Float, wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST);
    let dtex = mk(wgpu::TextureFormat::Depth32Float, wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::RENDER_ATTACHMENT);
    let target = mk(wgpu::TextureFormat::Rgba8Unorm, wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC);

    // depth: written from the R32 texture through frag_depth
    let dshader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(
            r#"
@group(0) @binding(0) var src: texture_2d<f32>;
@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    let p = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    return vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
@fragment fn fs(@builtin(position) pos: vec4<f32>) -> @builtin(frag_depth) f32 {
    return textureLoad(src, vec2<i32>(pos.xy), 0).r;
}"#
            .into(),
        ),
    });
    let dpipe = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None,
        layout: None,
        vertex: wgpu::VertexState { module: &dshader, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[] },
        fragment: Some(wgpu::FragmentState { module: &dshader, entry_point: Some("fs"), compilation_options: Default::default(), targets: &[] }),
        primitive: Default::default(),
        depth_stencil: Some(wgpu::DepthStencilState {
            format: wgpu::TextureFormat::Depth32Float,
            depth_write_enabled: Some(true),
            depth_compare: Some(wgpu::CompareFunction::Always),
            stencil: Default::default(),
            bias: Default::default(),
        }),
        multisample: Default::default(),
        multiview_mask: None,
        cache: None,
    });
    let dbg = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: None,
        layout: &dpipe.get_bind_group_layout(0),
        entries: &[wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&dsrc.create_view(&Default::default())) }],
    });
    let dview = dtex.create_view(&Default::default());
    let ubuf = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (shots[0].u.len() * 4) as u64, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
    let tex_entry = |binding, sample_type| wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Texture { sample_type, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false },
        count: None,
    };
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: None,
        entries: &[
            tex_entry(0, wgpu::TextureSampleType::Float { filterable: true }),
            tex_entry(1, wgpu::TextureSampleType::Depth),
            wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
            wgpu::BindGroupLayoutEntry { binding: 3, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::NonFiltering), count: None },
            wgpu::BindGroupLayoutEntry {
                binding: 4,
                visibility: wgpu::ShaderStages::FRAGMENT | wgpu::ShaderStages::VERTEX,
                ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 5,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Storage { read_only: true }, has_dynamic_offset: false, min_binding_size: None },
                count: None,
            },
        ],
    });
    // (the mod's data, as render.set-data gives it: $PREVIEW_DATA, or the one word 0 the game binds without it)
    let mut words: Vec<u32> = vec![0];
    if let Ok(path) = std::env::var("PREVIEW_DATA") {
        for l in std::fs::read_to_string(path).unwrap().lines() {
            let mut it = l.split_whitespace();
            let (Some(i), Some(v)) = (it.next(), it.next()) else { continue };
            let i: usize = i.parse().unwrap();
            if words.len() <= i {
                words.resize(i + 1, 0);
            }
            words[i] = match v.strip_suffix('u') {
                Some(u) => u.parse().unwrap(),
                None => v.parse::<f32>().unwrap().to_bits(),
            };
        }
    }
    let dbuf = {
        use wgpu::util::DeviceExt;
        device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: None, contents: bytemuck::cast_slice(&words), usage: wgpu::BufferUsages::STORAGE })
    };
    let lin = device.create_sampler(&wgpu::SamplerDescriptor { mag_filter: wgpu::FilterMode::Linear, min_filter: wgpu::FilterMode::Linear, ..Default::default() });
    let nea = device.create_sampler(&Default::default());
    let sview = scene.create_view(&Default::default());
    let bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: None,
        layout: &bgl,
        entries: &[
            wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&sview) },
            wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&dview) },
            wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&lin) },
            wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::Sampler(&nea) },
            wgpu::BindGroupEntry { binding: 4, resource: ubuf.as_entire_binding() },
            wgpu::BindGroupEntry { binding: 5, resource: dbuf.as_entire_binding() },
        ],
    });
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&bgl)], immediate_size: 0 });
    let pipe = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None,
        layout: Some(&pl),
        vertex: wgpu::VertexState { module: &module, entry_point: Some("horizon_mod_post_vertex"), compilation_options: Default::default(), buffers: &[] },
        fragment: Some(wgpu::FragmentState {
            module: &module,
            entry_point: Some("fs_main"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState { format: wgpu::TextureFormat::Rgba8Unorm, blend: None, write_mask: wgpu::ColorWrites::ALL })],
        }),
        primitive: Default::default(),
        depth_stencil: None,
        multisample: Default::default(),
        multiview_mask: None,
        cache: None,
    });
    eprintln!("compile: {:.0} ms", t_compile.elapsed().as_secs_f64() * 1000.0);
    let qs = device.create_query_set(&wgpu::QuerySetDescriptor { label: None, ty: wgpu::QueryType::Timestamp, count: 2 });
    let qbuf = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: 16, usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC, mapped_at_creation: false });
    let qread = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: 16, usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
    let tview = target.create_view(&Default::default());
    let mut warm = shots.iter().any(|s| s.frames > 1);
    for (n, sh) in shots.iter().enumerate() {
    queue.write_texture(scene.as_image_copy(), &sh.color, wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(w * 4), rows_per_image: None }, size);
    queue.write_texture(dsrc.as_image_copy(), bytemuck::cast_slice(&sh.depth), wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(w * 4), rows_per_image: None }, size);
    queue.write_buffer(&ubuf, 0, bytemuck::cast_slice(&sh.u));
    {
        let mut enc = device.create_command_encoder(&Default::default());
        {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &dview,
                    depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(0.0), store: wgpu::StoreOp::Store }),
                    stencil_ops: None,
                }),
                ..Default::default()
            });
            pass.set_pipeline(&dpipe);
            pass.set_bind_group(0, &dbg, &[]);
            pass.draw(0..3, 0..1);
        }
        queue.submit([enc.finish()]);
    }

    let mut times = Vec::new();
    // (timing: the GPU's clocks brought up first, so the first shot's numbers are not a cold card's)
    let draws = sh.frames.max(1) + if warm { 40 } else { 0 };
    warm = false;
    for _ in 0..draws {
        let mut enc = device.create_command_encoder(&Default::default());
        {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &tview,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store },
                })],
                timestamp_writes: Some(wgpu::RenderPassTimestampWrites { query_set: &qs, beginning_of_pass_write_index: Some(0), end_of_pass_write_index: Some(1) }),
                ..Default::default()
            });
            pass.set_pipeline(&pipe);
            pass.set_bind_group(0, &bg, &[]);
            pass.draw(0..3, 0..1);
        }
        enc.resolve_query_set(&qs, 0..2, &qbuf, 0);
        enc.copy_buffer_to_buffer(&qbuf, 0, &qread, 0, 16);
        queue.submit([enc.finish()]);
        qread.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
        let ts: Vec<u64> = bytemuck::cast_slice(&qread.slice(..).get_mapped_range().unwrap()).to_vec();
        qread.unmap();
        times.push((ts[1] - ts[0]) as f64 * queue.get_timestamp_period() as f64 / 1.0e6);
    }
    let keep = times.len() - sh.frames.max(1) as usize;
    let times = &mut times[keep..];
    times.sort_by(|a, b| a.total_cmp(b));
    eprintln!("{n:02}: pass {:.2} ms (median of {})", times[times.len() / 2], times.len());

    let pad = (w * 4).div_ceil(256) * 256;
    let rb = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (pad * h) as u64, usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
    let mut enc = device.create_command_encoder(&Default::default());
    enc.copy_texture_to_buffer(
        target.as_image_copy(),
        wgpu::TexelCopyBufferInfo { buffer: &rb, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(pad), rows_per_image: None } },
        size,
    );
    queue.submit([enc.finish()]);
    rb.slice(..).map_async(wgpu::MapMode::Read, |_| {});
    device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
    let data = rb.slice(..).get_mapped_range().unwrap();
    let mut img = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        img.extend_from_slice(&data[(y * pad) as usize..(y * pad + w * 4) as usize]);
    }
    drop(data);
    rb.unmap();
    let f = std::fs::File::create(format!("{out}/{n:02}.png")).unwrap();
    let mut e = png::Encoder::new(std::io::BufWriter::new(f), w, h);
    e.set_color(png::ColorType::Rgba);
    e.set_depth(png::BitDepth::Eight);
    e.write_header().unwrap().write_image_data(&img).unwrap();
}
}
