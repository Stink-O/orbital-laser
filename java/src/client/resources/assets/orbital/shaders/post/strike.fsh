#version 330
#extension GL_ARB_separate_shader_objects : require
struct Frame {
    mat4x4 view;
    mat4x4 projection;
    mat4x4 inverse_view;
    mat4x4 inverse_projection;
    vec4 camera_position;
    vec4 resolution;
    vec4 time;
    vec4 sun;
    vec4 sky_color;
    vec4 fog_color;
    vec4 view_params;
    vec4 mod_params[4];
};
struct StageIn {
    vec4 position;
    vec2 uv;
};
struct Piece {
    vec3 c;
    vec3 u;
    float k;
    float glow;
    float alive;
    vec4 tide;
    float r;
};
struct BhLens {
    bool on;
    bool captured;
    bool hit;
    vec3 bent;
    float trans;
    vec3 acc;
    float rmin;
    vec3 p;
    vec3 v;
    float w;
};
struct MsFrame {
    vec2 c;
    vec2 ax;
    vec2 sd;
    float y0_;
    float shift;
    float sx;
    float sz;
    float sy;
    float px;
};
struct MsHit {
    float t;
    vec2 q;
    float h;
    int kind;
};
const float RAY_DEPTH = 2e-5;
const float TAU = 6.2831855;
const float T_FIRE = 4.0;
const float PILLAR_R = 40.0;
const float PILLAR_A0_ = 0.5235988;
const float SIGIL_R1_ = 31.0;
const float HOLE_H = 28.0;
const float BH_END = 10.0;
const float BH_RS = 3.6;
const float DISK_IN = 2.6;
const float DISK_OUT = 9.0;
const float LENS_R = 12.0;
const int DEBRIS = 160;
const int MET_N = 72;
const float MET_SPAN = 120.0;
const float BIG_T = 13.5;
const float BIG_R = 16.0;
const float MET_V = 150.0;
const float MET_A = 45.0;
const float MET_ENTRY = 5.0;
const float BIG_V = 260.0;
const float MET_END = 34.0;
const float MS_H = 420.0;
const float MS_ARRIVE = 3.0;
const float MS_SNAP = 0.167;
const float MS_IN = 0.28;
const float MS_WARP = 0.45;
const float MS_BEAM = 8.0;
const float MS_HIT = 8.2;
const float MS_SWEEP0_ = 10.0;
const float MS_SWEEP1_ = 19.0;
const float MS_CUT = 20.0;
const float MS_LEAVE = 23.0;
const float MS_OUT = 0.3;
const float MS_END = 32.0;
const float MS_FAR = 24000.0;
const float MS_COAST = 14.0;
const float MS_SHUTTER = 0.0417;
const float TRENCH_L = 100.0;
const float MS_HL = 560.0;
const float MS_HW = 250.0;
const float MS_CHAMFER = 50.0;
const float MS_TAPER = 220.0;
const float MS_TIP = 70.0;
const float MS_EM_X = 70.0;
const float MS_EYE_R = 46.0;
const float MS_EYE_UP = 18.0;
const float MS_FOCUS = 70.0;
const float MS_TIER_B = 28.0;
const float MS_TIER_C = 56.0;
const float MS_TOP = 150.0;
const vec4 MS_HANGAR = vec4(-290.0, 0.0, 90.0, 100.0);
const float MS_HANGAR_UP = 115.0;
const float CLOUD_Y = 192.0;

uniform sampler2D _group_0_binding_0_fs;

uniform sampler2D _group_0_binding_1_fs;


vec4 orbitalSceneLod(sampler2D s, vec2 uv, float lod) {
    return textureLod(s, vec2(uv.x, 1.0 - uv.y), lod);
}

layout(std140) uniform Frame_block_0Fragment { Frame _group_0_binding_4_fs; };

layout(location = 0) in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

float depth_at(vec2 uv) {
    float _e4 = textureLod(_group_0_binding_1_fs, vec2(uv.x, 1.0 - uv.y), 0.0).r;
    return _e4;
}

float depth_px(ivec2 q_1) {
    vec4 _e7 = _group_0_binding_4_fs.resolution;
    float _e10 = depth_at(((vec2(q_1) + vec2(0.5)) * _e7.zw));
    return _e10;
}

bool is_sky(float depth) {
    return (depth <= 0.0);
}

float linear_depth(float depth_1) {
    float n_2 = _group_0_binding_4_fs.view_params.x;
    float f_9 = _group_0_binding_4_fs.view_params.y;
    return ((n_2 * f_9) / ((depth_1 * (f_9 - n_2)) + n_2));
}

vec3 view_position(vec2 uv_1, float depth_2) {
    vec4 ndc = vec4(((uv_1.x * 2.0) - 1.0), (1.0 - (uv_1.y * 2.0)), depth_2, 1.0);
    mat4x4 _e16 = _group_0_binding_4_fs.inverse_projection;
    vec4 p_20 = (_e16 * ndc);
    return (p_20.xyz / vec3(p_20.w));
}

vec3 world_offset(vec2 uv_2, float depth_3) {
    mat4x4 _e4 = _group_0_binding_4_fs.inverse_view;
    vec3 _e5 = view_position(uv_2, depth_3);
    return (_e4 * vec4(_e5, 1.0)).xyz;
}

float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 srgb_to_linear(vec3 c_1) {
    vec3 lo = (c_1 / vec3(12.92));
    vec3 hi = pow(((c_1 + vec3(0.055)) / vec3(1.055)), vec3(2.4));
    return mix(hi, lo, lessThanEqual(c_1, vec3(0.04045)));
}

vec3 linear_to_srgb(vec3 c_2) {
    vec3 lo_1 = (c_2 * 12.92);
    vec3 hi_1 = ((1.055 * pow(c_2, vec3(0.41666666))) - vec3(0.055));
    return mix(hi_1, lo_1, lessThanEqual(c_2, vec3(0.0031308)));
}

float target_x() {
    float _e4 = _group_0_binding_4_fs.mod_params[0].x;
    return _e4;
}

float target_y() {
    float _e4 = _group_0_binding_4_fs.mod_params[0].y;
    return _e4;
}

float target_z() {
    float _e4 = _group_0_binding_4_fs.mod_params[0].z;
    return _e4;
}

float anchor_x() {
    float _e4 = _group_0_binding_4_fs.mod_params[1].x;
    return _e4;
}

float anchor_z() {
    float _e4 = _group_0_binding_4_fs.mod_params[1].y;
    return _e4;
}

float wing_a() {
    float _e4 = _group_0_binding_4_fs.mod_params[1].z;
    return _e4;
}

float laser() {
    float _e4 = _group_0_binding_4_fs.mod_params[1].w;
    return _e4;
}

float seed_v() {
    float _e4 = _group_0_binding_4_fs.mod_params[2].x;
    return _e4;
}

float intensity_v() {
    float _e4 = _group_0_binding_4_fs.mod_params[2].y;
    return max(_e4, 0.05);
}

float capture() {
    float _e4 = _group_0_binding_4_fs.mod_params[2].z;
    return _e4;
}

float block_y() {
    float _e4 = _group_0_binding_4_fs.mod_params[2].w;
    return _e4;
}

int approach() {
    float _e4 = _group_0_binding_4_fs.mod_params[3].x;
    return int((_e4 + 0.5));
}

vec3 ship_tint(vec3 c_3) {
    mat3x3 m = mat3x3(vec3(0.25, 0.25, 0.25), vec3(0.62, 0.65, 0.68), vec3(0.1, 0.1, 0.1));
    float _e5 = _group_0_binding_4_fs.mod_params[3].w;
    int i_22 = int((_e5 + 0.5));
    if ((i_22 <= 0)) {
        return c_3;
    }
    switch(i_22) {
        case 1: {
            m = mat3x3(vec3(0.2, 0.35, 0.0), vec3(1.0, 0.1, 0.03), vec3(0.0, 0.0, 0.2));
            break;
        }
        case 2: {
            m = mat3x3(vec3(0.2, 0.3, 0.0), vec3(1.0, 0.55, 0.05), vec3(0.0, 0.0, 0.15));
            break;
        }
        case 3: {
            m = mat3x3(vec3(0.1, 0.1, 0.2), vec3(0.12, 0.45, 1.0), vec3(0.0, 0.1, 0.3));
            break;
        }
        case 4: {
            m = mat3x3(vec3(0.2, 0.2, 0.1), vec3(0.7, 0.12, 1.0), vec3(0.0, 0.0, 0.3));
            break;
        }
        default: {
            break;
        }
    }
    mat3x3 _e77 = m;
    return (_e77 * c_3);
}

int arrival_style() {
    float _e4 = _group_0_binding_4_fs.mod_params[3].y;
    return int((_e4 + 0.5));
}

float hash21_(vec2 p) {
    return fract((sin(dot(p, vec2(127.1, 311.7))) * 43758.547));
}

float hash31_(vec3 p_1) {
    return fract((sin(dot(p_1, vec3(127.1, 311.7, 74.7))) * 43758.547));
}

float vnoise(vec2 p_2) {
    vec2 i_23 = floor(p_2);
    vec2 f_10 = fract(p_2);
    vec2 u_7 = ((f_10 * f_10) * (vec2(3.0) - (2.0 * f_10)));
    float _e10 = hash21_(i_23);
    float _e15 = hash21_((i_23 + vec2(1.0, 0.0)));
    float _e20 = hash21_((i_23 + vec2(0.0, 1.0)));
    float _e25 = hash21_((i_23 + vec2(1.0, 1.0)));
    return mix(mix(_e10, _e15, u_7.x), mix(_e20, _e25, u_7.x), u_7.y);
}

float fbm(vec2 p_3) {
    vec2 o_1 = vec2(17.3, 9.1);
    vec2 q1_ = ((p_3 * 2.03) + o_1);
    vec2 q2_ = ((q1_ * 2.03) + o_1);
    vec2 q3_ = ((q2_ * 2.03) + o_1);
    vec2 q4_ = ((q3_ * 2.03) + o_1);
    float _e16 = vnoise(p_3);
    float _e19 = vnoise(q1_);
    float _e23 = vnoise(q2_);
    float _e27 = vnoise(q3_);
    float _e31 = vnoise(q4_);
    return (((((0.5 * _e16) + (0.25 * _e19)) + (0.125 * _e23)) + (0.0625 * _e27)) + (0.03125 * _e31));
}

float vnoise3_(vec3 p_4) {
    vec3 i_24 = floor(p_4);
    vec3 f_11 = fract(p_4);
    vec3 u_8 = ((f_11 * f_11) * (vec3(3.0) - (2.0 * f_11)));
    float _e10 = hash31_(i_24);
    float _e16 = hash31_((i_24 + vec3(1.0, 0.0, 0.0)));
    float a_9 = mix(_e10, _e16, u_8.x);
    float _e24 = hash31_((i_24 + vec3(0.0, 1.0, 0.0)));
    float _e30 = hash31_((i_24 + vec3(1.0, 1.0, 0.0)));
    float b_9 = mix(_e24, _e30, u_8.x);
    float _e38 = hash31_((i_24 + vec3(0.0, 0.0, 1.0)));
    float _e44 = hash31_((i_24 + vec3(1.0, 0.0, 1.0)));
    float c_12 = mix(_e38, _e44, u_8.x);
    float _e52 = hash31_((i_24 + vec3(0.0, 1.0, 1.0)));
    float _e58 = hash31_((i_24 + vec3(1.0, 1.0, 1.0)));
    float d_5 = mix(_e52, _e58, u_8.x);
    return mix(mix(a_9, b_9, u_8.y), mix(c_12, d_5, u_8.y), u_8.z);
}

float fbm3_(vec3 p_5) {
    vec3 q_9 = ((p_5 * 2.07) + vec3(5.1, 1.3, 7.7));
    vec3 r_5 = ((q_9 * 2.11) + vec3(2.9, 8.3, 4.1));
    float _e15 = vnoise3_(p_5);
    float _e18 = vnoise3_(q_9);
    float _e22 = vnoise3_(r_5);
    return (((0.55 * _e15) + (0.3 * _e18)) + (0.15 * _e22));
}

uint pcg(uint x) {
    uint s_3 = ((x * 747796405u) + 2891336453u);
    uint w_4 = (((s_3 >> ((s_3 >> 28u) + 4u)) ^ s_3) * 277803737u);
    return ((w_4 >> 22u) ^ w_4);
}

float fh21_(vec2 p_6) {
    uvec2 q_10 = uvec2(ivec2(floor(p_6)));
    uint _e6 = pcg(q_10.y);
    uint _e8 = pcg((q_10.x ^ _e6));
    return (float(_e8) * 2.3283064e-10);
}

float fh31_(vec3 p_7) {
    uvec3 q_11 = uvec3(ivec3(floor(p_7)));
    uint _e7 = pcg(q_11.z);
    uint _e9 = pcg((q_11.y ^ _e7));
    uint _e11 = pcg((q_11.x ^ _e9));
    return (float(_e11) * 2.3283064e-10);
}

float fvnoise(vec2 p_8) {
    vec2 i_25 = floor(p_8);
    vec2 f_12 = fract(p_8);
    vec2 u_9 = ((f_12 * f_12) * (vec2(3.0) - (2.0 * f_12)));
    float _e10 = fh21_(i_25);
    float _e15 = fh21_((i_25 + vec2(1.0, 0.0)));
    float _e22 = fh21_((i_25 + vec2(0.0, 1.0)));
    float _e27 = fh21_((i_25 + vec2(1.0, 1.0)));
    return mix(mix(_e10, _e15, u_9.x), mix(_e22, _e27, u_9.x), u_9.y);
}

float ffbm(vec2 p_9) {
    float _e1 = fvnoise(p_9);
    float _e10 = fvnoise(((p_9 * 2.03) + vec2(17.3, 9.1)));
    float _e20 = fvnoise(((p_9 * 4.1) + vec2(3.1, 5.7)));
    return (((0.55 * _e1) + (0.3 * _e10)) + (0.15 * _e20));
}

float fvnoise3_(vec3 p_10) {
    vec3 i_26 = floor(p_10);
    vec3 f_13 = fract(p_10);
    vec3 u_10 = ((f_13 * f_13) * (vec3(3.0) - (2.0 * f_13)));
    float _e10 = fh31_(i_26);
    float _e16 = fh31_((i_26 + vec3(1.0, 0.0, 0.0)));
    float a_10 = mix(_e10, _e16, u_10.x);
    float _e24 = fh31_((i_26 + vec3(0.0, 1.0, 0.0)));
    float _e30 = fh31_((i_26 + vec3(1.0, 1.0, 0.0)));
    float b_10 = mix(_e24, _e30, u_10.x);
    float _e38 = fh31_((i_26 + vec3(0.0, 0.0, 1.0)));
    float _e44 = fh31_((i_26 + vec3(1.0, 0.0, 1.0)));
    float c_13 = mix(_e38, _e44, u_10.x);
    float _e52 = fh31_((i_26 + vec3(0.0, 1.0, 1.0)));
    float _e58 = fh31_((i_26 + vec3(1.0, 1.0, 1.0)));
    float d_6 = mix(_e52, _e58, u_10.x);
    return mix(mix(a_10, b_10, u_10.y), mix(c_13, d_6, u_10.y), u_10.z);
}

float ffbm3_(vec3 p_11) {
    float _e1 = fvnoise3_(p_11);
    float _e11 = fvnoise3_(((p_11 * 2.07) + vec3(5.1, 1.3, 7.7)));
    return ((0.62 * _e1) + (0.38 * _e11));
}

vec3 lava_ramp(float x_1) {
    vec3 c_4 = vec3(0.0);
    float h_1 = clamp(x_1, 0.0, 1.0);
    c_4 = mix(vec3(0.02, 0.0, 0.0), vec3(0.7, 0.05, 0.0), smoothstep(0.0, 0.3, h_1));
    vec3 _e15 = c_4;
    c_4 = mix(_e15, vec3(1.0, 0.38, 0.02), smoothstep(0.25, 0.55, h_1));
    vec3 _e24 = c_4;
    c_4 = mix(_e24, vec3(1.0, 0.85, 0.35), smoothstep(0.5, 0.8, h_1));
    vec3 _e33 = c_4;
    c_4 = mix(_e33, vec3(1.0, 1.0, 1.0), smoothstep(0.8, 1.0, h_1));
    vec3 _e42 = c_4;
    return _e42;
}

vec3 gold_ramp(float x_2) {
    vec3 c_5 = vec3(0.0);
    float h_2 = clamp(x_2, 0.0, 1.0);
    c_5 = mix(vec3(0.12, 0.05, 0.0), vec3(0.85, 0.45, 0.05), smoothstep(0.0, 0.3, h_2));
    vec3 _e15 = c_5;
    c_5 = mix(_e15, vec3(1.0, 0.82, 0.3), smoothstep(0.25, 0.6, h_2));
    vec3 _e24 = c_5;
    c_5 = mix(_e24, vec3(1.0, 0.98, 0.9), smoothstep(0.6, 1.0, h_2));
    vec3 _e33 = c_5;
    return _e33;
}

vec3 plasma_ramp(float x_3) {
    vec3 c_6 = vec3(0.0);
    float h_3 = clamp(x_3, 0.0, 1.0);
    c_6 = mix(vec3(0.0), vec3(0.35, 0.08, 0.6), smoothstep(0.05, 0.3, h_3));
    vec3 _e13 = c_6;
    c_6 = mix(_e13, vec3(0.3, 0.6, 2.2), smoothstep(0.25, 0.55, h_3));
    vec3 _e22 = c_6;
    c_6 = mix(_e22, vec3(1.2, 2.0, 3.0), smoothstep(0.5, 0.8, h_3));
    vec3 _e31 = c_6;
    c_6 = mix(_e31, vec3(4.0, 4.0, 4.2), smoothstep(0.8, 1.0, h_3));
    vec3 _e40 = c_6;
    return _e40;
}

float th_is(float i_8) {
    float _e1 = laser();
    return (1.0 - step(0.5, abs((_e1 - i_8))));
}

vec3 pick2_(vec3 a, vec3 b_2) {
    float _e3 = th_is(0.0);
    float _e6 = th_is(1.0);
    return ((a * _e3) + (b_2 * _e6));
}

vec3 aces(vec3 x_4) {
    return clamp(((x_4 * ((2.51 * x_4) + vec3(0.03))) / ((x_4 * ((2.43 * x_4) + vec3(0.59))) + vec3(0.14))), vec3(0.0), vec3(1.0));
}

vec3 target_pos() {
    vec3 v_2 = vec3(0.0);
    float _e4 = target_x();
    v_2.x = _e4;
    float _e6 = target_y();
    v_2.y = _e6;
    float _e8 = target_z();
    v_2.z = _e8;
    vec3 _e9 = v_2;
    return _e9;
}

vec2 anchor_xz() {
    vec2 v_3 = vec2(0.0);
    float _e4 = anchor_x();
    v_3.x = _e4;
    float _e6 = anchor_z();
    v_3.y = _e6;
    vec2 _e7 = v_3;
    return _e7;
}

vec4 wing_dirs() {
    float _e0 = wing_a();
    float c_14 = cos(_e0);
    float s_4 = sin(_e0);
    return vec4(c_14, s_4, -(s_4), c_14);
}

float now() {
    float _e4 = _group_0_binding_4_fs.mod_params[0].w;
    return _e4;
}

float phase_time() {
    float _e0 = now();
    return _e0;
}

vec3 project_rel(vec3 p_12) {
    mat4x4 _e3 = _group_0_binding_4_fs.projection;
    mat4x4 _e6 = _group_0_binding_4_fs.view;
    vec4 clip = (_e3 * (_e6 * vec4(p_12, 1.0)));
    vec2 ndc_1 = (clip.xy / vec2(max(abs(clip.w), 0.0001)));
    return vec3(((ndc_1.x * 0.5) + 0.5), (0.5 - (ndc_1.y * 0.5)), ((clip.w > 0.0) ? 1.0 : -1.0));
}

float bolt_disp(float len, float u, float seed, float tq) {
    float amp = (len * 0.2);
    float _e10 = vnoise(vec2(((u * 4.0) + seed), tq));
    float n1_ = ((_e10 - 0.5) * 2.0);
    float _e23 = vnoise(vec2(((u * 13.0) + (seed * 3.1)), (tq * 1.7)));
    float n2_1 = ((_e23 - 0.5) * 2.0);
    float _e36 = vnoise(vec2(((u * 41.0) + (seed * 5.3)), (tq * 2.3)));
    float n3_ = ((_e36 - 0.5) * 2.0);
    return ((((n1_ * amp) + ((n2_1 * amp) * 0.38)) + ((n3_ * amp) * 0.12)) * smoothstep(0.0, 0.1, u));
}

vec3 bolt_line(vec2 p_13, vec2 a_1, vec2 b_3, float seed_1, float tq_1, float wid) {
    vec2 ab = (b_3 - a_1);
    float len_1 = max(length(ab), 0.0001);
    vec2 dir_1 = (ab / vec2(len_1));
    vec2 nrm = vec2(-(dir_1.y), dir_1.x);
    vec2 ap = (p_13 - a_1);
    float u_11 = clamp((dot(ap, dir_1) / len_1), 0.0, 1.0);
    float _e23 = bolt_disp(len_1, u_11, seed_1, tq_1);
    float off_2 = (dot(ap, nrm) - _e23);
    float along = (dot(ap, dir_1) - (u_11 * len_1));
    float d_7 = length(vec2(off_2, along));
    float w_5 = (wid * (1.0 - (0.75 * u_11)));
    float core_1 = exp(-(pow((d_7 / w_5), 2.0)));
    float g = (1.0 / (1.0 + pow((d_7 / (w_5 * 3.0)), 2.0)));
    return vec3(core_1, (g * g), u_11);
}

vec2 seg_soft(vec2 p_14, vec2 a_2, vec2 b_4, float w) {
    vec2 ab_1 = (b_4 - a_2);
    float l2_ = max(dot(ab_1, ab_1), 1e-8);
    float u_12 = clamp((dot((p_14 - a_2), ab_1) / l2_), 0.0, 1.0);
    float d_8 = length((p_14 - (a_2 + (ab_1 * u_12))));
    float ww = (w * (1.0 - (0.65 * u_12)));
    return vec2(exp(-(pow((d_8 / ww), 2.0))), (1.0 / (1.0 + pow((d_8 / (ww * 4.0)), 2.0))));
}

float tri_line(float r, float ang, float R, float w_1) {
    float a_11 = (ang - (floor(((ang / 2.0943952) + 0.5)) * 2.0943952));
    float d_9 = ((r * cos(a_11)) - (R * 0.5));
    return (exp(-(pow((d_9 / w_1), 2.0))) * (1.0 - smoothstep((R * 0.98), (R * 1.04), r)));
}

vec3 axis_hit(vec2 c_7, vec2 v2_, float vv, float cam_y, float rdy) {
    float t = 0.0;
    float d = 0.0;
    t = length(c_7);
    d = length(c_7);
    if ((vv > 1e-5)) {
        t = (dot(c_7, v2_) / vv);
        float _e13 = t;
        d = length((c_7 - (v2_ * _e13)));
    }
    float _e17 = t;
    float _e18 = d;
    float _e19 = t;
    return vec3(_e17, _e18, (cam_y + (rdy * _e19)));
}

vec3 bh_sky(vec3 d_1, float seed_2) {
    vec3 q_12 = (d_1 * 140.0);
    vec3 f_14 = (fract(q_12) - vec3(0.5));
    float _e11 = fh31_((floor(q_12) + vec3(seed_2)));
    float star = ((step(0.975, _e11) * exp((-(dot(f_14, f_14)) * 40.0))) * (0.5 + (4.0 * fract((_e11 * 37.0)))));
    vec3 tint = mix(vec3(0.7, 0.8, 1.25), vec3(1.25, 0.9, 0.7), fract((_e11 * 91.0)));
    float _e46 = ffbm3_(((d_1 * 2.6) + vec3((seed_2 * 0.01))));
    float _e54 = ffbm3_(((d_1 * 6.0) - vec3(2.0, 0.0, 1.0)));
    vec3 haze_3 = ((vec3(0.1, 0.02, 0.17) * smoothstep(0.4, 0.85, _e46)) + (vec3(0.02, 0.04, 0.13) * smoothstep(0.5, 0.9, _e54)));
    return ((tint * star) + haze_3);
}

vec3 disk_ramp(float x_5) {
    vec3 c_8 = vec3(0.0);
    float h_4 = clamp(x_5, 0.0, 1.0);
    c_8 = mix(vec3(0.0), vec3(0.7, 0.07, 0.02), smoothstep(0.0, 0.25, h_4));
    vec3 _e13 = c_8;
    c_8 = mix(_e13, vec3(2.4, 0.75, 0.12), smoothstep(0.2, 0.5, h_4));
    vec3 _e22 = c_8;
    c_8 = mix(_e22, vec3(3.4, 2.5, 1.35), smoothstep(0.45, 0.75, h_4));
    vec3 _e31 = c_8;
    c_8 = mix(_e31, vec3(3.2, 3.6, 5.0), smoothstep(0.75, 1.0, h_4));
    vec3 _e40 = c_8;
    return _e40;
}

vec3 bh_scene(vec2 uvs, vec3 dir, float seed_3, float sky_env, float dim) {
    vec4 _e8 = orbitalSceneLod(_group_0_binding_0_fs, vec2(uvs), 0.0);
    vec3 _e10 = srgb_to_linear(_e8.xyz);
    vec3 c_15 = (_e10 * dim);
    float _e12 = depth_at(uvs);
    bool _e13 = is_sky(_e12);
    if (_e13) {
        vec3 _e14 = bh_sky(dir, seed_3);
        return mix(c_15, _e14, (sky_env * 0.94));
    }
    return c_15;
}

float debris_angle(float fi, float seed_4) {
    return (fract(((fi * 0.381966) + (seed_4 * 0.1137))) * TAU);
}

float debris_r0_(float fi_1, float seed_5) {
    return (35.0 + (15.0 * fract(((fi_1 * 0.618034) + (seed_5 * 0.1234)))));
}

float debris_t(float fi_2) {
    return ((0.4 + ((6.0 * fi_2) / 160.0)) + (0.3 * fract((fi_2 * 0.7548777))));
}

bool debris_big(float fi_3, float seed_6) {
    return (fract(((fi_3 * 0.2763932) + (seed_6 * 0.0517))) > 0.78);
}

vec3 rot_axis(vec3 v_4, vec3 a_3, float ang_1) {
    float c_16 = cos(ang_1);
    float s_5 = sin(ang_1);
    return (((v_4 * c_16) + (cross(a_3, v_4) * s_5)) + ((a_3 * dot(a_3, v_4)) * (1.0 - c_16)));
}

float bh_fall(float r0_, float u_1) {
    return (r0_ * pow(max((1.0 - (u_1 * u_1)), 0.0), 0.6667));
}

float bh_tide(float r0_1, float l0_, float r_1, float u_2, float lag) {
    float _e7 = bh_fall((r0_1 + l0_), (u_2 / lag));
    return clamp(((_e7 - r_1) / l0_), 1.0, 6.0);
}

float bh_tide_max(float r0_2, float l0_1, float r_2, float u_3, float lag_1) {
    float rt = ((((r0_2 + l0_1) / r0_2) * r_2) * (1.0 + ((((1.3333 * u_3) * u_3) * (1.0 - (1.0 / lag_1))) / max((1.0 - (u_3 * u_3)), 0.0001))));
    return ((u_3 > 0.97) ? 6.0 : clamp(((rt - r_2) / l0_1), 1.0, 6.0));
}

vec3 bh_redshift(float r_3, float rs) {
    float z_1 = sqrt(clamp((1.0 - (rs / max(r_3, 0.001))), 0.0, 1.0));
    return vec3(pow(z_1, 0.7), pow(z_1, 1.6), pow(z_1, 2.6));
}

vec4 bh_chunk(vec3 c_9, vec3 rd, vec3 u_4, float k, float hs, vec3 ax, float ang_2, vec3 H, float rs_1) {
    bool local_14 = false;
    bool local_15 = false;
    float sk = sqrt(k);
    vec3 ro = -(c_9);
    vec3 ro_s = (((ro - (u_4 * dot(u_4, ro))) * sk) + ((u_4 * dot(u_4, ro)) / vec3(k)));
    vec3 rd_s = (((rd - (u_4 * dot(u_4, rd))) * sk) + ((u_4 * dot(u_4, rd)) / vec3(k)));
    vec3 _e30 = rot_axis(ro_s, ax, -(ang_2));
    vec3 ro_l = (_e30 / vec3(hs));
    vec3 _e34 = rot_axis(rd_s, ax, -(ang_2));
    vec3 rd_l = (_e34 / vec3(hs));
    vec3 inv = (vec3(1.0) / mix(rd_l, vec3(1e-6), lessThan(abs(rd_l), vec3(1e-6))));
    vec3 ta_1 = ((vec3(-1.0) - ro_l) * inv);
    vec3 tb = ((vec3(1.0) - ro_l) * inv);
    vec3 tlo = min(ta_1, tb);
    vec3 thi = max(ta_1, tb);
    float tn = max(max(tlo.x, tlo.y), tlo.z);
    float tf = min(min(thi.x, thi.y), thi.z);
    if (!((tf < tn))) {
        local_14 = (tn < 0.0);
    } else {
        local_14 = true;
    }
    bool _e74 = local_14;
    if (!(_e74)) {
        local_15 = (length(((rd * tn) - H)) < rs_1);
    } else {
        local_15 = true;
    }
    bool _e83 = local_15;
    if (_e83) {
        return vec4(-1.0);
    }
    return vec4(tn, (ro_l + (rd_l * tn)));
}

vec3 bh_chunk_n(vec3 lp, vec3 u_5, float k_1, vec3 ax_1, float ang_3) {
    vec3 nl = vec3(0.0);
    bool local_16 = false;
    vec3 al = abs(lp);
    nl = vec3(0.0, sign(lp.y), 0.0);
    if ((al.x >= al.y)) {
        local_16 = (al.x >= al.z);
    } else {
        local_16 = false;
    }
    bool _e21 = local_16;
    if (_e21) {
        nl = vec3(sign(lp.x), 0.0, 0.0);
    } else {
        if ((al.z >= al.y)) {
            nl = vec3(0.0, 0.0, sign(lp.z));
        }
    }
    vec3 _e35 = nl;
    vec3 _e36 = rot_axis(_e35, ax_1, ang_3);
    return normalize((((_e36 - (u_5 * dot(u_5, _e36))) * sqrt(k_1)) + ((u_5 * dot(u_5, _e36)) / vec3(k_1))));
}

Piece debris_piece(int i_9, float ft, float seed_7, vec3 cam, vec3 tgt, vec3 H_1, vec3 n, float rs_2) {
    Piece pc = Piece(vec3(0.0), vec3(0.0), 0.0, 0.0, 0.0, vec4(0.0), 0.0);
    vec3 c_10 = vec3(0.0);
    float alive = 0.0;
    bool local_17 = false;
    float stretch = 0.0;
    bool local_18 = false;
    bool local_19 = false;
    pc.alive = 0.0;
    pc.k = 1.0;
    pc.glow = 0.0;
    pc.u = vec3(0.0, 1.0, 0.0);
    pc.c = vec3(0.0);
    float fi_9 = float(i_9);
    float _e24 = debris_t(fi_9);
    float s_6 = (min(ft, BH_END) - _e24);
    if ((s_6 <= 0.0)) {
        Piece _e30 = pc;
        return _e30;
    }
    float _e31 = debris_angle(fi_9, seed_7);
    float _e32 = debris_r0_(fi_9, seed_7);
    bool _e33 = debris_big(fi_9, seed_7);
    float _e37 = fh21_(vec2(fi_9, (seed_7 + 5.0)));
    float _e41 = fh21_(vec2(fi_9, (seed_7 + 9.0)));
    float T_in = (2.6 + (1.4 * _e41));
    bool flung = (_e37 < 0.28);
    float u_f = (0.5 + (0.2 * _e41));
    float ub = (s_6 / T_in);
    float l0_2 = (_e33 ? 2.0 : 1.0);
    float lag_2 = (((_e32 + l0_2) / _e32) * sqrt(((_e32 + l0_2) / _e32)));
    float u_13 = min(ub, (flung ? u_f : lag_2));
    vec3 E1_ = normalize((vec3(1.0, 0.0, 0.0) - (n * n.x)));
    vec3 E2_ = normalize(((vec3(0.0, 0.0, 1.0) - (n * n.z)) - (E1_ * dot(vec3(0.0, 0.0, 1.0), E1_))));
    float rsn = max(rs_2, 0.6);
    float _e89 = bh_fall(_e32, u_13);
    float th = (_e31 - (((3.0 + (3.0 * _e37)) * u_13) * u_13));
    float lift = smoothstep(0.0, 0.45, u_13);
    vec2 src = (floor((tgt.xz + (vec2(cos(_e31), sin(_e31)) * _e32))) + (_e33 ? vec2(0.0) : vec2(0.5)));
    float _e113 = block_y();
    float gy = (_e113 + (_e33 ? 0.0 : 0.5));
    vec3 ground = (vec3(src.x, gy, src.y) - cam);
    vec3 ground_r = (vec3((tgt.x - cam.x), (gy - cam.y), (tgt.z - cam.z)) + (vec3(cos(th), 0.0, sin(th)) * _e89));
    vec3 gp = mix(ground, ground_r, smoothstep(0.0, 0.15, u_13));
    vec3 dp = (H_1 + (((E1_ * cos(th)) + (E2_ * sin(th))) * _e89));
    c_10 = (mix(gp, dp, lift) + vec3(0.0, (sin((lift * 3.14159)) * 7.0), 0.0));
    alive = smoothstep(0.0, 0.05, s_6);
    float _e163 = bh_tide_max(_e32, l0_2, _e89, u_13, lag_2);
    if (!(!(flung))) {
        local_17 = (ub < u_f);
    } else {
        local_17 = true;
    }
    bool _e171 = local_17;
    stretch = (_e171 ? -(_e163) : 1.0);
    if (flung) {
        local_18 = (ub > u_f);
    } else {
        local_18 = false;
    }
    bool _e179 = local_18;
    if (_e179) {
        float dt = ((ub - u_f) * T_in);
        vec3 tdir = ((E1_ * sin(th)) - (E2_ * cos(th)));
        vec3 _e187 = c_10;
        c_10 = (_e187 + (((tdir * 65.0) + (n * 16.0)) * dt));
        float _e195 = alive;
        alive = (_e195 * (1.0 - smoothstep(2.5, 4.0, dt)));
        stretch = 1.0;
    } else {
        if (!(flung)) {
            float _e204 = alive;
            alive = (_e204 * (1.0 - step(lag_2, ub)));
        }
    }
    if ((ft > BH_END)) {
        float ef = (ft - BH_END);
        vec3 _e213 = c_10;
        vec3 _e214 = c_10;
        c_10 = (_e213 + ((normalize((_e214 - H_1)) * ef) * 70.0));
        float _e221 = alive;
        alive = (_e221 * (1.0 - smoothstep(1.0, 2.5, ef)));
        stretch = 1.0;
    }
    vec3 _e230 = c_10;
    pc.u = normalize(((_e230 - H_1) + vec3(0.0001)));
    vec3 _e237 = c_10;
    pc.c = _e237;
    float _e239 = stretch;
    pc.k = _e239;
    pc.tide = vec4(_e32, l0_2, u_13, lag_2);
    pc.r = _e89;
    if (flung) {
        local_19 = (ub > u_f);
    } else {
        local_19 = false;
    }
    bool _e253 = local_19;
    pc.glow = ((_e253 ? 0.0 : smoothstep((rsn * 4.0), (rsn * 1.2), _e89)) * float((ft <= BH_END)));
    float _e261 = alive;
    pc.alive = _e261;
    Piece _e262 = pc;
    return _e262;
}

