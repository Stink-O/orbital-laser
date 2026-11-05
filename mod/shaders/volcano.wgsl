// Orbital Laser's post pass for the Supervolcano (laser 14; stub).
fn volcano(in: StageIn, stage: u32, up: vec4<f32>, len: f32) -> vec4<f32> {
    let scene = textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);
    return scene;
}
@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return volcano(in, 0u, vec4<f32>(0.0), 0.0);
}
