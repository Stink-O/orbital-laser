// Put before a mod's post pass (capability `render`, docs/mods.md): what the pass is given. The world's picture
// and depth, a uniform describing the frame, a full-screen triangle, and a few helpers. The renderer's depth is
// reversed (1 at the near plane, 0 at the far plane and for the sky); the helpers turn it back into positions.
//
// A pass may be drawn in two stages: with `@fragment fn fs_half` and `@fragment fn fs_join` besides `fs_main`, the
// game draws fs_half into one or two RGBA16F pictures half the width and height (rounded up; its locations 0 and 1),
// then fs_join over the world in place of fs_main. fs_join reads them as bindings 6 and 7, which the pass declares
// itself, so the same source compiles (and runs fs_main) on a game without the stages:
//     @group(0) @binding(6) var half_picture: texture_2d<f32>;
//     @group(0) @binding(7) var half_extra: texture_2d<f32>;
// fs_half may not read them. `frame.resolution` is the world's picture's in both stages.

struct Frame {
    view: mat4x4<f32>,
    projection: mat4x4<f32>,
    inverse_view: mat4x4<f32>,
    inverse_projection: mat4x4<f32>,
    // xyz: where the camera is in the world
    camera_position: vec4<f32>,
    // width, height, 1 / width, 1 / height, of the world's picture in pixels
    resolution: vec4<f32>,
    // seconds since the game started, the time of day (0 sunrise, 0.25 noon), the partial tick
    time: vec4<f32>,
    // xyz: towards the sun, in the world; w: the sun's angle in radians
    sun: vec4<f32>,
    sky_color: vec4<f32>,
    fog_color: vec4<f32>,
    // near plane, far plane, render distance in blocks, vertical field of view in radians
    view_params: vec4<f32>,
    // the sixteen floats the mod sets with render.set-params
    mod_params: array<vec4<f32>, 4>,
}
@group(0) @binding(0) var scene_color: texture_2d<f32>;
@group(0) @binding(1) var scene_depth: texture_depth_2d;
@group(0) @binding(2) var linear_sampler: sampler;
@group(0) @binding(3) var nearest_sampler: sampler;
@group(0) @binding(4) var<uniform> frame: Frame;
// The words the mod gives with render.set-data (one word, 0, until it gives some; bitcast<f32> for floats). Read
// arrayLength(&mod_data) before indexing it.
@group(0) @binding(5) var<storage, read> mod_data: array<u32>;

struct StageIn {
    @builtin(position) position: vec4<f32>,
    // 0,0 at the top left of the picture, 1,1 at the bottom right
    @location(0) uv: vec2<f32>,
}
@vertex fn horizon_mod_post_vertex(@builtin(vertex_index) i: u32) -> StageIn {
    let corner = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    var v: StageIn;
    v.position = vec4<f32>(corner.x * 2.0 - 1.0, corner.y * 2.0 - 1.0, 0.0, 1.0);
    v.uv = vec2<f32>(corner.x, 1.0 - corner.y);
    return v;
}

// The depth at `uv`, as the renderer stores it.
fn depth_at(uv: vec2<f32>) -> f32 {
    return textureSampleLevel(scene_depth, nearest_sampler, uv, 0);
}
fn is_sky(depth: f32) -> bool {
    return depth <= 0.0;
}
// The distance from the eye along the view direction, in blocks.
fn linear_depth(depth: f32) -> f32 {
    let n = frame.view_params.x;
    let f = frame.view_params.y;
    return n * f / (depth * (f - n) + n);
}
// The point under `uv` at `depth`, in view space.
fn view_position(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let ndc = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let p = frame.inverse_projection * ndc;
    return p.xyz / p.w;
}
// The point under `uv` at `depth`, relative to the camera in world axes (add camera_position.xyz for the world).
fn world_offset(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    return (frame.inverse_view * vec4<f32>(view_position(uv, depth), 1.0)).xyz;
}
fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lo = c / 12.92;
    let hi = pow((c + vec3<f32>(0.055)) / 1.055, vec3<f32>(2.4));
    return select(hi, lo, c <= vec3<f32>(0.04045));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    let lo = c * 12.92;
    let hi = 1.055 * pow(c, vec3<f32>(1.0 / 2.4)) - vec3<f32>(0.055);
    return select(hi, lo, c <= vec3<f32>(0.0031308));
}