vec3 debris_tex(int kind, vec2 px, bool top, float side_y, float seed_8) {
    bool local_20 = false;
    float _e12 = fh21_((px + vec2((seed_8 * 3.1), (float(kind) * 17.0))));
    float _e18 = fh21_(((px * 1.7) + vec2(5.0, seed_8)));
    switch(kind) {
        case 0: {
            if (!(top)) {
                local_20 = (side_y > 0.8);
            } else {
                local_20 = true;
            }
            bool _e25 = local_20;
            if (_e25) {
                return (vec3(0.33, 0.55, 0.2) * (0.75 + (0.45 * _e12)));
            }
            return (vec3(0.52, 0.36, 0.24) * (0.75 + (0.45 * _e12)));
        }
        case 1: {
            return (vec3(0.52, 0.36, 0.24) * (0.75 + (0.45 * _e12)));
        }
        case 2: {
            return ((vec3(0.5, 0.5, 0.5) * (0.78 + (0.35 * _e12))) * (0.9 + (0.1 * _e18)));
        }
        case 3: {
            return (vec3(0.27, 0.27, 0.3) * (0.75 + (0.4 * _e12)));
        }
        case 4: {
            if (top) {
                float ring = fract((length((px - vec2(7.5))) * 0.35));
                return (mix(vec3(0.68, 0.55, 0.34), vec3(0.5, 0.38, 0.22), step(0.5, ring)) * (0.9 + (0.2 * _e12)));
            }
            float _e105 = hash21_(vec2(px.x, seed_8));
            return ((vec3(0.4, 0.31, 0.19) * (0.7 + (0.5 * _e105))) * (0.9 + (0.2 * _e12)));
        }
        default: {
            return ((vec3(0.2, 0.42, 0.13) * (0.5 + (0.8 * _e12))) * (0.6 + (0.4 * step(0.25, _e18))));
        }
    }
}

BhLens bh_lens(vec3 H_2, float rs_l, vec3 rd_1, vec2 uv2_1, float scene_len, bool sky, vec3 n_1, vec3 e1_, vec3 e2_, float disk_env, float hot, float seed_9, float time, float sky_env_1, float dim_1) {
    BhLens L = BhLens(false, false, false, vec3(0.0), 0.0, vec3(0.0), 0.0, vec3(0.0), vec3(0.0), 0.0);
    bool local_21 = false;
    bool local_22 = false;
    vec3 pp = vec3(0.0);
    vec3 v_5 = vec3(0.0);
    float travel = 0.0;
    float trans_1 = 1.0;
    vec3 acc_1 = vec3(0.0);
    bool captured = false;
    bool hit = false;
    float rmin = 1000000000.0;
    int i_10 = 0;
    bool local_23 = false;
    bool local_24 = false;
    bool local_25 = false;
    bool local_26 = false;
    vec3 bent = vec3(0.0);
    vec3 far = vec3(0.0);
    bool local_27 = false;
    bool local_28 = false;
    bool local_29 = false;
    L.on = false;
    L.captured = false;
    L.hit = false;
    L.bent = vec3(0.0);
    L.trans = 1.0;
    L.acc = vec3(0.0);
    L.rmin = 1000000000.0;
    L.p = vec3(0.0);
    L.v = rd_1;
    L.w = 0.0;
    float infl = (LENS_R * rs_l);
    float tc = dot(H_2, rd_1);
    float b_11 = length((H_2 - (rd_1 * tc)));
    float t0_ = max((tc - infl), 0.0);
    if ((b_11 < infl)) {
        local_21 = ((tc + infl) > 0.0);
    } else {
        local_21 = false;
    }
    bool _e54 = local_21;
    if (_e54) {
        local_22 = (scene_len > t0_);
    } else {
        local_22 = false;
    }
    bool _e59 = local_22;
    if (_e59) {
        L.on = true;
        pp = (((rd_1 * t0_) - H_2) / vec3(rs_l));
        v_5 = rd_1;
        travel = t0_;
        vec3 _e69 = pp;
        vec3 _e70 = v_5;
        vec3 hv = cross(_e69, _e70);
        float h2_ = dot(hv, hv);
        bool loop_init = true;
        while(true) {
            if (!loop_init) {
                int _e281 = i_10;
                i_10 = (_e281 + 1);
            }
            loop_init = false;
            int _e86 = i_10;
            if ((_e86 < 96)) {
            } else {
                break;
            }
            {
                vec3 _e89 = pp;
                float r_6 = length(_e89);
                float _e91 = rmin;
                rmin = min(_e91, r_6);
                if ((r_6 < 1.0)) {
                    captured = true;
                    break;
                }
                if ((r_6 > 12.5)) {
                    vec3 _e100 = pp;
                    vec3 _e101 = v_5;
                    local_23 = (dot(_e100, _e101) > 0.0);
                } else {
                    local_23 = false;
                }
                bool _e106 = local_23;
                if (_e106) {
                    break;
                }
                float dt_1 = clamp(((r_6 - 0.9) * 0.16), 0.03, 1.5);
                vec3 prev_1 = pp;
                float r2_ = (r_6 * r_6);
                vec3 _e116 = v_5;
                vec3 _e119 = pp;
                v_5 = normalize((_e116 - ((((1.5 * h2_) * _e119) / vec3(((r2_ * r2_) * r_6))) * dt_1)));
                vec3 _e128 = pp;
                vec3 _e129 = v_5;
                pp = (_e128 + (_e129 * dt_1));
                float _e132 = travel;
                travel = (_e132 + (dt_1 * rs_l));
                if (!(sky)) {
                    float _e138 = travel;
                    local_24 = (_e138 > scene_len);
                } else {
                    local_24 = false;
                }
                bool _e141 = local_24;
                if (_e141) {
                    hit = true;
                    break;
                }
                float s0_ = dot(prev_1, n_1);
                vec3 _e144 = pp;
                float s1_ = dot(_e144, n_1);
                if ((disk_env > 0.001)) {
                    local_25 = ((s0_ * s1_) < 0.0);
                } else {
                    local_25 = false;
                }
                bool _e154 = local_25;
                if (_e154) {
                    vec3 _e155 = pp;
                    vec3 x_8 = mix(prev_1, _e155, (s0_ / (s0_ - s1_)));
                    float dr = length(x_8);
                    if ((dr > 2.34)) {
                        local_26 = (dr < DISK_OUT);
                    } else {
                        local_26 = false;
                    }
                    bool _e167 = local_26;
                    if (_e167) {
                        vec2 dx = vec2(dot(x_8, e1_), dot(x_8, e2_));
                        float rot = ((-(time) * 5.5) / pow(dr, 1.5));
                        vec2 q_13 = vec2(((dx.x * cos(rot)) - (dx.y * sin(rot))), ((dx.x * sin(rot)) + (dx.y * cos(rot))));
                        float _e197 = fbm(((q_13 * 0.9) + vec2(seed_9, 3.0)));
                        float bands = (0.55 + (0.45 * sin(((dr * 7.0) + (_e197 * 7.0)))));
                        float dens = clamp((bands * (0.35 + (1.1 * _e197))), 0.0, 1.0);
                        float edge = (smoothstep(2.34, 2.9899998, dr) * (1.0 - smoothstep(4.9500003, DISK_OUT, dr)));
                        vec3 tdir_1 = normalize(cross(n_1, x_8));
                        float beta = (0.62 * sqrt((DISK_IN / dr)));
                        vec3 _e234 = v_5;
                        float g_1 = (sqrt((1.0 - (beta * beta))) / (1.0 - (beta * dot(tdir_1, -(_e234)))));
                        float temp = ((((pow((DISK_IN / dr), 0.85) * (0.7 + (0.4 * _e197))) * g_1) * 0.95) * hot);
                        float a_d = (clamp(((dens * edge) * 1.1), 0.0, 1.0) * disk_env);
                        vec3 _e259 = acc_1;
                        float _e260 = trans_1;
                        vec3 _e262 = disk_ramp(temp);
                        acc_1 = (_e259 + ((((_e260 * a_d) * _e262) * min(((g_1 * g_1) * g_1), 4.0)) * 1.6));
                        float _e272 = trans_1;
                        trans_1 = (_e272 * (1.0 - (a_d * 0.92)));
                    }
                }
                float _e278 = trans_1;
                if ((_e278 < 0.02)) {
                    break;
                }
            }
        }
        float _e286 = rmin;
        float w_6 = (1.0 - smoothstep(4.2, 11.4, _e286));
        bool _e293 = captured;
        if (!(_e293)) {
            vec3 _e295 = v_5;
            vec3 dir_b = normalize(mix(rd_1, _e295, w_6));
            vec3 _e298 = pp;
            vec3 _e301 = v_5;
            far = ((H_2 + (_e298 * rs_l)) + (_e301 * 4000.0));
            bool _e306 = hit;
            if (_e306) {
                vec3 _e307 = pp;
                far = (H_2 + (_e307 * rs_l));
            }
            vec3 _e310 = far;
            vec3 _e311 = project_rel(_e310);
            vec2 uvb = mix(uv2_1, _e311.xy, w_6);
            if ((_e311.z > 0.0)) {
                local_27 = all(greaterThan(uvb, vec2(0.001)));
            } else {
                local_27 = false;
            }
            bool _e324 = local_27;
            if (_e324) {
                local_28 = all(lessThan(uvb, vec2(0.999)));
            } else {
                local_28 = false;
            }
            bool on = local_28;
            if (!(on)) {
                local_29 = (w_6 < 0.01);
            } else {
                local_29 = true;
            }
            bool _e339 = local_29;
            if (_e339) {
                vec3 _e345 = bh_scene(clamp(uvb, vec2(0.001), vec2(0.999)), dir_b, seed_9, sky_env_1, dim_1);
                bent = _e345;
            } else {
                if ((dir_b.y > -0.03)) {
                    vec3 _e349 = bh_sky(dir_b, seed_9);
                    bent = ((_e349 * sky_env_1) + (vec3(0.03, 0.025, 0.04) * (1.0 - sky_env_1)));
                } else {
                    bent = (vec3(0.02, 0.016, 0.022) * dim_1);
                }
            }
        }
        bool _e365 = captured;
        L.captured = _e365;
        bool _e367 = hit;
        L.hit = _e367;
        vec3 _e369 = bent;
        L.bent = _e369;
        float _e371 = trans_1;
        L.trans = _e371;
        vec3 _e373 = acc_1;
        L.acc = _e373;
        float _e375 = rmin;
        L.rmin = _e375;
        vec3 _e377 = pp;
        L.p = (H_2 + (_e377 * rs_l));
        vec3 _e381 = v_5;
        L.v = _e381;
        L.w = w_6;
    }
    BhLens _e383 = L;
    return _e383;
}

vec3 ray_seg(vec3 rd_2, vec3 a_4, vec3 b_5) {
    float s = 0.0;
    vec3 ab_2 = (b_5 - a_4);
    float l2_1 = max(dot(ab_2, ab_2), 1e-6);
    float rab = dot(rd_2, ab_2);
    float den = (l2_1 - (rab * rab));
    s = clamp(((den > 1e-6) ? (((rab * dot(rd_2, a_4)) - dot(a_4, ab_2)) / den) : 0.0), 0.0, 1.0);
    float _e23 = s;
    float t_4 = max(dot(rd_2, (a_4 + (ab_2 * _e23))), 0.0);
    s = clamp((dot(((rd_2 * t_4) - a_4), ab_2) / l2_1), 0.0, 1.0);
    float _e37 = s;
    float _e42 = s;
    return vec3(length(((rd_2 * t_4) - (a_4 + (ab_2 * _e37)))), t_4, _e42);
}

vec4 singularity(StageIn in_1) {
    bool local_30 = false;
    vec2 rdir = vec2(0.0);
    vec3 col_1 = vec3(0.0);
    vec3 add_1 = vec3(0.0);
    bool swallowed = false;
    float ret_1 = 0.0;
    bool local_31 = false;
    bool local_32 = false;
    bool local_33 = false;
    vec3 jb = vec3(0.0);
    float best = 0.0;
    vec3 dcol = vec3(0.0);
    bool found = false;
    int i_11 = 0;
    bool local_34 = false;
    bool local_35 = false;
    bool local_36 = false;
    bool local_37 = false;
    bool local_38 = false;
    vec2 fuv = vec2(0.0);
    bool top_1 = false;
    bool local_39 = false;
    vec3 cc = vec3(0.0);
    bool local_40 = false;
    bool local_41 = false;
    vec3 outc_1 = vec3(0.0);
    vec3 srgb = vec3(0.0);
    vec2 uv_4 = in_1.uv;
    float _e5 = _group_0_binding_4_fs.resolution.x;
    float _e9 = _group_0_binding_4_fs.resolution.y;
    float aspect = (_e5 / _e9);
    float _e11 = now();
    vec4 _e14 = _group_0_binding_4_fs.camera_position;
    vec3 cam_6 = _e14.xyz;
    vec3 _e16 = target_pos();
    vec3 crel = (_e16 - cam_6);
    float _e18 = intensity_v();
    float _e19 = seed_v();
    float charging = ((_e11 < T_FIRE) ? clamp((_e11 / T_FIRE), 0.0, 1.0) : 0.0);
    float fire_t = (_e11 - T_FIRE);
    bool fired = (fire_t > 0.0);
    float ft_1 = max(fire_t, 0.0);
    float left = clamp(((BH_END - ft_1) / 1.6), 0.0, 1.0);
    float life = (fired ? (smoothstep(0.0, 0.07, ft_1) * pow(left, 0.4)) : 0.0);
    float ring_in = (0.12 * exp((-(ft_1) * 6.0)));
    float rs_l_1 = ((BH_RS * life) * ((1.0 + ring_in) + (0.03 * sin((_e11 * 5.0)))));
    float disk_env_1 = ((smoothstep(0.0, 0.12, ft_1) * pow(left, 0.5)) * float(fired));
    float hot_1 = ((1.0 + (1.6 * (1.0 - left))) + (2.2 * exp((-(ft_1) * 2.0))));
    float jet_env = ((smoothstep(0.3, 0.9, ft_1) * (1.0 - smoothstep(8.8, 9.7, ft_1))) * float(fired));
    float ef_1 = (ft_1 - BH_END);
    float evap = ((ef_1 > 0.0) ? exp((-(ef_1) * 2.6)) : 0.0);
    float sky_env_2 = (smoothstep(0.5, 3.8, _e11) * (1.0 - smoothstep(12.0, 20.0, ft_1)));
    float open = (fired ? exp((-(fire_t) * 7.0)) : 0.0);
    float implode = (clamp(((_e11 - 2.7) / 1.3), 0.0, 1.0) * (1.0 - float(fired)));
    float pull_env = (max((charging * charging), life) * (1.0 - smoothstep(BH_END, 13.0, ft_1)));
    float pinch = (smoothstep(3.5, T_FIRE, _e11) * (1.0 - float(fired)));
    vec3 H_3 = (crel + vec3(0.0, 28.0, 0.0));
    vec4 _e149 = wing_dirs();
    vec3 n_3 = normalize((vec3(0.0, 1.0, 0.0) + (0.32 * vec3(_e149.x, 0.0, _e149.y))));
    vec3 e1_1 = vec3(_e149.z, 0.0, _e149.w);
    vec3 e2_1 = cross(n_3, e1_1);
    vec3 _e167 = project_rel(H_3);
    vec3 _e168 = project_rel(crel);
    float _e169 = depth_at(uv_4);
    bool _e170 = is_sky(_e169);
    vec3 _e173 = world_offset(uv_4, (_e170 ? 0.5 : _e169));
    vec3 p0_1 = (cam_6 + _e173);
    float r0_3 = length((p0_1.xz - _e16.xz));
    float ri = (75.0 * pow((1.0 - implode), 1.6));
    float rw = (ft_1 * 58.0);
    if (fired) {
        local_30 = !(_e170);
    } else {
        local_30 = false;
    }
    bool _e214 = local_30;
    float ring_mask = ((!(_e170) ? (exp(-(pow(((r0_3 - ri) / 3.0), 2.0))) * implode) : 0.0) + (_e214 ? (exp(-(pow(((r0_3 - rw) / 3.5), 2.0))) * exp((-(ft_1) * 0.6))) : 0.0));
    rdir = (uv_4 - _e168.xy);
    vec2 _e221 = rdir;
    vec2 _e222 = rdir;
    rdir = (_e221 / vec2(max(length(_e222), 0.0001)));
    vec2 sdv = ((uv_4 - _e167.xy) * vec2(aspect, 1.0));
    float sdist = length(sdv);
    float gw = (((exp(-(pow(((sdist - (ft_1 * 2.4)) / 0.07), 2.0))) * exp((-(ft_1) * 1.6))) * float(fired)) * step(0.0, _e167.z));
    vec2 gw_dir = ((uv_4 - _e167.xy) / vec2(max(sdist, 0.0001)));
    vec2 suck = ((((((_e167.xy - uv_4) * pinch) * pinch) * 0.32) * _e18) * step(0.0, _e167.z));
    vec2 _e271 = rdir;
    vec2 uv2_2 = clamp((((uv_4 - ((((_e271 * ring_mask) * 0.06) * _e18) * _e168.z)) + suck) + (((gw_dir * gw) * 0.045) * _e18)), vec2(0.002), vec2(0.998));
    float _e290 = depth_at(uv2_2);
    bool _e291 = is_sky(_e290);
    vec3 _e294 = world_offset(uv2_2, (_e291 ? 0.5 : _e290));
    float scene_len_3 = (!(_e291) ? length(_e294) : 1000000000.0);
    vec3 _e300 = world_offset(uv2_2, RAY_DEPTH);
    vec3 rd_7 = normalize(_e300);
    vec3 P = (cam_6 + _e294);
    vec2 v2_1 = rd_7.xz;
    float vv_1 = dot(v2_1, v2_1);
    float dim_2 = clamp((1.0 - ((((((0.5 * charging) * charging) + ((0.55 * sky_env_2) * float(fired))) + (0.2 * life)) + (0.5 * pinch)) * _e18)), 0.08, 1.0);
    float ca = ((((((open * 0.02) + (evap * 0.015)) + (ring_mask * 0.006)) + (gw * 0.03)) + ((pinch * pinch) * 0.012)) * _e18);
    vec2 ca_dir = ((uv2_2 - _e167.xy) * ca);
    vec4 _e348 = orbitalSceneLod(_group_0_binding_0_fs, vec2((uv2_2 + ca_dir)), 0.0);
    vec4 _e353 = orbitalSceneLod(_group_0_binding_0_fs, vec2(uv2_2), 0.0);
    vec4 _e359 = orbitalSceneLod(_group_0_binding_0_fs, vec2((uv2_2 - ca_dir)), 0.0);
    vec3 _e362 = srgb_to_linear(vec3(_e348.x, _e353.y, _e359.z));
    col_1 = (_e362 * dim_2);
    if (_e291) {
        vec3 _e365 = col_1;
        vec3 _e366 = bh_sky(rd_7, _e19);
        col_1 = mix(_e365, _e366, (sky_env_2 * 0.94));
    }
    if ((rs_l_1 > 0.02)) {
        BhLens _e377 = bh_lens(H_3, rs_l_1, rd_7, uv2_2, scene_len_3, _e291, n_3, e1_1, e2_1, disk_env_1, hot_1, _e19, _e11, sky_env_2, dim_2);
        if (_e377.on) {
            col_1 = ((_e377.bent * _e377.trans) + (_e377.acc * _e18));
            swallowed = _e377.captured;
            vec3 _e386 = add_1;
            add_1 = (_e386 + (((((vec3(2.6, 1.7, 1.0) * exp(-(pow(((_e377.rmin - 1.52) / 0.05), 2.0)))) * disk_env_1) * (_e377.captured ? 0.0 : 1.0)) * 1.4) * _e18));
        }
    }
    if (!(_e291)) {
        vec2 dxg = (P.xz - _e16.xz);
        float r_7 = length(dxg);
        float ang_4 = atan(dxg.y, dxg.x);
        float dy = (P.y - _e16.y);
        float near_y = (1.0 / (1.0 + ((dy * dy) / 40.0)));
        float lr = log(max(r_7, 0.5));
        float conv = mix(48.0, 4.0, (1.0 - pow((1.0 - charging), 2.5)));
        float arms = pow((0.5 + (0.5 * cos(((4.0 * (ang_4 - (lr * 2.6))) + (_e11 * (2.0 + (6.0 * charging))))))), 6.0);
        ret_1 = (((arms * (1.0 - smoothstep((conv - 6.0), conv, r_7))) * smoothstep(1.0, 4.0, r_7)) * 0.6);
        float _e472 = ret_1;
        ret_1 = (_e472 + (exp(-(pow(((r_7 - conv) / 0.4), 2.0))) * 1.4));
        float _e483 = ret_1;
        ret_1 = (_e483 + (exp(-(pow(((r_7 - 3.0) / 0.25), 2.0))) * charging));
        vec3 _e494 = add_1;
        float _e499 = ret_1;
        add_1 = (_e494 + (((((vec3(0.75, 0.25, 1.4) * _e499) * charging) * near_y) * 1.8) * _e18));
        vec3 _e507 = add_1;
        add_1 = (_e507 + (((((vec3(0.9, 0.5, 1.6) * exp(-(pow(((r_7 - ri) / 1.4), 2.0)))) * implode) * near_y) * 4.0) * _e18));
        float wave = (((exp(-(pow(((r_7 - rw) / 2.6), 2.0))) * exp((-(ft_1) * 0.5))) * float(fired)) * near_y);
        vec3 _e541 = add_1;
        add_1 = (_e541 + (((vec3(1.1, 0.7, 1.8) * wave) * 5.0) * _e18));
        vec3 _e551 = col_1;
        col_1 = (_e551 * (1.0 - ((((exp(-(pow((((r_7 - rw) + 5.0) / 4.0), 2.0))) * exp((-(ft_1) * 0.5))) * float(fired)) * near_y) * 0.6)));
        float sa = (ang_4 - (lr * 1.2));
        float _e589 = fbm(((vec2(cos(sa), sin(sa)) * 9.0) + vec2(((lr * 2.0) + (_e11 * 0.9)), _e19)));
        float streak = ((smoothstep(0.55, 0.8, _e589) * smoothstep(6.0, 14.0, r_7)) * (1.0 - smoothstep(40.0, 85.0, r_7)));
        vec3 _e603 = add_1;
        add_1 = (_e603 + (((((vec3(0.5, 0.15, 0.9) * streak) * life) * near_y) * 0.6) * _e18));
        vec3 lh = ((cam_6 + H_3) - P);
        float ld2_ = dot(lh, lh);
        vec3 light = (((((vec3(1.8, 0.85, 0.4) * disk_env_1) * hot_1) * 700.0) / vec3((ld2_ + 300.0))) + (((vec3(0.8, 0.4, 1.6) * jet_env) * 30.0) / vec3(((r_7 * r_7) + 30.0))));
        vec3 _e643 = col_1;
        vec3 _e644 = col_1;
        col_1 = (_e643 + (((_e644 * light) * _e18) / vec3(max(dim_2, 0.2))));
        if (fired) {
            local_31 = (r_7 < 14.0);
        } else {
            local_31 = false;
        }
        bool _e657 = local_31;
        if (_e657) {
            float bore = (((1.0 - smoothstep(3.0, 8.5, r_7)) * smoothstep(-2.0, 0.0, (dy + 1.5))) * (1.0 - smoothstep(0.0, 8.0, dy)));
            float _e684 = fbm(((dxg * 0.8) + vec2((_e11 * 0.3), (P.y * 0.5))));
            vec3 _e685 = col_1;
            col_1 = (_e685 * (1.0 - ((bore * jet_env) * 0.85)));
            vec3 _e692 = add_1;
            add_1 = (_e692 + ((((mix(vec3(0.5, 0.1, 1.2), vec3(1.6, 1.2, 2.2), _e684) * bore) * jet_env) * 1.6) * _e18));
        }
    }
    vec3 _e711 = axis_hit(crel.xz, v2_1, vv_1, cam_6.y, rd_7.y);
    if ((_e711.x > 0.0)) {
        if (!((jet_env > 0.001))) {
            local_33 = (charging > 0.001);
        } else {
            local_33 = true;
        }
        bool _e725 = local_33;
        local_32 = _e725;
    } else {
        local_32 = false;
    }
    bool _e727 = local_32;
    if (_e727) {
        float dist = _e711.y;
        float y_p = _e711.z;
        vec2 off_3 = ((v2_1 * _e711.x) - crel.xz);
        float ang_b = atan(off_3.y, off_3.x);
        float vis = (!(_e291) ? (1.0 - smoothstep((scene_len_3 - 0.6), (scene_len_3 + 0.6), _e711.x)) : 1.0);
        float hy = (_e16.y + HOLE_H);
        float away = abs((y_p - hy));
        float des = ((exp(-(pow((dist / 0.07), 2.0))) * charging) * smoothstep((_e16.y - 1.0), (_e16.y + 0.5), y_p));
        vec3 _e768 = add_1;
        add_1 = (_e768 + ((((vec3(0.8, 0.2, 1.4) * des) * vis) * 2.5) * (0.7 + (0.3 * sin((_e11 * 30.0))))));
        if ((jet_env > 0.001)) {
            float reach_up = ((ft_1 - 0.3) * 260.0);
            float reach_dn = ((ft_1 - 0.3) * 120.0);
            float up_1 = ((step(hy, y_p) * (1.0 - smoothstep((reach_up - 20.0), reach_up, away))) * exp((-(away) / 500.0)));
            float dn = ((step(y_p, hy) * smoothstep((_e16.y - 1.5), (_e16.y + 0.5), y_p)) * (1.0 - smoothstep((reach_dn - 2.0), reach_dn, away)));
            float from_h = smoothstep((rs_l_1 * 1.1), (rs_l_1 * 2.2), away);
            float rj = (((0.55 + (0.035 * away)) * (1.0 + (0.15 * sin(((_e11 * 17.0) + (away * 0.2)))))) * _e18);
            float core_2 = exp(-(pow((dist / (rj * 0.5)), 2.0)));
            float sheath = exp(-(pow((dist / (rj * 1.8)), 2.0)));
            float halo = (1.0 / (1.0 + pow((dist / (rj * 6.0)), 2.0)));
            float knot = pow((0.5 + (0.5 * sin(((away - (_e11 * 60.0)) * 0.25)))), 8.0);
            float strand = (pow((0.5 + (0.5 * sin((((ang_b * 2.0) + (away * 0.45)) - (_e11 * 14.0))))), 10.0) * exp(-(pow(((dist - (rj * 1.3)) / (rj * 0.5)), 2.0))));
            float _e913 = fbm(vec2((ang_b * 2.0), ((away * 0.08) - (_e11 * 8.0))));
            jb = ((core_2 * vec3(6.0, 5.5, 9.0)) + (((sheath * vec3(1.2, 0.5, 2.8)) * (0.6 + (0.8 * _e913))) * (1.0 + (2.0 * knot))));
            vec3 _e936 = jb;
            jb = ((_e936 + ((halo * vec3(0.5, 0.2, 1.0)) * 0.35)) + (vec3(1.4, 1.0, 2.6) * strand));
            vec3 _e951 = add_1;
            vec3 _e952 = jb;
            add_1 = (_e951 + ((((_e952 * (up_1 + dn)) * from_h) * jet_env) * mix(0.25, 1.0, vis)));
        }
    }
    if (fired) {
        float tch = dot(H_3, rd_7);
        best = scene_len_3;
        bool loop_init_1 = true;
        while(true) {
            if (!loop_init_1) {
                int _e1236 = i_11;
                i_11 = (_e1236 + 1);
            }
            loop_init_1 = false;
            int _e971 = i_11;
            if ((_e971 < DEBRIS)) {
            } else {
                break;
            }
            {
                int _e974 = i_11;
                Piece _e975 = debris_piece(_e974, ft_1, _e19, cam_6, _e16, H_3, n_3, rs_l_1);
                if ((_e975.alive < 0.01)) {
                    continue;
                }
                int _e979 = i_11;
                float fi_10 = float(_e979);
                bool _e981 = debris_big(fi_10, _e19);
                float hs_1 = (_e981 ? 1.0 : 0.5);
                float far_2 = (abs(_e975.k) * hs_1);
                vec3 mid = (_e975.c + (_e975.u * far_2));
                float tq_2 = dot(mid, rd_7);
                float reach = ((hs_1 * 1.8) + far_2);
                if (!((tq_2 < 0.0))) {
                    local_34 = (length((mid - (rd_7 * tq_2))) > reach);
                } else {
                    local_34 = true;
                }
                bool _e1006 = local_34;
                if (!(_e1006)) {
                    float _e1011 = best;
                    local_35 = ((tq_2 - reach) > _e1011);
                } else {
                    local_35 = true;
                }
                bool _e1014 = local_35;
                if (_e1014) {
                    continue;
                }
                float _e1025 = bh_tide(_e975.tide.x, _e975.tide.y, _e975.r, _e975.tide.z, _e975.tide.w);
                float k_9 = ((_e975.k < 0.0) ? _e1025 : _e975.k);
                vec3 cen = (_e975.c + (_e975.u * ((_e975.tide.y * 0.5) * k_9)));
                if ((k_9 > 1.5)) {
                    vec3 _e1049 = ray_seg(rd_7, _e975.c, (_e975.c + (_e975.u * (_e975.tide.y * k_9))));
                    if ((_e1049.x > (hs_1 * 1.8))) {
                        continue;
                    }
                }
                float _e1056 = fh21_(vec2(fi_10, 1.0));
                float _e1059 = fh21_(vec2(fi_10, 2.0));
                float _e1062 = fh21_(vec2(fi_10, 3.0));
                vec3 ax_2 = normalize(((vec3(_e1056, _e1059, _e1062) - vec3(0.5)) + vec3(0.001)));
                float _e1071 = debris_t(fi_10);
                float _e1075 = fh21_(vec2(fi_10, 4.0));
                float spin = (((ft_1 - _e1071) * (1.5 + (3.0 * _e1075))) * (1.0 + (2.0 * _e975.glow)));
                vec4 _e1088 = bh_chunk(cen, rd_7, _e975.u, k_9, hs_1, ax_2, spin, H_3, rs_l_1);
                if (!((_e1088.x < 0.0))) {
                    float _e1096 = best;
                    local_36 = (_e1088.x > _e1096);
                } else {
                    local_36 = true;
                }
                bool _e1099 = local_36;
                if (!(_e1099)) {
                    bool _e1103 = swallowed;
                    if (_e1103) {
                        local_38 = (_e1088.x > tch);
                    } else {
                        local_38 = false;
                    }
                    bool _e1109 = local_38;
                    local_37 = _e1109;
                } else {
                    local_37 = true;
                }
                bool _e1111 = local_37;
                if (_e1111) {
                    continue;
                }
                best = _e1088.x;
                found = true;
                vec3 lp_1 = _e1088.yzw;
                vec3 al_1 = abs(lp_1);
                fuv = lp_1.xz;
                top_1 = (lp_1.y > 0.0);
                if ((al_1.x >= al_1.y)) {
                    local_39 = (al_1.x >= al_1.z);
                } else {
                    local_39 = false;
                }
                bool _e1131 = local_39;
                if (_e1131) {
                    fuv = lp_1.zy;
                    top_1 = false;
                } else {
                    if ((al_1.z >= al_1.y)) {
                        fuv = lp_1.xy;
                        top_1 = false;
                    }
                }
                vec3 _e1140 = bh_chunk_n(lp_1, _e975.u, k_9, ax_2, spin);
                vec2 _e1141 = fuv;
                vec2 px_2 = floor((((((_e1141 * 0.5) + vec2(0.5)) * 16.0) * hs_1) * 2.0));
                float _e1156 = fh21_(vec2(fi_10, (_e19 + 13.0)));
                int kind_1 = min(int((_e1156 * 6.0)), 5);
                bool _e1162 = top_1;
                vec3 _e1165 = debris_tex(kind_1, px_2, _e1162, lp_1.y, (_e19 + fi_10));
                vec3 _e1166 = srgb_to_linear(_e1165);
                float sunl = (0.3 + (0.7 * max(dot(_e1140, vec3(0.28221625, 0.94072086, 0.18814416)), 0.0)));
                float rp = length(((rd_7 * _e1088.x) - H_3));
                float rl = (rp / max(rs_l_1, 0.6));
                vec3 diskl = ((((vec3(2.2, 1.0, 0.45) * max(dot(_e1140, -(_e975.u)), 0.0)) * disk_env_1) * 6.0) / vec3((1.0 + (rl * 0.5))));
                cc = (_e1166 * (vec3((sunl * dim_2)) + diskl));
                vec3 _e1209 = cc;
                cc = ((_e1209 + (((vec3(2.6, 0.7, 0.15) * _e975.glow) * _e975.glow) * 1.5)) + ((vec3(0.6, 0.2, 1.0) * _e975.glow) * 0.3));
                vec3 _e1230 = cc;
                vec3 _e1231 = bh_redshift(rp, rs_l_1);
                cc = ((_e1230 * _e1231) * _e975.alive);
                vec3 _e1235 = cc;
                dcol = _e1235;
            }
        }
        bool _e1239 = found;
        if (_e1239) {
            vec3 _e1240 = dcol;
            col_1 = _e1240;
            vec3 _e1241 = add_1;
            add_1 = (_e1241 * 0.15);
        }
    }
    if ((ef_1 > 0.0)) {
        local_40 = (ef_1 < 8.0);
    } else {
        local_40 = false;
    }
    bool _e1251 = local_40;
    if (_e1251) {
        float tcs = dot(H_3, rd_7);
        float bs = length((H_3 - (rd_7 * max(tcs, 0.0))));
        float re = (ef_1 * 75.0);
        if (!((tcs > 0.0))) {
            local_41 = (length(H_3) < re);
        } else {
            local_41 = true;
        }
        bool _e1283 = local_41;
        float shell = ((exp(-(pow(((bs - re) / (1.5 + (re * 0.06))), 2.0))) * exp((-(ef_1) * 0.7))) * (_e1283 ? 1.0 : 0.0));
        vec3 _e1288 = add_1;
        add_1 = (_e1288 + (((vec3(1.6, 1.2, 2.4) * shell) * 2.5) * _e18));
        vec3 _e1298 = add_1;
        add_1 = (_e1298 + ((((vec3(2.2, 2.0, 2.6) * evap) * evap) * 2.5) * _e18));
        vec3 _e1309 = add_1;
        add_1 = (_e1309 + ((((vec3(1.2, 0.9, 1.8) * exp((-(bs) * 0.08))) * evap) * 3.0) * _e18));
    }
    if ((_e167.z > 0.0)) {
        vec2 dd = ((uv_4 - _e167.xy) * vec2(aspect, 1.0));
        vec3 _e1332 = add_1;
        add_1 = (_e1332 + (((((vec3(2.0, 1.6, 3.0) * pinch) * pinch) * pinch) * (((1.0 / (1.0 + (dot(dd, dd) * 9000.0))) * 6.0) + ((1.0 / (1.0 + (dot(dd, dd) * 400.0))) * 0.6))) * _e18));
        vec3 _e1362 = add_1;
        add_1 = (_e1362 + (((((vec3(1.6, 1.2, 2.4) * exp(-(pow(((sdist - (ft_1 * 2.4)) / 0.02), 2.0)))) * exp((-(ft_1) * 2.2))) * float(fired)) * 0.8) * _e18));
        float bloom = (1.0 / (1.0 + (dot(dd, dd) * 60.0)));
        vec3 _e1395 = add_1;
        add_1 = (_e1395 + (((((vec3(1.2, 0.6, 0.35) * bloom) * disk_env_1) * hot_1) * 0.22) * _e18));
        float streak_1 = (exp((-(abs(dd.y)) * 240.0)) * exp((-(abs(dd.x)) * 2.6)));
        vec3 _e1420 = add_1;
        add_1 = (_e1420 + (((vec3(1.2, 0.5, 2.6) * streak_1) * ((disk_env_1 * 0.6) + (evap * 2.0))) * _e18));
    }
    vec3 _e1434 = col_1;
    vec3 _e1435 = add_1;
    outc_1 = (_e1434 + _e1435);
    float vg = length(((uv_4 - vec2(0.5)) * vec2(aspect, 1.0)));
    vec3 _e1445 = outc_1;
    outc_1 = ((_e1445 * (1.0 - ((smoothstep(0.3, 1.0, vg) * (0.25 + (0.45 * pull_env))) * _e18))) + ((((vec3(0.25, 0.05, 0.5) * smoothstep(0.35, 1.0, vg)) * pull_env) * 0.06) * _e18));
    vec3 _e1471 = outc_1;
    vec3 _e1474 = aces((_e1471 * 0.9));
    outc_1 = _e1474;
    vec3 _e1475 = outc_1;
    vec3 _e1476 = linear_to_srgb(_e1475);
    srgb = _e1476;
    vec3 _e1478 = srgb;
    vec3 _e1481 = srgb;
    srgb = mix(_e1478, (vec3(1.0) - _e1481), clamp(((open * 1.2) * _e18), 0.0, 1.0));
    float _e1488 = capture();
    if ((_e1488 > 2.5)) {
        vec2 sp = floor(in_1.position.xy);
        float chk = fract(((sp.x + sp.y) * 0.5));
        float _e1501 = srgb.y;
        float _e1505 = srgb.x;
        float _e1507 = srgb.z;
        float ycc_y = ((_e1501 * 0.5) + ((_e1505 + _e1507) * 0.25));
        float _e1513 = srgb.x;
        float _e1515 = srgb.z;
        float ycc_co = (_e1513 - _e1515);
        float _e1518 = srgb.y;
        float _e1520 = srgb.x;
        float _e1522 = srgb.z;
        float ycc_cg = (_e1518 - ((_e1520 + _e1522) * 0.5));
        return vec4(ycc_y, ((((chk < 0.25) ? ycc_co : ycc_cg) * 0.5) + 0.5), 0.0, 1.0);
    }
    vec3 _e1537 = srgb;
    return vec4(_e1537, 1.0);
}

