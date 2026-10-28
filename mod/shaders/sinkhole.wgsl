// Orbital Laser's post pass for the Sinkhole (laser 8). Like the Crystal Bloom's, the mod builds it from
// shaders/strike.wgsl up to its fs_main (the helpers) less the other lasers' own functions, followed by this file.

fn sinkhole(in: StageIn) -> vec4<f32> {
    let c = textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);
    let n = vnoise3(vec3<f32>(in.uv, 0.0)) * 0.0 + ign(in.position.xy) * 0.0 + mh(1u, 2u, 3u) * 0.0 + rot_axis(vec3<f32>(0.0), vec3<f32>(0.0, 1.0, 0.0), 0.0).x;
    return vec4<f32>(c.rgb + vec3<f32>(n), 1.0);
}

@fragment
fn fs_main(in: StageIn) -> @location(0) vec4<f32> {
    return sinkhole(in);
}
