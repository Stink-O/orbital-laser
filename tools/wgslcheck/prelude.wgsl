// Horizon shader pack prelude, api 1 (docs/shader-packs.md): placed before
// every stage's source. Bindings, the Frame uniform, the full-screen vertex
// shader and helpers that hide the renderer's reversed depth.
struct Frame {
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
    inverse_view: mat4x4<f32>,
    inverse_projection: mat4x4<f32>,
    camera_position: vec4<f32>,
    resolution: vec4<f32>,
    time: vec4<f32>,
    sun: vec4<f32>,
    moon: vec4<f32>,
    sky_color: vec4<f32>,
    fog_color: vec4<f32>,
    fog: vec4<f32>,
    weather: vec4<f32>,
    camera_state: vec4<f32>,
    view_params: vec4<f32>,
    dimension: vec4<f32>,
    /// Sixteen floats a mod's post pass is given (capability `render`);
    /// zero in a shader pack's own stages.
    mod_params: array<vec4<f32>, 4>,
}
@group(0) @binding(0) var scene_color: texture_2d<f32>;
@group(0) @binding(1) var scene_depth: texture_depth_2d;
@group(0) @binding(2) var previous: texture_2d<f32>;
@group(0) @binding(3) var linear_sampler: sampler;
@group(0) @binding(4) var nearest_sampler: sampler;
@group(0) @binding(5) var<uniform> frame: Frame;

struct StageIn {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}
@vertex fn horizon_stage_vertex(@builtin(vertex_index) i: u32) -> StageIn {
    let p = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    var out: StageIn;
    out.position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = vec2(p.x, 1.0 - p.y);
    return out;
}

// The world's depth at `uv`: 1 at the near plane, 0 for the sky.
fn depth_at(uv: vec2<f32>) -> f32 {
    return textureSampleLevel(scene_depth, nearest_sampler, uv, 0);
}
fn is_sky(depth: f32) -> bool {
    return depth <= 0.0;
}
// Blocks from the eye along the view axis.
fn linear_depth(depth: f32) -> f32 {
    let near = frame.view_params.x;
    let far = frame.view_params.y;
    return near * far / ((far - near) * depth + near);
}
fn view_position(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let v = frame.inverse_projection * vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    return v.xyz / v.w;
}
// World position relative to the eye (add frame.camera_position.xyz for the
// absolute one).
fn world_offset(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    return (frame.inverse_view * vec4(view_position(uv, depth), 1.0)).xyz;
}
fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return select(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, c <= vec3(0.04045));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return select(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, c <= vec3(0.0031308));
}