uvec3 pcg3d(uvec3 v0_) {
    uvec3 v_6 = uvec3(0u);
    v_6 = ((v0_ * 1664525u) + uvec3(1013904223u));
    uint _e9 = v_6.x;
    uint _e11 = v_6.y;
    uint _e13 = v_6.z;
    v_6.x = (_e9 + (_e11 * _e13));
    uint _e18 = v_6.y;
    uint _e20 = v_6.z;
    uint _e22 = v_6.x;
    v_6.y = (_e18 + (_e20 * _e22));
    uint _e27 = v_6.z;
    uint _e29 = v_6.x;
    uint _e31 = v_6.y;
    v_6.z = (_e27 + (_e29 * _e31));
    uvec3 _e34 = v_6;
    uvec3 _e35 = v_6;
    v_6 = (_e34 ^ (_e35 >> uvec3(16u)));
    uint _e42 = v_6.x;
    uint _e44 = v_6.y;
    uint _e46 = v_6.z;
    v_6.x = (_e42 + (_e44 * _e46));
    uint _e51 = v_6.y;
    uint _e53 = v_6.z;
    uint _e55 = v_6.x;
    v_6.y = (_e51 + (_e53 * _e55));
    uint _e60 = v_6.z;
    uint _e62 = v_6.x;
    uint _e64 = v_6.y;
    v_6.z = (_e60 + (_e62 * _e64));
    uvec3 _e67 = v_6;
    return _e67;
}

vec3 grad3_(vec3 i_12) {
    uvec3 _e3 = pcg3d(uvec3(ivec3(i_12)));
    return ((vec3(_e3) * 4.656613e-10) - vec3(1.0));
}

float gnoise3_(vec3 p_15) {
    vec3 i_27 = floor(p_15);
    vec3 f_15 = (p_15 - i_27);
    vec3 u_14 = (((f_15 * f_15) * f_15) * ((f_15 * ((f_15 * 6.0) - vec3(15.0))) + vec3(10.0)));
    vec3 _e15 = grad3_(i_27);
    float n000_ = dot(_e15, f_15);
    vec3 _e22 = grad3_((i_27 + vec3(1.0, 0.0, 0.0)));
    float n100_ = dot(_e22, (f_15 - vec3(1.0, 0.0, 0.0)));
    vec3 _e34 = grad3_((i_27 + vec3(0.0, 1.0, 0.0)));
    float n010_ = dot(_e34, (f_15 - vec3(0.0, 1.0, 0.0)));
    vec3 _e46 = grad3_((i_27 + vec3(1.0, 1.0, 0.0)));
    float n110_ = dot(_e46, (f_15 - vec3(1.0, 1.0, 0.0)));
    vec3 _e58 = grad3_((i_27 + vec3(0.0, 0.0, 1.0)));
    float n001_ = dot(_e58, (f_15 - vec3(0.0, 0.0, 1.0)));
    vec3 _e70 = grad3_((i_27 + vec3(1.0, 0.0, 1.0)));
    float n101_ = dot(_e70, (f_15 - vec3(1.0, 0.0, 1.0)));
    vec3 _e82 = grad3_((i_27 + vec3(0.0, 1.0, 1.0)));
    float n011_ = dot(_e82, (f_15 - vec3(0.0, 1.0, 1.0)));
    vec3 _e94 = grad3_((i_27 + vec3(1.0, 1.0, 1.0)));
    float n111_ = dot(_e94, (f_15 - vec3(1.0, 1.0, 1.0)));
    float x0_ = mix(mix(n000_, n100_, u_14.x), mix(n010_, n110_, u_14.x), u_14.y);
    float x1_ = mix(mix(n001_, n101_, u_14.x), mix(n011_, n111_, u_14.x), u_14.y);
    return ((mix(x0_, x1_, u_14.z) * 0.75) + 0.5);
}

float gfbm3_(vec3 p_16, int octaves) {
    vec3 q_2 = vec3(0.0);
    float a_5 = 0.5;
    float s_1 = 0.0;
    float w_2 = 0.0;
    int o = 0;
    mat3x3 m_2 = mat3x3(vec3(0.0, 0.8, 0.6), vec3(-0.8, 0.36, -0.48), vec3(-0.6, -0.48, 0.64));
    q_2 = p_16;
    bool loop_init_2 = true;
    while(true) {
        if (!loop_init_2) {
            int _e47 = o;
            o = (_e47 + 1);
        }
        loop_init_2 = false;
        int _e24 = o;
        if ((_e24 < octaves)) {
        } else {
            break;
        }
        {
            float _e26 = s_1;
            float _e27 = a_5;
            vec3 _e28 = q_2;
            float _e29 = gnoise3_(_e28);
            s_1 = (_e26 + (_e27 * _e29));
            float _e32 = w_2;
            float _e33 = a_5;
            w_2 = (_e32 + _e33);
            vec3 _e35 = q_2;
            q_2 = (((m_2 * _e35) * 2.03) + vec3(1.7, 9.2, 5.3));
            float _e44 = a_5;
            a_5 = (_e44 * 0.5);
        }
    }
    float _e50 = s_1;
    float _e51 = w_2;
    return (_e50 / _e51);
}

vec2 grad2_(vec2 i_13) {
    uvec3 _e5 = pcg3d(uvec3(ivec3(ivec2(i_13), 7)));
    return ((vec2(_e5.xy) * 4.656613e-10) - vec2(1.0));
}

float gnoise2_(vec2 p_17) {
    vec2 i_28 = floor(p_17);
    vec2 f_16 = (p_17 - i_28);
    vec2 u_15 = (((f_16 * f_16) * f_16) * ((f_16 * ((f_16 * 6.0) - vec2(15.0))) + vec2(10.0)));
    vec2 _e15 = grad2_(i_28);
    float a_12 = dot(_e15, f_16);
    vec2 _e21 = grad2_((i_28 + vec2(1.0, 0.0)));
    float b_12 = dot(_e21, (f_16 - vec2(1.0, 0.0)));
    vec2 _e31 = grad2_((i_28 + vec2(0.0, 1.0)));
    float c_17 = dot(_e31, (f_16 - vec2(0.0, 1.0)));
    vec2 _e41 = grad2_((i_28 + vec2(1.0, 1.0)));
    float d_10 = dot(_e41, (f_16 - vec2(1.0, 1.0)));
    return ((mix(mix(a_12, b_12, u_15.x), mix(c_17, d_10, u_15.x), u_15.y) * 0.9) + 0.5);
}

float gfbm2_(vec2 p_18) {
    mat2x2 m_3 = mat2x2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
    vec2 q1_1 = (((m_3 * p_18) * 2.03) + vec2(1.7, 9.2));
    vec2 q2_1 = (((m_3 * q1_1) * 2.01) + vec2(5.3, 2.8));
    float _e22 = gnoise2_(p_18);
    float _e25 = gnoise2_(q1_1);
    float _e29 = gnoise2_(q2_1);
    return ((((0.5 * _e22) + (0.25 * _e25)) + (0.125 * _e29)) / 0.875);
}

float ign(vec2 px_1) {
    return fract((52.982918 * fract(dot(px_1, vec2(0.06711056, 0.00583715)))));
}

float mh(uint i_14, uint seed_10, uint k_2) {
    uint _e3 = pcg(k_2);
    uint _e5 = pcg((seed_10 ^ _e3));
    uint _e7 = pcg((i_14 ^ _e5));
    return (float(_e7) * 2.3283064e-10);
}

vec3 met_where(float fi_4, float seed_11) {
    uint i_29 = uint(fi_4);
    uint s_7 = uint(seed_11);
    float _e5 = mh(i_29, s_7, 5u);
    if ((_e5 < 0.33)) {
        float _e10 = mh(i_29, s_7, 6u);
        uint c_18 = (100u + min(uint((_e10 * 6.0)), 5u));
        float _e18 = mh(c_18, s_7, 1u);
        float ca_1 = (_e18 * TAU);
        float _e23 = mh(c_18, s_7, 2u);
        float cr = (24.0 + (90.0 * sqrt(_e23)));
        float _e29 = mh(i_29, s_7, 7u);
        float oa = (_e29 * TAU);
        float _e33 = mh(i_29, s_7, 8u);
        float orr = (3.0 + (11.0 * _e33));
        vec2 pos = ((vec2(cos(ca_1), sin(ca_1)) * cr) + (vec2(cos(oa), sin(oa)) * orr));
        float _e48 = mh(c_18, s_7, 3u);
        float _e54 = mh(i_29, s_7, 9u);
        return vec3(pos, ((3.0 + (8.5 * _e48)) + (1.4 * _e54)));
    }
    float _e60 = mh(i_29, s_7, 1u);
    float a_13 = (_e60 * TAU);
    float _e65 = mh(i_29, s_7, 2u);
    float r_8 = (14.0 + (106.0 * sqrt(_e65)));
    float _e75 = mh(i_29, s_7, 3u);
    return vec3((cos(a_13) * r_8), (sin(a_13) * r_8), (2.5 + (9.5 * _e75)));
}

float met_t(float fi_5, float seed_12) {
    vec3 _e2 = met_where(fi_5, seed_12);
    return _e2.z;
}

float met_path(float tau) {
    return ((MET_V * tau) + ((MET_A * tau) * tau));
}

float met_when(float l) {
    return ((sqrt((22500.0 + (180.0 * l))) - MET_V) / 90.0);
}

vec2 met_off(float fi_6, float seed_13) {
    vec3 _e2 = met_where(fi_6, seed_13);
    return _e2.xy;
}

int met_class(float fi_7, float seed_14) {
    float _e5 = mh(uint(fi_7), uint(seed_14), 4u);
    return ((_e5 < 0.6) ? 0 : ((_e5 < 0.87) ? 1 : 2));
}

vec3 met_dir(float fi_8, float seed_15, float elev, float spread) {
    float _e11 = fh21_(vec2(fi_8, 31.0));
    float phi = ((fract((seed_15 * 0.0911)) * TAU) + (((_e11 - 0.5) * 0.45) * spread));
    float _e20 = fh21_(vec2(fi_8, 37.0));
    float e = (elev + (((_e20 - 0.5) * 0.3) * spread));
    return vec3((cos(e) * cos(phi)), sin(e), (cos(e) * sin(phi)));
}

vec4 meteor_storm(StageIn in_2) {
    bool local_42 = false;
    vec2 sdir = vec2(0.0);
    vec2 haze = vec2(0.0);
    bool local_43 = false;
    int i_15 = 0;
    bool local_44 = false;
    vec3 col_2 = vec3(0.0);
    vec3 add_2 = vec3(0.0);
    float z = 0.0;
    int i_16 = 0;
    bool local_45 = false;
    bool local_46 = false;
    bool local_47 = false;
    bool local_48 = false;
    bool local_49 = false;
    bool local_50 = false;
    bool local_51 = false;
    int j_2 = 0;
    bool local_52 = false;
    bool local_53 = false;
    bool local_54 = false;
    bool local_55 = false;
    bool local_56 = false;
    bool local_57 = false;
    bool local_58 = false;
    float trans_2 = 1.0;
    vec3 acc_2 = vec3(0.0);
    int i_17 = 0;
    float coarse = 0.0;
    bool local_59 = false;
    int j_3 = 0;
    bool local_60 = false;
    bool local_61 = false;
    vec3 outc_2 = vec3(0.0);
    vec2 uv_5 = in_2.uv;
    float _e5 = _group_0_binding_4_fs.resolution.x;
    float _e9 = _group_0_binding_4_fs.resolution.y;
    float aspect_1 = (_e5 / _e9);
    float _e11 = now();
    vec4 _e14 = _group_0_binding_4_fs.camera_position;
    vec3 cam_7 = _e14.xyz;
    vec3 _e16 = target_pos();
    vec3 crel_1 = (_e16 - cam_7);
    float _e18 = intensity_v();
    float _e19 = seed_v();
    float charging_1 = ((_e11 < T_FIRE) ? clamp((_e11 / T_FIRE), 0.0, 1.0) : 0.0);
    float fire_t_1 = (_e11 - T_FIRE);
    bool fired_1 = (fire_t_1 > 0.0);
    float ft_2 = max(fire_t_1, 0.0);
    float dtb = (ft_2 - BIG_T);
    bool hit_b = (dtb > 0.0);
    float end_env = (1.0 - smoothstep(28.0, MET_END, ft_2));
    float storm_env = (smoothstep(0.0, 1.5, _e11) * (1.0 - smoothstep(15.5, 19.5, ft_2)));
    float approach_1 = (smoothstep(7.5, BIG_T, ft_2) * (1.0 - float(hit_b)));
    float flash = (hit_b ? exp((-(dtb) * 2.2)) : 0.0);
    float dust_env = (smoothstep(14.0, 20.5, ft_2) * end_env);
    vec3 _e71 = met_dir(-1.0, _e19, 0.42, 0.0);
    vec3 big_head = (crel_1 + ((_e71 * BIG_V) * max((BIG_T - ft_2), 0.0)));
    vec3 _e80 = project_rel(big_head);
    vec3 _e81 = project_rel(crel_1);
    float _e82 = depth_at(uv_5);
    bool _e83 = is_sky(_e82);
    vec3 _e86 = world_offset(uv_5, (_e83 ? 0.5 : _e82));
    vec3 p0_2 = (cam_7 + _e86);
    float r0_4 = length((p0_2.xz - _e16.xz));
    float rsb = (max(dtb, 0.0) * 95.0);
    if (hit_b) {
        local_42 = !(_e83);
    } else {
        local_42 = false;
    }
    bool _e114 = local_42;
    float shock_mask = (_e114 ? (exp(-(pow(((r0_4 - rsb) / 5.0), 2.0))) * exp((-(max(dtb, 0.0)) * 0.3))) : 0.0);
    sdir = (uv_5 - _e81.xy);
    vec2 _e120 = sdir;
    vec2 _e121 = sdir;
    sdir = (_e120 / vec2(max(length(_e121), 0.0001)));
    if (fired_1) {
        local_43 = !(_e83);
    } else {
        local_43 = false;
    }
    bool _e134 = local_43;
    if (_e134) {
        bool loop_init_3 = true;
        while(true) {
            if (!loop_init_3) {
                int _e220 = i_15;
                i_15 = (_e220 + 1);
            }
            loop_init_3 = false;
            int _e137 = i_15;
            if ((_e137 < MET_N)) {
            } else {
                break;
            }
            {
                int _e140 = i_15;
                float fi_11 = float(_e140);
                float _e142 = met_t(fi_11, _e19);
                float dtm = (fire_t_1 - _e142);
                if (!((dtm < 0.0))) {
                    local_44 = (dtm > 1.1);
                } else {
                    local_44 = true;
                }
                bool _e152 = local_44;
                if (_e152) {
                    continue;
                }
                int _e153 = met_class(fi_11, _e19);
                float fc = float(_e153);
                vec2 _e155 = met_off(fi_11, _e19);
                float gi = length((p0_2.xz - (_e16.xz + _e155)));
                float m_4 = (((exp(-(pow(((gi - (dtm * (55.0 + (25.0 * fc)))) / (1.5 + fc)), 2.0))) * exp((-(dtm) * 3.5))) * (0.5 + (0.5 * fc))) * (1.0 - smoothstep(20.0, 40.0, abs((p0_2.y - _e16.y)))));
                if ((m_4 > 0.002)) {
                    vec3 _e205 = project_rel((vec3((_e16.x + _e155.x), _e16.y, (_e16.z + _e155.y)) - cam_7));
                    vec2 dir_2 = (uv_5 - _e205.xy);
                    vec2 _e208 = haze;
                    haze = (_e208 + ((((dir_2 / vec2(max(length(dir_2), 0.0001))) * m_4) * 0.012) * _e205.z));
                }
            }
        }
    }
    vec2 _e223 = sdir;
    vec2 _e231 = haze;
    vec2 uv2_3 = clamp(((uv_5 + ((((_e223 * shock_mask) * 0.05) * _e18) * _e81.z)) + (_e231 * _e18)), vec2(0.002), vec2(0.998));
    float _e239 = depth_at(uv2_3);
    bool _e240 = is_sky(_e239);
    vec3 _e243 = world_offset(uv2_3, (_e240 ? 0.5 : _e239));
    float scene_len_4 = (!(_e240) ? length(_e243) : 1000000000.0);
    vec3 _e249 = world_offset(uv2_3, RAY_DEPTH);
    vec3 rd_8 = normalize(_e249);
    vec3 P_1 = (cam_7 + _e243);
    float ca_2 = (((flash * 0.02) + (shock_mask * 0.01)) * _e18);
    vec2 ca_dir_1 = ((uv2_3 - vec2(0.5)) * ca_2);
    vec4 _e266 = orbitalSceneLod(_group_0_binding_0_fs, vec2((uv2_3 + ca_dir_1)), 0.0);
    vec4 _e271 = orbitalSceneLod(_group_0_binding_0_fs, vec2(uv2_3), 0.0);
    vec4 _e277 = orbitalSceneLod(_group_0_binding_0_fs, vec2((uv2_3 - ca_dir_1)), 0.0);
    vec3 _e280 = srgb_to_linear(vec3(_e266.x, _e271.y, _e277.z));
    col_2 = _e280;
    float dim_3 = clamp((1.0 - (((((0.35 * charging_1) * charging_1) + (0.3 * storm_env)) + (0.45 * dust_env)) * _e18)), 0.2, 1.0);
    vec3 _e297 = col_2;
    col_2 = ((_e297 * dim_3) * mix(vec3(1.0), vec3(1.15, 0.8, 0.6), (clamp((storm_env + dust_env), 0.0, 1.0) * _e18)));
    vec3 _e310 = col_2;
    col_2 = (_e310 * (vec3(1.0) + ((((vec3(1.4, 0.75, 0.3) * approach_1) * approach_1) * 1.6) * _e18)));
    if (_e240) {
        float grad = pow((1.0 - uv2_3.y), 1.5);
        vec3 dusk = (vec3(0.32, 0.1, 0.05) + (vec3(0.55, 0.22, 0.08) * grad));
        vec3 _e339 = col_2;
        col_2 = mix(_e339, dusk, (clamp(((storm_env * 0.65) + (charging_1 * 0.3)), 0.0, 1.0) * _e18));
        float _e370 = gfbm2_((((rd_8.xz / vec2(max(rd_8.y, 0.05))) * 1.5) + vec2((_e11 * 0.05), 0.0)));
        vec3 dusty = (vec3(0.16, 0.07, 0.035) + ((vec3(0.25, 0.09, 0.03) * grad) * (0.6 + (0.6 * _e370))));
        vec3 _e377 = col_2;
        col_2 = mix(_e377, dusty, ((dust_env * 0.88) * _e18));
        float tow = max(dot(rd_8, normalize(big_head)), 0.0);
        vec3 _e386 = col_2;
        col_2 = (_e386 + ((((vec3(1.6, 0.75, 0.25) * pow(tow, 12.0)) * approach_1) * 1.6) * _e18));
    }
    if (!(_e240)) {
        vec2 dxg_1 = (P_1.xz - _e16.xz);
        float r_9 = length(dxg_1);
        float ang_5 = atan(dxg_1.y, dxg_1.x);
        float dy_1 = (P_1.y - _e16.y);
        float on_ground = (1.0 - smoothstep(28.0, 45.0, dy_1));
        float near_y_1 = (on_ground / (1.0 + ((dy_1 * dy_1) / 200.0)));
        float zone_env = (max(charging_1, ((storm_env * 0.35) * (1.0 - float(hit_b)))) * end_env);
        if ((zone_env > 0.001)) {
            float dash = step(0.5, fract((((ang_5 / TAU) * 48.0) + (_e11 * 0.08))));
            z = ((exp(-(pow(((r_9 - MET_SPAN) / 0.8), 2.0))) * dash) * 1.2);
            float conv_1 = mix(MET_SPAN, 10.0, (1.0 - pow((1.0 - charging_1), 2.0)));
            float _e465 = z;
            z = (_e465 + (exp(-(pow(((r_9 - conv_1) / 0.6), 2.0))) * charging_1));
            float _e475 = z;
            z = (_e475 + ((exp(-(pow(((r_9 - 6.0) / 0.3), 2.0))) + exp(-(pow(((r_9 - 2.5) / 0.25), 2.0)))) * (0.6 + (0.4 * sin((_e11 * 8.0))))));
            float cross_ = ((1.0 - smoothstep(0.15, 0.35, min(abs(dxg_1.x), abs(dxg_1.y)))) * (1.0 - smoothstep(9.0, 10.0, r_9)));
            float _e518 = z;
            z = (_e518 + (cross_ * 0.7));
            vec3 _e522 = add_2;
            float _e527 = z;
            add_2 = (_e522 + (((((vec3(1.6, 0.25, 0.1) * _e527) * zone_env) * near_y_1) * 2.0) * _e18));
        }
        if (hit_b) {
            float edge_1 = ((exp(-(pow(((r_9 - rsb) / 4.0), 2.0))) * exp((-(dtb) * 0.28))) * near_y_1);
            vec3 _e548 = add_2;
            add_2 = (_e548 + (((vec3(2.2, 1.3, 0.6) * edge_1) * 5.0) * _e18));
            float behind = ((smoothstep((rsb + 2.0), (rsb - 40.0), r_9) * exp((-(dtb) * 0.12))) * on_ground);
            vec3 _e569 = col_2;
            float _e581 = gfbm2_(((dxg_1 * 0.03) + vec2((_e11 * 0.3), 0.0)));
            col_2 = mix(_e569, (vec3(0.2, 0.12, 0.07) * (0.6 + (0.8 * _e581))), ((behind * 0.55) * _e18));
            float _e600 = gfbm2_(((dxg_1 * 0.12) + vec2((_e11 * 0.1), (-(_e11) * 0.07))));
            float heat_2 = (((((1.0 - (r_9 / 75.0)) * 0.9) + ((_e600 - 0.5) * 0.8)) + (clamp(((_e16.y - P_1.y) / 30.0), 0.0, 1.0) * 0.6)) - (dtb * 0.02));
            float mask = ((((1.0 - smoothstep(55.0, 80.0, r_9)) * smoothstep(0.0, 1.5, dtb)) * end_env) * on_ground);
            vec3 _e635 = add_2;
            vec3 _e636 = lava_ramp(heat_2);
            add_2 = (_e635 + (((_e636 * mask) * 3.0) * _e18));
        }
    }
    vec2 v2_2 = rd_8.xz;
    float vv_2 = dot(v2_2, v2_2);
    bool loop_init_4 = true;
    while(true) {
        if (!loop_init_4) {
            int _e1618 = i_16;
            i_16 = (_e1618 + 1);
        }
        loop_init_4 = false;
        int _e646 = i_16;
        if ((_e646 < MET_N)) {
        } else {
            break;
        }
        {
            int _e649 = i_16;
            float fi_12 = float(_e649);
            float _e651 = met_t(fi_12, _e19);
            float dtm_1 = (fire_t_1 - _e651);
            if (!((dtm_1 < -5.0))) {
                local_45 = (dtm_1 > 9.0);
            } else {
                local_45 = true;
            }
            bool _e661 = local_45;
            if (_e661) {
                continue;
            }
            int _e662 = met_class(fi_12, _e19);
            float fc_1 = float(_e662);
            vec2 _e664 = met_off(fi_12, _e19);
            vec3 I = (vec3((_e16.x + _e664.x), _e16.y, (_e16.z + _e664.y)) - cam_7);
            vec3 _e676 = met_dir(fi_12, _e19, 0.62, 1.0);
            float rr = ((0.6 + (0.5 * fc_1)) + ((0.3 * fc_1) * fc_1));
            float tau_1 = -(dtm_1);
            float _e688 = met_path(max(tau_1, 0.0));
            float _e690 = met_path(MET_ENTRY);
            vec3 headp = (I + (_e676 * _e688));
            vec3 _e695 = ray_seg(rd_8, headp, (I + (_e676 * _e690)));
            float l_1 = mix(_e688, _e690, _e695.z);
            float _e698 = met_when(l_1);
            float age = max((_e698 - tau_1), 0.0);
            float burn = smoothstep(1700.0, 1050.0, l_1);
            float vis_1 = (!(_e240) ? (1.0 - smoothstep((scene_len_4 - 0.5), (scene_len_4 + 0.5), _e695.y)) : 1.0);
            float _e721 = fvnoise(vec2((_e11 * 13.0), (fi_12 * 7.0)));
            float flick = (0.7 + (0.6 * _e721));
            float sw = ((rr * 1.4) + (age * (1.6 + (1.2 * fc_1))));
            float swp = max(sw, (_e695.y * 0.0015));
            if ((vis_1 > 0.001)) {
                local_46 = (_e695.x < (swp * 3.0));
            } else {
                local_46 = false;
            }
            bool _e747 = local_46;
            if (_e747) {
                float s_env = (((((exp(-(pow((_e695.x / swp), 2.0))) * (sw / swp)) * burn) * smoothstep(0.08, 0.6, age)) * exp((-(age) / (3.5 + (2.0 * fc_1))))) * (0.55 + (0.2 * fc_1)));
                if ((s_env > 0.006)) {
                    float _e784 = gfbm2_(vec2((l_1 * 0.06), ((age * 0.7) + (fi_12 * 3.1))));
                    vec3 _e785 = col_2;
                    col_2 = mix(_e785, ((vec3(0.32, 0.29, 0.27) * dim_3) * (0.55 + (0.7 * _e784))), (clamp((s_env * (0.3 + (0.6 * _e784))), 0.0, 1.0) * vis_1));
                }
                float fw0_ = (rr * (1.0 + (age * 5.0)));
                float fw = max(fw0_, (_e695.y * 0.0012));
                float fire = ((exp(-(pow((_e695.x / fw), 2.0))) * (fw0_ / fw)) * exp((-(age) * 3.2)));
                vec3 fcol = mix(vec3(3.4, 3.0, 2.2), vec3(2.6, 0.75, 0.12), smoothstep(0.0, 0.3, age));
                vec3 _e838 = add_2;
                add_2 = (_e838 + ((((((fcol * fire) * burn) * flick) * (0.8 + (0.4 * fc_1))) * vis_1) * _e18));
                float _e860 = fh21_(vec2(floor((l_1 * 0.5)), (floor((age * 14.0)) + (fi_12 * 17.0))));
                float side = ((fract((_e860 * 53.0)) - 0.5) * ((rr * 2.0) + (age * 6.0)));
                float spark = (((step(0.9, _e860) * exp(-(pow(((_e695.x - abs(side)) / max((rr * 0.5), (_e695.y * 0.001))), 2.0)))) * exp((-(age) * 2.5))) * smoothstep(0.02, 0.15, age));
                vec3 _e898 = add_2;
                add_2 = (_e898 + ((((vec3(3.0, 1.4, 0.35) * spark) * burn) * vis_1) * _e18));
            }
            if ((tau_1 > -0.05)) {
                float th_1 = dot(headp, rd_8);
                if ((th_1 > 0.0)) {
                    float dh = length((headp - (rd_8 * th_1)));
                    float visg = (!(_e240) ? (1.0 - smoothstep((scene_len_4 - 1.0), (scene_len_4 + 1.0), th_1)) : 1.0);
                    float glow = (1.0 / (1.0 + pow((dh / ((rr * 2.5) + (th_1 * 0.002))), 2.0)));
                    vec3 _e938 = add_2;
                    add_2 = (_e938 + ((((((vec3(2.2, 1.3, 0.55) * glow) * (0.08 + (0.9 * burn))) * flick) * 0.55) * visg) * _e18));
                    float hq = ((rr * rr) - (dh * dh));
                    if ((hq > 0.0)) {
                        float t0_1 = (th_1 - sqrt(hq));
                        if ((t0_1 > 0.0)) {
                            local_47 = (t0_1 < scene_len_4);
                        } else {
                            local_47 = false;
                        }
                        bool _e968 = local_47;
                        if (_e968) {
                            vec3 nrm_1 = normalize(((rd_8 * t0_1) - headp));
                            float _e981 = gfbm3_(((nrm_1 * 2.5) + vec3((_e11 * 0.6), fi_12, (_e11 * 0.4))), 2);
                            if ((dot(nrm_1, -(rd_8)) > ((0.45 * _e981) - 0.05))) {
                                float front = clamp(((dot(nrm_1, -(_e676)) * 0.5) + 0.5), 0.0, 1.0);
                                vec3 rock = ((vec3(0.08, 0.07, 0.06) * (0.5 + (0.9 * _e981))) * dim_3);
                                vec3 _e1010 = lava_ramp((0.3 + (0.7 * front)));
                                col_2 = (rock + (((_e1010 * pow(front, 3.0)) * 2.4) * burn));
                            }
                        }
                    }
                }
            }
            if ((dtm_1 >= 0.0)) {
                float fr = ((3.0 + (2.5 * fc_1)) + ((0.5 * fc_1) * fc_1));
                float Rf = ((fr * (1.0 - exp((-(dtm_1) * 5.0)))) + 0.5);
                vec3 C = (I + vec3(0.0, (Rf * 0.4), 0.0));
                float tcp = dot(C, rd_8);
                if ((tcp > 0.0)) {
                    float dc = length((C - (rd_8 * tcp)));
                    float visf = (!(_e240) ? smoothstep((tcp - (Rf * 1.2)), (tcp - (Rf * 0.2)), scene_len_4) : 1.0);
                    float fire_1 = (exp(-(pow((dc / Rf), 2.0))) * exp((-(dtm_1) * 1.8)));
                    vec3 _e1069 = add_2;
                    vec3 _e1074 = lava_ramp((0.45 + (fire_1 * 0.6)));
                    add_2 = (_e1069 + ((((_e1074 * fire_1) * (2.8 + fc_1)) * visf) * _e18));
                    vec3 _e1082 = add_2;
                    add_2 = (_e1082 + ((((((vec3(1.5, 0.7, 0.3) / vec3((1.0 + pow((dc / (Rf * 3.0)), 2.0)))) * exp((-(dtm_1) * 4.0))) * 0.5) * (1.0 + fc_1)) * visf) * _e18));
                }
                vec3 _e1112 = axis_hit(I.xz, v2_2, vv_2, cam_7.y, rd_8.y);
                float Hp = ((fr * 3.0) * (1.0 - exp((-(dtm_1) * 1.1))));
                float Rp = ((fr * 0.6) + (dtm_1 * 0.9));
                if ((_e1112.x > 0.0)) {
                    local_48 = (_e1112.y < (Rp * 3.0));
                } else {
                    local_48 = false;
                }
                bool _e1137 = local_48;
                if (_e1137) {
                    local_49 = ((_e1112.z - _e16.y) > -2.0);
                } else {
                    local_49 = false;
                }
                bool _e1146 = local_49;
                if (_e1146) {
                    local_50 = ((_e1112.z - _e16.y) < (Hp + 2.0));
                } else {
                    local_50 = false;
                }
                bool _e1156 = local_50;
                if (_e1156) {
                    float yrel = (_e1112.z - _e16.y);
                    float _e1170 = gfbm2_(vec2(((yrel * 0.22) - (dtm_1 * 1.2)), (fi_12 + (_e1112.y * 0.3))));
                    float dens_1 = (((((exp(-(pow((_e1112.y / Rp), 2.0))) * smoothstep(Hp, (Hp * 0.5), yrel)) * smoothstep(-1.0, 0.5, yrel)) * exp((-(dtm_1) / 5.0))) * smoothstep(0.0, 0.3, dtm_1)) * (0.4 + (0.7 * _e1170)));
                    float visp = (!(_e240) ? (1.0 - smoothstep((scene_len_4 - 0.5), (scene_len_4 + 0.5), _e1112.x)) : 1.0);
                    vec3 _e1210 = col_2;
                    col_2 = mix(_e1210, ((vec3(0.26, 0.2, 0.15) * dim_3) * (0.6 + (0.6 * _e1170))), (clamp((dens_1 * 0.85), 0.0, 1.0) * visp));
                }
                if ((_e662 > 0)) {
                    local_51 = (dtm_1 < 2.6);
                } else {
                    local_51 = false;
                }
                bool _e1233 = local_51;
                if (_e1233) {
                    j_2 = 0;
                    bool loop_init_5 = true;
                    while(true) {
                        if (!loop_init_5) {
                            int _e1350 = j_2;
                            j_2 = (_e1350 + 1);
                        }
                        loop_init_5 = false;
                        int _e1236 = j_2;
                        if ((_e1236 < 5)) {
                        } else {
                            break;
                        }
                        {
                            int _e1239 = j_2;
                            float fj = float(_e1239);
                            float _e1245 = fh21_(vec2(((fi_12 * 7.0) + fj), _e19));
                            float az = (_e1245 * TAU);
                            float _e1252 = fh21_(vec2(fj, ((fi_12 * 3.0) + _e19)));
                            float vh = ((8.0 + (10.0 * _e1252)) * (0.8 + (0.6 * fc_1)));
                            float vy = ((11.0 + (9.0 * _e1252)) * (0.9 + (0.4 * fc_1)));
                            float t1_ = max((dtm_1 - 0.12), 0.0);
                            vec3 pa = (I + vec3(((cos(az) * vh) * dtm_1), ((vy * dtm_1) - ((12.5 * dtm_1) * dtm_1)), ((sin(az) * vh) * dtm_1)));
                            vec3 pb = (I + vec3(((cos(az) * vh) * t1_), ((vy * t1_) - ((12.5 * t1_) * t1_)), ((sin(az) * vh) * t1_)));
                            if ((pa.y < (I.y - 2.0))) {
                                continue;
                            }
                            vec3 _e1306 = ray_seg(rd_8, pa, pb);
                            float visj = (!(_e240) ? (1.0 - smoothstep((scene_len_4 - 0.4), (scene_len_4 + 0.4), _e1306.y)) : 1.0);
                            float w_7 = max((0.35 * (1.0 + _e1306.z)), (_e1306.y * 0.0012));
                            vec3 _e1327 = add_2;
                            add_2 = (_e1327 + (((((vec3(2.6, 1.0, 0.25) * exp(-(pow((_e1306.x / w_7), 2.0)))) * (0.35 / w_7)) * exp((-(dtm_1) * 0.6))) * visj) * _e18));
                        }
                    }
                }
                vec2 dxi = (P_1.xz - (_e16.xz + _e664));
                float gr = length(dxi);
                float Rd = ((fr * 4.5) * (1.0 - exp((-(dtm_1) * 2.0))));
                if (!(_e240)) {
                    local_52 = (dtm_1 < 1.0);
                } else {
                    local_52 = false;
                }
                bool _e1373 = local_52;
                if (_e1373) {
                    float gw_1 = (1.0 - smoothstep(20.0, 40.0, abs((P_1.y - _e16.y))));
                    float edge_2 = (exp(-(pow(((gr - (dtm_1 * (55.0 + (25.0 * fc_1)))) / (0.4 + (0.3 * fc_1))), 2.0))) * exp((-(dtm_1) * 9.0)));
                    vec3 _e1403 = add_2;
                    add_2 = (_e1403 + ((((vec3(1.5, 1.1, 0.7) * edge_2) * (0.4 + (0.4 * fc_1))) * gw_1) * _e18));
                }
                if (!(_e240)) {
                    local_53 = (gr < max((Rd + (fr * 2.0)), (fr * 3.0)));
                } else {
                    local_53 = false;
                }
                bool _e1428 = local_53;
                if (_e1428) {
                    float gw_2 = (1.0 - smoothstep(20.0, 40.0, abs((P_1.y - _e16.y))));
                    float inside = smoothstep((Rd + 1.0), (Rd - (fr * 0.8)), gr);
                    float front_1 = exp(-(pow(((gr - (Rd * 0.92)) / (0.6 + (fr * 0.35))), 2.0)));
                    float _e1464 = gfbm2_(((dxi * 0.35) + vec2((dtm_1 * 0.8), (fi_12 * 2.3))));
                    float _e1472 = fh21_((floor((P_1.xz * 4.0)) + vec2(fi_12, 3.0)));
                    float skirt = (((((inside * 0.35) + (front_1 * 0.9)) * (0.45 + (0.8 * _e1464))) * exp((-(dtm_1) / (2.5 + fc_1)))) * smoothstep(0.0, 0.15, dtm_1));
                    vec3 _e1494 = lava_ramp(0.5);
                    vec3 lit_2 = (((_e1494 * 0.3) * exp((-(dtm_1) * 1.5))) * (1.0 - smoothstep(0.0, (fr * 2.0), gr)));
                    vec3 dust_col = (((mix(vec3(0.24, 0.18, 0.13), vec3(0.42, 0.3, 0.2), _e1464) * dim_3) * (0.8 + (0.4 * _e1472))) + lit_2);
                    vec3 _e1525 = col_2;
                    col_2 = mix(_e1525, dust_col, ((clamp((skirt * (0.6 + (0.2 * fc_1))), 0.0, 1.0) * gw_2) * _e18));
                    float glow_1 = ((1.0 - smoothstep((fr * 0.3), (fr * 1.1), gr)) * exp((-(dtm_1) * 0.3)));
                    float _e1553 = gfbm2_(((dxi * 0.9) + vec2((_e11 * 0.3), fi_12)));
                    vec3 _e1554 = add_2;
                    vec3 _e1562 = lava_ramp(((0.35 + (0.5 * glow_1)) + (0.3 * _e1553)));
                    add_2 = (_e1554 + ((((_e1562 * glow_1) * gw_2) * 1.8) * _e18));
                    float _e1578 = fh21_((floor((P_1.xz * 2.0)) + vec2((fi_12 * 13.0), 7.0)));
                    float spark_1 = (((step(0.93, _e1578) * (1.0 - smoothstep(fr, (fr * 2.8), gr))) * exp((-(dtm_1) * (0.4 + (2.0 * fract((_e1578 * 37.0))))))) * (0.55 + (0.45 * sin(((_e11 * 18.0) + (_e1578 * 60.0))))));
                    vec3 _e1609 = add_2;
                    add_2 = (_e1609 + (((vec3(2.4, 0.9, 0.2) * spark_1) * gw_2) * _e18));
                }
            }
        }
    }
    if (fired_1) {
        local_54 = (ft_2 > 4.0);
    } else {
        local_54 = false;
    }
    bool _e1626 = local_54;
    if (_e1626) {
        local_55 = (dtb < 12.0);
    } else {
        local_55 = false;
    }
    bool _e1632 = local_55;
    if (_e1632) {
        float heat_3 = (smoothstep(4.0, 11.5, ft_2) * (1.0 - smoothstep(0.0, 0.1, dtb)));
        float Lb = (BIG_V * max((BIG_T - ft_2), 0.0));
        vec3 _e1651 = ray_seg(rd_8, big_head, (crel_1 + (_e71 * 2470.0)));
        float l_2 = mix(Lb, 2470.0, _e1651.z);
        float age_1 = (((l_2 - Lb) / BIG_V) + max(dtb, 0.0));
        float burn_1 = smoothstep(2470.0, (2470.0 * 0.7), l_2);
        float vis_2 = (!(_e240) ? (1.0 - smoothstep((scene_len_4 - 2.0), (scene_len_4 + 2.0), _e1651.y)) : 1.0);
        float sw_1 = (20.8 + (age_1 * 7.0));
        float swp_1 = max(sw_1, (_e1651.y * 0.0015));
        float _e1693 = gfbm2_(vec2(((l_2 * 0.02) - (age_1 * 0.3)), (((_e1651.x / swp_1) * 2.0) + _e19)));
        float sa_1 = (((((exp(-(pow((_e1651.x / swp_1), 2.0))) * (sw_1 / swp_1)) * burn_1) * smoothstep(0.1, 0.8, age_1)) * exp((-(age_1) / 14.0))) * (0.35 + (0.65 * _e1693)));
        vec3 _e1717 = col_2;
        col_2 = mix(_e1717, ((vec3(0.3, 0.26, 0.23) * dim_3) * (0.5 + (0.8 * _e1693))), (clamp((sa_1 * 0.9), 0.0, 1.0) * vis_2));
        float fw0_1 = (BIG_R * (1.0 + (age_1 * 2.5)));
        float fw_1 = max(fw0_1, (_e1651.y * 0.0015));
        float core_3 = ((exp(-(pow((_e1651.x / (fw_1 * 0.7)), 2.0))) * (fw0_1 / fw_1)) * exp((-(age_1) * 1.4)));
        vec3 hot_2 = mix(vec3(4.0, 3.4, 2.2), vec3(3.0, 0.9, 0.15), smoothstep(0.0, 0.8, age_1));
        vec3 _e1770 = add_2;
        add_2 = (_e1770 + (((((hot_2 * core_3) * vis_2) * (0.3 + (0.9 * heat_3))) * (1.0 - float(hit_b))) * _e18));
        if (!(hit_b)) {
            vec3 oc = -(big_head);
            float bq = dot(oc, rd_8);
            float cq = (dot(oc, oc) - 256.0);
            float hq_1 = ((bq * bq) - cq);
            if ((hq_1 > 0.0)) {
                float t0_2 = (-(bq) - sqrt(hq_1));
                if ((t0_2 > 0.0)) {
                    local_56 = (t0_2 < scene_len_4);
                } else {
                    local_56 = false;
                }
                bool _e1803 = local_56;
                if (_e1803) {
                    vec3 nrm_2 = normalize(((rd_8 * t0_2) - big_head));
                    float front_2 = clamp(dot(nrm_2, -(_e71)), 0.0, 1.0);
                    float _e1815 = gfbm3_(((nrm_2 * 5.0) + vec3(_e19)), 3);
                    float cracks = smoothstep(0.55, 0.75, _e1815);
                    float _e1826 = gfbm3_((nrm_2 * 9.0), 2);
                    vec3 rock_1 = (vec3(0.06, 0.05, 0.045) * (0.5 + _e1826));
                    vec3 _e1837 = lava_ramp(((0.4 + (0.6 * front_2)) + (0.3 * cracks)));
                    col_2 = (rock_1 + ((_e1837 * ((pow(front_2, 2.0) * 3.0) + (cracks * 1.2))) * (0.3 + heat_3)));
                }
            }
            float th_2 = dot(big_head, rd_8);
            if ((th_2 > 0.0)) {
                float dh_1 = length((big_head - (rd_8 * th_2)));
                float glare = (1.0 / (1.0 + pow((dh_1 / (40.0 + (th_2 * 0.004))), 2.0)));
                vec3 _e1867 = add_2;
                if (!(_e240)) {
                    local_57 = (scene_len_4 < th_2);
                } else {
                    local_57 = false;
                }
                bool _e1883 = local_57;
                add_2 = (_e1867 + ((((vec3(2.2, 1.4, 0.7) * glare) * (0.35 + (1.2 * heat_3))) * (_e1883 ? 0.3 : 1.0)) * _e18));
            }
        }
    }
    if (hit_b) {
        local_58 = (dtb < 24.0);
    } else {
        local_58 = false;
    }
    bool _e1895 = local_58;
    if (_e1895) {
        float Rv = (115.0 * (1.0 - exp((-(dtb) * 0.55))));
        float top_s = (30.0 + (dtb * 16.0));
        float capr = (25.0 + (dtb * 3.0));
        float Rb = (max((Rv * 1.35), (top_s + capr)) + 4.0);
        vec3 oc_1 = (cam_7 - _e16);
        float bq_1 = dot(oc_1, rd_8);
        float cq_1 = (dot(oc_1, oc_1) - (Rb * Rb));
        float hq_2 = ((bq_1 * bq_1) - cq_1);
        if ((hq_2 > 0.0)) {
            float sq = sqrt(hq_2);
            float ta_2 = max((-(bq_1) - sq), 0.0);
            float tb_1 = min((-(bq_1) + sq), scene_len_4);
            if ((tb_1 > ta_2)) {
                float dt_2 = ((tb_1 - ta_2) / float(16));
                float fade = (1.0 - smoothstep(16.0, 24.0, dtb));
                float _e1952 = ign(in_2.position.xy);
                float grow = smoothstep(1.0, 4.0, dtb);
                bool loop_init_6 = true;
                while(true) {
                    if (!loop_init_6) {
                        int _e2154 = i_17;
                        i_17 = (_e2154 + 1);
                    }
                    loop_init_6 = false;
                    int _e1958 = i_17;
                    if ((_e1958 < 16)) {
                    } else {
                        break;
                    }
                    {
                        int _e1960 = i_17;
                        float ts = (ta_2 + ((float(_e1960) + _e1952) * dt_2));
                        vec3 lp_2 = (oc_1 + (rd_8 * ts));
                        float rl_1 = length(lp_2);
                        float rr_1 = length(lp_2.xz);
                        float stem = (((1.0 - (rr_1 / (22.0 + (max(lp_2.y, 0.0) * 0.12)))) * 1.3) * (1.0 - smoothstep((top_s - 8.0), top_s, lp_2.y)));
                        float capq = length(vec2((rr_1 / max((capr * 1.6), 1.0)), ((lp_2.y - top_s) / max((capr * 0.6), 1.0))));
                        coarse = (max(stem, ((1.0 - capq) * 1.6)) * grow);
                        if ((rl_1 < ((Rv * 1.6) + 2.0))) {
                            vec3 dirn = (lp_2 / vec3(max(rl_1, 0.001)));
                            float _e2028 = gnoise3_(((dirn * 2.4) + vec3((_e19 * 0.37), 3.1, (_e19 * 0.11))));
                            float Re = (Rv * ((0.6 + (0.75 * _e2028)) + (0.25 * clamp(dot(dirn, -(_e71)), 0.0, 1.0))));
                            float _e2040 = coarse;
                            coarse = max(_e2040, (((1.0 - (rl_1 / max(Re, 1.0))) * 1.5) - 0.2));
                        }
                        float _e2051 = coarse;
                        if (!((_e2051 < -1.25))) {
                            local_59 = (lp_2.y < -8.0);
                        } else {
                            local_59 = true;
                        }
                        bool _e2061 = local_59;
                        if (_e2061) {
                            continue;
                        }
                        float _e2075 = gfbm3_(((lp_2 * 0.03) + vec3(0.0, (-(dtb) * 0.45), _e19)), ((ts < 200.0) ? 3 : 2));
                        float _e2076 = coarse;
                        float body_1 = (_e2076 + ((_e2075 - 0.5) * 2.6));
                        float dens_2 = ((clamp((body_1 * 1.2), 0.0, 1.0) * smoothstep(-8.0, 4.0, lp_2.y)) * fade);
                        if ((dens_2 < 0.002)) {
                            continue;
                        }
                        float temp_1 = clamp(((((body_1 * 0.6) + 0.42) - (dtb * 0.045)) - (max(lp_2.y, 0.0) / 260.0)), 0.0, 1.0);
                        vec3 _e2107 = lava_ramp(temp_1);
                        vec3 emit_1 = ((_e2107 * 3.0) * (0.3 + (0.7 * exp((-(dtb) * 0.12)))));
                        vec3 _e2128 = lava_ramp((temp_1 * 0.8));
                        vec3 smoke = ((vec3(0.11, 0.085, 0.07) * (0.45 + _e2075)) + (_e2128 * 0.12));
                        float a_14 = ((1.0 - exp(((-(dens_2) * dt_2) * 0.07))) * 0.88);
                        vec3 _e2141 = acc_2;
                        float _e2142 = trans_2;
                        acc_2 = (_e2141 + ((_e2142 * a_14) * (emit_1 + smoke)));
                        float _e2147 = trans_2;
                        trans_2 = (_e2147 * (1.0 - a_14));
                        float _e2151 = trans_2;
                        if ((_e2151 < 0.05)) {
                            break;
                        }
                    }
                }
                vec3 _e2157 = col_2;
                float _e2158 = trans_2;
                vec3 _e2160 = acc_2;
                col_2 = ((_e2157 * _e2158) + (_e2160 * _e18));
            }
        }
        vec2 down = normalize((vec2(-(_e71.x), -(_e71.z)) + vec2(0.0001)));
        bool loop_init_7 = true;
        while(true) {
            if (!loop_init_7) {
                int _e2366 = j_3;
                j_3 = (_e2366 + 1);
            }
            loop_init_7 = false;
            int _e2174 = j_3;
            if ((_e2174 < 64)) {
            } else {
                break;
            }
            {
                int _e2177 = j_3;
                float fj_1 = float(_e2177);
                float _e2182 = fh21_(vec2(fj_1, (_e19 + 51.0)));
                float _e2186 = fh21_(vec2(fj_1, (_e19 + 57.0)));
                float _e2190 = fh21_(vec2(fj_1, (_e19 + 61.0)));
                float _e2194 = fh21_(vec2(fj_1, (_e19 + 67.0)));
                float tau_2 = ((dtb - 0.1) - ((1.4 * _e2190) * _e2190));
                if (!((tau_2 <= 0.0))) {
                    local_60 = (tau_2 > 16.0);
                } else {
                    local_60 = true;
                }
                bool _e2209 = local_60;
                if (_e2209) {
                    continue;
                }
                float ray_a = (((floor((_e2182 * 7.0)) * TAU) / 7.0) + (_e19 * 0.3));
                bool along_ray = (_e2194 < 0.6);
                float az0_ = (along_ray ? (ray_a + ((_e2186 - 0.5) * 0.18)) : (_e2182 * TAU));
                vec2 dvec = normalize((mix(vec2(cos(az0_), sin(az0_)), down, (0.35 * _e2186)) + vec2(0.0001)));
                float elev_1 = mix(0.15, 1.35, pow(_e2190, 0.7));
                float speed = ((55.0 + ((95.0 * _e2194) * _e2194)) * (0.7 + (0.6 * _e2186)));
                float vh_1 = (cos(elev_1) * speed);
                float vy_1 = (sin(elev_1) * speed);
                vec3 p0_3 = (crel_1 + (vec3(dvec.x, 0.0, dvec.y) * (18.0 + (18.0 * _e2186))));
                vec3 ph = (p0_3 + vec3(((dvec.x * vh_1) * tau_2), ((vy_1 * tau_2) - ((15.0 * tau_2) * tau_2)), ((dvec.y * vh_1) * tau_2)));
                float t1_1 = max((tau_2 - 0.22), 0.0);
                vec3 pt1_ = (p0_3 + vec3(((dvec.x * vh_1) * t1_1), ((vy_1 * t1_1) - ((15.0 * t1_1) * t1_1)), ((dvec.y * vh_1) * t1_1)));
                if (((ph.y + cam_7.y) < (_e16.y - 6.0))) {
                    continue;
                }
                float sz = (0.8 + ((2.2 * _e2182) * _e2194));
                vec3 _e2311 = ray_seg(rd_8, ph, pt1_);
                float vis_3 = (!(_e240) ? (1.0 - smoothstep((scene_len_4 - 0.5), (scene_len_4 + 0.5), _e2311.y)) : 1.0);
                float w_8 = max((sz * (1.0 + _e2311.z)), (_e2311.y * 0.0012));
                float core_4 = (exp(-(pow((_e2311.x / w_8), 2.0))) * (sz / w_8));
                float cool = exp((-(tau_2) * 0.2));
                vec3 _e2343 = add_2;
                add_2 = (_e2343 + (((((mix(vec3(1.6, 0.25, 0.05), vec3(3.0, 1.6, 0.6), cool) * core_4) * (1.0 - (_e2311.z * 0.6))) * vis_3) * (0.5 + cool)) * _e18));
            }
        }
    }
    if ((_e80.z > 0.0)) {
        local_61 = (approach_1 > 0.001);
    } else {
        local_61 = false;
    }
    bool _e2377 = local_61;
    if (_e2377) {
        vec2 dd_1 = ((uv_5 - _e80.xy) * vec2(aspect_1, 1.0));
        vec3 _e2383 = add_2;
        add_2 = (_e2383 + (((((vec3(1.6, 0.9, 0.4) * approach_1) * approach_1) / vec3((1.0 + (dot(dd_1, dd_1) * 25.0)))) * 1.2) * _e18));
        float streak_2 = (exp((-(abs(dd_1.y)) * 220.0)) * exp((-(abs(dd_1.x)) * 2.0)));
        vec3 _e2414 = add_2;
        add_2 = (_e2414 + (((vec3(2.0, 1.0, 0.4) * streak_2) * approach_1) * _e18));
    }
    vec3 _e2423 = add_2;
    add_2 = (_e2423 + (((vec3(6.0, 5.4, 4.6) * flash) * flash) * _e18));
    vec3 _e2432 = add_2;
    add_2 = (_e2432 + (((vec3(1.5, 0.8, 0.4) * (hit_b ? exp((-(dtb) * 0.6)) : 0.0)) * 0.4) * _e18));
    vec3 _e2448 = col_2;
    vec3 _e2449 = add_2;
    outc_2 = (_e2448 + _e2449);
    float vg_1 = length(((uv_5 - vec2(0.5)) * vec2(aspect_1, 1.0)));
    vec3 _e2459 = outc_2;
    outc_2 = ((_e2459 * (1.0 - ((smoothstep(0.3, 1.0, vg_1) * (0.2 + (0.35 * max(storm_env, dust_env)))) * _e18))) + ((((vec3(0.4, 0.1, 0.02) * smoothstep(0.35, 1.0, vg_1)) * max(storm_env, dust_env)) * 0.08) * _e18));
    vec3 _e2487 = outc_2;
    vec3 _e2490 = aces((_e2487 * 0.9));
    outc_2 = _e2490;
    vec3 _e2491 = outc_2;
    vec3 _e2492 = linear_to_srgb(_e2491);
    float _e2493 = capture();
    if ((_e2493 > 2.5)) {
        vec2 sp_1 = floor(in_2.position.xy);
        float chk_1 = fract(((sp_1.x + sp_1.y) * 0.5));
        float ycc_y_1 = ((_e2492.y * 0.5) + ((_e2492.x + _e2492.z) * 0.25));
        float ycc_co_1 = (_e2492.x - _e2492.z);
        float ycc_cg_1 = (_e2492.y - ((_e2492.x + _e2492.z) * 0.5));
        return vec4(ycc_y_1, ((((chk_1 < 0.25) ? ycc_co_1 : ycc_cg_1) * 0.5) + 0.5), 0.0, 1.0);
    }
    return vec4(_e2492, 1.0);
}

float ms_sweep(float t_1) {
    float s_8 = clamp(((t_1 - MS_SWEEP0_) / 9.0), 0.0, 1.0);
    return ((s_8 * s_8) * (3.0 - (2.0 * s_8)));
}

float ms_when(float u_6) {
    return (MS_SWEEP0_ + (9.0 * (0.5 - sin((asin((1.0 - (2.0 * clamp(u_6, 0.0, 1.0)))) / 3.0)))));
}

vec2 ms_axis() {
    float _e0 = wing_a();
    return -(vec2(cos(_e0), sin(_e0)));
}

float ms_stop(int style) {
    return ((style == 0) ? MS_SNAP : ((style == 1) ? MS_IN : MS_WARP));
}

MsFrame ms_frame(MsFrame base, float t_2, int mode, int style_1) {
    MsFrame f = MsFrame(vec2(0.0), vec2(0.0), vec2(0.0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float far_1 = 0.0;
    f = base;
    bool up_2 = (mode == 4);
    float td = (t_2 - MS_LEAVE);
    if ((td > 0.0)) {
        float u_16 = (td / MS_OUT);
        float lead = (((MS_FAR * u_16) * u_16) * u_16);
        float lag_3 = (MS_FAR * pow(u_16, 4.5));
        if (up_2) {
            float _e23 = f.y0_;
            f.y0_ = (_e23 + lag_3);
            f.sy = (1.0 + ((lead - lag_3) / MS_TOP));
        } else {
            f.shift = lag_3;
            f.px = -560.0;
            f.sx = (1.0 + ((lead - lag_3) / 1120.0));
        }
        MsFrame _e40 = f;
        return _e40;
    }
    float ta_3 = max((t_2 - MS_ARRIVE), 0.0);
    far_1 = (MS_COAST * exp((-(ta_3) / 1.3)));
    if ((style_1 == 2)) {
        float s_9 = (1.0 + (70.0 * exp((-(ta_3) * 13.0))));
        if (up_2) {
            f.sy = s_9;
        } else {
            f.sx = s_9;
            f.px = MS_HL;
            f.sz = (1.0 / (1.0 + ((s_9 - 1.0) * 0.3)));
        }
    } else {
        if ((style_1 == 1)) {
            float u_17 = clamp((ta_3 / MS_IN), 0.0, 1.0);
            float _e80 = far_1;
            far_1 = (_e80 + (MS_FAR * pow((1.0 - u_17), 4.0)));
            float s_10 = max((1.0 - pow((1.0 - u_17), 2.2)), 0.002);
            f.sx = s_10;
            f.sz = s_10;
            f.sy = s_10;
        } else {
            float _e99 = far_1;
            far_1 = (_e99 + (MS_FAR * pow((1.0 - clamp((ta_3 / MS_SNAP), 0.0, 1.0)), 5.0)));
        }
    }
    if (up_2) {
        float _e112 = f.y0_;
        float _e113 = far_1;
        f.y0_ = (_e112 + _e113);
    } else {
        float _e116 = far_1;
        f.shift = -(_e116);
    }
    MsFrame _e118 = f;
    return _e118;
}

bool ms_here(float t_3) {
    bool local_62 = false;
    if ((t_3 >= MS_ARRIVE)) {
        local_62 = (t_3 < 23.3);
    } else {
        local_62 = false;
    }
    bool _e8 = local_62;
    return _e8;
}

vec2 ms_local(MsFrame f_1, vec2 p_19) {
    vec2 r_10 = (p_19 - f_1.c);
    return vec2(((((dot(r_10, f_1.ax) - f_1.shift) - f_1.px) / f_1.sx) + f_1.px), (dot(r_10, f_1.sd) / f_1.sz));
}

vec2 ms_world(MsFrame f_2, vec2 q_3) {
    return ((f_2.c + (f_2.ax * ((f_2.shift + f_2.px) + ((q_3.x - f_2.px) * f_2.sx)))) + (f_2.sd * (q_3.y * f_2.sz)));
}

float ms_sponson(float x_6) {
    return (32.0 * (step(abs((x_6 + 150.0)), 70.0) + step(abs((x_6 - 130.0)), 70.0)));
}

float ms_half_w(float x_7) {
    float _e2 = ms_sponson(x_7);
    return min((MS_HW + _e2), (MS_HW - ((180.0 * (x_7 - 340.0)) / MS_TAPER)));
}

float ms_outline(vec2 q_4, float inset) {
    float d_2 = 0.0;
    vec2 a_15 = abs(q_4);
    float _e11 = ms_sponson(q_4.x);
    d_2 = max(((a_15.x - MS_HL) + inset), (((a_15.y - MS_HW) - _e11) + inset));
    float _e16 = d_2;
    d_2 = max(_e16, ((((a_15.x + a_15.y) - 760.0) + (inset * 1.4142)) * 0.7071));
    float _e29 = d_2;
    return max(_e29, ((((a_15.y + (0.8181818 * (q_4.x - 340.0))) - MS_HW) / sqrt((1.0 + (0.8181818 * 0.8181818)))) + inset));
}

float ms_hangar(vec2 q_5) {
    return max((abs((q_5.x - -290.0)) - 90.0), (abs((q_5.y - 0.0)) - 100.0));
}

float ms_tier(vec2 q_6, int k_3) {
    float d_3 = 0.0;
    if ((k_3 == 0)) {
        float _e9 = ms_outline(q_6, 30.0);
        float ridge = max((abs(q_6.y) - 70.0), _e9);
        float _e20 = ms_outline(q_6, 42.0);
        float engines = max(max((abs(q_6.y) - 170.0), (q_6.x + 430.0)), _e20);
        float _e23 = ms_hangar(q_6);
        return max(min(ridge, engines), -(_e23));
    }
    if ((k_3 == 1)) {
        float _e29 = ms_outline(q_6, 40.0);
        d_3 = _e29;
        float cell = floor((q_6.x / 140.0));
        float bay = max((abs((q_6.x - ((cell + 0.5) * 140.0))) - 36.0), (176.0 - abs(q_6.y)));
        float _e49 = d_3;
        float _e58 = fh21_(vec2(cell, ((sign(q_6.y) * 3.0) + 11.0)));
        d_3 = max(_e49, ((_e58 > 0.35) ? -(bay) : -1000000000.0));
        float trench = max((abs((abs(q_6.y) - 119.0)) - 7.0), (abs((q_6.x + 60.0)) - 360.0));
        float _e78 = d_3;
        float _e81 = ms_hangar(q_6);
        return max(max(_e78, -(trench)), -(_e81));
    }
    float _e93 = fh21_(vec2(floor((q_6.x / 100.0)), (sign(q_6.y) + 3.0)));
    float step_in = (step(0.5, _e93) * step(abs(q_6.x), 500.0));
    float _e102 = ms_outline(q_6, 0.0);
    return (_e102 + (8.0 * step_in));
}

float ms_eye(vec2 q_7) {
    return (length((q_7 - vec2(70.0, 0.0))) - MS_EYE_R);
}

float ms_tier_h(int k_4) {
    return ((k_4 < 2) ? ((k_4 == 0) ? 0.0 : MS_TIER_B) : ((k_4 == 2) ? MS_TIER_C : MS_TOP));
}

MsHit ms_recess(MsFrame f_3, vec3 cam_1, vec3 rd_3, float t_lo, float up, int which) {
    MsHit hit_1 = MsHit(0.0, vec2(0.0), 0.0, 0);
    float a_6 = 0.0;
    float b_6 = 0.0;
    int i_18 = 0;
    float t_c = (((f_3.y0_ + (up * f_3.sy)) - cam_1.y) / rd_3.y);
    vec2 _e19 = ms_local(f_3, (cam_1.xz + (rd_3.xz * t_c)));
    float _e20 = ms_hangar(_e19);
    float _e21 = ms_eye(_e19);
    if ((((which == 0) ? _e21 : _e20) < 0.0)) {
        hit_1.t = t_c;
        hit_1.q = _e19;
        hit_1.h = up;
        hit_1.kind = ((which == 0) ? 4 : 6);
        MsHit _e36 = hit_1;
        return _e36;
    }
    a_6 = t_lo;
    b_6 = t_c;
    bool loop_init_8 = true;
    while(true) {
        if (!loop_init_8) {
            int _e61 = i_18;
            i_18 = (_e61 + 1);
        }
        loop_init_8 = false;
        int _e41 = i_18;
        if ((_e41 < 5)) {
        } else {
            break;
        }
        {
            float _e44 = a_6;
            float _e45 = b_6;
            float m_5 = (0.5 * (_e44 + _e45));
            vec2 _e53 = ms_local(f_3, (cam_1.xz + (rd_3.xz * m_5)));
            float _e54 = ms_hangar(_e53);
            float _e55 = ms_eye(_e53);
            if ((((which == 0) ? _e55 : _e54) < 0.0)) {
                a_6 = m_5;
            } else {
                b_6 = m_5;
            }
        }
    }
    float _e65 = b_6;
    hit_1.t = _e65;
    float _e69 = b_6;
    vec2 _e72 = ms_local(f_3, (cam_1.xz + (rd_3.xz * _e69)));
    hit_1.q = _e72;
    float _e76 = b_6;
    hit_1.h = (((cam_1.y + (rd_3.y * _e76)) - f_3.y0_) / f_3.sy);
    hit_1.kind = ((which == 0) ? 5 : 7);
    MsHit _e89 = hit_1;
    return _e89;
}

MsHit ms_trace(MsFrame f_4, vec3 cam_2, vec3 rd_4) {
    MsHit hit_2 = MsHit(0.0, vec2(0.0), 0.0, 0);
    bool local_63 = false;
    int k_5 = 0;
    bool local_64 = false;
    bool local_65 = false;
    bool local_66 = false;
    float a_7 = 0.0;
    float b_7 = 0.0;
    int i_19 = 0;
    hit_2.t = 1000000000.0;
    hit_2.q = vec2(0.0);
    hit_2.h = 0.0;
    hit_2.kind = -1;
    if (!((rd_4.y < 0.001))) {
        local_63 = (cam_2.y > f_4.y0_);
    } else {
        local_63 = true;
    }
    bool _e23 = local_63;
    if (_e23) {
        MsHit _e24 = hit_2;
        return _e24;
    }
    vec2 pa_1 = (cam_2.xz + (rd_4.xz * ((f_4.y0_ - cam_2.y) / rd_4.y)));
    vec2 pb_1 = (cam_2.xz + (rd_4.xz * (((f_4.y0_ + (MS_TOP * f_4.sy)) - cam_2.y) / rd_4.y)));
    vec2 ab_3 = (pb_1 - pa_1);
    vec2 _e50 = ms_world(f_4, vec2(0.0));
    float u_18 = clamp((dot((_e50 - pa_1), ab_3) / max(dot(ab_3, ab_3), 0.0001)), 0.0, 1.0);
    if ((length(((pa_1 + (ab_3 * u_18)) - _e50)) > (640.0 * max(f_4.sx, f_4.sz)))) {
        MsHit _e68 = hit_2;
        return _e68;
    }
    bool loop_init_9 = true;
    while(true) {
        if (!loop_init_9) {
            int _e202 = k_5;
            k_5 = (_e202 + 1);
        }
        loop_init_9 = false;
        int _e71 = k_5;
        if ((_e71 < 3)) {
        } else {
            break;
        }
        {
            int _e75 = k_5;
            float _e76 = ms_tier_h(_e75);
            float t_lo_1 = (((f_4.y0_ + (_e76 * f_4.sy)) - cam_2.y) / rd_4.y);
            int _e85 = k_5;
            float _e88 = ms_tier_h((_e85 + 1));
            float t_hi = (((f_4.y0_ + (_e88 * f_4.sy)) - cam_2.y) / rd_4.y);
            vec2 _e100 = ms_local(f_4, (cam_2.xz + (rd_4.xz * t_lo_1)));
            int _e101 = k_5;
            if ((_e101 == 1)) {
                float _e106 = ms_hangar(_e100);
                local_64 = (_e106 < 0.0);
            } else {
                local_64 = false;
            }
            bool _e110 = local_64;
            if (_e110) {
                float _e114 = ms_outline(_e100, 40.0);
                local_65 = (_e114 < 0.0);
            } else {
                local_65 = false;
            }
            bool _e118 = local_65;
            if (_e118) {
                MsHit _e121 = ms_recess(f_4, cam_2, rd_4, t_lo_1, MS_HANGAR_UP, 1);
                return _e121;
            }
            int _e122 = k_5;
            float _e123 = ms_tier(_e100, _e122);
            if ((_e123 < 0.0)) {
                int _e126 = k_5;
                if ((_e126 == 0)) {
                    float _e131 = ms_eye(_e100);
                    local_66 = (_e131 < 0.0);
                } else {
                    local_66 = false;
                }
                bool _e135 = local_66;
                if (_e135) {
                    MsHit _e138 = ms_recess(f_4, cam_2, rd_4, t_lo_1, MS_EYE_UP, 0);
                    return _e138;
                }
                hit_2.t = t_lo_1;
                hit_2.q = _e100;
                int _e142 = k_5;
                float _e143 = ms_tier_h(_e142);
                hit_2.h = _e143;
                int _e145 = k_5;
                hit_2.kind = _e145;
                MsHit _e146 = hit_2;
                return _e146;
            }
            vec2 _e151 = ms_local(f_4, (cam_2.xz + (rd_4.xz * t_hi)));
            int _e152 = k_5;
            float _e153 = ms_tier(_e151, _e152);
            if ((_e153 < 0.0)) {
                a_7 = t_lo_1;
                b_7 = t_hi;
                i_19 = 0;
                bool loop_init_10 = true;
                while(true) {
                    if (!loop_init_10) {
                        int _e177 = i_19;
                        i_19 = (_e177 + 1);
                    }
                    loop_init_10 = false;
                    int _e160 = i_19;
                    if ((_e160 < 5)) {
                    } else {
                        break;
                    }
                    {
                        float _e163 = a_7;
                        float _e164 = b_7;
                        float m_6 = (0.5 * (_e163 + _e164));
                        vec2 _e172 = ms_local(f_4, (cam_2.xz + (rd_4.xz * m_6)));
                        int _e173 = k_5;
                        float _e174 = ms_tier(_e172, _e173);
                        if ((_e174 < 0.0)) {
                            b_7 = m_6;
                        } else {
                            a_7 = m_6;
                        }
                    }
                }
                float _e181 = b_7;
                hit_2.t = _e181;
                float _e185 = b_7;
                vec2 _e188 = ms_local(f_4, (cam_2.xz + (rd_4.xz * _e185)));
                hit_2.q = _e188;
                float _e192 = b_7;
                hit_2.h = (((cam_2.y + (rd_4.y * _e192)) - f_4.y0_) / f_4.sy);
                hit_2.kind = 3;
                MsHit _e201 = hit_2;
                return _e201;
            }
        }
    }
    MsHit _e205 = hit_2;
    return _e205;
}

vec4 ms_plates(vec2 q_8, float fp) {
    float _e10 = fh21_((floor((q_8 / vec2(48.0))) + vec2(17.0, 3.0)));
    vec2 size = vec2(((_e10 > 0.45) ? 24.0 : 48.0), ((_e10 > 0.75) ? 24.0 : 48.0));
    vec2 c_19 = floor((q_8 / size));
    vec2 fr_1 = (q_8 - (c_19 * size));
    float e_1 = min(min(fr_1.x, (size.x - fr_1.x)), min(fr_1.y, (size.y - fr_1.y)));
    float seam = ((1.0 - smoothstep((0.45 * 0.5), (0.45 + fp), e_1)) * min(1.0, ((2.0 * 0.45) / max(fp, 0.001))));
    float _e59 = fh21_(((c_19 * vec2(1.0, 1.7)) + (size * 0.37)));
    return vec4(seam, _e59, size);
}

float ms_line(float d_4, float w_3, float fp_1) {
    float ww_1 = max(w_3, fp_1);
    return (exp(-(pow((d_4 / ww_1), 2.0))) * (w_3 / ww_1));
}

vec3 ms_env(vec3 r_4, vec3 haze_1, vec3 sun, float day) {
    float _e4 = luminance(haze_1);
    vec3 grey = mix(haze_1, vec3(_e4), 0.65);
    vec3 ground_1 = ((vec3(0.16, 0.17, 0.13) * (0.08 + (0.92 * day))) * mix(0.35, 1.0, smoothstep(-0.75, -0.3, r_4.y)));
    vec3 e_2 = mix(ground_1, (grey * 1.1), smoothstep(-0.28, 0.0, r_4.y));
    vec3 glare_1 = (((vec3(1.0, 0.88, 0.7) * pow(max(dot(r_4, normalize(vec3(sun.x, -(abs(sun.y)), sun.z))), 0.0), 24.0)) * 1.1) * day);
    return (mix(e_2, (grey * 0.9), smoothstep(0.0, 0.5, r_4.y)) + glare_1);
}

vec3 ms_hull(MsHit h, MsFrame f_5, vec3 rd_5, float time_1, float lit_1, float chase_on, float core, float beam, vec3 focus, vec3 haze_2, float day_1, vec3 sun_1, float boost, float wake, float eng) {
    bool local_67 = false;
    bool local_68 = false;
    float tone = 1.0;
    float rough = 0.35;
    vec3 nl_1 = vec3(0.0, -1.0, 0.0);
    vec3 emit = vec3(0.0);
    bool local_69 = false;
    bool local_70 = false;
    bool local_71 = false;
    bool local_72 = false;
    bool local_73 = false;
    bool local_74 = false;
    bool local_75 = false;
    float s_2 = 0.0;
    bool local_76 = false;
    vec2 n2_ = vec2(0.0);
    bool local_77 = false;
    bool local_78 = false;
    bool local_79 = false;
    bool local_80 = false;
    vec3 c_11 = vec3(0.0);
    vec2 q_14 = h.q;
    float _e20 = _group_0_binding_4_fs.projection[1][1];
    float _e24 = _group_0_binding_4_fs.resolution.y;
    float pix = (2.0 / (_e20 * _e24));
    if (!((h.kind == 3))) {
        local_67 = (h.kind == 5);
    } else {
        local_67 = true;
    }
    bool _e38 = local_67;
    if (!(_e38)) {
        local_68 = (h.kind == 7);
    } else {
        local_68 = true;
    }
    bool wall = local_68;
    float fp_2 = ((h.t * pix) / (wall ? 0.6 : max(rd_5.y, 0.12)));
    vec3 X = (rd_5 * h.t);
    vec3 green = vec3(0.12, 1.5, 0.3);
    float _e78 = fh21_((floor((q_14 / vec2(23.0))) + vec2(77.0, 1.0)));
    float on_at = ((0.35 + ((0.25 * (q_14.x + MS_HL)) / 1120.0)) + (0.06 * _e78));
    float on_1 = smoothstep(on_at, (on_at + 0.05), wake);
    float chase = (pow((0.5 + (0.5 * sin(((q_14.x * 0.025) - (time_1 * 7.0))))), 6.0) * chase_on);
    float glow_2 = ((((0.25 + (0.9 * lit_1)) + (1.6 * chase)) * boost) * on_1);
    if ((h.kind <= 2)) {
        vec4 _e123 = ms_plates(q_14, fp_2);
        uvec3 _e131 = pcg3d(uvec3(ivec3(ivec2(floor((q_14 / _e123.zw))), 9)));
        vec3 hv_1 = (vec3(_e131) * 2.3283064e-10);
        nl_1 = normalize(vec3(((hv_1.x - 0.5) * 0.45), -1.0, ((hv_1.y - 0.5) * 0.45)));
        rough = (0.15 + (0.6 * hv_1.z));
        tone = (((0.55 + (0.7 * _e123.y)) * mix(1.0, 0.25, _e123.x)) * ((h.kind == 0) ? 0.85 : ((h.kind == 1) ? 1.0 : 1.1)));
        float _e175 = tone;
        float _e182 = gnoise2_(((q_14 * 0.006) + vec2(3.1, 7.7)));
        tone = (_e175 * (0.65 + (0.7 * _e182)));
        float _e198 = fh21_((floor((q_14 / vec2(6.0))) + vec2((_e123.y * 91.0), 5.0)));
        float _e199 = tone;
        tone = (_e199 * mix(1.0, (0.65 + ((0.7 * _e198) * _e198)), clamp((2.0 - (fp_2 / 3.0)), 0.0, 1.0)));
        float seam_d = (12.0 - (abs((fract((q_14.y / 24.0)) - 0.5)) * 24.0));
        float _e231 = gnoise2_(vec2((q_14.x * 0.015), (q_14.y * 0.45)));
        float streak_3 = smoothstep(0.45, 0.75, _e231);
        float _e235 = tone;
        tone = (_e235 * (1.0 - (((0.45 * exp((-(seam_d) / 2.5))) * streak_3) * clamp((2.0 - (fp_2 / 2.0)), 0.0, 1.0))));
        if ((_e123.y > 0.82)) {
            vec2 rdl = vec2(dot(rd_5.xz, f_5.ax), dot(rd_5.xz, f_5.sd));
            vec2 qd = (q_14 + (rdl * (4.0 / max(rd_5.y, 0.2))));
            if (any(notEqual(floor((qd / _e123.zw)), floor((q_14 / _e123.zw))))) {
                float _e277 = tone;
                tone = (_e277 * 0.3);
            } else {
                vec2 gd = (abs((fract((qd / vec2(3.0))) - vec2(0.5))) * 3.0);
                float _e290 = tone;
                tone = (_e290 * mix(0.45, 0.7, clamp((min(gd.x, gd.y) / max(fp_2, 0.4)), 0.0, 1.0)));
                rough = 0.8;
            }
        } else {
            if ((_e123.y > 0.6)) {
                local_69 = (_e123.y < 0.7);
            } else {
                local_69 = false;
            }
            bool _e312 = local_69;
            if (_e312) {
                float _e313 = tone;
                tone = (_e313 * mix(1.0, (0.75 + (0.5 * smoothstep(0.15, 0.35, abs((fract((q_14.y / 2.5)) - 0.5))))), clamp((1.5 - fp_2), 0.0, 1.0)));
            } else {
                if ((_e123.y < 0.12)) {
                    float slot = (step(abs((fract((q_14.x / 4.0)) - 0.5)), 0.3) * step(abs((fract((q_14.y / _e123.w)) - 0.5)), 0.3));
                    float _e356 = tone;
                    tone = (_e356 * mix(1.0, (1.0 - (0.85 * slot)), clamp((2.0 - (fp_2 / 1.5)), 0.0, 1.0)));
                }
            }
        }
        if ((h.kind == 1)) {
            local_70 = (abs(q_14.y) > 70.0);
        } else {
            local_70 = false;
        }
        bool _e379 = local_70;
        if (_e379) {
            float lz = ((abs(q_14.y) - 70.0) / 34.0);
            float fl = fract(lz);
            float _e387 = tone;
            float _e391 = fh21_(vec2(floor(lz), 61.0));
            tone = (_e387 * (0.85 + (0.3 * _e391)));
            float _e397 = tone;
            tone = ((_e397 * (1.0 - (0.5 * exp(((-(fl) * 34.0) / 2.5))))) + (0.9 * exp(((-((1.0 - fl)) * 34.0) / max(1.0, fp_2)))));
        }
        if ((h.kind == 2)) {
            vec2 fc_2 = floor((q_14 / vec2(80.0, 60.0)));
            float _e433 = fh21_((fc_2 + vec2(13.0, 29.0)));
            if ((_e433 > 0.62)) {
                local_71 = (abs(q_14.x) < 440.0);
            } else {
                local_71 = false;
            }
            bool _e443 = local_71;
            if (_e443) {
                float rdl_1 = dot(rd_5.xz, f_5.ax);
                float fin = smoothstep(0.3, 0.7, fract(((q_14.x / 3.0) + (0.2 * sign(rdl_1)))));
                float _e458 = tone;
                tone = (_e458 * mix(0.8, (0.45 + (0.7 * fin)), clamp((1.6 - (fp_2 / 1.5)), 0.0, 1.0)));
                rough = 0.5;
            }
        }
        if ((q_14.x > 310.0)) {
            local_72 = (h.kind > 0);
        } else {
            local_72 = false;
        }
        bool _e481 = local_72;
        if (_e481) {
            vec2 sc = floor((q_14 / vec2(16.0)));
            float _e490 = fh21_((sc + vec2(5.0, 83.0)));
            vec2 dv = (q_14 - ((sc + vec2(0.5)) * 16.0));
            float dd_2 = length(dv);
            if ((_e490 > 0.45)) {
                local_73 = (dd_2 < 5.0);
            } else {
                local_73 = false;
            }
            bool _e505 = local_73;
            if (_e505) {
                nl_1 = normalize(vec3((dv.x / 5.0), -(sqrt(max((1.0 - ((dd_2 * dd_2) / 25.0)), 0.05))), (dv.y / 5.0)));
                tone = 1.3;
                rough = 0.1;
                vec3 _e525 = emit;
                float _e531 = ms_line(dd_2, 0.6, fp_2);
                emit = (_e525 + (((vec3(0.4, 2.6, 0.5) * _e531) * step(0.75, _e490)) * step(0.6, fract(((time_1 * 0.7) + (_e490 * 9.0))))));
            } else {
                if ((_e490 > 0.3)) {
                    local_74 = (dd_2 < 6.0);
                } else {
                    local_74 = false;
                }
                bool _e553 = local_74;
                if (_e553) {
                    float _e554 = tone;
                    tone = (_e554 * (0.4 + (0.6 * smoothstep(0.5, 1.0, (abs((fract((dd_2 / 2.0)) - 0.5)) * 2.0)))));
                }
            }
        }
        if ((h.h >= MS_TOP)) {
            float _e576 = nl_1.y;
            nl_1.y = -(_e576);
        }
        float _e579 = ms_tier(q_14, h.kind);
        float edge_3 = -(_e579);
        if ((h.kind == 0)) {
            float _e592 = ms_eye(q_14);
            local_75 = (_e592 < 2.0);
        } else {
            local_75 = false;
        }
        bool _e596 = local_75;
        float bevel = ((1.0 - smoothstep(0.0, (2.5 + fp_2), edge_3)) * (_e596 ? 0.0 : 1.0));
        float _e601 = tone;
        tone = (_e601 + (1.2 * bevel));
        float _e605 = rough;
        rough = mix(_e605, 0.1, bevel);
        float _e620 = ms_line((abs((fract(((q_14.x / 120.0) + 0.5)) - 0.5)) * 120.0), 0.5, fp_2);
        float _e636 = fh21_(vec2(floor(((q_14.x / 120.0) + 0.5)), (floor((q_14.y / 70.0)) + 40.0)));
        s_2 = ((_e620 * 0.35) * step(0.4, _e636));
        if ((h.kind == 0)) {
            float _e644 = s_2;
            float _e651 = ms_line(abs((abs(q_14.y) - 20.0)), 0.5, fp_2);
            s_2 = (_e644 + (_e651 * 0.6));
        } else {
            float _e655 = s_2;
            float _e659 = ms_tier(q_14, (h.kind - 1));
            float _e663 = ms_line((_e659 - 1.4), 0.6, fp_2);
            s_2 = (_e655 + (_e663 * 1.3));
        }
        vec3 _e667 = emit;
        float _e668 = s_2;
        emit = (_e667 + ((green * _e668) * glow_2));
        if ((h.kind > 0)) {
            float row = floor((q_14.y / 6.0));
            float _e688 = fh21_((vec2(row, floor((q_14.x / 90.0))) + vec2(3.0, 17.0)));
            float wx = floor((q_14.x / 2.0));
            float _e698 = fh21_((vec2(wx, row) + vec2(41.0, 5.0)));
            if ((_e688 > 0.64)) {
                local_76 = (_e698 > 0.72);
            } else {
                local_76 = false;
            }
            bool _e706 = local_76;
            if (_e706) {
                float d_11 = length((q_14 - vec2(((wx * 2.0) + 1.0), ((row * 6.0) + 3.0))));
                float flick_1 = (0.6 + (0.4 * step(0.2, fract(((_e698 * 13.0) + (floor((time_1 * 0.5)) * 0.37))))));
                vec3 _e733 = emit;
                float _e739 = ms_line(d_11, 0.45, fp_2);
                emit = (_e733 + (((((vec3(0.55, 1.5, 0.6) * _e739) * flick_1) * boost) * on_1) * 0.6));
            }
        }
        if ((h.kind == 2)) {
            float cx = floor((q_14.x / 40.0));
            float lx = ((cx * 40.0) + 20.0);
            float _e760 = ms_half_w(lx);
            float d_12 = length((q_14 - vec2(lx, (sign(q_14.y) * (_e760 - 14.0)))));
            float blink = step(0.82, fract(((time_1 * 0.9) - (cx * 0.11))));
            vec3 rc_1 = ((q_14.y > 0.0) ? vec3(0.08, 1.1, 0.18) : vec3(0.4, 2.6, 0.5));
            vec3 _e787 = emit;
            float _e794 = ms_line(d_12, 1.3, fp_2);
            emit = (_e787 + (((mix(rc_1, vec3(3.5, 4.0, 3.5), blink) * _e794) * (0.6 + (1.4 * blink))) * boost));
        }
    } else {
        if ((h.kind == 4)) {
            vec2 e_3 = (q_14 - vec2(70.0, 0.0));
            float re_1 = length(e_3);
            float ae = atan(e_3.y, e_3.x);
            float ke = floor(((ae / 1.0471976) + 0.5));
            float de = length((e_3 - (vec2(cos((ke * 1.0471976)), sin((ke * 1.0471976))) * 30.0)));
            float ribs = smoothstep(0.2, 0.6, (abs((fract(((ae / 1.0471976) * 4.0)) - 0.5)) * 2.0));
            tone = (0.45 + (0.4 * ribs));
            rough = 0.5;
            vec3 hot_3 = mix(vec3(0.15, 1.8, 0.35), vec3(3.5, 5.0, 3.6), core);
            vec3 _e854 = emit;
            emit = (_e854 + (hot_3 * (((1.0 - smoothstep(5.0, (5.0 + fp_2), de)) * (((0.3 * on_1) + (7.0 * core)) + (6.0 * beam))) + (exp((-(de) / 6.0)) * ((0.2 * on_1) + (2.5 * core))))));
            vec3 _e883 = emit;
            emit = (_e883 + ((vec3(4.5, 6.0, 4.5) * (1.0 - smoothstep(9.0, (9.0 + fp_2), re_1))) * (((0.2 * on_1) + (10.0 * core)) + (10.0 * beam))));
            vec3 _e905 = emit;
            float _e909 = ms_line((re_1 - 18.0), 0.6, fp_2);
            float _e913 = ms_line((re_1 - 42.0), 0.8, fp_2);
            emit = (_e905 + ((green * (_e909 + _e913)) * glow_2));
        } else {
            if ((h.kind == 6)) {
                vec2 hq_3 = (q_14 - vec2(-290.0, 0.0));
                float _e937 = ms_line((abs((fract(((hq_3.y / 16.0) + 0.5)) - 0.5)) * 16.0), 1.2, fp_2);
                float docked = max(((abs((fract((hq_3.x / 30.0)) - 0.5)) * 30.0) - 9.0), ((abs((fract((hq_3.y / 16.0)) - 0.5)) * 16.0) - 4.0));
                float _e965 = fh21_(floor((hq_3 / vec2(30.0))));
                tone = (0.35 * (0.8 + (0.4 * _e965)));
                rough = 0.7;
                vec3 inner = ((vec3(0.8, 1.6, 0.9) * (0.25 + (1.2 * _e937))) * on_1);
                vec3 _e983 = emit;
                emit = (_e983 + (inner * ((docked < 0.0) ? 0.1 : 1.0)));
            } else {
                if ((h.kind == 3)) {
                    int k_10 = ((h.h > MS_TIER_B) ? ((h.h > MS_TIER_C) ? 2 : 1) : 0);
                    float _e1012 = ms_tier((q_14 + vec2(1.0, 0.0)), k_10);
                    float _e1017 = ms_tier((q_14 - vec2(1.0, 0.0)), k_10);
                    float _e1023 = ms_tier((q_14 + vec2(0.0, 1.0)), k_10);
                    float _e1028 = ms_tier((q_14 - vec2(0.0, 1.0)), k_10);
                    n2_ = vec2((_e1012 - _e1017), (_e1023 - _e1028));
                } else {
                    if ((h.kind == 5)) {
                        n2_ = (vec2(70.0, 0.0) - q_14);
                    } else {
                        vec2 hq_4 = (q_14 - vec2(-290.0, 0.0));
                        n2_ = (((abs(hq_4.x) - 90.0) > (abs(hq_4.y) - 100.0)) ? vec2(-(sign(hq_4.x)), 0.0) : vec2(0.0, -(sign(hq_4.y))));
                    }
                }
                vec2 _e1062 = n2_;
                vec2 _e1063 = n2_;
                n2_ = (_e1062 / vec2(max(length(_e1063), 0.0001)));
                float _e1070 = n2_.x;
                float _e1072 = n2_.y;
                nl_1 = vec3(_e1070, 0.0, _e1072);
                float _e1076 = n2_.y;
                float _e1079 = n2_.x;
                float u_19 = ((h.kind == 5) ? (atan(q_14.y, (q_14.x - MS_EM_X)) * MS_EYE_R) : dot(q_14, vec2(-(_e1076), _e1079)));
                float deck = (abs((fract((h.h / 5.0)) - 0.5)) * 5.0);
                float deck_l = mix(mix(0.45, 1.0, clamp(((deck - 0.3) / max((fp_2 * 0.5), 0.2)), 0.0, 1.0)), 0.93, smoothstep(0.7, 2.2, fp_2));
                float _e1125 = fh21_(vec2(floor((u_19 / 30.0)), 9.0));
                tone = ((0.8 * deck_l) * (0.75 + (0.4 * _e1125)));
                float _e1136 = fh21_(vec2(floor((u_19 / 30.0)), 19.0));
                rough = (0.3 + (0.4 * _e1136));
                vec2 wc = vec2(floor((u_19 / 3.5)), floor((h.h / 5.0)));
                float _e1153 = fh21_((wc + vec2(3.0, 51.0)));
                float win = ((step(((h.kind == 7) ? 0.55 : 0.88), _e1153) * step(1.2, deck)) * step(abs((fract((u_19 / 3.5)) - 0.5)), 0.3));
                vec3 _e1173 = emit;
                emit = (_e1173 + (((((vec3(0.45, 1.5, 0.5) * win) * clamp((1.6 - (fp_2 / 2.5)), 0.0, 1.0)) * boost) * on_1) * ((h.kind == 7) ? 2.0 : 1.0)));
                vec3 _e1195 = emit;
                float _e1200 = ms_line((MS_TOP - h.h), 0.8, fp_2);
                emit = (_e1195 + (((green * _e1200) * glow_2) * ((h.kind == 3) ? 1.0 : 0.0)));
                if ((h.kind == 3)) {
                    float _e1217 = n2_.x;
                    local_77 = (_e1217 > 0.8);
                } else {
                    local_77 = false;
                }
                bool _e1221 = local_77;
                if (_e1221) {
                    local_78 = (q_14.x > 556.0);
                } else {
                    local_78 = false;
                }
                bool _e1228 = local_78;
                if (_e1228) {
                    float rib = (abs((fract((q_14.y / 14.0)) - 0.5)) * 14.0);
                    float _e1238 = tone;
                    tone = (_e1238 * mix(1.0, (0.5 + (0.6 * smoothstep(1.0, 3.0, rib))), clamp((2.0 - (fp_2 / 2.0)), 0.0, 1.0)));
                    vec3 _e1254 = emit;
                    float _e1260 = ms_line(abs((h.h - 75.0)), 1.2, fp_2);
                    emit = (_e1254 + (((green * _e1260) * (0.4 + glow_2)) * 1.5));
                }
                if ((h.kind == 3)) {
                    float _e1274 = n2_.x;
                    local_79 = (_e1274 < -0.8);
                } else {
                    local_79 = false;
                }
                bool _e1278 = local_79;
                if (_e1278) {
                    bool big = (h.h > MS_TIER_C);
                    float pitch = (big ? 90.0 : 50.0);
                    float r_11 = (big ? 34.0 : 14.0);
                    float zc = ((floor((q_14.y / pitch)) + 0.5) * pitch);
                    float vc = (big ? 103.0 : 14.0);
                    float d_13 = length(vec2((q_14.y - zc), (h.h - vc)));
                    if ((abs(zc) < (big ? 200.0 : 160.0))) {
                        local_80 = (d_13 < (r_11 * 1.3));
                    } else {
                        local_80 = false;
                    }
                    bool _e1314 = local_80;
                    if (_e1314) {
                        float _e1315 = tone;
                        tone = (_e1315 * mix(1.0, 0.25, step(d_13, r_11)));
                        float _e1323 = ms_line((d_13 - r_11), 1.5, fp_2);
                        float bell = ((_e1323 * 1.5) + ((1.0 - smoothstep((r_11 * 0.2), r_11, d_13)) * 1.2));
                        vec3 _e1334 = emit;
                        emit = (_e1334 + ((mix(vec3(0.2, 1.8, 0.4), vec3(3.0, 5.0, 3.2), clamp((eng - 1.0), 0.0, 1.0)) * bell) * eng));
                    }
                }
            }
        }
    }
    float _e1357 = nl_1.x;
    float _e1360 = nl_1.y;
    float _e1372 = nl_1.z;
    vec3 n_4 = normalize((((vec3(f_5.ax.x, 0.0, f_5.ax.y) * _e1357) + vec3(0.0, _e1360, 0.0)) + (vec3(f_5.sd.x, 0.0, f_5.sd.y) * _e1372)));
    vec3 r_12 = reflect(rd_5, n_4);
    float cosv = max(dot(-(rd_5), n_4), 0.0);
    float fres = (0.45 + (0.55 * pow((1.0 - cosv), 5.0)));
    vec3 _e1389 = ms_env(r_12, haze_2, sun_1, day_1);
    float _e1390 = luminance(haze_2);
    float _e1404 = rough;
    vec3 env = mix(_e1389, (((mix(haze_2, vec3(_e1390), 0.65) * 0.6) + (vec3(0.08, 0.085, 0.07) * day_1)) * 0.6), (_e1404 * 0.8));
    vec3 sun_c = ((vec3(2.5, 2.3, 2.0) * day_1) * step(0.0, sun_1.y));
    float _e1420 = rough;
    float _e1426 = rough;
    vec3 glint = ((((sun_c * pow(max(dot(r_12, sun_1), 0.0), mix(300.0, 20.0, _e1420))) * (1.0 - _e1426)) * max(dot(n_4, sun_1), 0.0)) * 4.0);
    float _e1440 = tone;
    vec3 metal = (vec3(0.42, 0.43, 0.44) * _e1440);
    c_11 = ((metal * ((env * fres) + glint)) + (((metal * 0.04) * (haze_2 + (vec3(0.1) * day_1))) * max(dot(n_4, sun_1), 0.0)));
    vec3 lf = (X - focus);
    vec3 _e1459 = c_11;
    vec3 _e1464 = ship_tint(vec3(0.4, 2.0, 0.6));
    c_11 = (_e1459 + (((((metal * _e1464) * ((core * 0.8) + (beam * 1.6))) * 4000.0) / vec3((dot(lf, lf) + 2500.0))) * 0.3));
    float hz = (1.0 - exp((-(h.t) / 3000.0)));
    vec3 _e1489 = c_11;
    vec3 _e1495 = emit;
    vec3 _e1496 = ship_tint(_e1495);
    return (mix(_e1489, (haze_2 * 0.6), (hz * 0.35)) + (_e1496 * exp((-(h.t) / 3000.0))));
}

vec2 ms_air(vec2 uv_3, vec3 cam_3, vec3 p0_, bool sky0_, float stir, float tr, float wake_1, MsFrame base_1, MsFrame f_6, float time_2, float seed_16, float k_6) {
    vec2 off = vec2(0.0);
    bool local_81 = false;
    bool local_82 = false;
    bool local_83 = false;
    bool local_84 = false;
    bool local_85 = false;
    bool local_86 = false;
    bool local_87 = false;
    bool local_88 = false;
    bool local_89 = false;
    if ((stir > 0.001)) {
        local_81 = !(sky0_);
    } else {
        local_81 = false;
    }
    bool _e21 = local_81;
    if (_e21) {
        local_82 = (abs(((p0_.y - CLOUD_Y) - 2.0)) < 6.0);
    } else {
        local_82 = false;
    }
    bool _e33 = local_82;
    if (_e33) {
        float _e41 = gnoise2_(((p0_.xz * 0.012) + vec2((time_2 * 0.35), seed_16)));
        float _e50 = gnoise2_(((p0_.xz * 0.012) + vec2(7.0, (time_2 * 0.3))));
        vec2 sw_2 = (vec2(_e41, _e50) - vec2(0.5));
        vec2 _e55 = off;
        off = (_e55 + ((((sw_2 * 0.014) * stir) * stir) * k_6));
    }
    vec3 _e63 = world_offset(uv_3, RAY_DEPTH);
    vec3 rd0_ = normalize(_e63);
    if ((tr > 0.0)) {
        local_83 = (tr < 6.0);
    } else {
        local_83 = false;
    }
    bool _e72 = local_83;
    if (_e72) {
        local_84 = (abs(rd0_.y) > 0.001);
    } else {
        local_84 = false;
    }
    bool _e80 = local_84;
    if (_e80) {
        float t_cl = ((CLOUD_Y - cam_3.y) / rd0_.y);
        if ((t_cl > 0.0)) {
            if (!(sky0_)) {
                local_86 = (t_cl < (length((p0_ - cam_3)) + 40.0));
            } else {
                local_86 = true;
            }
            bool _e99 = local_86;
            local_85 = _e99;
        } else {
            local_85 = false;
        }
        bool _e101 = local_85;
        if (_e101) {
            float rr_2 = length(((cam_3.xz + (rd0_.xz * t_cl)) - base_1.c));
            float ripple = (exp(-(pow(((rr_2 - (tr * 650.0)) / (40.0 + (tr * 15.0))), 2.0))) * exp((-(tr) * 0.8)));
            vec3 _e133 = project_rel((vec3(base_1.c.x, CLOUD_Y, base_1.c.y) - cam_3));
            vec2 rdir_1 = (uv_3 - _e133.xy);
            vec2 _e136 = off;
            off = (_e136 + (((((rdir_1 / vec2(max(length(rdir_1), 0.0001))) * ripple) * 0.012) * _e133.z) * k_6));
        }
    }
    if ((wake_1 > 0.0)) {
        local_87 = (wake_1 < 1.2);
    } else {
        local_87 = false;
    }
    bool _e156 = local_87;
    if (_e156) {
        local_88 = (rd0_.y > 0.001);
    } else {
        local_88 = false;
    }
    bool _e163 = local_88;
    if (_e163) {
        local_89 = (cam_3.y < base_1.y0_);
    } else {
        local_89 = false;
    }
    bool _e170 = local_89;
    if (_e170) {
        vec2 _e182 = ms_local(f_6, (cam_3.xz + (rd0_.xz * (((base_1.y0_ + 20.0) - cam_3.y) / rd0_.y))));
        float _e184 = ms_tier(_e182, 2);
        float m_7 = (exp(-(pow((_e184 / 18.0), 2.0))) * (1.0 - (wake_1 / 1.2)));
        if ((m_7 > 0.01)) {
            float _e207 = gnoise2_(((uv_3 * vec2(120.0, 60.0)) + vec2(0.0, (time_2 * 6.0))));
            float _e217 = gnoise2_(((uv_3 * vec2(120.0, 60.0)) + vec2(17.0, (time_2 * 5.0))));
            vec2 hw = (vec2(_e207, _e217) - vec2(0.5));
            vec2 _e222 = off;
            off = (_e222 + (((hw * 0.006) * m_7) * k_6));
        }
    }
    vec2 _e228 = off;
    return _e228;
}

vec3 ms_arrival_fx(MsFrame f_7, MsFrame base_2, vec3 cam_4, vec3 rd_6, bool sky_1, float scene_len_1, float ta, int mode_1, int style_2, bool blurring, bool present, float k_7) {
    vec3 add_3 = vec3(0.0);
    bool local_90 = false;
    bool local_91 = false;
    bool local_92 = false;
    bool local_93 = false;
    bool local_94 = false;
    bool local_95 = false;
    bool local_96 = false;
    bool local_97 = false;
    int j_4 = 0;
    bool local_98 = false;
    if ((style_2 == 1)) {
        local_90 = (ta >= 0.0);
    } else {
        local_90 = false;
    }
    bool _e22 = local_90;
    if (_e22) {
        local_91 = (ta < MS_IN);
    } else {
        local_91 = false;
    }
    bool _e28 = local_91;
    if (_e28) {
        vec2 _e31 = ms_world(f_7, vec2(0.0));
        vec2 _e40 = ms_world(f_7, vec2(0.0));
        vec3 pc_1 = (vec3(_e31.x, (f_7.y0_ + (40.0 * f_7.sy)), _e40.y) - cam_4);
        float tp = dot(pc_1, rd_6);
        if ((tp > 0.0)) {
            if (!(sky_1)) {
                local_93 = (tp < scene_len_1);
            } else {
                local_93 = true;
            }
            bool _e54 = local_93;
            local_92 = _e54;
        } else {
            local_92 = false;
        }
        bool _e56 = local_92;
        if (_e56) {
            float ang_6 = (length((pc_1 - (rd_6 * tp))) / tp);
            float born = pow((1.0 - f_7.sx), 1.5);
            vec3 _e66 = add_3;
            add_3 = (_e66 + ((((vec3(4.0, 6.0, 4.0) * exp(-(pow((ang_6 / 0.0025), 2.0)))) + ((vec3(0.4, 1.6, 0.5) * exp((-(ang_6) / 0.012))) * 0.5)) * born) * k_7));
        }
    }
    if ((style_2 == 2)) {
        local_94 = (ta > -0.3);
    } else {
        local_94 = false;
    }
    bool _e100 = local_94;
    if (_e100) {
        local_95 = (ta < 0.06);
    } else {
        local_95 = false;
    }
    bool _e106 = local_95;
    if (_e106) {
        bool up_3 = (mode_1 == 4);
        float head = (MS_HL - (30000.0 * pow(clamp((-(ta) / 0.3), 0.0, 1.0), 2.0)));
        vec2 _e123 = ms_world(base_2, vec2((up_3 ? 0.0 : head), 0.0));
        vec2 _e130 = ms_world(base_2, vec2((up_3 ? 0.0 : (head - 30000.0)), 0.0));
        float ya = (base_2.y0_ + (up_3 ? ((MS_TOP - head) + MS_HL) : 30.0));
        vec3 _e151 = ray_seg(rd_6, (vec3(_e123.x, ya, _e123.y) - cam_4), (vec3(_e130.x, (ya + (up_3 ? 30000.0 : 0.0)), _e130.y) - cam_4));
        float w_9 = max(3.0, (_e151.y * 0.0015));
        if (!(sky_1)) {
            local_96 = (_e151.y > scene_len_1);
        } else {
            local_96 = false;
        }
        bool _e163 = local_96;
        float vis_4 = (_e163 ? 0.0 : 1.0);
        vec3 _e167 = add_3;
        add_3 = (_e167 + (((((((vec3(1.2, 2.6, 1.5) * exp(-(pow((_e151.x / w_9), 2.0)))) * (3.0 / w_9)) * 2.0) * smoothstep(-0.3, -0.1, ta)) * (1.0 - smoothstep(0.0, 0.06, ta))) * vis_4) * k_7));
    }
    if (blurring) {
        local_97 = present;
    } else {
        local_97 = false;
    }
    bool _e200 = local_97;
    if (_e200) {
        bool loop_init_11 = true;
        while(true) {
            if (!loop_init_11) {
                int _e280 = j_4;
                j_4 = (_e280 + 1);
            }
            loop_init_11 = false;
            int _e203 = j_4;
            if ((_e203 < 5)) {
            } else {
                break;
            }
            {
                int _e206 = j_4;
                float zc_1 = ((float(_e206) - 2.0) * 90.0);
                vec2 _e214 = ms_world(f_7, vec2(-560.0, zc_1));
                vec2 _e217 = ms_world(f_7, vec2(-820.0, zc_1));
                vec3 _e236 = ray_seg(rd_6, (vec3(_e214.x, (f_7.y0_ + (103.0 * f_7.sy)), _e214.y) - cam_4), (vec3(_e217.x, (f_7.y0_ + (103.0 * f_7.sy)), _e217.y) - cam_4));
                float w_10 = max((16.0 + (30.0 * _e236.z)), (_e236.y * 0.0015));
                if (!(sky_1)) {
                    local_98 = (_e236.y > scene_len_1);
                } else {
                    local_98 = false;
                }
                bool _e252 = local_98;
                float vis_5 = (_e252 ? 0.0 : 1.0);
                vec3 _e256 = add_3;
                add_3 = (_e256 + ((((((vec3(0.4, 2.2, 0.6) * exp(-(pow((_e236.x / w_10), 2.0)))) * (16.0 / w_10)) * (1.0 - _e236.z)) * 0.8) * vis_5) * k_7));
            }
        }
    }
    vec3 _e283 = add_3;
    vec3 _e284 = ship_tint(_e283);
    return _e284;
}

vec3 ms_charge_fx(MsFrame f_8, vec3 cam_5, vec3 rdb, vec3 focus_1, bool sky_2, float scene_len_2, float ship_t, float conv_env, float core_env, bool present_1, float time_3, float k_8) {
    vec3 add_4 = vec3(0.0);
    bool local_99 = false;
    int i_20 = 0;
    bool local_100 = false;
    bool local_101 = false;
    bool local_102 = false;
    bool local_103 = false;
    if ((conv_env > 0.001)) {
        local_99 = present_1;
    } else {
        local_99 = false;
    }
    bool _e20 = local_99;
    if (_e20) {
        bool loop_init_12 = true;
        while(true) {
            if (!loop_init_12) {
                int _e124 = i_20;
                i_20 = (_e124 + 1);
            }
            loop_init_12 = false;
            int _e24 = i_20;
            if ((_e24 < 6)) {
            } else {
                break;
            }
            {
                int _e27 = i_20;
                float a_16 = ((float(_e27) * TAU) / 6.0);
                vec2 _e40 = ms_world(f_8, vec2((MS_EM_X + (cos(a_16) * 30.0)), (sin(a_16) * 30.0)));
                vec3 e3_ = (vec3(_e40.x, (f_8.y0_ + MS_EYE_UP), _e40.y) - cam_5);
                vec3 _e48 = ray_seg(rdb, e3_, focus_1);
                float w_11 = max((1.2 + (0.8 * core_env)), (_e48.y * 0.0012));
                if (!(sky_2)) {
                    local_100 = (_e48.y > scene_len_2);
                } else {
                    local_100 = false;
                }
                bool _e63 = local_100;
                if (!(_e63)) {
                    local_101 = (_e48.y > (ship_t + 1.0));
                } else {
                    local_101 = true;
                }
                bool _e72 = local_101;
                float vis_6 = (_e72 ? 0.0 : 1.0);
                int _e78 = i_20;
                float flick_2 = (0.8 + (0.2 * sin(((time_3 * 40.0) + (float(_e78) * 2.1)))));
                vec3 _e88 = add_4;
                add_4 = (_e88 + (((((((vec3(2.6, 4.8, 2.6) * exp(-(pow((_e48.x / (w_11 * 0.5)), 2.0)))) + (vec3(0.15, 1.4, 0.3) * exp(-(pow((_e48.x / (w_11 * 2.5)), 2.0))))) * (1.2 / w_11)) * conv_env) * flick_2) * vis_6) * k_8));
            }
        }
    }
    if ((core_env > 0.001)) {
        float tc_1 = dot(focus_1, rdb);
        if ((tc_1 > 0.0)) {
            float dc_1 = length((focus_1 - (rdb * tc_1)));
            float R_1 = ((1.0 + (3.5 * core_env)) * (1.0 + (0.08 * sin((time_3 * 33.0)))));
            if (!(sky_2)) {
                local_102 = (tc_1 > scene_len_2);
            } else {
                local_102 = false;
            }
            bool _e152 = local_102;
            if (!(_e152)) {
                local_103 = (tc_1 > (ship_t + 2.0));
            } else {
                local_103 = true;
            }
            bool _e160 = local_103;
            float vis_7 = (_e160 ? 0.2 : 1.0);
            vec3 _e164 = add_4;
            add_4 = (_e164 + ((((((vec3(5.0, 6.0, 5.0) * exp(-(pow((dc_1 / R_1), 2.0)))) + ((vec3(0.6, 2.6, 0.8) * exp((-(dc_1) / R_1))) * 0.9)) + ((vec3(0.12, 0.7, 0.2) * exp((-(dc_1) / (R_1 * 5.0)))) * 0.4)) * core_env) * vis_7) * k_8));
        }
    }
    vec3 _e203 = add_4;
    vec3 _e204 = ship_tint(_e203);
    return _e204;
}

vec4 mothership(StageIn in_3) {
    MsFrame base_3 = MsFrame(vec2(0.0), vec2(0.0), vec2(0.0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    bool local_104 = false;
    bool local_105 = false;
    bool local_106 = false;
    vec2 off_1 = vec2(0.0);
    bool local_107 = false;
    float m_1 = 0.0;
    bool local_108 = false;
    vec3 col_3 = vec3(0.0);
    bool local_109 = false;
    bool local_110 = false;
    vec3 add_5 = vec3(0.0);
    bool local_111 = false;
    bool local_112 = false;
    bool local_113 = false;
    bool local_114 = false;
    bool local_115 = false;
    float heat_1 = 0.0;
    bool local_116 = false;
    float ship_t_1 = 1000000000.0;
    bool local_117 = false;
    bool local_118 = false;
    vec3 acc_3 = vec3(0.0);
    float cover = 0.0;
    int i_21 = 0;
    bool local_119 = false;
    bool local_120 = false;
    bool local_121 = false;
    vec3 hc = vec3(0.0);
    bool local_122 = false;
    float a_8 = 0.0;
    bool local_123 = false;
    bool local_124 = false;
    bool local_125 = false;
    int j_5 = 0;
    bool local_126 = false;
    bool local_127 = false;
    bool local_128 = false;
    bool local_129 = false;
    bool local_130 = false;
    bool local_131 = false;
    bool local_132 = false;
    float rc = 0.0;
    bool local_133 = false;
    vec3 b_8 = vec3(0.0);
    bool local_134 = false;
    bool local_135 = false;
    int j_6 = 0;
    bool local_136 = false;
    bool local_137 = false;
    bool local_138 = false;
    vec3 outc_3 = vec3(0.0);
    vec2 uv_6 = in_3.uv;
    float _e5 = _group_0_binding_4_fs.resolution.x;
    float _e9 = _group_0_binding_4_fs.resolution.y;
    float aspect_2 = (_e5 / _e9);
    float _e11 = now();
    vec4 _e14 = _group_0_binding_4_fs.camera_position;
    vec3 cam_8 = _e14.xyz;
    vec3 _e16 = target_pos();
    vec3 crel_2 = (_e16 - cam_8);
    float _e18 = intensity_v();
    float _e19 = seed_v();
    float ta_4 = (_e11 - MS_ARRIVE);
    float td_1 = (_e11 - MS_LEAVE);
    bool _e24 = ms_here(_e11);
    float here = float(_e24);
    float stir_1 = (smoothstep(0.0, MS_ARRIVE, _e11) * float((ta_4 < 0.0)));
    float charge = clamp(((_e11 - T_FIRE) / 4.0), 0.0, 1.0);
    float lit_3 = ((charge * (1.0 - smoothstep(MS_CUT, 21.4, _e11))) + smoothstep(21.4, MS_LEAVE, _e11));
    float chase_on_1 = (charge * (1.0 - smoothstep(MS_BEAM, 9.2, _e11)));
    float conv_env_1 = (smoothstep(5.2, 7.7, _e11) * (1.0 - smoothstep(MS_CUT, 20.4, _e11)));
    float core_env_1 = (smoothstep(6.0, MS_BEAM, _e11) * (1.0 - smoothstep(MS_CUT, 20.6, _e11)));
    float beam_env = (smoothstep(MS_BEAM, 8.04, _e11) * (1.0 - smoothstep(MS_CUT, 20.3, _e11)));
    float hit_t = (_e11 - MS_HIT);
    bool landed = (hit_t > 0.0);
    float flash_1 = (landed ? exp((-(hit_t) * 8.0)) : 0.0);
    float end_env_1 = (1.0 - smoothstep(26.0, MS_END, _e11));
    float _e96 = ms_sweep(_e11);
    vec2 _e97 = ms_axis();
    int _e98 = approach();
    vec2 right = vec2(-(_e97.y), _e97.x);
    base_3.ax = ((_e98 == 1) ? _e97 : ((_e98 == 3) ? -(right) : ((_e98 == 2) ? right : -(_e97))));
    vec2 _e119 = base_3.ax;
    base_3.c = (_e16.xz - (_e119 * MS_EM_X));
    float _e126 = base_3.ax.y;
    float _e130 = base_3.ax.x;
    base_3.sd = vec2(-(_e126), _e130);
    base_3.y0_ = (_e16.y + MS_H);
    base_3.shift = 0.0;
    base_3.sx = 1.0;
    base_3.sz = 1.0;
    base_3.sy = 1.0;
    base_3.px = 0.0;
    int _e146 = arrival_style();
    MsFrame _e147 = base_3;
    MsFrame _e148 = ms_frame(_e147, _e11, _e98, _e146);
    float _e149 = ms_stop(_e146);
    float wake_2 = (ta_4 - _e149);
    float land = (smoothstep(_e149, (_e149 + 0.3), ta_4) * float((td_1 < MS_OUT)));
    if ((ta_4 >= 0.0)) {
        local_104 = (ta_4 < (_e149 + MS_SHUTTER));
    } else {
        local_104 = false;
    }
    bool arriving = local_104;
    if (!(arriving)) {
        if ((td_1 > 0.0)) {
            local_106 = (td_1 < 0.34170002);
        } else {
            local_106 = false;
        }
        bool _e177 = local_106;
        local_105 = _e177;
    } else {
        local_105 = true;
    }
    bool blurring_1 = local_105;
    float eng_1 = ((0.35 + (2.6 * float(blurring_1))) + (1.5 * smoothstep(21.4, MS_LEAVE, _e11)));
    float _e193 = base_3.y0_;
    vec3 focus_2 = (vec3(_e16.x, (_e193 - MS_FOCUS), _e16.z) - cam_8);
    vec2 gxz = (_e16.xz + ((_e97 * TRENCH_L) * _e96));
    vec3 G = (vec3(gxz.x, _e16.y, gxz.y) - cam_8);
    vec4 _e211 = _group_0_binding_4_fs.sun;
    vec3 sun_2 = _e211.xyz;
    float day_2 = clamp(((sun_2.y * 2.5) + 0.35), 0.0, 1.0);
    vec4 _e221 = _group_0_binding_4_fs.sky_color;
    vec3 _e224 = srgb_to_linear(clamp(_e221.xyz, vec3(0.0), vec3(1.0)));
    vec3 haze_4 = ((_e224 * 0.95) + vec3(0.01, 0.015, 0.03));
    float _e232 = depth_at(uv_6);
    bool _e233 = is_sky(_e232);
    vec3 _e236 = world_offset(uv_6, (_e233 ? 0.5 : _e232));
    vec3 p0_4 = (cam_8 + _e236);
    float tr_1 = ((td_1 > 0.0) ? (td_1 - 0.15) : (ta_4 - _e149));
    MsFrame _e244 = base_3;
    vec2 _e245 = ms_air(uv_6, cam_8, p0_4, _e233, stir_1, tr_1, wake_2, _e244, _e148, _e11, _e19, _e18);
    off_1 = _e245;
    vec3 _e247 = project_rel(focus_2);
    vec3 _e248 = project_rel(G);
    if ((beam_env > 0.001)) {
        local_107 = (_e248.z > 0.0);
    } else {
        local_107 = false;
    }
    bool _e257 = local_107;
    if (_e257) {
        m_1 = (exp((-(length(((uv_6 - _e248.xy) * vec2(aspect_2, 1.0)))) / 0.05)) * 1.5);
        if ((_e247.z > 0.0)) {
            vec2 a2_ = (_e247.xy * vec2(aspect_2, 1.0));
            vec2 ab2_ = ((_e248.xy * vec2(aspect_2, 1.0)) - a2_);
            float u2_ = clamp((dot(((uv_6 * vec2(aspect_2, 1.0)) - a2_), ab2_) / max(dot(ab2_, ab2_), 1e-6)), 0.0, 1.0);
            float sdist_1 = length((((uv_6 * vec2(aspect_2, 1.0)) - a2_) - (ab2_ * u2_)));
            float _e300 = m_1;
            m_1 = (_e300 + exp(-(pow((sdist_1 / (0.012 + (0.02 * u2_))), 2.0))));
        }
        float _e311 = m_1;
        if ((_e311 > 0.01)) {
            float _e324 = gnoise2_(((uv_6 * vec2(140.0, 50.0)) + vec2(0.0, (-(_e11) * 9.0))));
            float _e335 = gnoise2_(((uv_6 * vec2(140.0, 50.0)) + vec2(31.0, (-(_e11) * 8.0))));
            vec2 hw_1 = (vec2(_e324, _e335) - vec2(0.5));
            vec2 _e340 = off_1;
            float _e343 = m_1;
            off_1 = (_e340 + ((((hw_1 * 0.004) * _e343) * beam_env) * _e18));
        }
    }
    vec2 _e348 = off_1;
    vec2 uv2_4 = clamp((uv_6 + _e348), vec2(0.002), vec2(0.998));
    float _e355 = depth_at(uv2_4);
    bool _e356 = is_sky(_e355);
    vec3 _e359 = world_offset(uv2_4, (_e356 ? 0.5 : _e355));
    float scene_len_5 = (!(_e356) ? length(_e359) : 1000000000.0);
    vec3 _e365 = world_offset(uv2_4, RAY_DEPTH);
    vec3 rd_9 = normalize(_e365);
    vec3 _e368 = world_offset(uv_6, RAY_DEPTH);
    vec3 rdb_1 = normalize(_e368);
    vec3 P_2 = (cam_8 + _e359);
    if (!(_e356)) {
        local_108 = (abs(((P_2.y - CLOUD_Y) - 2.0)) < 6.0);
    } else {
        local_108 = false;
    }
    bool cloud = local_108;
    float ca_3 = ((flash_1 * 0.02) * _e18);
    vec2 ca_dir_2 = ((uv2_4 - vec2(0.5)) * ca_3);
    vec4 _e395 = orbitalSceneLod(_group_0_binding_0_fs, vec2((uv2_4 + ca_dir_2)), 0.0);
    vec4 _e400 = orbitalSceneLod(_group_0_binding_0_fs, vec2(uv2_4), 0.0);
    vec4 _e406 = orbitalSceneLod(_group_0_binding_0_fs, vec2((uv2_4 - ca_dir_2)), 0.0);
    vec3 _e409 = srgb_to_linear(vec3(_e395.x, _e400.y, _e406.z));
    col_3 = _e409;
    float dim_4 = clamp((1.0 - (((((0.12 * stir_1) + (0.14 * land)) + (((0.22 * charge) * charge) * (1.0 - float(landed)))) + (0.1 * beam_env)) * _e18)), 0.3, 1.0);
    vec3 _e433 = col_3;
    col_3 = (_e433 * dim_4);
    if (!(_e356)) {
        local_109 = _e24;
    } else {
        local_109 = false;
    }
    bool _e439 = local_109;
    if (_e439) {
        local_110 = (P_2.y < _e148.y0_);
    } else {
        local_110 = false;
    }
    bool _e446 = local_110;
    if (_e446) {
        vec3 ls = ((sun_2.y > 0.0) ? normalize(vec3(sun_2.x, max(sun_2.y, 0.6), sun_2.z)) : vec3(0.0, 1.0, 0.0));
        vec2 Q = (P_2.xz + ((ls.xz * ((_e148.y0_ + 28.0) - P_2.y)) / vec2(ls.y)));
        float pen = (4.0 + ((_e148.y0_ - P_2.y) * 0.012));
        vec2 _e482 = ms_local(_e148, Q);
        float _e484 = ms_tier(_e482, 2);
        float sh = (1.0 - smoothstep(-(pen), pen, _e484));
        vec3 _e488 = col_3;
        col_3 = (_e488 * (1.0 - (((sh * ((0.6 * day_2) + 0.15)) * land) * _e18)));
    }
    if (!(_e356)) {
        vec2 rel2_ = (P_2.xz - _e16.xz);
        float r_13 = length(rel2_);
        float dy_2 = (P_2.y - _e16.y);
        float on_ground_1 = (1.0 - smoothstep(25.0, 40.0, dy_2));
        vec3 _e519 = ship_tint(vec3(0.3, 1.8, 0.45));
        if ((charge > 0.0)) {
            local_111 = (hit_t < 0.5);
        } else {
            local_111 = false;
        }
        bool _e527 = local_111;
        if (_e527) {
            float fade_1 = (1.0 - smoothstep(0.0, 0.5, hit_t));
            float conv_2 = mix(60.0, 5.0, pow(charge, 1.5));
            float g_2 = ((((exp((-(r_13) / 14.0)) * charge) * charge) * 1.4) + ((exp(-(pow(((r_13 - conv_2) / 1.2), 2.0))) * charge) * 1.6));
            vec3 _e557 = add_5;
            add_5 = (_e557 + ((((_e519 * g_2) * on_ground_1) * fade_1) * _e18));
            if ((r_13 < 50.0)) {
                float _e574 = gfbm2_(((rel2_ * 0.08) + vec2((_e11 * 0.4), (-(_e11) * 0.3))));
                float dust = ((((clamp(((_e574 * 1.5) - 0.45), 0.0, 1.0) * charge) * (1.0 - smoothstep(10.0, 45.0, r_13))) * on_ground_1) * fade_1);
                vec3 _e589 = col_3;
                col_3 = mix(_e589, (vec3(0.3, 0.26, 0.2) * dim_4), ((dust * 0.4) * _e18));
            }
        }
        float gr_1 = length((P_2.xz - gxz));
        vec3 _e602 = col_3;
        vec3 _e603 = col_3;
        col_3 = (_e602 + ((((((_e603 * _e519) * core_env_1) * 0.6) / vec3((1.0 + ((r_13 * r_13) / 40000.0)))) * on_ground_1) * _e18));
        vec3 _e618 = col_3;
        vec3 _e619 = col_3;
        col_3 = (_e618 + ((((((_e619 * vec3(1.4, 2.0, 1.3)) * beam_env) * 1500.0) / vec3((((gr_1 * gr_1) + (dy_2 * dy_2)) + 150.0))) * on_ground_1) * _e18));
        if ((beam_env > 0.001)) {
            local_112 = (gr_1 < 32.0);
        } else {
            local_112 = false;
        }
        bool _e645 = local_112;
        if (_e645) {
            float ang_7 = atan((P_2.z - gxz.y), (P_2.x - gxz.x));
            float _e663 = gfbm2_((vec2((ang_7 * 3.0), ((gr_1 * 0.15) - (_e11 * 3.0))) + vec2(_e19)));
            float splash = ((exp((-(gr_1) / 4.0)) * 1.5) + (smoothstep(0.55, 0.85, _e663) * exp((-(gr_1) / 12.0))));
            vec3 _e679 = add_5;
            vec3 _e688 = lava_ramp((0.55 + (0.5 * exp((-(gr_1) / 6.0)))));
            add_5 = (_e679 + (((((_e688 * splash) * beam_env) * on_ground_1) * 3.0) * _e18));
        }
        float along_1 = dot(rel2_, _e97);
        float across = dot(rel2_, vec2(-(_e97.y), _e97.x));
        if (landed) {
            local_113 = (along_1 > -30.0);
        } else {
            local_113 = false;
        }
        bool _e707 = local_113;
        if (_e707) {
            local_114 = (along_1 < 112.0);
        } else {
            local_114 = false;
        }
        bool _e713 = local_114;
        if (_e713) {
            local_115 = (abs(across) < 30.0);
        } else {
            local_115 = false;
        }
        bool _e720 = local_115;
        if (_e720) {
            float deep = clamp((-(dy_2) / 16.0), 0.0, 1.0);
            float m_cr = (1.0 - smoothstep(14.0, 26.0, r_13));
            if ((m_cr > 0.0)) {
                float _e734 = heat_1;
                heat_1 = max(_e734, ((((exp((-(hit_t) / 7.0)) * 0.9) * (1.0 - ((0.5 * r_13) / 26.0))) + ((deep * 0.5) * exp((-(hit_t) / 20.0)))) * m_cr));
            }
            float swept = (TRENCH_L * _e96);
            if ((along_1 > 0.0)) {
                local_116 = (along_1 < (swept + 3.0));
            } else {
                local_116 = false;
            }
            bool _e768 = local_116;
            if (_e768) {
                float _e771 = ms_when((along_1 / TRENCH_L));
                float age_2 = max((_e11 - _e771), 0.0);
                float m_tr = ((1.0 - smoothstep(5.0, 9.0, abs(across))) * (1.0 - smoothstep(swept, (swept + 3.0), along_1)));
                float _e787 = heat_1;
                heat_1 = max(_e787, (((exp((-(age_2) / 6.0)) * 0.95) + ((deep * 0.5) * exp((-(age_2) / 18.0)))) * m_tr));
            }
            float _e804 = heat_1;
            if ((_e804 > 0.01)) {
                float _e814 = gfbm2_(((rel2_ * 0.16) + vec2((P_2.y * 0.3), _e19)));
                float veins = exp(-(pow(((_e814 - 0.5) / 0.07), 2.0)));
                float _e825 = heat_1;
                float _e826 = heat_1;
                float molten = mix((veins * 0.9), 1.0, (_e825 * _e826));
                float _e830 = heat_1;
                float _e839 = gnoise2_(((rel2_ * 0.9) + vec2((_e11 * 0.2), P_2.y)));
                float hh = ((_e830 * molten) * (0.8 + (0.4 * _e839)));
                vec3 _e845 = add_5;
                vec3 _e846 = lava_ramp(hh);
                float _e847 = heat_1;
                add_5 = (_e845 + (((((_e846 * smoothstep(0.03, 0.25, (_e847 * molten))) * on_ground_1) * end_env_1) * 2.4) * _e18));
                vec3 _e859 = col_3;
                float _e860 = heat_1;
                col_3 = (_e859 * (1.0 - (((0.6 * smoothstep(0.0, 0.3, _e860)) * (1.0 - molten)) * on_ground_1)));
            }
        }
    }
    if (!(_e24)) {
        local_117 = blurring_1;
    } else {
        local_117 = true;
    }
    bool _e879 = local_117;
    if (_e879) {
        int n_5 = (blurring_1 ? 12 : 1);
        float _e885 = ign(in_3.position.xy);
        float jit = (blurring_1 ? _e885 : 0.0);
        if (arriving) {
            local_118 = (_e146 == 0);
        } else {
            local_118 = false;
        }
        bool film = local_118;
        float t_film = (MS_ARRIVE + (floor((ta_4 / MS_SHUTTER)) * MS_SHUTTER));
        bool loop_init_13 = true;
        while(true) {
            if (!loop_init_13) {
                int _e1074 = i_21;
                i_21 = (_e1074 + 1);
            }
            loop_init_13 = false;
            int _e908 = i_21;
            if ((_e908 < n_5)) {
            } else {
                break;
            }
            {
                int _e910 = i_21;
                float fr_2 = ((float(_e910) + jit) / float(n_5));
                float ts_1 = (film ? (t_film + (0.02085 * fr_2)) : (_e11 - (blurring_1 ? (MS_SHUTTER * fr_2) : 0.0)));
                bool _e924 = ms_here(ts_1);
                if (!(_e924)) {
                    continue;
                }
                MsFrame _e926 = base_3;
                MsFrame _e927 = ms_frame(_e926, ts_1, _e98, _e146);
                MsHit _e928 = ms_trace(_e927, cam_8, rd_9);
                if ((_e928.kind < 0)) {
                    continue;
                }
                if (cloud) {
                    local_119 = (cam_8.y > 200.0);
                } else {
                    local_119 = false;
                }
                bool over = local_119;
                if (!(_e356)) {
                    local_120 = (_e928.t < scene_len_5);
                } else {
                    local_120 = true;
                }
                bool _e948 = local_120;
                if (!(_e948)) {
                    local_121 = over;
                } else {
                    local_121 = true;
                }
                bool _e953 = local_121;
                float vis_8 = ((_e953 ? 1.0 : (cloud ? 0.3 : 0.0)) * (1.0 - smoothstep(4000.0, 20000.0, _e928.t)));
                if ((vis_8 > 0.0)) {
                    vec3 _e971 = ms_hull(_e928, _e927, rd_9, ts_1, lit_3, chase_on_1, core_env_1, beam_env, focus_2, haze_4, day_2, sun_2, (blurring_1 ? 3.0 : 1.0), ((ts_1 - MS_ARRIVE) - _e149), eng_1);
                    hc = _e971;
                    if (over) {
                        local_122 = (_e928.t > scene_len_5);
                    } else {
                        local_122 = false;
                    }
                    bool _e978 = local_122;
                    if (_e978) {
                        vec3 _e979 = hc;
                        vec3 _e980 = col_3;
                        float _e981 = luminance(_e980);
                        hc = mix(_e979, vec3(_e981), 0.3);
                    }
                    a_8 = vis_8;
                    if ((_e146 == 2)) {
                        local_123 = (ts_1 < MS_LEAVE);
                    } else {
                        local_123 = false;
                    }
                    bool _e993 = local_123;
                    if (_e993) {
                        float w_12 = clamp(((max(_e927.sx, _e927.sy) - 1.0) / 8.0), 0.0, 1.0);
                        float _e1007 = ms_half_w(_e928.q.x);
                        float az_1 = (abs(_e928.q.y) / max(_e1007, 1.0));
                        float smear = ((((exp(-(pow((az_1 / 0.05), 2.0))) * 2.0) + (pow((0.5 + (0.5 * cos((az_1 * 40.0)))), 12.0) * 0.6)) + 0.15) * (0.4 + (0.6 * clamp(((_e928.q.x + MS_HL) / 1120.0), 0.0, 1.0))));
                        a_8 = (vis_8 * (1.0 - (0.9 * w_12)));
                        vec3 _e1050 = hc;
                        vec3 _e1060 = ship_tint(vec3(1.2, 2.6, 1.5));
                        hc = ((_e1050 * (1.0 - (0.9 * w_12))) + ((_e1060 * smear) * w_12));
                    }
                    vec3 _e1064 = acc_3;
                    vec3 _e1065 = hc;
                    acc_3 = (_e1064 + (_e1065 * vis_8));
                    float _e1068 = cover;
                    float _e1069 = a_8;
                    cover = (_e1068 + _e1069);
                    float _e1071 = ship_t_1;
                    ship_t_1 = min(_e1071, _e928.t);
                }
            }
        }
        float _e1077 = cover;
        float a_17 = (_e1077 / float(n_5));
        vec3 _e1080 = col_3;
        vec3 _e1084 = acc_3;
        col_3 = ((_e1080 * (1.0 - a_17)) + (_e1084 / vec3(float(n_5))));
        vec3 _e1089 = add_5;
        add_5 = (_e1089 * (1.0 - a_17));
        float _e1093 = ship_t_1;
        ship_t_1 = ((a_17 > 0.5) ? _e1093 : 1000000000.0);
    }
    float _e1098 = ship_t_1;
    float scene_lh = min(scene_len_5, _e1098);
    if (_e356) {
        float _e1102 = ship_t_1;
        local_124 = (_e1102 > 100000000.0);
    } else {
        local_124 = false;
    }
    bool sky_h = local_124;
    vec3 _e1107 = add_5;
    MsFrame _e1108 = base_3;
    vec3 _e1109 = ms_arrival_fx(_e148, _e1108, cam_8, rd_9, sky_h, scene_lh, ta_4, _e98, _e146, blurring_1, _e24, _e18);
    add_5 = (_e1107 + _e1109);
    if ((wake_2 > 1.0)) {
        local_125 = (td_1 < 0.0);
    } else {
        local_125 = false;
    }
    bool _e1118 = local_125;
    if (_e1118) {
        bool loop_init_14 = true;
        while(true) {
            if (!loop_init_14) {
                int _e1246 = j_5;
                j_5 = (_e1246 + 1);
            }
            loop_init_14 = false;
            int _e1121 = j_5;
            if ((_e1121 < 6)) {
            } else {
                break;
            }
            {
                int _e1124 = j_5;
                float fj_2 = float(_e1124);
                float rad = (180.0 + (240.0 * fract((fj_2 * 0.618034))));
                int _e1140 = j_5;
                float spd = ((0.05 + (0.07 * fract((fj_2 * 0.754878)))) * (((_e1140 % 2) == 0) ? 1.0 : -1.0));
                float ang_8 = ((fj_2 * 1.7) + ((wake_2 - 1.0) * spd));
                float lift_1 = smoothstep(1.0, 4.0, wake_2);
                vec2 _e1159 = base_3.c;
                vec2 _e1161 = base_3.ax;
                vec2 _e1167 = base_3.sd;
                vec2 pc2_ = ((_e1159 + ((_e1161 * cos(ang_8)) * rad)) + (((_e1167 * sin(ang_8)) * rad) * 0.5));
                float _e1176 = base_3.y0_;
                vec3 pc_2 = (vec3(pc2_.x, ((_e1176 - 20.0) - ((25.0 + (40.0 * fract((fj_2 * 0.381966)))) * lift_1)), pc2_.y) - cam_8);
                float tp_1 = dot(pc_2, rd_9);
                if ((tp_1 > 0.0)) {
                    if (!(sky_h)) {
                        local_127 = (tp_1 < scene_lh);
                    } else {
                        local_127 = true;
                    }
                    bool _e1201 = local_127;
                    local_126 = _e1201;
                } else {
                    local_126 = false;
                }
                bool _e1203 = local_126;
                if (_e1203) {
                    float dpx = length((pc_2 - (rd_9 * tp_1)));
                    float fpc = (tp_1 * 0.0012);
                    vec3 _e1209 = col_3;
                    col_3 = mix(_e1209, vec3(0.03, 0.03, 0.035), ((1.0 - smoothstep(2.5, (2.5 + fpc), dpx)) * lift_1));
                    float blink_1 = step(0.7, fract(((_e11 * 1.3) + (fj_2 * 0.37))));
                    vec3 _e1230 = add_5;
                    float _e1239 = ms_line(dpx, 0.6, fpc);
                    add_5 = (_e1230 + ((((mix(vec3(0.4, 2.4, 0.6), vec3(3.0), blink_1) * _e1239) * 2.0) * lift_1) * _e18));
                }
            }
        }
    }
    if ((td_1 > 0.0)) {
        local_128 = (td_1 < 0.90000004);
    } else {
        local_128 = false;
    }
    bool _e1256 = local_128;
    if (_e1256) {
        bool up_4 = (_e98 == 4);
        MsFrame _e1259 = base_3;
        vec2 _e1265 = ms_world(_e1259, vec2((up_4 ? 0.0 : 600.0), 0.0));
        MsFrame _e1266 = base_3;
        vec2 _e1272 = ms_world(_e1266, vec2((up_4 ? 0.0 : 24560.0), 0.0));
        float _e1275 = base_3.y0_;
        float _e1285 = base_3.y0_;
        vec3 _e1293 = ray_seg(rd_9, (vec3(_e1265.x, (_e1275 + (up_4 ? 190.0 : 30.0)), _e1265.y) - cam_8), (vec3(_e1272.x, (_e1285 + (up_4 ? MS_FAR : 30.0)), _e1272.y) - cam_8));
        float w_13 = max(2.0, (_e1293.y * 0.0012));
        if (!(sky_h)) {
            local_129 = (_e1293.y > scene_lh);
        } else {
            local_129 = false;
        }
        bool _e1305 = local_129;
        float vis_9 = (_e1305 ? 0.0 : 1.0);
        vec3 _e1309 = add_5;
        add_5 = (_e1309 + (((((((vec3(0.5, 1.6, 0.6) * exp(-(pow((_e1293.x / w_13), 2.0)))) * (2.0 / w_13)) * 0.6) * smoothstep(0.08, 0.2, td_1)) * exp((-(max((td_1 - MS_OUT), 0.0)) * 5.0))) * vis_9) * _e18));
    }
    if (landed) {
        local_130 = (end_env_1 > 0.001);
    } else {
        local_130 = false;
    }
    bool _e1347 = local_130;
    if (_e1347) {
        vec3 s0_1 = (crel_2 + vec3(0.0, 9.0, 0.0));
        vec3 s1_1 = (G + vec3(0.0, 9.0, 0.0));
        vec3 _e1358 = ray_seg(rd_9, s0_1, s1_1);
        float along_2 = ((_e1358.z * TRENCH_L) * _e96);
        float _e1366 = ms_when((along_2 / TRENCH_L));
        float age_3 = max((_e11 - ((_e96 > 0.0) ? _e1366 : MS_HIT)), 0.0);
        float W = (6.0 + (1.6 * age_3));
        if ((_e1358.x < (W * 2.5))) {
            float vis_10 = (!(sky_h) ? (1.0 - smoothstep((scene_lh - 1.0), (scene_lh + 1.0), _e1358.y)) : 1.0);
            float yq = ((cam_8.y + (rd_9.y * _e1358.y)) - _e16.y);
            float _e1411 = gfbm2_(vec2(((along_2 * 0.07) - (_e11 * 0.1)), (((yq * 0.09) - (_e11 * 0.55)) + _e19)));
            float dens_3 = (((((exp(-(pow((_e1358.x / W), 2.0))) * smoothstep(0.3, 2.0, age_3)) * exp((-(age_3) / 12.0))) * (0.25 + (1.1 * _e1411))) * smoothstep(-2.0, 3.0, yq)) * end_env_1);
            float under = (exp((-(max(yq, 0.0)) / 8.0)) * exp((-(age_3) / 6.0)));
            float pale = smoothstep(1.0, 8.0, age_3);
            vec3 _e1472 = lava_ramp(0.5);
            vec3 steam = ((((mix(vec3(0.1, 0.09, 0.085), vec3(0.7, 0.7, 0.72), pale) * dim_4) * (0.35 + (0.65 * day_2))) * (0.65 + (0.5 * _e1411))) + ((_e1472 * under) * 0.5));
            vec3 _e1477 = col_3;
            col_3 = mix(_e1477, steam, (clamp((dens_3 * 0.85), 0.0, 1.0) * vis_10));
        }
    }
    vec3 _e1483 = add_5;
    float _e1484 = ship_t_1;
    vec3 _e1485 = ms_charge_fx(_e148, cam_8, rdb_1, focus_2, _e356, scene_len_5, _e1484, conv_env_1, core_env_1, _e24, _e11, _e18);
    add_5 = (_e1483 + _e1485);
    if ((charge > 0.6)) {
        local_131 = (_e11 < MS_HIT);
    } else {
        local_131 = false;
    }
    bool _e1494 = local_131;
    if (_e1494) {
        vec3 _e1495 = ray_seg(rd_9, focus_2, crel_2);
        float w_14 = max(0.12, (_e1495.y * 0.0008));
        if (!(sky_h)) {
            local_132 = (_e1495.y > (scene_lh + 0.5));
        } else {
            local_132 = false;
        }
        bool _e1509 = local_132;
        float vis_11 = (_e1509 ? 0.0 : 1.0);
        vec3 _e1513 = add_5;
        add_5 = (_e1513 + ((((((vec3(0.7, 3.0, 0.9) * exp(-(pow((_e1495.x / w_14), 2.0)))) * (0.12 / w_14)) * smoothstep(0.6, 0.9, charge)) * (0.7 + (0.3 * sin((_e11 * 50.0))))) * vis_11) * _e18));
    }
    if ((beam_env > 0.001)) {
        vec3 gb = (G - vec3(0.0, 18.0, 0.0));
        vec3 _e1550 = ray_seg(rdb_1, focus_2, gb);
        float lenb = length((gb - focus_2));
        float along_3 = (_e1550.z * lenb);
        float hgt = (((focus_2.y + cam_8.y) + ((gb.y - focus_2.y) * _e1550.z)) - _e16.y);
        float head_1 = clamp(((_e11 - MS_BEAM) / 0.19999981), 0.0, 1.0);
        rc = (((1.9 + (0.3 * sin((_e11 * 29.0)))) + (0.25 * sin(((_e11 * 47.0) + 1.0)))) * (1.0 + (1.2 * exp((-(max(hit_t, 0.0)) * 2.5)))));
        float _e1598 = rc;
        rc = (((_e1598 * (1.0 + (1.6 * exp((-(max(hgt, 0.0)) / 7.0))))) * mix(0.45, 1.0, smoothstep(0.0, 0.25, _e1550.z))) * _e18);
        float _e1619 = rc;
        float w_15 = max(_e1619, (_e1550.y * 0.0012));
        float _e1624 = rc;
        float e_4 = (_e1624 / w_15);
        float dd_3 = _e1550.x;
        if ((dd_3 < (w_15 * 40.0))) {
            local_133 = (_e1550.z <= (head_1 + 0.01));
        } else {
            local_133 = false;
        }
        bool _e1637 = local_133;
        if (_e1637) {
            float vis_12 = (!(sky_h) ? (1.0 - smoothstep((scene_lh - 0.8), (scene_lh + 0.8), _e1550.y)) : 1.0);
            float vis_mix = mix(0.1, 1.0, vis_12);
            vec3 bdir = ((gb - focus_2) / vec3(max(lenb, 0.001)));
            vec3 e1_2 = normalize(cross(bdir, vec3(1.0, 0.0, 0.0)));
            vec3 e2_2 = cross(bdir, e1_2);
            vec3 ofs = ((rdb_1 * _e1550.y) - (focus_2 + ((gb - focus_2) * _e1550.z)));
            float ang_9 = atan(dot(ofs, e2_2), dot(ofs, e1_2));
            float _e1682 = gnoise2_(vec2((ang_9 * 1.6), ((along_3 * 0.05) - (_e11 * 16.0))));
            float _e1693 = gnoise2_(vec2(((ang_9 * 2.3) + 7.0), ((along_3 * 0.11) - (_e11 * 23.0))));
            float pulse = pow((0.5 + (0.5 * sin(((along_3 * 0.04) - (_e11 * 55.0))))), 6.0);
            float strand_1 = (pow((0.5 + (0.5 * sin((((ang_9 * 3.0) + (along_3 * 0.12)) - (_e11 * 20.0))))), 12.0) * exp(-(pow(((dd_3 - (w_15 * 2.2)) / (w_15 * 0.6)), 2.0))));
            float core_5 = exp(-(pow((dd_3 / (w_15 * 0.55)), 2.0)));
            float inner_1 = (exp(-(pow((dd_3 / (w_15 * 1.5)), 2.0))) * (0.6 + (0.8 * _e1682)));
            float outer = (exp(-(pow((dd_3 / (w_15 * 3.8)), 2.0))) * (0.4 + (0.9 * _e1693)));
            float _e1764 = rc;
            float halo_1 = exp((-(dd_3) / (_e1764 * 5.0)));
            b_8 = ((((((core_5 * vec3(9.0, 10.0, 9.0)) * (1.0 + (0.6 * pulse))) + ((inner_1 * vec3(0.35, 1.8, 0.5)) * (1.0 + (1.2 * pulse)))) + (outer * vec3(0.04, 0.45, 0.1))) + ((strand_1 * vec3(0.6, 2.8, 0.8)) * 0.8)) * e_4);
            vec3 _e1806 = b_8;
            b_8 = (_e1806 + (((vec3(8.0, 9.5, 8.0) * exp(-(pow((((_e1550.z - head_1) * lenb) / 6.0), 2.0)))) * core_5) * (1.0 - step(1.0, head_1))));
            vec3 _e1828 = add_5;
            vec3 _e1829 = b_8;
            vec3 _e1838 = ship_tint(((_e1829 * vis_12) + ((halo_1 * vec3(0.03, 0.18, 0.05)) * vis_mix)));
            add_5 = (_e1828 + ((_e1838 * beam_env) * _e18));
        }
        if (landed) {
            vec3 cf = (G + vec3(0.0, 3.5, 0.0));
            float tcp_1 = dot(cf, rd_9);
            float Rf_1 = ((8.0 + (6.0 * exp((-(hit_t) * 2.0)))) * (0.9 + (0.1 * sin((_e11 * 13.0)))));
            if ((tcp_1 > 0.0)) {
                float dc_2 = length((cf - (rd_9 * tcp_1)));
                if ((dc_2 < (Rf_1 * 4.0))) {
                    vec3 hx = normalize((cross(rd_9, vec3(0.0, 1.0, 0.0)) + vec3(0.0001, 0.0, 0.0)));
                    vec3 hy_1 = cross(hx, rd_9);
                    vec3 on_2 = ((rd_9 * tcp_1) - cf);
                    float ang_10 = atan(dot(on_2, hy_1), dot(on_2, hx));
                    float _e1899 = gfbm2_(vec2(((ang_10 * 1.3) + _e19), (((dc_2 / Rf_1) * 2.0) - (_e11 * 2.5))));
                    float fire_2 = exp(-(pow((dc_2 / (Rf_1 * (0.75 + (0.5 * _e1899)))), 2.0)));
                    float visf_1 = (!(sky_h) ? smoothstep((tcp_1 - (Rf_1 * 1.3)), (tcp_1 - (Rf_1 * 0.2)), scene_lh) : 1.0);
                    vec3 _e1920 = add_5;
                    vec3 _e1925 = lava_ramp((0.55 + (0.5 * fire_2)));
                    vec3 _e1933 = ship_tint(vec3(0.5, 2.0, 0.6));
                    add_5 = (_e1920 + ((((((_e1925 * fire_2) * 3.5) + (((_e1933 * fire_2) * fire_2) * 1.5)) * visf_1) * beam_env) * _e18));
                    vec3 _e1943 = add_5;
                    add_5 = (_e1943 + (((((vec3(1.6, 1.0, 0.6) * exp((-(dc_2) / Rf_1))) * 0.25) * beam_env) * visf_1) * _e18));
                }
            }
        }
    }
    float _e1963 = ms_sweep((_e11 - 2.0));
    vec2 sp_a = (_e16.xz + ((_e97 * TRENCH_L) * _e1963));
    vec3 _e1978 = ray_seg(rd_9, (vec3(sp_a.x, (_e16.y + 8.0), sp_a.y) - cam_8), (G + vec3(0.0, 8.0, 0.0)));
    if (landed) {
        local_134 = (_e11 < 22.0);
    } else {
        local_134 = false;
    }
    bool _e1984 = local_134;
    if (_e1984) {
        local_135 = (_e1978.x < 50.0);
    } else {
        local_135 = false;
    }
    bool _e1991 = local_135;
    if (_e1991) {
        bool loop_init_15 = true;
        while(true) {
            if (!loop_init_15) {
                int _e2176 = j_6;
                j_6 = (_e2176 + 1);
            }
            loop_init_15 = false;
            int _e1994 = j_6;
            if ((_e1994 < 24)) {
            } else {
                break;
            }
            {
                int _e1997 = j_6;
                float fj_3 = float(_e1997);
                float life_1 = (1.1 + (0.9 * fract((fj_3 * 0.618034))));
                float ph_1 = (fract((fj_3 * 0.754878)) * life_1);
                float gen = floor(((_e11 + ph_1) / life_1));
                float tb_2 = ((gen * life_1) - ph_1);
                float a_18 = (_e11 - tb_2);
                if (!((tb_2 < MS_HIT))) {
                    local_136 = (tb_2 > MS_CUT);
                } else {
                    local_136 = true;
                }
                bool _e2024 = local_136;
                if (_e2024) {
                    continue;
                }
                float _e2028 = ms_sweep(tb_2);
                vec2 src_1 = (_e16.xz + ((_e97 * TRENCH_L) * _e2028));
                int _e2031 = j_6;
                uvec3 _e2036 = pcg3d(uvec3(uint(_e2031), uint(gen), uint(_e19)));
                vec3 hv_2 = (vec3(_e2036) * 2.3283064e-10);
                float h1_ = hv_2.x;
                float h2_1 = hv_2.y;
                float h3_ = hv_2.z;
                float az_2 = (h1_ * TAU);
                float vh_2 = (6.0 + (16.0 * h2_1));
                float vy_2 = (12.0 + (18.0 * h3_));
                vec3 s3_ = (vec3(src_1.x, (_e16.y + 1.0), src_1.y) - cam_8);
                vec3 pa_2 = (s3_ + vec3(((cos(az_2) * vh_2) * a_18), ((vy_2 * a_18) - ((16.0 * a_18) * a_18)), ((sin(az_2) * vh_2) * a_18)));
                float a1_ = max((a_18 - 0.06), 0.0);
                vec3 pb_2 = (s3_ + vec3(((cos(az_2) * vh_2) * a1_), ((vy_2 * a1_) - ((16.0 * a1_) * a1_)), ((sin(az_2) * vh_2) * a1_)));
                if (((pa_2.y + cam_8.y) < (_e16.y - 4.0))) {
                    continue;
                }
                vec3 _e2097 = ray_seg(rd_9, pa_2, pb_2);
                float vis_13 = (!(sky_h) ? (1.0 - smoothstep((scene_lh - 0.4), (scene_lh + 0.4), _e2097.y)) : 1.0);
                int _e2109 = j_6;
                if (((_e2109 % 3) == 0)) {
                    float w_16 = (0.25 + (0.3 * h2_1));
                    vec3 _e2118 = col_3;
                    col_3 = mix(_e2118, (vec3(0.05, 0.04, 0.035) * dim_4), ((exp(-(pow((_e2097.x / max(w_16, (_e2097.y * 0.0012))), 4.0))) * (w_16 / max(w_16, (_e2097.y * 0.0012)))) * vis_13));
                } else {
                    float w_17 = max(0.25, (_e2097.y * 0.0012));
                    vec3 _e2147 = add_5;
                    add_5 = (_e2147 + (((((mix(vec3(4.0, 3.2, 2.2), vec3(2.6, 0.7, 0.12), clamp((a_18 / life_1), 0.0, 1.0)) * exp(-(pow((_e2097.x / w_17), 2.0)))) * (0.25 / w_17)) * (1.0 - (a_18 / life_1))) * vis_13) * _e18));
                }
            }
        }
    }
    if ((_e247.z > 0.0)) {
        local_137 = (core_env_1 > 0.001);
    } else {
        local_137 = false;
    }
    bool _e2187 = local_137;
    if (_e2187) {
        vec2 dd_4 = ((uv_6 - _e247.xy) * vec2(aspect_2, 1.0));
        vec3 _e2193 = add_5;
        vec3 _e2198 = ship_tint(vec3(0.6, 1.9, 0.7));
        add_5 = (_e2193 + ((((_e2198 * core_env_1) / vec3((1.0 + (dot(dd_4, dd_4) * 600.0)))) * 0.4) * _e18));
    }
    if ((_e248.z > 0.0)) {
        local_138 = (beam_env > 0.001);
    } else {
        local_138 = false;
    }
    bool _e2219 = local_138;
    if (_e2219) {
        vec2 dd_5 = ((uv_6 - _e248.xy) * vec2(aspect_2, 1.0));
        vec3 _e2225 = add_5;
        vec3 _e2230 = ship_tint(vec3(1.1, 1.8, 1.1));
        add_5 = (_e2225 + ((((_e2230 * beam_env) / vec3((1.0 + (dot(dd_5, dd_5) * 400.0)))) * 0.5) * _e18));
        vec3 _e2243 = add_5;
        vec3 _e2248 = ship_tint(vec3(0.4, 2.3, 0.6));
        add_5 = (_e2243 + (((((_e2248 * exp((-(abs(dd_5.y)) * 260.0))) * exp((-(abs(dd_5.x)) * 6.0))) * beam_env) * 0.4) * _e18));
    }
    vec3 _e2268 = add_5;
    add_5 = (_e2268 + (((vec3(2.4, 2.9, 2.4) * flash_1) * flash_1) * _e18));
    vec3 _e2277 = col_3;
    vec3 _e2278 = add_5;
    outc_3 = (_e2277 + _e2278);
    float vg_2 = length(((uv_6 - vec2(0.5)) * vec2(aspect_2, 1.0)));
    vec3 _e2288 = outc_3;
    outc_3 = (_e2288 * (1.0 - ((smoothstep(0.3, 1.0, vg_2) * ((0.2 + (0.25 * here)) + (0.2 * beam_env))) * _e18)));
    vec3 _e2304 = outc_3;
    vec3 _e2307 = aces((_e2304 * 0.9));
    outc_3 = _e2307;
    vec3 _e2308 = outc_3;
    vec3 _e2309 = linear_to_srgb(_e2308);
    float _e2310 = capture();
    if ((_e2310 > 2.5)) {
        vec2 sp_2 = floor(in_3.position.xy);
        float chk_2 = fract(((sp_2.x + sp_2.y) * 0.5));
        float ycc_y_2 = ((_e2309.y * 0.5) + ((_e2309.x + _e2309.z) * 0.25));
        float ycc_co_2 = (_e2309.x - _e2309.z);
        float ycc_cg_2 = (_e2309.y - ((_e2309.x + _e2309.z) * 0.5));
        return vec4(ycc_y_2, ((((chk_2 < 0.25) ? ycc_co_2 : ycc_cg_2) * 0.5) + 0.5), 0.0, 1.0);
    }
    return vec4(_e2309, 1.0);
}

void main() {
    StageIn in_ = StageIn(gl_FragCoord, _vs2fs_location0);
    bool local = false;
    vec2 shock_dir = vec2(0.0);
    vec2 uv2_ = vec2(0.0);
    vec3 col = vec3(0.0);
    bool local_1 = false;
    vec3 add = vec3(0.0);
    bool local_2 = false;
    float ret = 0.0;
    float sig = 0.0;
    float heat = 0.0;
    int q = 0;
    vec3 b = vec3(0.0);
    vec3 b_1 = vec3(0.0);
    bool local_3 = false;
    float trans = 1.0;
    vec3 acc = vec3(0.0);
    int i_1 = 0;
    float body = 0.0;
    bool local_4 = false;
    bool local_5 = false;
    vec3 lit = vec3(0.0);
    int i_2 = 0;
    bool local_6 = false;
    vec3 v_1 = vec3(0.0);
    int j = 0;
    vec3 holy = vec3(0.0);
    int i_3 = 0;
    bool local_7 = false;
    bool local_8 = false;
    float ringv = 0.0;
    bool local_9 = false;
    bool local_10 = false;
    bool local_11 = false;
    vec2 wing = vec2(0.0);
    int i_4 = 0;
    int i_5 = 0;
    int i_6 = 0;
    bool local_12 = false;
    int rb = 0;
    vec3 prev = vec3(0.0);
    int j_1 = 0;
    bool local_13 = false;
    vec3 outc = vec3(0.0);
    float _e2 = th_is(2.0);
    if ((_e2 > 0.5)) {
        vec4 _e5 = singularity(in_);
        _fs2p_location0 = _e5;
        return;
    }
    float _e7 = th_is(3.0);
    if ((_e7 > 0.5)) {
        vec4 _e10 = meteor_storm(in_);
        _fs2p_location0 = _e10;
        return;
    }
    float _e12 = th_is(4.0);
    if ((_e12 > 0.5)) {
        vec4 _e15 = mothership(in_);
        _fs2p_location0 = _e15;
        return;
    }
    vec2 uv_7 = in_.uv;
    float _e20 = _group_0_binding_4_fs.resolution.x;
    float _e24 = _group_0_binding_4_fs.resolution.y;
    float aspect_3 = (_e20 / _e24);
    float _e26 = now();
    float _e27 = phase_time();
    vec4 _e30 = _group_0_binding_4_fs.camera_position;
    vec3 cam_9 = _e30.xyz;
    vec3 _e32 = target_pos();
    vec2 _e33 = anchor_xz();
    vec3 crel_3 = (_e32 - cam_9);
    float _e36 = th_is(0.0);
    float _e38 = th_is(1.0);
    float _e39 = seed_v();
    float charging_2 = ((_e27 < T_FIRE) ? clamp((_e27 / T_FIRE), 0.0, 1.0) : 0.0);
    float fire_t_2 = (_e27 - T_FIRE);
    bool fired_2 = (fire_t_2 > 0.0);
    float fire_b = (fire_t_2 + (0.6 * _e38));
    float beam_env_1 = (smoothstep(0.0, 0.1, fire_b) * (1.0 - smoothstep(9.0, 11.0, fire_t_2)));
    float crater_env = (smoothstep(0.0, 0.8, fire_t_2) * (1.0 - smoothstep(10.0, 20.0, fire_t_2)));
    float flash_2 = (fired_2 ? exp((-(fire_t_2) * 9.0)) : 0.0);
    float reticle_env = max(charging_2, (fired_2 ? exp((-(fire_t_2) * 2.5)) : 0.0));
    float after = (1.0 - (smoothstep(13.0, 21.0, fire_t_2) * float(fired_2)));
    float _e92 = intensity_v();
    float _e95 = hash21_(vec2(_e39, 3.7));
    float _e98 = hash21_(vec2(_e39, 11.3));
    float _e101 = hash21_(vec2(_e39, 23.9));
    float _e107 = vnoise(vec2((_e26 * 1.9), (_e39 * 13.0)));
    float surge = ((pow(_e107, 2.5) * 2.2) * _e36);
    float _e118 = vnoise(vec2((_e26 * 9.0), (_e39 * 5.0)));
    float stutter = (1.0 - ((0.4 * step(0.8, _e118)) * _e36));
    float _e129 = vnoise(vec2((_e26 * 2.3), _e39));
    float _e135 = vnoise(vec2((_e26 * 2.1), (_e39 * 2.0)));
    vec2 wobble = (((vec2(_e129, _e135) - vec2(0.5)) * 1.6) * surge);
    vec3 tint_pal = mix(vec3(0.25, 1.1, 3.8), vec3(3.4, 0.5, 2.6), step(0.34, _e95));
    vec3 tint_p = mix(tint_pal, vec3(0.5, 3.2, 0.9), step(0.67, _e95));
    vec3 _e165 = pick2_(tint_p, vec3(3.4, 2.6, 1.0));
    vec3 _e171 = pick2_(tint_p.zxy, vec3(3.0, 2.8, 1.8));
    vec3 _e180 = pick2_(vec3(1.0, 0.75, 0.45), vec3(1.6, 1.3, 0.7));
    vec3 tint_l = mix(mix(vec3(0.4, 0.45, 1.8), vec3(1.8, 0.4, 1.2), step(0.34, _e95)), vec3(0.3, 1.8, 0.5), step(0.67, _e95));
    vec3 gold = vec3(1.6, 1.2, 0.55);
    vec3 white = vec3(1.6, 1.55, 1.3);
    vec3 _e207 = project_rel(crel_3);
    vec2 uvT = _e207.xy;
    float _e209 = depth_at(uv_7);
    bool _e210 = is_sky(_e209);
    vec3 _e213 = world_offset(uv_7, (_e210 ? 0.5 : _e209));
    vec3 p0_5 = (cam_9 + _e213);
    float r0_5 = length((p0_5.xz - _e32.xz));
    float rs_3 = (fire_t_2 * 62.0);
    float shock_fade = (fired_2 ? exp((-(fire_t_2) * 0.55)) : 0.0);
    if (fired_2) {
        local = !(_e210);
    } else {
        local = false;
    }
    bool _e238 = local;
    float shock_mask_1 = ((_e238 ? exp(-(pow(((r0_5 - rs_3) / 3.5), 2.0))) : 0.0) * shock_fade);
    shock_dir = (uv_7 - uvT);
    vec2 _e244 = shock_dir;
    vec2 _e245 = shock_dir;
    shock_dir = (_e244 / vec2(max(length(_e245), 0.0001)));
    vec2 _e251 = shock_dir;
    uv2_ = (uv_7 + ((((_e251 * shock_mask_1) * 0.08) * _e92) * _e207.z));
    float haze_5 = (((((beam_env_1 + (crater_env * 0.6)) * _e92) * exp((-(length(((uv_7 - uvT) * vec2(aspect_3, 1.0)))) * 4.0))) * _e207.z) * _e36);
    vec2 _e277 = uv2_;
    uv2_ = (_e277 + ((vec2(sin(((uv_7.y * 90.0) + (_e26 * 14.0))), cos(((uv_7.x * 70.0) - (_e26 * 11.0)))) * 0.0025) * haze_5));
    vec2 _e297 = uv2_;
    uv2_ = clamp(_e297, vec2(0.002), vec2(0.998));
    float ca_4 = (((flash_2 * 0.012) + (shock_mask_1 * 0.008)) * _e92);
    vec2 _e309 = uv2_;
    vec2 ca_dir_3 = ((_e309 - vec2(0.5)) * ca_4);
    vec2 _e316 = uv2_;
    vec4 _e319 = orbitalSceneLod(_group_0_binding_0_fs, vec2((_e316 + ca_dir_3)), 0.0);
    float sr = _e319.x;
    vec2 _e323 = uv2_;
    vec4 _e325 = orbitalSceneLod(_group_0_binding_0_fs, vec2(_e323), 0.0);
    float sg = _e325.y;
    vec2 _e329 = uv2_;
    vec4 _e332 = orbitalSceneLod(_group_0_binding_0_fs, vec2((_e329 - ca_dir_3)), 0.0);
    float sb = _e332.z;
    vec3 _e335 = srgb_to_linear(vec3(sr, sg, sb));
    col = _e335;
    vec2 _e337 = uv2_;
    float _e338 = depth_at(_e337);
    bool _e339 = is_sky(_e338);
    vec2 _e340 = uv2_;
    vec3 _e343 = world_offset(_e340, (_e339 ? 0.5 : _e338));
    float scene_len_6 = (!(_e339) ? length(_e343) : 1000000000.0);
    vec2 _e348 = uv2_;
    vec3 _e350 = world_offset(_e348, RAY_DEPTH);
    vec3 rd_10 = normalize(_e350);
    vec3 P_3 = (cam_9 + _e343);
    vec2 v2_3 = rd_10.xz;
    float vv_3 = dot(v2_3, v2_3);
    float dim_5 = (1.0 - ((((((0.45 * charging_2) * charging_2) + (0.4 * beam_env_1)) + (0.2 * crater_env)) * _e92) * mix(1.0, 0.75, _e38)));
    vec3 _e371 = col;
    col = (_e371 * clamp(dim_5, 0.2, 1.0));
    if (_e339) {
        float st = (beam_env_1 * _e92);
        float _e378 = uv2_.y;
        float grad_1 = pow((1.0 - _e378), 2.0);
        if ((_e36 > 0.5)) {
            vec3 _e385 = col;
            col = mix(_e385, (vec3(0.04, 0.0, 0.1) + (vec3(0.25, 0.0, 0.35) * grad_1)), (st * 0.7));
            vec3 _e399 = col;
            float _e410 = uv2_.y;
            col = (_e399 + (((((vec3(0.5, 0.02, 0.02) * charging_2) * charging_2) * _e92) * 0.35) * (1.0 - _e410)));
        } else {
            float cover_env = (smoothstep(0.0, 2.5, _e27) * after);
            if ((rd_10.y > 0.015)) {
                local_1 = (cover_env > 0.001);
            } else {
                local_1 = false;
            }
            bool _e427 = local_1;
            if (_e427) {
                float H_4 = (_e32.y + 150.0);
                float th_3 = ((H_4 - cam_9.y) / rd_10.y);
                vec3 hit_3 = (cam_9 + (rd_10 * max(th_3, 0.0)));
                vec2 q_15 = (hit_3.xz - _e33);
                float rq = length(q_15);
                float aq = atan(q_15.y, q_15.x);
                float Ra = (58.0 * smoothstep(0.6, 4.2, _e27));
                float swirl = (aq + ((9.0 / (1.0 + (rq * 0.04))) * (0.2 + (0.05 * _e26))));
                vec2 qs = (vec2(cos(swirl), sin(swirl)) * rq);
                float _e472 = fbm(((qs * 0.012) + vec2((_e26 * 0.03), _e39)));
                float _e480 = fbm(((qs * 0.035) - vec2((_e26 * 0.05), 0.0)));
                float dens_4 = (smoothstep(0.32, 0.7, ((_e472 * 0.8) + (_e480 * 0.35))) * smoothstep((Ra * 0.85), (Ra * 1.25), rq));
                float horizon = smoothstep(0.015, 0.14, rd_10.y);
                float lit_4 = exp((-(max((rq - Ra), 0.0)) / 70.0));
                vec3 deck_1 = (mix(vec3(0.1, 0.09, 0.09), vec3(1.25, 0.85, 0.42), lit_4) * (0.55 + (0.6 * _e480)));
                float cover_1 = (((0.55 + (0.45 * dens_4)) * cover_env) * horizon);
                vec3 _e526 = col;
                col = mix(_e526, deck_1, cover_1);
                float open_1 = (((1.0 - smoothstep((Ra * 0.55), (Ra * 1.05), rq)) * cover_env) * horizon);
                float _e542 = fbm(vec2((aq * 7.0), (_e26 * 0.25)));
                float rays = ((pow(_e542, 2.0) * exp((-(max((rq - (Ra * 0.8)), 0.0)) / 45.0))) * (1.0 - dens_4));
                vec3 _e558 = col;
                col = (_e558 + (((vec3(2.6, 2.2, 1.5) * open_1) + (((vec3(1.4, 1.0, 0.45) * rays) * cover_env) * horizon)) * _e92));
            } else {
                vec3 _e574 = col;
                col = mix(_e574, (vec3(0.16, 0.08, 0.03) + (vec3(0.6, 0.32, 0.1) * grad_1)), (0.6 * cover_env));
            }
        }
    }
    if (!(_e339)) {
        vec2 dxg_2 = (P_3.xz - _e32.xz);
        float r_14 = length(dxg_2);
        float ang_11 = atan(dxg_2.y, dxg_2.x);
        float dy_3 = (P_3.y - _e32.y);
        float near_y_2 = (1.0 / (1.0 + ((dy_3 * dy_3) / 40.0)));
        vec3 _e617 = pick2_(vec3(1.0, 0.05, 0.03), vec3(1.0, 0.75, 0.2));
        vec3 _e626 = pick2_(vec3(1.0, 0.9, 0.8), vec3(1.0, 1.0, 0.9));
        vec3 rc_2 = mix(_e617, _e626, (charging_2 * charging_2));
        if ((_e36 > 0.5)) {
            local_2 = (reticle_env > 0.001);
        } else {
            local_2 = false;
        }
        bool _e636 = local_2;
        if (_e636) {
            float conv_3 = mix(30.0, 5.0, (1.0 - pow((1.0 - charging_2), 3.0)));
            float _e648 = ret;
            ret = (_e648 + (exp(-(pow(((r_14 - conv_3) / 0.35), 2.0))) * 1.3));
            float spin1_ = step(0.5, fract((((ang_11 / TAU) * 24.0) + (_e26 * 0.35))));
            float _e669 = ret;
            ret = (_e669 + (exp(-(pow(((r_14 - 9.0) / 0.22), 2.0))) * spin1_));
            float spin2_ = step(0.35, fract((((ang_11 / TAU) * 12.0) - (_e26 * 0.6))));
            float _e690 = ret;
            ret = (_e690 + ((exp(-(pow(((r_14 - 14.0) / 0.2), 2.0))) * spin2_) * 0.9));
            float _e703 = ret;
            ret = (_e703 + exp(-(pow(((r_14 - 3.0) / 0.2), 2.0))));
            float spokes = (1.0 - smoothstep(0.0, 0.06, ((abs((fract((((ang_11 / TAU) * 8.0) + (_e26 * 0.12))) - 0.5)) * r_14) * 0.05)));
            float _e732 = ret;
            ret = (_e732 + (((spokes * (1.0 - smoothstep((conv_3 - 2.0), conv_3, r_14))) * smoothstep(1.0, 2.0, r_14)) * 0.45));
            float scan = (exp(-(pow(((r_14 - (fract((_e26 * 0.7)) * 30.0)) / 0.5), 2.0))) * 0.7);
            float _e760 = ret;
            ret = (_e760 + (scan * ((charging_2 > 0.0) ? 1.0 : 0.0)));
            vec3 _e768 = add;
            float _e769 = ret;
            add = (_e768 + (((((rc_2 * _e769) * reticle_env) * near_y_2) * 2.2) * _e92));
        }
        if ((_e38 > 0.5)) {
            float sg_env = (max(reticle_env, crater_env) * after);
            if ((sg_env > 0.001)) {
                vec2 qa = (P_3.xz - _e33);
                float ra = length(qa);
                float aa = atan(qa.y, qa.x);
                float draw = smoothstep(0.0, 3.6, _e27);
                float sweep = step(fract((((aa - PILLAR_A0_) / TAU) + 1.0)), draw);
                sig = ((exp(-(pow(((ra - SIGIL_R1_) / 0.45), 2.0))) + exp(-(pow(((ra - PILLAR_R) / 0.45), 2.0)))) * sweep);
                float _e825 = tri_line(ra, ((aa - PILLAR_A0_) - 1.0471976), PILLAR_R, 0.45);
                float _e830 = tri_line(ra, (aa - PILLAR_A0_), PILLAR_R, 0.45);
                float hexa = (_e825 + _e830);
                float _e832 = sig;
                sig = (_e832 + (hexa * smoothstep(1.2, 3.8, _e27)));
                float rune_a = (aa - (_e26 * 0.05));
                float rf = fract(((rune_a / TAU) * 48.0));
                float _e853 = hash21_(vec2(floor(((rune_a / TAU) * 48.0)), 3.0));
                float rune = ((step(0.4, _e853) * step(0.2, rf)) * step(rf, 0.8));
                float _e862 = sig;
                sig = (_e862 + ((((rune * step(34.0, ra)) * (1.0 - step(37.0, ra))) * 0.8) * sweep));
                float pulse_1 = (0.75 + (0.25 * sin(((_e26 * 2.0) - (ra * 0.15)))));
                vec3 _e885 = add;
                float _e886 = sig;
                add = (_e885 + ((((((rc_2 * _e886) * sg_env) * near_y_2) * 2.6) * pulse_1) * _e92));
            }
        }
        if (fired_2) {
            float Rc = (1.2 + (7.5 * (1.0 - exp((-(fire_t_2) * 0.45)))));
            float reach_1 = (Rc * 1.8);
            if ((r_14 < (reach_1 * 1.4))) {
                float deep_1 = clamp(((_e32.y - P_3.y) / 14.0), 0.0, 1.0);
                float _e930 = fbm((((dxg_2 * 0.85) + vec2((_e26 * 0.12), (-(_e26) * 0.09))) + vec2((P_3.y * 0.6))));
                heat = ((((1.0 - (r_14 / reach_1)) * 0.9) + ((_e930 - 0.5) * 0.9)) + (deep_1 * 0.7));
                float _e953 = fbm(((dxg_2 * 1.7) + vec2(3.7, (P_3.y * 0.8))));
                float crust = smoothstep(0.35, 0.65, _e953);
                float _e957 = heat;
                heat = (_e957 - (crust * 0.25));
                float mask_1 = ((1.0 - smoothstep((reach_1 * 0.7), (reach_1 * 1.4), r_14)) * exp((-(max(dy_3, 0.0)) / 4.0)));
                vec3 _e975 = add;
                float _e976 = heat;
                vec3 _e977 = lava_ramp(_e976);
                float _e979 = heat;
                vec3 _e980 = gold_ramp(_e979);
                add = (_e975 + ((((((_e977 * _e36) + (_e980 * _e38)) * mask_1) * crater_env) * 4.5) * _e92));
                float bore_1 = (((1.0 - smoothstep((Rc * 0.15), (Rc * 0.65), r_14)) * smoothstep(-2.0, 0.0, (dy_3 + 1.5))) * (1.0 - smoothstep(0.0, 8.0, dy_3)));
                vec3 _e1008 = col;
                col = (_e1008 * (1.0 - ((bore_1 * crater_env) * 0.92)));
                vec3 _e1015 = add;
                vec3 _e1024 = pick2_(vec3(1.0, 0.8, 0.5), vec3(1.0, 0.95, 0.7));
                add = (_e1015 + (((((_e1024 * bore_1) * bore_1) * crater_env) * 2.2) * _e92));
            }
            if ((_e38 > 0.5)) {
                float reach_c = (3.0 + (fire_t_2 * 6.5));
                if ((r_14 < reach_c)) {
                    float _e1048 = fbm(vec2(((ang_11 * 3.0) + (r_14 * 0.12)), ((r_14 * 0.18) + _e39)));
                    float cang = fract((((ang_11 / TAU) * 11.0) + ((_e1048 - 0.5) * 1.3)));
                    float cdist = (0.5 - abs((cang - 0.5)));
                    float thr = (1.76 / (TAU * max(r_14, 1.5)));
                    float crack = (((1.0 - smoothstep((thr * 0.4), thr, cdist)) * (1.0 - smoothstep((reach_c * 0.55), reach_c, r_14))) * smoothstep(1.5, 4.0, r_14));
                    vec3 _e1085 = add;
                    add = (_e1085 + (((((vec3(1.3, 1.0, 0.45) * crack) * crater_env) * near_y_2) * 3.0) * _e92));
                }
            }
            bool loop_init_16 = true;
            while(true) {
                if (!loop_init_16) {
                    int _e1153 = q;
                    q = (_e1153 + 1);
                }
                loop_init_16 = false;
                int _e1099 = q;
                if ((_e1099 < 4)) {
                } else {
                    break;
                }
                {
                    int _e1102 = q;
                    float fq = float(_e1102);
                    float _e1111 = hash21_(vec2(_e39, (fq + 41.0)));
                    float tq0_ = ((1.3 + (fq * 2.2)) + (1.5 * _e1111));
                    float dtq = (fire_t_2 - tq0_);
                    float _e1121 = hash21_(vec2(_e39, (fq + 7.0)));
                    float rq_1 = (max(dtq, 0.0) * (24.0 + (20.0 * _e1121)));
                    float ringq = ((exp(-(pow(((r_14 - rq_1) / 1.2), 2.0))) * exp((-(max(dtq, 0.0)) * 0.8))) * step(0.0, dtq));
                    vec3 _e1144 = add;
                    add = (_e1144 + (((((_e180 * 0.9) * ringq) * near_y_2) * 2.5) * _e92));
                }
            }
            float rs_eff = (rs_3 * (1.0 + ((0.07 * _e38) * sin(((12.0 * ang_11) + (_e26 * 0.6))))));
            float edge_4 = ((exp(-(pow(((r_14 - rs_eff) / 2.8), 2.0))) * shock_fade) * near_y_2);
            vec3 _e1177 = add;
            add = (_e1177 + (((_e180 * edge_4) * 7.0) * _e92));
            vec3 _e1183 = col;
            col = (_e1183 * (1.0 - ((((exp(-(pow((((r_14 - rs_eff) + 4.0) / 3.0), 2.0))) * shock_fade) * near_y_2) * 0.5) * _e36)));
            float rs_in = ((rs_3 * 0.62) * (1.0 + (0.07 * sin((((12.0 * ang_11) + 3.1416) - (_e26 * 0.6))))));
            vec3 _e1216 = add;
            add = (_e1216 + ((((((_e180 * exp(-(pow(((r_14 - rs_in) / 1.2), 2.0)))) * shock_fade) * near_y_2) * 3.0) * _e92) * _e38));
        }
    }
    vec3 _e1236 = axis_hit((crel_3.xz + wobble), v2_3, vv_3, cam_9.y, rd_10.y);
    float t_ray = _e1236.x;
    float dist_1 = _e1236.y;
    float y_p_1 = _e1236.z;
    if ((t_ray > 0.0)) {
        vec2 c2_ = (crel_3.xz + wobble);
        vec2 off_4 = ((v2_3 * t_ray) - c2_);
        float ang_b_1 = atan(off_4.y, off_4.x);
        float vis_14 = (!(_e339) ? (1.0 - smoothstep((scene_len_6 - 0.6), (scene_len_6 + 0.6), t_ray)) : 1.0);
        float vis_mix_1 = mix(0.22, 1.0, vis_14);
        float head_2 = (_e32.y + (800.0 * pow((1.0 - clamp((fire_b / mix(0.16, 0.6, _e38)), 0.0, 1.0)), 2.0)));
        float above = (smoothstep((_e32.y - 1.5), (_e32.y + 0.5), y_p_1) * ((fire_b > 0.0) ? smoothstep((head_2 - 3.0), (head_2 + 3.0), y_p_1) : 1.0));
        float _e1300 = fbm(vec2((ang_b_1 * 2.5), ((y_p_1 * 0.07) - (_e26 * 9.0))));
        float _e1314 = fbm(vec2((((ang_b_1 * 2.2) + 11.0) + (_e26 * 0.8)), ((y_p_1 * 0.11) - (_e26 * 9.0))));
        float des_1 = (((exp(-(pow((dist_1 / 0.07), 2.0))) * charging_2) * (1.0 - step(0.0, fire_b))) * smoothstep((_e32.y - 1.0), (_e32.y + 0.5), y_p_1));
        vec3 _e1335 = add;
        vec3 _e1344 = pick2_(vec3(1.0, 0.08, 0.04), vec3(1.0, 0.8, 0.3));
        add = (_e1335 + ((((_e1344 * des_1) * vis_14) * 2.5) * (0.7 + (0.3 * sin(((_e26 * 40.0) * _e36))))));
        if ((beam_env_1 > 0.001)) {
            float hgt_1 = max((y_p_1 - _e32.y), 0.0);
            if ((_e36 > 0.5)) {
                float plume = (1.0 + (3.2 * exp((-(hgt_1) / 9.0))));
                float rcb = ((((((0.9 + (1.1 * exp((-(fire_t_2) * 1.3)))) + (0.2 * sin((_e26 * 23.0)))) + (0.7 * surge)) * (0.85 + (0.45 * _e1300))) * _e92) * plume);
                float lat = (dist_1 * sign((dot(off_4, vec2(-(c2_.y), c2_.x)) + 1e-5)));
                float core_6 = exp(-(pow((dist_1 / (rcb * 0.5)), 2.0)));
                float sheath_1 = exp(-(pow((dist_1 / (rcb * 2.0)), 2.0)));
                float halo_2 = (1.0 / (1.0 + pow((dist_1 / (rcb * 6.0)), 2.0)));
                float _e1443 = fbm(vec2((((y_p_1 * 0.06) - (_e26 * 7.0)) + _e39), ((ang_b_1 * 0.9) + (_e26 * 0.7))));
                float pulse_2 = (pow(smoothstep(0.38, 0.82, _e1443), 2.0) * (0.7 + (1.1 * surge)));
                vec3 plasma = ((_e165 * (0.55 + (0.9 * _e1314))) * (1.0 + (3.0 * pulse_2)));
                b = ((((((core_6 * vec3(8.0, 8.0, 9.0)) * (0.85 + (0.5 * surge))) + (sheath_1 * plasma)) + ((halo_2 * _e171) * 0.3)) * above) * stutter);
                float spin_1 = ((6.0 + (10.0 * _e98)) * ((_e101 > 0.5) ? 1.0 : -1.0));
                float strand_2 = (pow((0.5 + (0.5 * sin((((ang_b_1 * 3.0) + (y_p_1 * 0.35)) - (_e26 * spin_1))))), 10.0) + pow((0.5 + (0.5 * sin((((ang_b_1 * 2.0) - (y_p_1 * 0.5)) + (_e26 * 9.0))))), 10.0));
                float band = exp(-(pow(((dist_1 - (rcb * 1.5)) / (rcb * 0.45)), 2.0)));
                vec3 _e1533 = b;
                b = (_e1533 + ((((_e171 * 0.8) * strand_2) * band) * above));
                vec3 _e1540 = add;
                vec3 _e1541 = b;
                add = (_e1540 + ((_e1541 * beam_env_1) * vis_mix_1));
                vec2 cell_1 = vec2((lat * 1.4), ((y_p_1 * 0.9) - (_e26 * 14.0)));
                vec2 id = floor(cell_1);
                vec2 f_17 = (fract(cell_1) - vec2(0.5));
                float _e1558 = hash21_(id);
                float spark_2 = ((step(0.92, _e1558) * exp((-(dot(f_17, f_17)) * 26.0))) * (1.0 - smoothstep((rcb * 1.2), (rcb * 9.0), abs(lat))));
                vec3 _e1576 = add;
                add = (_e1576 + ((((((vec3(1.0, 0.75, 0.4) * spark_2) * 3.5) * beam_env_1) * above) * vis_mix_1) * _e92));
            } else {
                float rcg = ((2.2 + (1.6 * exp((-(max(fire_t_2, 0.0)) * 1.5)))) * _e92);
                float core_7 = exp(-(pow((dist_1 / (rcg * 0.55)), 2.0)));
                float sheath_2 = exp(-(pow((dist_1 / (rcg * 2.2)), 2.0)));
                float halo_3 = (1.0 / (1.0 + pow((dist_1 / (rcg * 7.0)), 2.0)));
                float _e1631 = fbm(vec2((ang_b_1 * 3.0), ((y_p_1 * 0.05) + (_e26 * 2.5))));
                float stream = (0.75 + (0.5 * _e1631));
                float slide = fract((((y_p_1 - _e32.y) + (_e26 * 26.0)) / 24.0));
                float rings = (exp(-(pow(((slide - 0.5) / 0.03), 2.0))) * exp(-(pow(((dist_1 - (rcg * 1.3)) / (rcg * 0.9)), 2.0))));
                b_1 = (((core_7 * vec3(9.0, 8.2, 6.2)) + ((sheath_2 * vec3(3.0, 2.3, 1.0)) * stream)) + ((halo_3 * vec3(1.4, 1.1, 0.6)) * 0.25));
                vec3 _e1684 = b_1;
                b_1 = (_e1684 + ((vec3(3.2, 2.6, 1.3) * rings) * 1.5));
                vec3 _e1693 = add;
                vec3 _e1694 = b_1;
                add = (_e1693 + (((_e1694 * above) * beam_env_1) * vis_mix_1));
                float lat_1 = (dist_1 * sign((dot(off_4, vec2(-(c2_.y), c2_.x)) + 1e-5)));
                vec2 cell_2 = vec2((lat_1 * 0.9), ((y_p_1 * 0.5) - (_e26 * 3.0)));
                vec2 id_1 = floor(cell_2);
                vec2 f_18 = (fract(cell_2) - vec2(0.5));
                float _e1721 = hash21_(id_1);
                float mote = ((step(0.9, _e1721) * exp((-(dot(f_18, f_18)) * 30.0))) * (1.0 - smoothstep((rcg * 0.8), (rcg * 3.0), abs(lat_1))));
                vec3 _e1739 = add;
                add = (_e1739 + ((((((vec3(1.6, 1.4, 0.9) * mote) * 1.6) * beam_env_1) * above) * vis_mix_1) * _e92));
            }
        }
        float ember = (((((crater_env * (1.0 - beam_env_1)) * exp(-(pow((dist_1 / 4.0), 2.0)))) * smoothstep(_e32.y, (_e32.y + 3.0), y_p_1)) * exp((-((y_p_1 - _e32.y)) / 30.0))) * _e36);
        vec2 ecell = floor(vec2((ang_b_1 * 3.0), ((y_p_1 * 0.7) - (_e26 * 5.0))));
        vec3 _e1785 = add;
        float _e1790 = hash21_(ecell);
        add = (_e1785 + (((((vec3(1.0, 0.4, 0.08) * step(0.82, _e1790)) * ember) * vis_14) * 0.35) * _e92));
    }
    float smoke_env = ((smoothstep(1.2, 4.5, fire_t_2) * (1.0 - smoothstep(15.0, 26.0, fire_t_2))) * float(fired_2));
    if ((smoke_env > 0.001)) {
        vec3 _e1816 = axis_hit(crel_3.xz, v2_3, vv_3, cam_9.y, rd_10.y);
        float t_s = _e1816.x;
        float dist_s = _e1816.y;
        float y_s = _e1816.z;
        vec2 off_s = ((v2_3 * t_s) - crel_3.xz);
        float vis_s = (!(_e339) ? (1.0 - smoothstep((scene_len_6 - 0.6), (scene_len_6 + 0.6), t_s)) : 1.0);
        float h_5 = max((y_s - _e32.y), 0.0);
        float top_2 = ((fire_t_2 - 1.0) * 11.0);
        float crown = (smoothstep((top_2 - 30.0), (top_2 - 4.0), h_5) * (1.0 - smoothstep((top_2 - 6.0), (top_2 + 4.0), h_5)));
        float R_2 = ((3.5 + (0.2 * h_5)) + (13.0 * crown));
        float lat_s = (dist_s * sign((dot(off_s, vec2(-(crel_3.z), crel_3.x)) + 1e-5)));
        float _e1881 = fbm(vec2(((lat_s * 0.16) + 3.0), (((h_5 * 0.16) - (_e26 * 0.5)) + _e39)));
        float _e1892 = fbm(vec2(((lat_s * 0.34) - 4.0), ((h_5 * 0.34) - (_e26 * 0.9))));
        float dens_5 = (((exp(-(pow((dist_s / (R_2 * (0.75 + (0.5 * _e1881)))), 2.0))) * (0.35 + (0.9 * _e1892))) * (1.0 - smoothstep((top_2 - 5.0), (top_2 + 3.0), h_5))) * smoothstep(-1.0, 3.0, (y_s - _e32.y)));
        float a_s = ((((smoothstep(0.16, 0.7, (dens_5 * 1.7)) * mix(0.96, 0.35, _e38)) * smoke_env) * vis_s) * ((t_s > 0.0) ? 1.0 : 0.0));
        float under_1 = ((exp((-(h_5) / 9.0)) * crater_env) * (0.4 + (0.9 * _e1881)));
        float rim = pow(clamp((1.0 - (dist_s / (R_2 * 1.1))), 0.0, 1.0), 0.6);
        vec3 _e1965 = pick2_(vec3(0.025, 0.024, 0.027), vec3(1.0, 0.9, 0.7));
        vec3 _e1974 = pick2_(vec3(0.44, 0.42, 0.43), vec3(1.6, 1.45, 1.1));
        vec3 _e1983 = pick2_(vec3(1.0, 0.33, 0.05), vec3(1.4, 1.0, 0.4));
        vec3 smoke_col = (mix(_e1965, _e1974, (clamp((0.1 + ((0.8 * _e1892) * (0.35 + (h_5 / 80.0)))), 0.0, 1.0) * (1.0 - (0.5 * rim)))) + ((_e1983 * under_1) * 1.5));
        vec3 _e2004 = col;
        col = mix(_e2004, smoke_col, a_s);
    }
    if (fired_2) {
        local_3 = (fire_t_2 < 9.0);
    } else {
        local_3 = false;
    }
    bool _e2011 = local_3;
    if (_e2011) {
        float Rv_1 = (mix(36.0, 46.0, _e38) * (1.0 - exp((-(fire_t_2) * 1.6))));
        float top_s_1 = ((14.0 + (fire_t_2 * 13.0)) * _e36);
        float capr_1 = ((9.0 + (fire_t_2 * 2.6)) * _e36);
        float Rb_1 = (max(Rv_1, (top_s_1 + capr_1)) + 2.0);
        vec3 oc_2 = (cam_9 - _e32);
        float bq_2 = dot(oc_2, rd_10);
        float cq_2 = (dot(oc_2, oc_2) - (Rb_1 * Rb_1));
        float hq_5 = ((bq_2 * bq_2) - cq_2);
        if ((hq_5 > 0.0)) {
            float sq_1 = sqrt(hq_5);
            float ta_5 = max((-(bq_2) - sq_1), 0.0);
            float tb_3 = min((-(bq_2) + sq_1), scene_len_6);
            if ((tb_3 > ta_5)) {
                float dt_3 = ((tb_3 - ta_5) / float(26));
                float fade_2 = exp((-(fire_t_2) * 0.55));
                bool loop_init_17 = true;
                while(true) {
                    if (!loop_init_17) {
                        int _e2257 = i_1;
                        i_1 = (_e2257 + 1);
                    }
                    loop_init_17 = false;
                    int _e2069 = i_1;
                    if ((_e2069 < 26)) {
                    } else {
                        break;
                    }
                    {
                        int _e2071 = i_1;
                        int _e2075 = i_1;
                        float _e2079 = hash21_(((uv_7 * 913.0) + vec2(float(_e2075))));
                        float ts_2 = (ta_5 + ((float(_e2071) + _e2079) * dt_3));
                        vec3 lp_3 = (oc_2 + (rd_10 * ts_2));
                        float rl_2 = length(lp_3);
                        float _e2094 = fbm3_(((lp_3 * 0.07) + vec3(0.0, (-(fire_t_2) * 1.6), _e39)));
                        float up_5 = smoothstep(-2.0, 1.0, lp_3.y);
                        if ((_e36 > 0.5)) {
                            float s_11 = (rl_2 / max(Rv_1, 0.5));
                            float rr_3 = length(lp_3.xz);
                            body = ((((1.0 - s_11) * 1.5) + ((_e2094 - 0.5) * 2.4)) - 0.2);
                            float stem_1 = (((1.0 - (rr_3 / (3.5 + (max(lp_3.y, 0.0) * 0.08)))) * 1.3) * (1.0 - smoothstep((top_s_1 - 4.0), top_s_1, lp_3.y)));
                            float capq_1 = length(vec2((rr_3 / max(capr_1, 1.0)), ((lp_3.y - top_s_1) / max((capr_1 * 0.5), 1.0))));
                            float _e2149 = body;
                            body = max(_e2149, ((max(stem_1, ((1.0 - capq_1) * 1.6)) + ((_e2094 - 0.5) * 2.0)) * smoothstep(0.4, 1.6, fire_t_2)));
                            float _e2165 = body;
                            float dens_6 = ((clamp(_e2165, 0.0, 1.0) * smoothstep(-6.0, 2.0, lp_3.y)) * (1.0 - smoothstep(5.0, 9.0, fire_t_2)));
                            float _e2178 = body;
                            float temp_2 = clamp(((((_e2178 * 0.7) + 0.2) - (fire_t_2 * 0.12)) - (max(lp_3.y, 0.0) / 90.0)), 0.0, 1.0);
                            vec3 _e2193 = plasma_ramp(temp_2);
                            vec3 emit_2 = (_e2193 * 2.4);
                            vec3 smoke_1 = (vec3(0.12, 0.11, 0.12) * (0.4 + _e2094));
                            float a_19 = (1.0 - exp(((-(dens_6) * dt_3) * 0.15)));
                            vec3 _e2210 = acc;
                            float _e2211 = trans;
                            acc = (_e2210 + ((_e2211 * a_19) * (emit_2 + smoke_1)));
                            float _e2216 = trans;
                            trans = (_e2216 * (1.0 - a_19));
                        } else {
                            float shell_1 = ((exp(-(pow(((rl_2 - Rv_1) / (1.5 + (Rv_1 * 0.04))), 2.0))) * (0.5 + (0.9 * _e2094))) * up_5);
                            vec3 _e2236 = acc;
                            float _e2237 = trans;
                            vec3 _e2242 = gold_ramp((0.6 + (0.4 * _e2094)));
                            acc = (_e2236 + (((((_e2237 * _e2242) * shell_1) * exp((-(fire_t_2) * 0.9))) * dt_3) * 0.05));
                        }
                        float _e2254 = trans;
                        if ((_e2254 < 0.02)) {
                            break;
                        }
                    }
                }
                vec3 _e2260 = col;
                float _e2261 = trans;
                vec3 _e2263 = acc;
                col = ((_e2260 * _e2261) + (_e2263 * _e92));
            }
        }
        vec3 _e2266 = add;
        add = (_e2266 + (((((_e180 * 0.4) + vec3(1.2)) * exp((-(fire_t_2) * 7.0))) * mix(1.6, 0.9, _e38)) * _e92));
    }
    if ((_e36 > 0.5)) {
        local_4 = (beam_env_1 > 0.001);
    } else {
        local_4 = false;
    }
    bool _e2290 = local_4;
    if (_e2290) {
        local_5 = (_e207.z > 0.0);
    } else {
        local_5 = false;
    }
    bool _e2297 = local_5;
    if (_e2297) {
        vec2 pa_3 = vec2((uv_7.x * aspect_3), uv_7.y);
        bool loop_init_18 = true;
        while(true) {
            if (!loop_init_18) {
                int _e2539 = i_2;
                i_2 = (_e2539 + 1);
            }
            loop_init_18 = false;
            int _e2307 = i_2;
            if ((_e2307 < 6)) {
            } else {
                break;
            }
            {
                int _e2310 = i_2;
                float fi_13 = float(_e2310);
                float slot_1 = floor(((_e26 * (9.0 + (8.0 * _e98))) + (fi_13 * 3.7)));
                float _e2324 = hash21_(vec2(slot_1, (fi_13 * 5.3)));
                float _e2330 = hash21_(vec2((fi_13 * 9.1), (slot_1 + 4.0)));
                float _e2336 = hash21_(vec2((slot_1 * 1.3), (fi_13 + 8.0)));
                float _e2342 = hash21_(vec2((slot_1 + 7.0), (fi_13 * 2.2)));
                if ((_e2336 < (0.22 + (0.35 * _e101)))) {
                    continue;
                }
                float ang_12 = (_e2330 * TAU);
                float reach_2 = ((9.0 + (17.0 * _e2342)) * (0.8 + (0.7 * _e98)));
                vec3 a3_ = vec3((_e32.x - cam_9.x), (((_e32.y + 3.0) + (_e2324 * 55.0)) - cam_9.y), (_e32.z - cam_9.z));
                vec3 b3_ = (a3_ + vec3((cos(ang_12) * reach_2), ((_e2342 - 0.65) * 12.0), (sin(ang_12) * reach_2)));
                vec3 _e2384 = project_rel(a3_);
                vec3 _e2385 = project_rel(b3_);
                if (!((_e2384.z < 0.0))) {
                    local_6 = (_e2385.z < 0.0);
                } else {
                    local_6 = true;
                }
                bool _e2396 = local_6;
                if (_e2396) {
                    continue;
                }
                vec2 a2_1 = vec2((_e2384.x * aspect_3), _e2384.y);
                vec2 b2_ = vec2((_e2385.x * aspect_3), _e2385.y);
                float wid_1 = (0.0026 * _e92);
                vec3 _e2410 = bolt_line(pa_3, a2_1, b2_, (slot_1 + (fi_13 * 11.0)), slot_1, wid_1);
                v_1 = _e2410;
                vec2 ab_4 = (b2_ - a2_1);
                float len_2 = length(ab_4);
                vec2 dir_3 = (ab_4 / vec2(max(len_2, 0.0001)));
                vec2 nrm_3 = vec2(-(dir_3.y), dir_3.x);
                j = 0;
                bool loop_init_19 = true;
                while(true) {
                    if (!loop_init_19) {
                        int _e2491 = j;
                        j = (_e2491 + 1);
                    }
                    loop_init_19 = false;
                    int _e2424 = j;
                    if ((_e2424 < 2)) {
                    } else {
                        break;
                    }
                    {
                        int _e2427 = j;
                        float fj_4 = float(_e2427);
                        float u0_ = ((0.3 + (0.32 * fj_4)) + (0.08 * _e2324));
                        float _e2442 = bolt_disp(len_2, u0_, (slot_1 + (fi_13 * 11.0)), slot_1);
                        vec2 root = ((a2_1 + (dir_3 * (u0_ * len_2))) + (nrm_3 * _e2442));
                        float sgn = ((fract(((_e2330 * 7.0) + fj_4)) > 0.5) ? 1.0 : -1.0);
                        float c_20 = cos((0.7 * sgn));
                        float sn = sin((0.7 * sgn));
                        vec2 bd = vec2(((dir_3.x * c_20) - (dir_3.y * sn)), ((dir_3.x * sn) + (dir_3.y * c_20)));
                        vec3 _e2486 = bolt_line(pa_3, root, (root + (bd * (len_2 * (0.45 - (0.1 * fj_4))))), (((slot_1 + (fi_13 * 11.0)) + 5.0) + fj_4), slot_1, (wid_1 * 0.7));
                        vec3 _e2487 = v_1;
                        v_1 = max(_e2487, (_e2486 * 0.8));
                    }
                }
                float bolt_d = mix(length(a3_), length(b3_), _e2410.z);
                float vis_b = (!(_e339) ? smoothstep((bolt_d - 2.0), (bolt_d + 0.5), scene_len_6) : 1.0);
                float _e2510 = hash21_(vec2(floor((_e26 * 60.0)), fi_13));
                float flick_3 = (0.65 + (0.35 * _e2510));
                vec3 _e2515 = lit;
                float _e2521 = v_1.x;
                float _e2526 = v_1.y;
                lit = (_e2515 + ((((((vec3(0.85, 0.95, 1.0) * _e2521) * 7.0) + ((tint_l * _e2526) * 0.9)) * vis_b) * flick_3) * (0.7 + (0.6 * surge))));
            }
        }
        vec3 _e2542 = add;
        vec3 _e2543 = lit;
        add = (_e2542 + (_e2543 * beam_env_1));
    }
    if ((_e38 > 0.5)) {
        bool loop_init_20 = true;
        while(true) {
            if (!loop_init_20) {
                int _e2716 = i_3;
                i_3 = (_e2716 + 1);
            }
            loop_init_20 = false;
            int _e2553 = i_3;
            if ((_e2553 < 3)) {
            } else {
                break;
            }
            {
                int _e2556 = i_3;
                float fi_14 = float(_e2556);
                float hh_1 = (((_e32.y + 24.0) + (24.0 * fi_14)) + ((3.0 * fi_14) * fi_14));
                float rw_1 = (10.0 + (7.0 * fi_14));
                float env_h = (smoothstep((0.6 + (0.8 * fi_14)), (1.8 + (0.8 * fi_14)), _e27) * after);
                if ((env_h > 0.001)) {
                    local_7 = (abs(rd_10.y) > 0.0001);
                } else {
                    local_7 = false;
                }
                bool _e2591 = local_7;
                if (_e2591) {
                    float th_4 = ((hh_1 - cam_9.y) / rd_10.y);
                    if ((th_4 > 0.0)) {
                        local_8 = (th_4 < scene_len_6);
                    } else {
                        local_8 = false;
                    }
                    bool _e2602 = local_8;
                    if (_e2602) {
                        vec2 q_16 = ((cam_9.xz + (rd_10.xz * th_4)) - _e32.xz);
                        float rr_4 = length(q_16);
                        int _e2610 = i_3;
                        float dirn_1 = (((_e2610 & 1) == 0) ? 1.0 : -1.0);
                        float an = (atan(q_16.y, q_16.x) + ((_e26 * 0.12) * dirn_1));
                        float wpx = max((th_4 * 0.0018), 0.0001);
                        float w_18 = max(0.3, wpx);
                        float wn = (0.3 / w_18);
                        ringv = (exp(-(pow(((rr_4 - rw_1) / w_18), 2.0))) * (0.55 + (0.45 * step(0.5, fract(((an / TAU) * 36.0))))));
                        float _e2652 = ringv;
                        ringv = (_e2652 + (exp(-(pow((((rr_4 - rw_1) + 1.3) / (w_18 * 0.7)), 2.0))) * 0.8));
                        float _e2672 = hash21_(vec2(floor(((an / TAU) * 40.0)), fi_14));
                        float runes = (step(0.45, _e2672) * step(0.15, fract(((an / TAU) * 40.0))));
                        float _e2683 = ringv;
                        ringv = (_e2683 + ((runes * (1.0 - smoothstep(0.45, (0.5 + w_18), abs(((rr_4 - rw_1) - 1.6))))) * 0.7));
                        float glowr = (exp(-(pow(((rr_4 - rw_1) / 2.8), 2.0))) * 0.08);
                        vec3 _e2707 = holy;
                        float _e2708 = ringv;
                        holy = (_e2707 + (((gold * ((_e2708 * wn) + glowr)) * env_h) * 1.6));
                    }
                }
            }
        }
        float wing_env = ((smoothstep(0.2, 2.6, fire_t_2) * (1.0 - smoothstep(12.0, 20.0, fire_t_2))) * float(fired_2));
        if ((wing_env > 0.001)) {
            vec4 _e2732 = wing_dirs();
            vec3 nrm_4 = vec3(_e2732.x, 0.0, _e2732.y);
            vec3 span = vec3(_e2732.z, 0.0, _e2732.w);
            vec3 root_1 = (crel_3 + vec3(0.0, 36.0, 0.0));
            float den_1 = dot(rd_10, nrm_4);
            if ((abs(den_1) > 0.001)) {
                float th_5 = (dot(root_1, nrm_4) / den_1);
                if ((th_5 > 0.0)) {
                    local_9 = (th_5 < scene_len_6);
                } else {
                    local_9 = false;
                }
                bool _e2758 = local_9;
                if (_e2758) {
                    vec3 lp_4 = ((rd_10 * th_5) - root_1);
                    vec2 w2_ = vec2(dot(lp_4, span), lp_4.y);
                    if ((abs(w2_.x) < 70.0)) {
                        local_10 = (w2_.y > -40.0);
                    } else {
                        local_10 = false;
                    }
                    bool _e2774 = local_10;
                    if (_e2774) {
                        local_11 = (w2_.y < 40.0);
                    } else {
                        local_11 = false;
                    }
                    bool _e2781 = local_11;
                    if (_e2781) {
                        float sp_3 = (0.35 + (0.65 * smoothstep(0.2, 2.8, fire_t_2)));
                        float ww_2 = max(0.7, (th_5 * 0.002));
                        float wn_1 = (0.7 / ww_2);
                        float sgn_1 = ((w2_.x > 0.0) ? 1.0 : -1.0);
                        vec2 q_17 = vec2((w2_.x * sgn_1), w2_.y);
                        float flap = (0.06 * sin((_e26 * 1.1)));
                        vec2 elbow = (vec2(17.0, (11.0 + (4.0 * flap))) * sp_3);
                        vec2 wrist = (vec2(36.0, (17.0 + (8.0 * flap))) * sp_3);
                        vec2 _e2831 = seg_soft(q_17, vec2(0.0), elbow, (ww_2 * 1.3));
                        vec2 _e2834 = seg_soft(q_17, elbow, wrist, (ww_2 * 1.1));
                        vec2 _e2835 = wing;
                        wing = (_e2835 + ((_e2831 + _e2834) * 0.8));
                        bool loop_init_21 = true;
                        while(true) {
                            if (!loop_init_21) {
                                int _e2912 = i_4;
                                i_4 = (_e2912 + 1);
                            }
                            loop_init_21 = false;
                            int _e2842 = i_4;
                            if ((_e2842 < 14)) {
                            } else {
                                break;
                            }
                            {
                                int _e2845 = i_4;
                                float u_20 = ((float(_e2845) + 0.5) / 14.0);
                                vec2 base_4 = (((((1.0 - u_20) * (1.0 - u_20)) * vec2(0.0)) + (((2.0 * u_20) * (1.0 - u_20)) * elbow)) + ((u_20 * u_20) * wrist));
                                float fa = (mix(-1.75, -0.55, pow(u_20, 1.3)) + (0.04 * sin(((_e26 * 1.3) + (u_20 * 9.0)))));
                                vec2 fd = vec2(cos(fa), sin(fa));
                                float fl_1 = (mix(11.0, 30.0, pow(u_20, 0.8)) * sp_3);
                                vec2 _e2892 = wing;
                                vec2 _e2895 = seg_soft(q_17, base_4, (base_4 + (fd * fl_1)), ww_2);
                                wing = (_e2892 + _e2895);
                                vec2 _e2897 = wing;
                                vec2 _e2908 = seg_soft(q_17, (base_4 + vec2(0.0, 0.8)), (base_4 + ((fd * fl_1) * 0.42)), (ww_2 * 1.15));
                                wing = (_e2897 + (_e2908 * 0.7));
                            }
                        }
                        bool loop_init_22 = true;
                        while(true) {
                            if (!loop_init_22) {
                                int _e2939 = i_5;
                                i_5 = (_e2939 + 1);
                            }
                            loop_init_22 = false;
                            int _e2917 = i_5;
                            if ((_e2917 < 5)) {
                            } else {
                                break;
                            }
                            {
                                int _e2920 = i_5;
                                float fi_15 = (float(_e2920) / 4.0);
                                float fa_1 = mix(-0.5, 0.35, fi_15);
                                float fl_2 = (mix(30.0, 17.0, fi_15) * sp_3);
                                vec2 _e2931 = wing;
                                vec2 _e2937 = seg_soft(q_17, wrist, (wrist + (vec2(cos(fa_1), sin(fa_1)) * fl_2)), ww_2);
                                wing = (_e2931 + _e2937);
                            }
                        }
                        vec3 _e2942 = holy;
                        float _e2944 = wing.x;
                        float _e2952 = wing.y;
                        holy = (_e2942 + (((((white * min(_e2944, 1.4)) * wn_1) * 0.75) + ((gold * min(_e2952, 2.0)) * 0.06)) * wing_env));
                    }
                }
            }
        }
        bool loop_init_23 = true;
        while(true) {
            if (!loop_init_23) {
                int _e3079 = i_6;
                i_6 = (_e3079 + 1);
            }
            loop_init_23 = false;
            int _e2963 = i_6;
            if ((_e2963 < 6)) {
            } else {
                break;
            }
            {
                int _e2966 = i_6;
                float fi_16 = float(_e2966);
                float pa_4 = (PILLAR_A0_ + ((fi_16 * TAU) / 6.0));
                vec2 pc_3 = (floor((_e33 + (vec2(cos(pa_4), sin(pa_4)) * PILLAR_R))) + vec2(0.5));
                vec3 _e2988 = axis_hit((pc_3 - cam_9.xz), v2_3, vv_3, cam_9.y, rd_10.y);
                if ((_e2988.x > 0.0)) {
                    float envp = ((smoothstep(((0.25 * fi_16) + 0.1), ((0.25 * fi_16) + 0.5), fire_t_2) * (1.0 - smoothstep(9.0, 12.0, fire_t_2))) * float(fired_2));
                    float visp_1 = (!(_e339) ? (1.0 - smoothstep((scene_len_6 - 0.6), (scene_len_6 + 0.6), _e2988.x)) : 1.0);
                    float landed_1 = smoothstep((_e32.y - 3.0), (_e32.y - 1.0), _e2988.z);
                    float dropping = smoothstep(-2.0, 2.0, (_e2988.z - (_e32.y + (300.0 * pow((1.0 - clamp((((fire_t_2 - (0.25 * fi_16)) - 0.1) / 0.35), 0.0, 1.0)), 2.0)))));
                    float prof = ((exp(-(pow((_e2988.y / 0.55), 2.0))) * 3.0) + (exp(-(pow((_e2988.y / 2.0), 2.0))) * 0.6));
                    vec3 _e3068 = holy;
                    holy = (_e3068 + (((((vec3(1.5, 1.35, 0.9) * prof) * envp) * visp_1) * landed_1) * dropping));
                }
            }
        }
        float hx_env = ((smoothstep(0.5, 2.5, fire_t_2) * (1.0 - smoothstep(10.0, 13.0, fire_t_2))) * float(fired_2));
        if ((hx_env > 0.001)) {
            local_12 = (_e207.z > 0.0);
        } else {
            local_12 = false;
        }
        bool _e3101 = local_12;
        if (_e3101) {
            vec2 pa_5 = vec2((uv_7.x * aspect_3), uv_7.y);
            bool loop_init_24 = true;
            while(true) {
                if (!loop_init_24) {
                    int _e3225 = rb;
                    rb = (_e3225 + 1);
                }
                loop_init_24 = false;
                int _e3108 = rb;
                if ((_e3108 < 2)) {
                } else {
                    break;
                }
                {
                    int _e3111 = rb;
                    float ph0_ = (float(_e3111) * 3.14159);
                    vec3 _e3130 = project_rel((crel_3 + vec3((cos((ph0_ + (_e26 * 1.6))) * 5.0), 0.5, (sin((ph0_ + (_e26 * 1.6))) * 5.0))));
                    prev = _e3130;
                    j_1 = 1;
                    bool loop_init_25 = true;
                    while(true) {
                        if (!loop_init_25) {
                            int _e3222 = j_1;
                            j_1 = (_e3222 + 1);
                        }
                        loop_init_25 = false;
                        int _e3134 = j_1;
                        if ((_e3134 < 30)) {
                        } else {
                            break;
                        }
                        {
                            int _e3137 = j_1;
                            float hgt_2 = (float(_e3137) * 3.0);
                            float a_20 = ((ph0_ + (hgt_2 * 0.22)) + (_e26 * 1.6));
                            float rad_1 = (5.0 + (hgt_2 * 0.06));
                            vec3 p3_ = (crel_3 + vec3((cos(a_20) * rad_1), hgt_2, (sin(a_20) * rad_1)));
                            vec3 _e3157 = project_rel(p3_);
                            float _e3159 = prev.z;
                            if ((_e3159 > 0.0)) {
                                local_13 = (_e3157.z > 0.0);
                            } else {
                                local_13 = false;
                            }
                            bool _e3168 = local_13;
                            if (_e3168) {
                                float _e3170 = prev.x;
                                float _e3173 = prev.y;
                                vec2 _e3184 = seg_soft(pa_5, vec2((_e3170 * aspect_3), _e3173), vec2((_e3157.x * aspect_3), _e3157.y), (0.112 / max(length(p3_), 10.0)));
                                float vis_r = (!(_e339) ? step((length(p3_) - 1.0), scene_len_6) : 1.0);
                                int _e3192 = j_1;
                                float fade_3 = (1.0 - (float(_e3192) / 30.0));
                                vec3 _e3198 = holy;
                                holy = (_e3198 + (((((vec3(1.7, 1.3, 0.5) * _e3184.x) + ((vec3(1.2, 0.8, 0.3) * _e3184.y) * 0.3)) * hx_env) * (0.4 + (0.6 * fade_3))) * vis_r));
                            }
                            prev = _e3157;
                        }
                    }
                }
            }
        }
        vec3 _e3228 = add;
        vec3 _e3229 = holy;
        add = (_e3228 + (_e3229 * _e92));
    }
    if ((_e207.z > 0.0)) {
        vec2 dd_6 = ((uv_7 - uvT) * vec2(aspect_3, 1.0));
        float bloom_1 = (1.0 / (1.0 + (dot(dd_6, dd_6) * 220.0)));
        vec3 _e3246 = add;
        vec3 _e3255 = pick2_(vec3(1.0, 0.7, 0.5), vec3(1.0, 0.9, 0.6));
        add = (_e3246 + ((((_e3255 * bloom_1) * ((beam_env_1 * 0.6) + (flash_2 * 0.8))) * _e92) * mix(1.0, 0.45, _e38)));
        float streak_4 = (exp((-(abs(dd_6.y)) * 260.0)) * exp((-(abs(dd_6.x)) * 3.2)));
        vec3 _e3282 = add;
        add = (_e3282 + (((((vec3(0.3, 0.8, 2.6) * streak_4) * beam_env_1) * 0.9) * _e92) * _e36));
    }
    vec3 _e3294 = add;
    vec3 _e3303 = pick2_(vec3(0.9, 0.95, 1.0), vec3(1.0, 0.95, 0.75));
    add = (_e3294 + ((((_e3303 * flash_2) * flash_2) * 0.9) * _e92));
    vec3 _e3310 = col;
    vec3 _e3311 = add;
    outc = (_e3310 + _e3311);
    float vg_3 = length(((uv_7 - vec2(0.5)) * vec2(aspect_3, 1.0)));
    vec3 _e3329 = pick2_(vec3(1.0, 0.45, 0.35), vec3(1.0, 0.8, 0.3));
    vec3 _e3341 = pick2_(vec3(0.5, 0.2, 1.0), vec3(1.0, 0.85, 0.4));
    vec3 tint_1 = (((_e3329 * charging_2) * 0.12) + ((_e3341 * beam_env_1) * 0.07));
    vec3 _e3346 = outc;
    outc = ((_e3346 * (1.0 - (((smoothstep(0.35, 1.0, vg_3) * (0.15 + ((0.35 * (charging_2 + beam_env_1)) * 0.5))) * _e92) * mix(1.0, 0.4, _e38)))) + ((tint_1 * smoothstep(0.3, 1.0, vg_3)) * _e92));
    vec3 _e3372 = outc;
    vec3 _e3375 = aces((_e3372 * 0.9));
    outc = _e3375;
    vec3 _e3376 = outc;
    vec3 _e3377 = linear_to_srgb(_e3376);
    float _e3378 = capture();
    if ((_e3378 > 2.5)) {
        vec2 sp_4 = floor(in_.position.xy);
        float chk_3 = fract(((sp_4.x + sp_4.y) * 0.5));
        float ycc_y_3 = ((_e3377.y * 0.5) + ((_e3377.x + _e3377.z) * 0.25));
        float ycc_co_3 = (_e3377.x - _e3377.z);
        float ycc_cg_3 = (_e3377.y - ((_e3377.x + _e3377.z) * 0.5));
        _fs2p_location0 = vec4(ycc_y_3, ((((chk_3 < 0.25) ? ycc_co_3 : ycc_cg_3) * 0.5) + 0.5), 0.0, 1.0);
        return;
    }
    _fs2p_location0 = vec4(_e3377, 1.0);
    return;
}

