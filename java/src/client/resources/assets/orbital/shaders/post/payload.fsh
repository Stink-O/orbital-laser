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
struct PlCol {
    int n;
    vec3 lo;
    vec3 hi;
    float grow;
    float a;
    vec3 C;
    vec4 q[18];
    vec4 s0_;
    vec4 s1_;
    vec4 sk;
};
struct PlChunk {
    vec3 p;
    vec3 v;
    float s;
    float live;
};
struct PlOut {
    vec4 c;
    vec4 e;
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
const float PL_SEEN = 3.0;
const float PL_TURN = 10.6;
const float PL_HIT = 13.6;
const float PL_LEN = 70.0;
const float PL_FADE = 8.0;
const float PL_SOFT0_ = 21.0;
const float PL_SOFT1_ = 34.0;
const float PL_V = 343.0;
const uint PL_P = 16u;
const uint PL_PF = 400u;
const uint PL_PW = 8u;
const uint PL_HF = 1024u;
const uint PL_FR = 560u;
const uint PL_FW = 12u;
const int PL_NPUFF = 18;
const int PL_DEBRIS = 120;
const uint PL_DB = 10496u;
const uint PL_DW = 10u;

uniform sampler2D _group_0_binding_0_fs;

uniform sampler2D _group_0_binding_1_fs;


vec4 orbitalSceneLod(sampler2D s, vec2 uv, float lod) {
    return textureLod(s, vec2(uv.x, 1.0 - uv.y), lod);
}

layout(std140) uniform Frame_block_0Fragment { Frame _group_0_binding_4_fs; };

uniform usampler2D _group_0_binding_5_fs;

layout(location = 0) in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

uint md_len() {
    uvec2 d_8 = uvec2(textureSize(_group_0_binding_5_fs, 0).xy);
    return (d_8.x * d_8.y);
}

uint md_at(uint i_1) {
    uvec4 _e10 = texelFetch(_group_0_binding_5_fs, ivec2(int((i_1 & 4095u)), int((i_1 >> 12u))), 0);
    return _e10.x;
}

float depth_at(vec2 uv) {
    float _e4 = textureLod(_group_0_binding_1_fs, vec2(uv.x, 1.0 - uv.y), 0.0).r;
    return _e4;
}

float depth_px(ivec2 q) {
    vec4 _e7 = _group_0_binding_4_fs.resolution;
    float _e10 = depth_at(((vec2(q) + vec2(0.5)) * _e7.zw));
    return _e10;
}

bool is_sky(float depth) {
    return (depth <= 0.0);
}

float linear_depth(float depth_1) {
    float n_3 = _group_0_binding_4_fs.view_params.x;
    float f_10 = _group_0_binding_4_fs.view_params.y;
    return ((n_3 * f_10) / ((depth_1 * (f_10 - n_3)) + n_3));
}

vec3 view_position(vec2 uv_1, float depth_2) {
    vec4 ndc = vec4(((uv_1.x * 2.0) - 1.0), (1.0 - (uv_1.y * 2.0)), depth_2, 1.0);
    mat4x4 _e16 = _group_0_binding_4_fs.inverse_projection;
    vec4 p_26 = (_e16 * ndc);
    return (p_26.xyz / vec3(p_26.w));
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
    vec3 lo_2 = (c_1 / vec3(12.92));
    vec3 hi_2 = pow(((c_1 + vec3(0.055)) / vec3(1.055)), vec3(2.4));
    return mix(hi_2, lo_2, lessThanEqual(c_1, vec3(0.04045)));
}

vec3 linear_to_srgb(vec3 c_2) {
    vec3 lo_3 = (c_2 * 12.92);
    vec3 hi_3 = ((1.055 * pow(c_2, vec3(0.41666666))) - vec3(0.055));
    return mix(hi_3, lo_3, lessThanEqual(c_2, vec3(0.0031308)));
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
    int i_27 = int((_e5 + 0.5));
    if ((i_27 <= 0)) {
        return c_3;
    }
    switch(i_27) {
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
    vec2 i_28 = floor(p_2);
    vec2 f_11 = fract(p_2);
    vec2 u_7 = ((f_11 * f_11) * (vec2(3.0) - (2.0 * f_11)));
    float _e10 = hash21_(i_28);
    float _e15 = hash21_((i_28 + vec2(1.0, 0.0)));
    float _e20 = hash21_((i_28 + vec2(0.0, 1.0)));
    float _e25 = hash21_((i_28 + vec2(1.0, 1.0)));
    return mix(mix(_e10, _e15, u_7.x), mix(_e20, _e25, u_7.x), u_7.y);
}

float fbm(vec2 p_3) {
    vec2 o_4 = vec2(17.3, 9.1);
    vec2 q1_ = ((p_3 * 2.03) + o_4);
    vec2 q2_ = ((q1_ * 2.03) + o_4);
    vec2 q3_ = ((q2_ * 2.03) + o_4);
    vec2 q4_ = ((q3_ * 2.03) + o_4);
    float _e16 = vnoise(p_3);
    float _e19 = vnoise(q1_);
    float _e23 = vnoise(q2_);
    float _e27 = vnoise(q3_);
    float _e31 = vnoise(q4_);
    return (((((0.5 * _e16) + (0.25 * _e19)) + (0.125 * _e23)) + (0.0625 * _e27)) + (0.03125 * _e31));
}

float vnoise3_(vec3 p_4) {
    vec3 i_29 = floor(p_4);
    vec3 f_12 = fract(p_4);
    vec3 u_8 = ((f_12 * f_12) * (vec3(3.0) - (2.0 * f_12)));
    float _e10 = hash31_(i_29);
    float _e16 = hash31_((i_29 + vec3(1.0, 0.0, 0.0)));
    float a_15 = mix(_e10, _e16, u_8.x);
    float _e24 = hash31_((i_29 + vec3(0.0, 1.0, 0.0)));
    float _e30 = hash31_((i_29 + vec3(1.0, 1.0, 0.0)));
    float b_8 = mix(_e24, _e30, u_8.x);
    float _e38 = hash31_((i_29 + vec3(0.0, 0.0, 1.0)));
    float _e44 = hash31_((i_29 + vec3(1.0, 0.0, 1.0)));
    float c_17 = mix(_e38, _e44, u_8.x);
    float _e52 = hash31_((i_29 + vec3(0.0, 1.0, 1.0)));
    float _e58 = hash31_((i_29 + vec3(1.0, 1.0, 1.0)));
    float d_9 = mix(_e52, _e58, u_8.x);
    return mix(mix(a_15, b_8, u_8.y), mix(c_17, d_9, u_8.y), u_8.z);
}

float fbm3_(vec3 p_5) {
    vec3 q_10 = ((p_5 * 2.07) + vec3(5.1, 1.3, 7.7));
    vec3 r_6 = ((q_10 * 2.11) + vec3(2.9, 8.3, 4.1));
    float _e15 = vnoise3_(p_5);
    float _e18 = vnoise3_(q_10);
    float _e22 = vnoise3_(r_6);
    return (((0.55 * _e15) + (0.3 * _e18)) + (0.15 * _e22));
}

uint pcg(uint x) {
    uint s_6 = ((x * 747796405u) + 2891336453u);
    uint w_4 = (((s_6 >> ((s_6 >> 28u) + 4u)) ^ s_6) * 277803737u);
    return ((w_4 >> 22u) ^ w_4);
}

float fh21_(vec2 p_6) {
    uvec2 q_11 = uvec2(ivec2(floor(p_6)));
    uint _e6 = pcg(q_11.y);
    uint _e8 = pcg((q_11.x ^ _e6));
    return (float(_e8) * 2.3283064e-10);
}

float fh31_(vec3 p_7) {
    uvec3 q_12 = uvec3(ivec3(floor(p_7)));
    uint _e7 = pcg(q_12.z);
    uint _e9 = pcg((q_12.y ^ _e7));
    uint _e11 = pcg((q_12.x ^ _e9));
    return (float(_e11) * 2.3283064e-10);
}

float fvnoise(vec2 p_8) {
    vec2 i_30 = floor(p_8);
    vec2 f_13 = fract(p_8);
    vec2 u_9 = ((f_13 * f_13) * (vec2(3.0) - (2.0 * f_13)));
    float _e10 = fh21_(i_30);
    float _e15 = fh21_((i_30 + vec2(1.0, 0.0)));
    float _e22 = fh21_((i_30 + vec2(0.0, 1.0)));
    float _e27 = fh21_((i_30 + vec2(1.0, 1.0)));
    return mix(mix(_e10, _e15, u_9.x), mix(_e22, _e27, u_9.x), u_9.y);
}

float ffbm(vec2 p_9) {
    float _e1 = fvnoise(p_9);
    float _e10 = fvnoise(((p_9 * 2.03) + vec2(17.3, 9.1)));
    float _e20 = fvnoise(((p_9 * 4.1) + vec2(3.1, 5.7)));
    return (((0.55 * _e1) + (0.3 * _e10)) + (0.15 * _e20));
}

float fvnoise3_(vec3 p_10) {
    vec3 i_31 = floor(p_10);
    vec3 f_14 = fract(p_10);
    vec3 u_10 = ((f_14 * f_14) * (vec3(3.0) - (2.0 * f_14)));
    float _e10 = fh31_(i_31);
    float _e16 = fh31_((i_31 + vec3(1.0, 0.0, 0.0)));
    float a_16 = mix(_e10, _e16, u_10.x);
    float _e24 = fh31_((i_31 + vec3(0.0, 1.0, 0.0)));
    float _e30 = fh31_((i_31 + vec3(1.0, 1.0, 0.0)));
    float b_9 = mix(_e24, _e30, u_10.x);
    float _e38 = fh31_((i_31 + vec3(0.0, 0.0, 1.0)));
    float _e44 = fh31_((i_31 + vec3(1.0, 0.0, 1.0)));
    float c_18 = mix(_e38, _e44, u_10.x);
    float _e52 = fh31_((i_31 + vec3(0.0, 1.0, 1.0)));
    float _e58 = fh31_((i_31 + vec3(1.0, 1.0, 1.0)));
    float d_10 = mix(_e52, _e58, u_10.x);
    return mix(mix(a_16, b_9, u_10.y), mix(c_18, d_10, u_10.y), u_10.z);
}

float ffbm3_(vec3 p_11) {
    float _e1 = fvnoise3_(p_11);
    float _e11 = fvnoise3_(((p_11 * 2.07) + vec3(5.1, 1.3, 7.7)));
    return ((0.62 * _e1) + (0.38 * _e11));
}

vec3 lava_ramp(float x_1) {
    vec3 c_4 = vec3(0.0);
    float h_2 = clamp(x_1, 0.0, 1.0);
    c_4 = mix(vec3(0.02, 0.0, 0.0), vec3(0.7, 0.05, 0.0), smoothstep(0.0, 0.3, h_2));
    vec3 _e15 = c_4;
    c_4 = mix(_e15, vec3(1.0, 0.38, 0.02), smoothstep(0.25, 0.55, h_2));
    vec3 _e24 = c_4;
    c_4 = mix(_e24, vec3(1.0, 0.85, 0.35), smoothstep(0.5, 0.8, h_2));
    vec3 _e33 = c_4;
    c_4 = mix(_e33, vec3(1.0, 1.0, 1.0), smoothstep(0.8, 1.0, h_2));
    vec3 _e42 = c_4;
    return _e42;
}

vec3 gold_ramp(float x_2) {
    vec3 c_5 = vec3(0.0);
    float h_3 = clamp(x_2, 0.0, 1.0);
    c_5 = mix(vec3(0.12, 0.05, 0.0), vec3(0.85, 0.45, 0.05), smoothstep(0.0, 0.3, h_3));
    vec3 _e15 = c_5;
    c_5 = mix(_e15, vec3(1.0, 0.82, 0.3), smoothstep(0.25, 0.6, h_3));
    vec3 _e24 = c_5;
    c_5 = mix(_e24, vec3(1.0, 0.98, 0.9), smoothstep(0.6, 1.0, h_3));
    vec3 _e33 = c_5;
    return _e33;
}

vec3 plasma_ramp(float x_3) {
    vec3 c_6 = vec3(0.0);
    float h_4 = clamp(x_3, 0.0, 1.0);
    c_6 = mix(vec3(0.0), vec3(0.35, 0.08, 0.6), smoothstep(0.05, 0.3, h_4));
    vec3 _e13 = c_6;
    c_6 = mix(_e13, vec3(0.3, 0.6, 2.2), smoothstep(0.25, 0.55, h_4));
    vec3 _e22 = c_6;
    c_6 = mix(_e22, vec3(1.2, 2.0, 3.0), smoothstep(0.5, 0.8, h_4));
    vec3 _e31 = c_6;
    c_6 = mix(_e31, vec3(4.0, 4.0, 4.2), smoothstep(0.8, 1.0, h_4));
    vec3 _e40 = c_6;
    return _e40;
}

float th_is(float i_2) {
    float _e1 = laser();
    return (1.0 - step(0.5, abs((_e1 - i_2))));
}

vec3 pick2_(vec3 a, vec3 b) {
    float _e3 = th_is(0.0);
    float _e6 = th_is(1.0);
    return ((a * _e3) + (b * _e6));
}

vec3 aces(vec3 x_4) {
    return clamp(((x_4 * ((2.51 * x_4) + vec3(0.03))) / ((x_4 * ((2.43 * x_4) + vec3(0.59))) + vec3(0.14))), vec3(0.0), vec3(1.0));
}

vec3 target_pos() {
    vec3 v_1 = vec3(0.0);
    float _e4 = target_x();
    v_1.x = _e4;
    float _e6 = target_y();
    v_1.y = _e6;
    float _e8 = target_z();
    v_1.z = _e8;
    vec3 _e9 = v_1;
    return _e9;
}

vec2 anchor_xz() {
    vec2 v_2 = vec2(0.0);
    float _e4 = anchor_x();
    v_2.x = _e4;
    float _e6 = anchor_z();
    v_2.y = _e6;
    vec2 _e7 = v_2;
    return _e7;
}

vec4 wing_dirs() {
    float _e0 = wing_a();
    float c_19 = cos(_e0);
    float s_7 = sin(_e0);
    return vec4(c_19, s_7, -(s_7), c_19);
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
    float n1_1 = ((_e10 - 0.5) * 2.0);
    float _e23 = vnoise(vec2(((u * 13.0) + (seed * 3.1)), (tq * 1.7)));
    float n2_2 = ((_e23 - 0.5) * 2.0);
    float _e36 = vnoise(vec2(((u * 41.0) + (seed * 5.3)), (tq * 2.3)));
    float n3_1 = ((_e36 - 0.5) * 2.0);
    return ((((n1_1 * amp) + ((n2_2 * amp) * 0.38)) + ((n3_1 * amp) * 0.12)) * smoothstep(0.0, 0.1, u));
}

vec3 bolt_line(vec2 p_13, vec2 a_1, vec2 b_1, float seed_1, float tq_1, float wid) {
    vec2 ab = (b_1 - a_1);
    float len_1 = max(length(ab), 0.0001);
    vec2 dir_1 = (ab / vec2(len_1));
    vec2 nrm = vec2(-(dir_1.y), dir_1.x);
    vec2 ap = (p_13 - a_1);
    float u_11 = clamp((dot(ap, dir_1) / len_1), 0.0, 1.0);
    float _e23 = bolt_disp(len_1, u_11, seed_1, tq_1);
    float off_1 = (dot(ap, nrm) - _e23);
    float along = (dot(ap, dir_1) - (u_11 * len_1));
    float d_11 = length(vec2(off_1, along));
    float w_5 = (wid * (1.0 - (0.75 * u_11)));
    float core_1 = exp(-(pow((d_11 / w_5), 2.0)));
    float g = (1.0 / (1.0 + pow((d_11 / (w_5 * 3.0)), 2.0)));
    return vec3(core_1, (g * g), u_11);
}

vec2 seg_soft(vec2 p_14, vec2 a_2, vec2 b_2, float w) {
    vec2 ab_1 = (b_2 - a_2);
    float l2_ = max(dot(ab_1, ab_1), 1e-8);
    float u_12 = clamp((dot((p_14 - a_2), ab_1) / l2_), 0.0, 1.0);
    float d_12 = length((p_14 - (a_2 + (ab_1 * u_12))));
    float ww = (w * (1.0 - (0.65 * u_12)));
    return vec2(exp(-(pow((d_12 / ww), 2.0))), (1.0 / (1.0 + pow((d_12 / (ww * 4.0)), 2.0))));
}

float tri_line(float r, float ang, float R, float w_1) {
    float a_17 = (ang - (floor(((ang / 2.0943952) + 0.5)) * 2.0943952));
    float d_13 = ((r * cos(a_17)) - (R * 0.5));
    return (exp(-(pow((d_13 / w_1), 2.0))) * (1.0 - smoothstep((R * 0.98), (R * 1.04), r)));
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
    vec3 q_13 = (d_1 * 140.0);
    vec3 f_15 = (fract(q_13) - vec3(0.5));
    float _e11 = fh31_((floor(q_13) + vec3(seed_2)));
    float star = ((step(0.975, _e11) * exp((-(dot(f_15, f_15)) * 40.0))) * (0.5 + (4.0 * fract((_e11 * 37.0)))));
    vec3 tint = mix(vec3(0.7, 0.8, 1.25), vec3(1.25, 0.9, 0.7), fract((_e11 * 91.0)));
    float _e46 = ffbm3_(((d_1 * 2.6) + vec3((seed_2 * 0.01))));
    float _e54 = ffbm3_(((d_1 * 6.0) - vec3(2.0, 0.0, 1.0)));
    vec3 haze_2 = ((vec3(0.1, 0.02, 0.17) * smoothstep(0.4, 0.85, _e46)) + (vec3(0.02, 0.04, 0.13) * smoothstep(0.5, 0.9, _e54)));
    return ((tint * star) + haze_2);
}

vec3 disk_ramp(float x_5) {
    vec3 c_8 = vec3(0.0);
    float h_5 = clamp(x_5, 0.0, 1.0);
    c_8 = mix(vec3(0.0), vec3(0.7, 0.07, 0.02), smoothstep(0.0, 0.25, h_5));
    vec3 _e13 = c_8;
    c_8 = mix(_e13, vec3(2.4, 0.75, 0.12), smoothstep(0.2, 0.5, h_5));
    vec3 _e22 = c_8;
    c_8 = mix(_e22, vec3(3.4, 2.5, 1.35), smoothstep(0.45, 0.75, h_5));
    vec3 _e31 = c_8;
    c_8 = mix(_e31, vec3(3.2, 3.6, 5.0), smoothstep(0.75, 1.0, h_5));
    vec3 _e40 = c_8;
    return _e40;
}

vec3 bh_scene(vec2 uvs, vec3 dir, float seed_3, float sky_env, float dim) {
    vec4 _e8 = orbitalSceneLod(_group_0_binding_0_fs, vec2(uvs), 0.0);
    vec3 _e10 = srgb_to_linear(_e8.xyz);
    vec3 c_20 = (_e10 * dim);
    float _e12 = depth_at(uvs);
    bool _e13 = is_sky(_e12);
    if (_e13) {
        vec3 _e14 = bh_sky(dir, seed_3);
        return mix(c_20, _e14, (sky_env * 0.94));
    }
    return c_20;
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

vec3 rot_axis(vec3 v_3, vec3 a_3, float ang_1) {
    float c_21 = cos(ang_1);
    float s_8 = sin(ang_1);
    return (((v_3 * c_21) + (cross(a_3, v_3) * s_8)) + ((a_3 * dot(a_3, v_3)) * (1.0 - c_21)));
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
    float z = sqrt(clamp((1.0 - (rs / max(r_3, 0.001))), 0.0, 1.0));
    return vec3(pow(z, 0.7), pow(z, 1.6), pow(z, 2.6));
}

vec4 bh_chunk(vec3 c_9, vec3 rd, vec3 u_4, float k, float hs, vec3 ax, float ang_2, vec3 H, float rs_1) {
    bool local = false;
    bool local_1 = false;
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
        local = (tn < 0.0);
    } else {
        local = true;
    }
    bool _e74 = local;
    if (!(_e74)) {
        local_1 = (length(((rd * tn) - H)) < rs_1);
    } else {
        local_1 = true;
    }
    bool _e83 = local_1;
    if (_e83) {
        return vec4(-1.0);
    }
    return vec4(tn, (ro_l + (rd_l * tn)));
}

vec3 bh_chunk_n(vec3 lp, vec3 u_5, float k_1, vec3 ax_1, float ang_3) {
    vec3 nl = vec3(0.0);
    bool local_2 = false;
    vec3 al = abs(lp);
    nl = vec3(0.0, sign(lp.y), 0.0);
    if ((al.x >= al.y)) {
        local_2 = (al.x >= al.z);
    } else {
        local_2 = false;
    }
    bool _e21 = local_2;
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

Piece debris_piece(int i_3, float ft, float seed_7, vec3 cam, vec3 tgt, vec3 H_1, vec3 n, float rs_2) {
    Piece pc = Piece(vec3(0.0), vec3(0.0), 0.0, 0.0, 0.0, vec4(0.0), 0.0);
    vec3 c_10 = vec3(0.0);
    float alive = 0.0;
    bool local_3 = false;
    float stretch = 0.0;
    bool local_4 = false;
    bool local_5 = false;
    pc.alive = 0.0;
    pc.k = 1.0;
    pc.glow = 0.0;
    pc.u = vec3(0.0, 1.0, 0.0);
    pc.c = vec3(0.0);
    float fi_9 = float(i_3);
    float _e24 = debris_t(fi_9);
    float s_9 = (min(ft, BH_END) - _e24);
    if ((s_9 <= 0.0)) {
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
    float ub = (s_9 / T_in);
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
    alive = smoothstep(0.0, 0.05, s_9);
    float _e163 = bh_tide_max(_e32, l0_2, _e89, u_13, lag_2);
    if (!(!(flung))) {
        local_3 = (ub < u_f);
    } else {
        local_3 = true;
    }
    bool _e171 = local_3;
    stretch = (_e171 ? -(_e163) : 1.0);
    if (flung) {
        local_4 = (ub > u_f);
    } else {
        local_4 = false;
    }
    bool _e179 = local_4;
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
        local_5 = (ub > u_f);
    } else {
        local_5 = false;
    }
    bool _e253 = local_5;
    pc.glow = ((_e253 ? 0.0 : smoothstep((rsn * 4.0), (rsn * 1.2), _e89)) * float((ft <= BH_END)));
    float _e261 = alive;
    pc.alive = _e261;
    Piece _e262 = pc;
    return _e262;
}

vec3 debris_tex(int kind, vec2 px, bool top, float side_y, float seed_8) {
    bool local_6 = false;
    float _e12 = fh21_((px + vec2((seed_8 * 3.1), (float(kind) * 17.0))));
    float _e18 = fh21_(((px * 1.7) + vec2(5.0, seed_8)));
    switch(kind) {
        case 0: {
            if (!(top)) {
                local_6 = (side_y > 0.8);
            } else {
                local_6 = true;
            }
            bool _e25 = local_6;
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

BhLens bh_lens(vec3 H_2, float rs_l, vec3 rd_1, vec2 uv2_, float scene_len, bool sky, vec3 n_1, vec3 e1_, vec3 e2_, float disk_env, float hot, float seed_9, float time, float sky_env_1, float dim_1) {
    BhLens L = BhLens(false, false, false, vec3(0.0), 0.0, vec3(0.0), 0.0, vec3(0.0), vec3(0.0), 0.0);
    bool local_7 = false;
    bool local_8 = false;
    vec3 pp = vec3(0.0);
    vec3 v_4 = vec3(0.0);
    float travel = 0.0;
    float trans = 1.0;
    vec3 acc = vec3(0.0);
    bool captured = false;
    bool hit = false;
    float rmin = 1000000000.0;
    int i_4 = 0;
    bool local_9 = false;
    bool local_10 = false;
    bool local_11 = false;
    bool local_12 = false;
    vec3 bent = vec3(0.0);
    vec3 far = vec3(0.0);
    bool local_13 = false;
    bool local_14 = false;
    bool local_15 = false;
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
    float tc_1 = dot(H_2, rd_1);
    float b_10 = length((H_2 - (rd_1 * tc_1)));
    float t0_1 = max((tc_1 - infl), 0.0);
    if ((b_10 < infl)) {
        local_7 = ((tc_1 + infl) > 0.0);
    } else {
        local_7 = false;
    }
    bool _e54 = local_7;
    if (_e54) {
        local_8 = (scene_len > t0_1);
    } else {
        local_8 = false;
    }
    bool _e59 = local_8;
    if (_e59) {
        L.on = true;
        pp = (((rd_1 * t0_1) - H_2) / vec3(rs_l));
        v_4 = rd_1;
        travel = t0_1;
        vec3 _e69 = pp;
        vec3 _e70 = v_4;
        vec3 hv_1 = cross(_e69, _e70);
        float h2_ = dot(hv_1, hv_1);
        bool loop_init = true;
        while(true) {
            if (!loop_init) {
                int _e281 = i_4;
                i_4 = (_e281 + 1);
            }
            loop_init = false;
            int _e86 = i_4;
            if ((_e86 < 96)) {
            } else {
                break;
            }
            {
                vec3 _e89 = pp;
                float r_7 = length(_e89);
                float _e91 = rmin;
                rmin = min(_e91, r_7);
                if ((r_7 < 1.0)) {
                    captured = true;
                    break;
                }
                if ((r_7 > 12.5)) {
                    vec3 _e100 = pp;
                    vec3 _e101 = v_4;
                    local_9 = (dot(_e100, _e101) > 0.0);
                } else {
                    local_9 = false;
                }
                bool _e106 = local_9;
                if (_e106) {
                    break;
                }
                float dt_1 = clamp(((r_7 - 0.9) * 0.16), 0.03, 1.5);
                vec3 prev = pp;
                float r2_ = (r_7 * r_7);
                vec3 _e116 = v_4;
                vec3 _e119 = pp;
                v_4 = normalize((_e116 - ((((1.5 * h2_) * _e119) / vec3(((r2_ * r2_) * r_7))) * dt_1)));
                vec3 _e128 = pp;
                vec3 _e129 = v_4;
                pp = (_e128 + (_e129 * dt_1));
                float _e132 = travel;
                travel = (_e132 + (dt_1 * rs_l));
                if (!(sky)) {
                    float _e138 = travel;
                    local_10 = (_e138 > scene_len);
                } else {
                    local_10 = false;
                }
                bool _e141 = local_10;
                if (_e141) {
                    hit = true;
                    break;
                }
                float s0_ = dot(prev, n_1);
                vec3 _e144 = pp;
                float s1_ = dot(_e144, n_1);
                if ((disk_env > 0.001)) {
                    local_11 = ((s0_ * s1_) < 0.0);
                } else {
                    local_11 = false;
                }
                bool _e154 = local_11;
                if (_e154) {
                    vec3 _e155 = pp;
                    vec3 x_10 = mix(prev, _e155, (s0_ / (s0_ - s1_)));
                    float dr = length(x_10);
                    if ((dr > 2.34)) {
                        local_12 = (dr < DISK_OUT);
                    } else {
                        local_12 = false;
                    }
                    bool _e167 = local_12;
                    if (_e167) {
                        vec2 dx = vec2(dot(x_10, e1_), dot(x_10, e2_));
                        float rot = ((-(time) * 5.5) / pow(dr, 1.5));
                        vec2 q_14 = vec2(((dx.x * cos(rot)) - (dx.y * sin(rot))), ((dx.x * sin(rot)) + (dx.y * cos(rot))));
                        float _e197 = fbm(((q_14 * 0.9) + vec2(seed_9, 3.0)));
                        float bands = (0.55 + (0.45 * sin(((dr * 7.0) + (_e197 * 7.0)))));
                        float dens = clamp((bands * (0.35 + (1.1 * _e197))), 0.0, 1.0);
                        float edge = (smoothstep(2.34, 2.9899998, dr) * (1.0 - smoothstep(4.9500003, DISK_OUT, dr)));
                        vec3 tdir_1 = normalize(cross(n_1, x_10));
                        float beta = (0.62 * sqrt((DISK_IN / dr)));
                        vec3 _e234 = v_4;
                        float g_1 = (sqrt((1.0 - (beta * beta))) / (1.0 - (beta * dot(tdir_1, -(_e234)))));
                        float temp = ((((pow((DISK_IN / dr), 0.85) * (0.7 + (0.4 * _e197))) * g_1) * 0.95) * hot);
                        float a_d = (clamp(((dens * edge) * 1.1), 0.0, 1.0) * disk_env);
                        vec3 _e259 = acc;
                        float _e260 = trans;
                        vec3 _e262 = disk_ramp(temp);
                        acc = (_e259 + ((((_e260 * a_d) * _e262) * min(((g_1 * g_1) * g_1), 4.0)) * 1.6));
                        float _e272 = trans;
                        trans = (_e272 * (1.0 - (a_d * 0.92)));
                    }
                }
                float _e278 = trans;
                if ((_e278 < 0.02)) {
                    break;
                }
            }
        }
        float _e286 = rmin;
        float w_6 = (1.0 - smoothstep(4.2, 11.4, _e286));
        bool _e293 = captured;
        if (!(_e293)) {
            vec3 _e295 = v_4;
            vec3 dir_b = normalize(mix(rd_1, _e295, w_6));
            vec3 _e298 = pp;
            vec3 _e301 = v_4;
            far = ((H_2 + (_e298 * rs_l)) + (_e301 * 4000.0));
            bool _e306 = hit;
            if (_e306) {
                vec3 _e307 = pp;
                far = (H_2 + (_e307 * rs_l));
            }
            vec3 _e310 = far;
            vec3 _e311 = project_rel(_e310);
            vec2 uvb = mix(uv2_, _e311.xy, w_6);
            if ((_e311.z > 0.0)) {
                local_13 = all(greaterThan(uvb, vec2(0.001)));
            } else {
                local_13 = false;
            }
            bool _e324 = local_13;
            if (_e324) {
                local_14 = all(lessThan(uvb, vec2(0.999)));
            } else {
                local_14 = false;
            }
            bool on = local_14;
            if (!(on)) {
                local_15 = (w_6 < 0.01);
            } else {
                local_15 = true;
            }
            bool _e339 = local_15;
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
        float _e371 = trans;
        L.trans = _e371;
        vec3 _e373 = acc;
        L.acc = _e373;
        float _e375 = rmin;
        L.rmin = _e375;
        vec3 _e377 = pp;
        L.p = (H_2 + (_e377 * rs_l));
        vec3 _e381 = v_4;
        L.v = _e381;
        L.w = w_6;
    }
    BhLens _e383 = L;
    return _e383;
}

uvec3 pcg3d(uvec3 v0_) {
    uvec3 v_5 = uvec3(0u);
    v_5 = ((v0_ * 1664525u) + uvec3(1013904223u));
    uint _e9 = v_5.x;
    uint _e11 = v_5.y;
    uint _e13 = v_5.z;
    v_5.x = (_e9 + (_e11 * _e13));
    uint _e18 = v_5.y;
    uint _e20 = v_5.z;
    uint _e22 = v_5.x;
    v_5.y = (_e18 + (_e20 * _e22));
    uint _e27 = v_5.z;
    uint _e29 = v_5.x;
    uint _e31 = v_5.y;
    v_5.z = (_e27 + (_e29 * _e31));
    uvec3 _e34 = v_5;
    uvec3 _e35 = v_5;
    v_5 = (_e34 ^ (_e35 >> uvec3(16u)));
    uint _e42 = v_5.x;
    uint _e44 = v_5.y;
    uint _e46 = v_5.z;
    v_5.x = (_e42 + (_e44 * _e46));
    uint _e51 = v_5.y;
    uint _e53 = v_5.z;
    uint _e55 = v_5.x;
    v_5.y = (_e51 + (_e53 * _e55));
    uint _e60 = v_5.z;
    uint _e62 = v_5.x;
    uint _e64 = v_5.y;
    v_5.z = (_e60 + (_e62 * _e64));
    uvec3 _e67 = v_5;
    return _e67;
}

vec3 grad3_(vec3 i_5) {
    uvec3 _e3 = pcg3d(uvec3(ivec3(i_5)));
    return ((vec3(_e3) * 4.656613e-10) - vec3(1.0));
}

float gnoise3_(vec3 p_15) {
    vec3 i_32 = floor(p_15);
    vec3 f_16 = (p_15 - i_32);
    vec3 u_14 = (((f_16 * f_16) * f_16) * ((f_16 * ((f_16 * 6.0) - vec3(15.0))) + vec3(10.0)));
    vec3 _e15 = grad3_(i_32);
    float n000_ = dot(_e15, f_16);
    vec3 _e22 = grad3_((i_32 + vec3(1.0, 0.0, 0.0)));
    float n100_ = dot(_e22, (f_16 - vec3(1.0, 0.0, 0.0)));
    vec3 _e34 = grad3_((i_32 + vec3(0.0, 1.0, 0.0)));
    float n010_ = dot(_e34, (f_16 - vec3(0.0, 1.0, 0.0)));
    vec3 _e46 = grad3_((i_32 + vec3(1.0, 1.0, 0.0)));
    float n110_ = dot(_e46, (f_16 - vec3(1.0, 1.0, 0.0)));
    vec3 _e58 = grad3_((i_32 + vec3(0.0, 0.0, 1.0)));
    float n001_ = dot(_e58, (f_16 - vec3(0.0, 0.0, 1.0)));
    vec3 _e70 = grad3_((i_32 + vec3(1.0, 0.0, 1.0)));
    float n101_ = dot(_e70, (f_16 - vec3(1.0, 0.0, 1.0)));
    vec3 _e82 = grad3_((i_32 + vec3(0.0, 1.0, 1.0)));
    float n011_ = dot(_e82, (f_16 - vec3(0.0, 1.0, 1.0)));
    vec3 _e94 = grad3_((i_32 + vec3(1.0, 1.0, 1.0)));
    float n111_ = dot(_e94, (f_16 - vec3(1.0, 1.0, 1.0)));
    float x0_ = mix(mix(n000_, n100_, u_14.x), mix(n010_, n110_, u_14.x), u_14.y);
    float x1_ = mix(mix(n001_, n101_, u_14.x), mix(n011_, n111_, u_14.x), u_14.y);
    return ((mix(x0_, x1_, u_14.z) * 0.75) + 0.5);
}

float gfbm3_(vec3 p_16, int octaves) {
    vec3 q_1 = vec3(0.0);
    float a_4 = 0.5;
    float s = 0.0;
    float w_2 = 0.0;
    int o = 0;
    mat3x3 m_1 = mat3x3(vec3(0.0, 0.8, 0.6), vec3(-0.8, 0.36, -0.48), vec3(-0.6, -0.48, 0.64));
    q_1 = p_16;
    bool loop_init_1 = true;
    while(true) {
        if (!loop_init_1) {
            int _e47 = o;
            o = (_e47 + 1);
        }
        loop_init_1 = false;
        int _e24 = o;
        if ((_e24 < octaves)) {
        } else {
            break;
        }
        {
            float _e26 = s;
            float _e27 = a_4;
            vec3 _e28 = q_1;
            float _e29 = gnoise3_(_e28);
            s = (_e26 + (_e27 * _e29));
            float _e32 = w_2;
            float _e33 = a_4;
            w_2 = (_e32 + _e33);
            vec3 _e35 = q_1;
            q_1 = (((m_1 * _e35) * 2.03) + vec3(1.7, 9.2, 5.3));
            float _e44 = a_4;
            a_4 = (_e44 * 0.5);
        }
    }
    float _e50 = s;
    float _e51 = w_2;
    return (_e50 / _e51);
}

vec2 grad2_(vec2 i_6) {
    uvec3 _e5 = pcg3d(uvec3(ivec3(ivec2(i_6), 7)));
    return ((vec2(_e5.xy) * 4.656613e-10) - vec2(1.0));
}

float gnoise2_(vec2 p_17) {
    vec2 i_33 = floor(p_17);
    vec2 f_17 = (p_17 - i_33);
    vec2 u_15 = (((f_17 * f_17) * f_17) * ((f_17 * ((f_17 * 6.0) - vec2(15.0))) + vec2(10.0)));
    vec2 _e15 = grad2_(i_33);
    float a_18 = dot(_e15, f_17);
    vec2 _e21 = grad2_((i_33 + vec2(1.0, 0.0)));
    float b_11 = dot(_e21, (f_17 - vec2(1.0, 0.0)));
    vec2 _e31 = grad2_((i_33 + vec2(0.0, 1.0)));
    float c_22 = dot(_e31, (f_17 - vec2(0.0, 1.0)));
    vec2 _e41 = grad2_((i_33 + vec2(1.0, 1.0)));
    float d_14 = dot(_e41, (f_17 - vec2(1.0, 1.0)));
    return ((mix(mix(a_18, b_11, u_15.x), mix(c_22, d_14, u_15.x), u_15.y) * 0.9) + 0.5);
}

float gfbm2_(vec2 p_18) {
    mat2x2 m_2 = mat2x2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
    vec2 q1_1 = (((m_2 * p_18) * 2.03) + vec2(1.7, 9.2));
    vec2 q2_1 = (((m_2 * q1_1) * 2.01) + vec2(5.3, 2.8));
    float _e22 = gnoise2_(p_18);
    float _e25 = gnoise2_(q1_1);
    float _e29 = gnoise2_(q2_1);
    return ((((0.5 * _e22) + (0.25 * _e25)) + (0.125 * _e29)) / 0.875);
}

float ign(vec2 px_1) {
    return fract((52.982918 * fract(dot(px_1, vec2(0.06711056, 0.00583715)))));
}

float mh(uint i_7, uint seed_10, uint k_2) {
    uint _e3 = pcg(k_2);
    uint _e5 = pcg((seed_10 ^ _e3));
    uint _e7 = pcg((i_7 ^ _e5));
    return (float(_e7) * 2.3283064e-10);
}

vec3 met_where(float fi_4, float seed_11) {
    uint i_34 = uint(fi_4);
    uint s_10 = uint(seed_11);
    float _e5 = mh(i_34, s_10, 5u);
    if ((_e5 < 0.33)) {
        float _e10 = mh(i_34, s_10, 6u);
        uint c_23 = (100u + min(uint((_e10 * 6.0)), 5u));
        float _e18 = mh(c_23, s_10, 1u);
        float ca = (_e18 * TAU);
        float _e23 = mh(c_23, s_10, 2u);
        float cr = (24.0 + (90.0 * sqrt(_e23)));
        float _e29 = mh(i_34, s_10, 7u);
        float oa_1 = (_e29 * TAU);
        float _e33 = mh(i_34, s_10, 8u);
        float orr = (3.0 + (11.0 * _e33));
        vec2 pos = ((vec2(cos(ca), sin(ca)) * cr) + (vec2(cos(oa_1), sin(oa_1)) * orr));
        float _e48 = mh(c_23, s_10, 3u);
        float _e54 = mh(i_34, s_10, 9u);
        return vec3(pos, ((3.0 + (8.5 * _e48)) + (1.4 * _e54)));
    }
    float _e60 = mh(i_34, s_10, 1u);
    float a_19 = (_e60 * TAU);
    float _e65 = mh(i_34, s_10, 2u);
    float r_8 = (14.0 + (106.0 * sqrt(_e65)));
    float _e75 = mh(i_34, s_10, 3u);
    return vec3((cos(a_19) * r_8), (sin(a_19) * r_8), (2.5 + (9.5 * _e75)));
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

vec3 ray_seg(vec3 rd_2, vec3 a_5, vec3 b_3) {
    float s_1 = 0.0;
    vec3 ab_2 = (b_3 - a_5);
    float l2_1 = max(dot(ab_2, ab_2), 1e-6);
    float rab = dot(rd_2, ab_2);
    float den_1 = (l2_1 - (rab * rab));
    s_1 = clamp(((den_1 > 1e-6) ? (((rab * dot(rd_2, a_5)) - dot(a_5, ab_2)) / den_1) : 0.0), 0.0, 1.0);
    float _e23 = s_1;
    float t_8 = max(dot(rd_2, (a_5 + (ab_2 * _e23))), 0.0);
    s_1 = clamp((dot(((rd_2 * t_8) - a_5), ab_2) / l2_1), 0.0, 1.0);
    float _e37 = s_1;
    float _e42 = s_1;
    return vec3(length(((rd_2 * t_8) - (a_5 + (ab_2 * _e37)))), t_8, _e42);
}

float ms_sweep(float t_1) {
    float s_11 = clamp(((t_1 - MS_SWEEP0_) / 9.0), 0.0, 1.0);
    return ((s_11 * s_11) * (3.0 - (2.0 * s_11)));
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
    float ta_2 = max((t_2 - MS_ARRIVE), 0.0);
    far_1 = (MS_COAST * exp((-(ta_2) / 1.3)));
    if ((style_1 == 2)) {
        float s_12 = (1.0 + (70.0 * exp((-(ta_2) * 13.0))));
        if (up_2) {
            f.sy = s_12;
        } else {
            f.sx = s_12;
            f.px = MS_HL;
            f.sz = (1.0 / (1.0 + ((s_12 - 1.0) * 0.3)));
        }
    } else {
        if ((style_1 == 1)) {
            float u_17 = clamp((ta_2 / MS_IN), 0.0, 1.0);
            float _e80 = far_1;
            far_1 = (_e80 + (MS_FAR * pow((1.0 - u_17), 4.0)));
            float s_13 = max((1.0 - pow((1.0 - u_17), 2.2)), 0.002);
            f.sx = s_13;
            f.sz = s_13;
            f.sy = s_13;
        } else {
            float _e99 = far_1;
            far_1 = (_e99 + (MS_FAR * pow((1.0 - clamp((ta_2 / MS_SNAP), 0.0, 1.0)), 5.0)));
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
    bool local_16 = false;
    if ((t_3 >= MS_ARRIVE)) {
        local_16 = (t_3 < 23.3);
    } else {
        local_16 = false;
    }
    bool _e8 = local_16;
    return _e8;
}

vec2 ms_local(MsFrame f_1, vec2 p_19) {
    vec2 r_9 = (p_19 - f_1.c);
    return vec2(((((dot(r_9, f_1.ax) - f_1.shift) - f_1.px) / f_1.sx) + f_1.px), (dot(r_9, f_1.sd) / f_1.sz));
}

vec2 ms_world(MsFrame f_2, vec2 q_2) {
    return ((f_2.c + (f_2.ax * ((f_2.shift + f_2.px) + ((q_2.x - f_2.px) * f_2.sx)))) + (f_2.sd * (q_2.y * f_2.sz)));
}

float ms_sponson(float x_6) {
    return (32.0 * (step(abs((x_6 + 150.0)), 70.0) + step(abs((x_6 - 130.0)), 70.0)));
}

float ms_half_w(float x_7) {
    float _e2 = ms_sponson(x_7);
    return min((MS_HW + _e2), (MS_HW - ((180.0 * (x_7 - 340.0)) / MS_TAPER)));
}

float ms_outline(vec2 q_3, float inset) {
    float d_2 = 0.0;
    vec2 a_20 = abs(q_3);
    float _e11 = ms_sponson(q_3.x);
    d_2 = max(((a_20.x - MS_HL) + inset), (((a_20.y - MS_HW) - _e11) + inset));
    float _e16 = d_2;
    d_2 = max(_e16, ((((a_20.x + a_20.y) - 760.0) + (inset * 1.4142)) * 0.7071));
    float _e29 = d_2;
    return max(_e29, ((((a_20.y + (0.8181818 * (q_3.x - 340.0))) - MS_HW) / sqrt((1.0 + (0.8181818 * 0.8181818)))) + inset));
}

float ms_hangar(vec2 q_4) {
    return max((abs((q_4.x - -290.0)) - 90.0), (abs((q_4.y - 0.0)) - 100.0));
}

float ms_tier(vec2 q_5, int k_3) {
    float d_3 = 0.0;
    if ((k_3 == 0)) {
        float _e9 = ms_outline(q_5, 30.0);
        float ridge = max((abs(q_5.y) - 70.0), _e9);
        float _e20 = ms_outline(q_5, 42.0);
        float engines = max(max((abs(q_5.y) - 170.0), (q_5.x + 430.0)), _e20);
        float _e23 = ms_hangar(q_5);
        return max(min(ridge, engines), -(_e23));
    }
    if ((k_3 == 1)) {
        float _e29 = ms_outline(q_5, 40.0);
        d_3 = _e29;
        float cell = floor((q_5.x / 140.0));
        float bay = max((abs((q_5.x - ((cell + 0.5) * 140.0))) - 36.0), (176.0 - abs(q_5.y)));
        float _e49 = d_3;
        float _e58 = fh21_(vec2(cell, ((sign(q_5.y) * 3.0) + 11.0)));
        d_3 = max(_e49, ((_e58 > 0.35) ? -(bay) : -1000000000.0));
        float trench = max((abs((abs(q_5.y) - 119.0)) - 7.0), (abs((q_5.x + 60.0)) - 360.0));
        float _e78 = d_3;
        float _e81 = ms_hangar(q_5);
        return max(max(_e78, -(trench)), -(_e81));
    }
    float _e93 = fh21_(vec2(floor((q_5.x / 100.0)), (sign(q_5.y) + 3.0)));
    float step_in = (step(0.5, _e93) * step(abs(q_5.x), 500.0));
    float _e102 = ms_outline(q_5, 0.0);
    return (_e102 + (8.0 * step_in));
}

float ms_eye(vec2 q_6) {
    return (length((q_6 - vec2(70.0, 0.0))) - MS_EYE_R);
}

float ms_tier_h(int k_4) {
    return ((k_4 < 2) ? ((k_4 == 0) ? 0.0 : MS_TIER_B) : ((k_4 == 2) ? MS_TIER_C : MS_TOP));
}

MsHit ms_recess(MsFrame f_3, vec3 cam_1, vec3 rd_3, float t_lo, float up, int which) {
    MsHit hit_1 = MsHit(0.0, vec2(0.0), 0.0, 0);
    float a_6 = 0.0;
    float b_4 = 0.0;
    int i_8 = 0;
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
    b_4 = t_c;
    bool loop_init_2 = true;
    while(true) {
        if (!loop_init_2) {
            int _e61 = i_8;
            i_8 = (_e61 + 1);
        }
        loop_init_2 = false;
        int _e41 = i_8;
        if ((_e41 < 5)) {
        } else {
            break;
        }
        {
            float _e44 = a_6;
            float _e45 = b_4;
            float m_3 = (0.5 * (_e44 + _e45));
            vec2 _e53 = ms_local(f_3, (cam_1.xz + (rd_3.xz * m_3)));
            float _e54 = ms_hangar(_e53);
            float _e55 = ms_eye(_e53);
            if ((((which == 0) ? _e55 : _e54) < 0.0)) {
                a_6 = m_3;
            } else {
                b_4 = m_3;
            }
        }
    }
    float _e65 = b_4;
    hit_1.t = _e65;
    float _e69 = b_4;
    vec2 _e72 = ms_local(f_3, (cam_1.xz + (rd_3.xz * _e69)));
    hit_1.q = _e72;
    float _e76 = b_4;
    hit_1.h = (((cam_1.y + (rd_3.y * _e76)) - f_3.y0_) / f_3.sy);
    hit_1.kind = ((which == 0) ? 5 : 7);
    MsHit _e89 = hit_1;
    return _e89;
}

MsHit ms_trace(MsFrame f_4, vec3 cam_2, vec3 rd_4) {
    MsHit hit_2 = MsHit(0.0, vec2(0.0), 0.0, 0);
    bool local_17 = false;
    int k_5 = 0;
    bool local_18 = false;
    bool local_19 = false;
    bool local_20 = false;
    float a_7 = 0.0;
    float b_5 = 0.0;
    int i_9 = 0;
    hit_2.t = 1000000000.0;
    hit_2.q = vec2(0.0);
    hit_2.h = 0.0;
    hit_2.kind = -1;
    if (!((rd_4.y < 0.001))) {
        local_17 = (cam_2.y > f_4.y0_);
    } else {
        local_17 = true;
    }
    bool _e23 = local_17;
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
    bool loop_init_3 = true;
    while(true) {
        if (!loop_init_3) {
            int _e202 = k_5;
            k_5 = (_e202 + 1);
        }
        loop_init_3 = false;
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
                local_18 = (_e106 < 0.0);
            } else {
                local_18 = false;
            }
            bool _e110 = local_18;
            if (_e110) {
                float _e114 = ms_outline(_e100, 40.0);
                local_19 = (_e114 < 0.0);
            } else {
                local_19 = false;
            }
            bool _e118 = local_19;
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
                    local_20 = (_e131 < 0.0);
                } else {
                    local_20 = false;
                }
                bool _e135 = local_20;
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
                b_5 = t_hi;
                i_9 = 0;
                bool loop_init_4 = true;
                while(true) {
                    if (!loop_init_4) {
                        int _e177 = i_9;
                        i_9 = (_e177 + 1);
                    }
                    loop_init_4 = false;
                    int _e160 = i_9;
                    if ((_e160 < 5)) {
                    } else {
                        break;
                    }
                    {
                        float _e163 = a_7;
                        float _e164 = b_5;
                        float m_4 = (0.5 * (_e163 + _e164));
                        vec2 _e172 = ms_local(f_4, (cam_2.xz + (rd_4.xz * m_4)));
                        int _e173 = k_5;
                        float _e174 = ms_tier(_e172, _e173);
                        if ((_e174 < 0.0)) {
                            b_5 = m_4;
                        } else {
                            a_7 = m_4;
                        }
                    }
                }
                float _e181 = b_5;
                hit_2.t = _e181;
                float _e185 = b_5;
                vec2 _e188 = ms_local(f_4, (cam_2.xz + (rd_4.xz * _e185)));
                hit_2.q = _e188;
                float _e192 = b_5;
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

vec4 ms_plates(vec2 q_7, float fp) {
    float _e10 = fh21_((floor((q_7 / vec2(48.0))) + vec2(17.0, 3.0)));
    vec2 size = vec2(((_e10 > 0.45) ? 24.0 : 48.0), ((_e10 > 0.75) ? 24.0 : 48.0));
    vec2 c_24 = floor((q_7 / size));
    vec2 fr = (q_7 - (c_24 * size));
    float e_1 = min(min(fr.x, (size.x - fr.x)), min(fr.y, (size.y - fr.y)));
    float seam = ((1.0 - smoothstep((0.45 * 0.5), (0.45 + fp), e_1)) * min(1.0, ((2.0 * 0.45) / max(fp, 0.001))));
    float _e59 = fh21_(((c_24 * vec2(1.0, 1.7)) + (size * 0.37)));
    return vec4(seam, _e59, size);
}

float ms_line(float d_4, float w_3, float fp_1) {
    float ww_1 = max(w_3, fp_1);
    return (exp(-(pow((d_4 / ww_1), 2.0))) * (w_3 / ww_1));
}

vec3 ms_env(vec3 r_4, vec3 haze, vec3 sun, float day) {
    float _e4 = luminance(haze);
    vec3 grey = mix(haze, vec3(_e4), 0.65);
    vec3 ground_1 = ((vec3(0.16, 0.17, 0.13) * (0.08 + (0.92 * day))) * mix(0.35, 1.0, smoothstep(-0.75, -0.3, r_4.y)));
    vec3 e_2 = mix(ground_1, (grey * 1.1), smoothstep(-0.28, 0.0, r_4.y));
    vec3 glare = (((vec3(1.0, 0.88, 0.7) * pow(max(dot(r_4, normalize(vec3(sun.x, -(abs(sun.y)), sun.z))), 0.0), 24.0)) * 1.1) * day);
    return (mix(e_2, (grey * 0.9), smoothstep(0.0, 0.5, r_4.y)) + glare);
}

vec3 ms_hull(MsHit h, MsFrame f_5, vec3 rd_5, float time_1, float lit, float chase_on, float core, float beam, vec3 focus, vec3 haze_1, float day_1, vec3 sun_1, float boost, float wake, float eng) {
    bool local_21 = false;
    bool local_22 = false;
    float tone = 1.0;
    float rough = 0.35;
    vec3 nl_1 = vec3(0.0, -1.0, 0.0);
    vec3 emit = vec3(0.0);
    bool local_23 = false;
    bool local_24 = false;
    bool local_25 = false;
    bool local_26 = false;
    bool local_27 = false;
    bool local_28 = false;
    bool local_29 = false;
    float s_2 = 0.0;
    bool local_30 = false;
    vec2 n2_ = vec2(0.0);
    bool local_31 = false;
    bool local_32 = false;
    bool local_33 = false;
    bool local_34 = false;
    vec3 c_11 = vec3(0.0);
    vec2 q_15 = h.q;
    float _e20 = _group_0_binding_4_fs.projection[1][1];
    float _e24 = _group_0_binding_4_fs.resolution.y;
    float pix = (2.0 / (_e20 * _e24));
    if (!((h.kind == 3))) {
        local_21 = (h.kind == 5);
    } else {
        local_21 = true;
    }
    bool _e38 = local_21;
    if (!(_e38)) {
        local_22 = (h.kind == 7);
    } else {
        local_22 = true;
    }
    bool wall = local_22;
    float fp_2 = ((h.t * pix) / (wall ? 0.6 : max(rd_5.y, 0.12)));
    vec3 X = (rd_5 * h.t);
    vec3 green = vec3(0.12, 1.5, 0.3);
    float _e78 = fh21_((floor((q_15 / vec2(23.0))) + vec2(77.0, 1.0)));
    float on_at = ((0.35 + ((0.25 * (q_15.x + MS_HL)) / 1120.0)) + (0.06 * _e78));
    float on_1 = smoothstep(on_at, (on_at + 0.05), wake);
    float chase = (pow((0.5 + (0.5 * sin(((q_15.x * 0.025) - (time_1 * 7.0))))), 6.0) * chase_on);
    float glow_1 = ((((0.25 + (0.9 * lit)) + (1.6 * chase)) * boost) * on_1);
    if ((h.kind <= 2)) {
        vec4 _e123 = ms_plates(q_15, fp_2);
        uvec3 _e131 = pcg3d(uvec3(ivec3(ivec2(floor((q_15 / _e123.zw))), 9)));
        vec3 hv_2 = (vec3(_e131) * 2.3283064e-10);
        nl_1 = normalize(vec3(((hv_2.x - 0.5) * 0.45), -1.0, ((hv_2.y - 0.5) * 0.45)));
        rough = (0.15 + (0.6 * hv_2.z));
        tone = (((0.55 + (0.7 * _e123.y)) * mix(1.0, 0.25, _e123.x)) * ((h.kind == 0) ? 0.85 : ((h.kind == 1) ? 1.0 : 1.1)));
        float _e175 = tone;
        float _e182 = gnoise2_(((q_15 * 0.006) + vec2(3.1, 7.7)));
        tone = (_e175 * (0.65 + (0.7 * _e182)));
        float _e198 = fh21_((floor((q_15 / vec2(6.0))) + vec2((_e123.y * 91.0), 5.0)));
        float _e199 = tone;
        tone = (_e199 * mix(1.0, (0.65 + ((0.7 * _e198) * _e198)), clamp((2.0 - (fp_2 / 3.0)), 0.0, 1.0)));
        float seam_d = (12.0 - (abs((fract((q_15.y / 24.0)) - 0.5)) * 24.0));
        float _e231 = gnoise2_(vec2((q_15.x * 0.015), (q_15.y * 0.45)));
        float streak = smoothstep(0.45, 0.75, _e231);
        float _e235 = tone;
        tone = (_e235 * (1.0 - (((0.45 * exp((-(seam_d) / 2.5))) * streak) * clamp((2.0 - (fp_2 / 2.0)), 0.0, 1.0))));
        if ((_e123.y > 0.82)) {
            vec2 rdl = vec2(dot(rd_5.xz, f_5.ax), dot(rd_5.xz, f_5.sd));
            vec2 qd = (q_15 + (rdl * (4.0 / max(rd_5.y, 0.2))));
            if (any(notEqual(floor((qd / _e123.zw)), floor((q_15 / _e123.zw))))) {
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
                local_23 = (_e123.y < 0.7);
            } else {
                local_23 = false;
            }
            bool _e312 = local_23;
            if (_e312) {
                float _e313 = tone;
                tone = (_e313 * mix(1.0, (0.75 + (0.5 * smoothstep(0.15, 0.35, abs((fract((q_15.y / 2.5)) - 0.5))))), clamp((1.5 - fp_2), 0.0, 1.0)));
            } else {
                if ((_e123.y < 0.12)) {
                    float slot = (step(abs((fract((q_15.x / 4.0)) - 0.5)), 0.3) * step(abs((fract((q_15.y / _e123.w)) - 0.5)), 0.3));
                    float _e356 = tone;
                    tone = (_e356 * mix(1.0, (1.0 - (0.85 * slot)), clamp((2.0 - (fp_2 / 1.5)), 0.0, 1.0)));
                }
            }
        }
        if ((h.kind == 1)) {
            local_24 = (abs(q_15.y) > 70.0);
        } else {
            local_24 = false;
        }
        bool _e379 = local_24;
        if (_e379) {
            float lz = ((abs(q_15.y) - 70.0) / 34.0);
            float fl = fract(lz);
            float _e387 = tone;
            float _e391 = fh21_(vec2(floor(lz), 61.0));
            tone = (_e387 * (0.85 + (0.3 * _e391)));
            float _e397 = tone;
            tone = ((_e397 * (1.0 - (0.5 * exp(((-(fl) * 34.0) / 2.5))))) + (0.9 * exp(((-((1.0 - fl)) * 34.0) / max(1.0, fp_2)))));
        }
        if ((h.kind == 2)) {
            vec2 fc = floor((q_15 / vec2(80.0, 60.0)));
            float _e433 = fh21_((fc + vec2(13.0, 29.0)));
            if ((_e433 > 0.62)) {
                local_25 = (abs(q_15.x) < 440.0);
            } else {
                local_25 = false;
            }
            bool _e443 = local_25;
            if (_e443) {
                float rdl_1 = dot(rd_5.xz, f_5.ax);
                float fin = smoothstep(0.3, 0.7, fract(((q_15.x / 3.0) + (0.2 * sign(rdl_1)))));
                float _e458 = tone;
                tone = (_e458 * mix(0.8, (0.45 + (0.7 * fin)), clamp((1.6 - (fp_2 / 1.5)), 0.0, 1.0)));
                rough = 0.5;
            }
        }
        if ((q_15.x > 310.0)) {
            local_26 = (h.kind > 0);
        } else {
            local_26 = false;
        }
        bool _e481 = local_26;
        if (_e481) {
            vec2 sc = floor((q_15 / vec2(16.0)));
            float _e490 = fh21_((sc + vec2(5.0, 83.0)));
            vec2 dv = (q_15 - ((sc + vec2(0.5)) * 16.0));
            float dd = length(dv);
            if ((_e490 > 0.45)) {
                local_27 = (dd < 5.0);
            } else {
                local_27 = false;
            }
            bool _e505 = local_27;
            if (_e505) {
                nl_1 = normalize(vec3((dv.x / 5.0), -(sqrt(max((1.0 - ((dd * dd) / 25.0)), 0.05))), (dv.y / 5.0)));
                tone = 1.3;
                rough = 0.1;
                vec3 _e525 = emit;
                float _e531 = ms_line(dd, 0.6, fp_2);
                emit = (_e525 + (((vec3(0.4, 2.6, 0.5) * _e531) * step(0.75, _e490)) * step(0.6, fract(((time_1 * 0.7) + (_e490 * 9.0))))));
            } else {
                if ((_e490 > 0.3)) {
                    local_28 = (dd < 6.0);
                } else {
                    local_28 = false;
                }
                bool _e553 = local_28;
                if (_e553) {
                    float _e554 = tone;
                    tone = (_e554 * (0.4 + (0.6 * smoothstep(0.5, 1.0, (abs((fract((dd / 2.0)) - 0.5)) * 2.0)))));
                }
            }
        }
        if ((h.h >= MS_TOP)) {
            float _e576 = nl_1.y;
            nl_1.y = -(_e576);
        }
        float _e579 = ms_tier(q_15, h.kind);
        float edge_1 = -(_e579);
        if ((h.kind == 0)) {
            float _e592 = ms_eye(q_15);
            local_29 = (_e592 < 2.0);
        } else {
            local_29 = false;
        }
        bool _e596 = local_29;
        float bevel = ((1.0 - smoothstep(0.0, (2.5 + fp_2), edge_1)) * (_e596 ? 0.0 : 1.0));
        float _e601 = tone;
        tone = (_e601 + (1.2 * bevel));
        float _e605 = rough;
        rough = mix(_e605, 0.1, bevel);
        float _e620 = ms_line((abs((fract(((q_15.x / 120.0) + 0.5)) - 0.5)) * 120.0), 0.5, fp_2);
        float _e636 = fh21_(vec2(floor(((q_15.x / 120.0) + 0.5)), (floor((q_15.y / 70.0)) + 40.0)));
        s_2 = ((_e620 * 0.35) * step(0.4, _e636));
        if ((h.kind == 0)) {
            float _e644 = s_2;
            float _e651 = ms_line(abs((abs(q_15.y) - 20.0)), 0.5, fp_2);
            s_2 = (_e644 + (_e651 * 0.6));
        } else {
            float _e655 = s_2;
            float _e659 = ms_tier(q_15, (h.kind - 1));
            float _e663 = ms_line((_e659 - 1.4), 0.6, fp_2);
            s_2 = (_e655 + (_e663 * 1.3));
        }
        vec3 _e667 = emit;
        float _e668 = s_2;
        emit = (_e667 + ((green * _e668) * glow_1));
        if ((h.kind > 0)) {
            float row = floor((q_15.y / 6.0));
            float _e688 = fh21_((vec2(row, floor((q_15.x / 90.0))) + vec2(3.0, 17.0)));
            float wx = floor((q_15.x / 2.0));
            float _e698 = fh21_((vec2(wx, row) + vec2(41.0, 5.0)));
            if ((_e688 > 0.64)) {
                local_30 = (_e698 > 0.72);
            } else {
                local_30 = false;
            }
            bool _e706 = local_30;
            if (_e706) {
                float d_15 = length((q_15 - vec2(((wx * 2.0) + 1.0), ((row * 6.0) + 3.0))));
                float flick = (0.6 + (0.4 * step(0.2, fract(((_e698 * 13.0) + (floor((time_1 * 0.5)) * 0.37))))));
                vec3 _e733 = emit;
                float _e739 = ms_line(d_15, 0.45, fp_2);
                emit = (_e733 + (((((vec3(0.55, 1.5, 0.6) * _e739) * flick) * boost) * on_1) * 0.6));
            }
        }
        if ((h.kind == 2)) {
            float cx = floor((q_15.x / 40.0));
            float lx = ((cx * 40.0) + 20.0);
            float _e760 = ms_half_w(lx);
            float d_16 = length((q_15 - vec2(lx, (sign(q_15.y) * (_e760 - 14.0)))));
            float blink = step(0.82, fract(((time_1 * 0.9) - (cx * 0.11))));
            vec3 rc = ((q_15.y > 0.0) ? vec3(0.08, 1.1, 0.18) : vec3(0.4, 2.6, 0.5));
            vec3 _e787 = emit;
            float _e794 = ms_line(d_16, 1.3, fp_2);
            emit = (_e787 + (((mix(rc, vec3(3.5, 4.0, 3.5), blink) * _e794) * (0.6 + (1.4 * blink))) * boost));
        }
    } else {
        if ((h.kind == 4)) {
            vec2 e_3 = (q_15 - vec2(70.0, 0.0));
            float re = length(e_3);
            float ae = atan(e_3.y, e_3.x);
            float ke = floor(((ae / 1.0471976) + 0.5));
            float de = length((e_3 - (vec2(cos((ke * 1.0471976)), sin((ke * 1.0471976))) * 30.0)));
            float ribs = smoothstep(0.2, 0.6, (abs((fract(((ae / 1.0471976) * 4.0)) - 0.5)) * 2.0));
            tone = (0.45 + (0.4 * ribs));
            rough = 0.5;
            vec3 hot_1 = mix(vec3(0.15, 1.8, 0.35), vec3(3.5, 5.0, 3.6), core);
            vec3 _e854 = emit;
            emit = (_e854 + (hot_1 * (((1.0 - smoothstep(5.0, (5.0 + fp_2), de)) * (((0.3 * on_1) + (7.0 * core)) + (6.0 * beam))) + (exp((-(de) / 6.0)) * ((0.2 * on_1) + (2.5 * core))))));
            vec3 _e883 = emit;
            emit = (_e883 + ((vec3(4.5, 6.0, 4.5) * (1.0 - smoothstep(9.0, (9.0 + fp_2), re))) * (((0.2 * on_1) + (10.0 * core)) + (10.0 * beam))));
            vec3 _e905 = emit;
            float _e909 = ms_line((re - 18.0), 0.6, fp_2);
            float _e913 = ms_line((re - 42.0), 0.8, fp_2);
            emit = (_e905 + ((green * (_e909 + _e913)) * glow_1));
        } else {
            if ((h.kind == 6)) {
                vec2 hq = (q_15 - vec2(-290.0, 0.0));
                float _e937 = ms_line((abs((fract(((hq.y / 16.0) + 0.5)) - 0.5)) * 16.0), 1.2, fp_2);
                float docked = max(((abs((fract((hq.x / 30.0)) - 0.5)) * 30.0) - 9.0), ((abs((fract((hq.y / 16.0)) - 0.5)) * 16.0) - 4.0));
                float _e965 = fh21_(floor((hq / vec2(30.0))));
                tone = (0.35 * (0.8 + (0.4 * _e965)));
                rough = 0.7;
                vec3 inner = ((vec3(0.8, 1.6, 0.9) * (0.25 + (1.2 * _e937))) * on_1);
                vec3 _e983 = emit;
                emit = (_e983 + (inner * ((docked < 0.0) ? 0.1 : 1.0)));
            } else {
                if ((h.kind == 3)) {
                    int k_12 = ((h.h > MS_TIER_B) ? ((h.h > MS_TIER_C) ? 2 : 1) : 0);
                    float _e1012 = ms_tier((q_15 + vec2(1.0, 0.0)), k_12);
                    float _e1017 = ms_tier((q_15 - vec2(1.0, 0.0)), k_12);
                    float _e1023 = ms_tier((q_15 + vec2(0.0, 1.0)), k_12);
                    float _e1028 = ms_tier((q_15 - vec2(0.0, 1.0)), k_12);
                    n2_ = vec2((_e1012 - _e1017), (_e1023 - _e1028));
                } else {
                    if ((h.kind == 5)) {
                        n2_ = (vec2(70.0, 0.0) - q_15);
                    } else {
                        vec2 hq_1 = (q_15 - vec2(-290.0, 0.0));
                        n2_ = (((abs(hq_1.x) - 90.0) > (abs(hq_1.y) - 100.0)) ? vec2(-(sign(hq_1.x)), 0.0) : vec2(0.0, -(sign(hq_1.y))));
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
                float u_19 = ((h.kind == 5) ? (atan(q_15.y, (q_15.x - MS_EM_X)) * MS_EYE_R) : dot(q_15, vec2(-(_e1076), _e1079)));
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
                emit = (_e1195 + (((green * _e1200) * glow_1) * ((h.kind == 3) ? 1.0 : 0.0)));
                if ((h.kind == 3)) {
                    float _e1217 = n2_.x;
                    local_31 = (_e1217 > 0.8);
                } else {
                    local_31 = false;
                }
                bool _e1221 = local_31;
                if (_e1221) {
                    local_32 = (q_15.x > 556.0);
                } else {
                    local_32 = false;
                }
                bool _e1228 = local_32;
                if (_e1228) {
                    float rib = (abs((fract((q_15.y / 14.0)) - 0.5)) * 14.0);
                    float _e1238 = tone;
                    tone = (_e1238 * mix(1.0, (0.5 + (0.6 * smoothstep(1.0, 3.0, rib))), clamp((2.0 - (fp_2 / 2.0)), 0.0, 1.0)));
                    vec3 _e1254 = emit;
                    float _e1260 = ms_line(abs((h.h - 75.0)), 1.2, fp_2);
                    emit = (_e1254 + (((green * _e1260) * (0.4 + glow_1)) * 1.5));
                }
                if ((h.kind == 3)) {
                    float _e1274 = n2_.x;
                    local_33 = (_e1274 < -0.8);
                } else {
                    local_33 = false;
                }
                bool _e1278 = local_33;
                if (_e1278) {
                    bool big = (h.h > MS_TIER_C);
                    float pitch = (big ? 90.0 : 50.0);
                    float r_10 = (big ? 34.0 : 14.0);
                    float zc = ((floor((q_15.y / pitch)) + 0.5) * pitch);
                    float vc = (big ? 103.0 : 14.0);
                    float d_17 = length(vec2((q_15.y - zc), (h.h - vc)));
                    if ((abs(zc) < (big ? 200.0 : 160.0))) {
                        local_34 = (d_17 < (r_10 * 1.3));
                    } else {
                        local_34 = false;
                    }
                    bool _e1314 = local_34;
                    if (_e1314) {
                        float _e1315 = tone;
                        tone = (_e1315 * mix(1.0, 0.25, step(d_17, r_10)));
                        float _e1323 = ms_line((d_17 - r_10), 1.5, fp_2);
                        float bell = ((_e1323 * 1.5) + ((1.0 - smoothstep((r_10 * 0.2), r_10, d_17)) * 1.2));
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
    vec3 r_11 = reflect(rd_5, n_4);
    float cosv = max(dot(-(rd_5), n_4), 0.0);
    float fres = (0.45 + (0.55 * pow((1.0 - cosv), 5.0)));
    vec3 _e1389 = ms_env(r_11, haze_1, sun_1, day_1);
    float _e1390 = luminance(haze_1);
    float _e1404 = rough;
    vec3 env = mix(_e1389, (((mix(haze_1, vec3(_e1390), 0.65) * 0.6) + (vec3(0.08, 0.085, 0.07) * day_1)) * 0.6), (_e1404 * 0.8));
    vec3 sun_c = ((vec3(2.5, 2.3, 2.0) * day_1) * step(0.0, sun_1.y));
    float _e1420 = rough;
    float _e1426 = rough;
    vec3 glint = ((((sun_c * pow(max(dot(r_11, sun_1), 0.0), mix(300.0, 20.0, _e1420))) * (1.0 - _e1426)) * max(dot(n_4, sun_1), 0.0)) * 4.0);
    float _e1440 = tone;
    vec3 metal = (vec3(0.42, 0.43, 0.44) * _e1440);
    c_11 = ((metal * ((env * fres) + glint)) + (((metal * 0.04) * (haze_1 + (vec3(0.1) * day_1))) * max(dot(n_4, sun_1), 0.0)));
    vec3 lf = (X - focus);
    vec3 _e1459 = c_11;
    vec3 _e1464 = ship_tint(vec3(0.4, 2.0, 0.6));
    c_11 = (_e1459 + (((((metal * _e1464) * ((core * 0.8) + (beam * 1.6))) * 4000.0) / vec3((dot(lf, lf) + 2500.0))) * 0.3));
    float hz = (1.0 - exp((-(h.t) / 3000.0)));
    vec3 _e1489 = c_11;
    vec3 _e1495 = emit;
    vec3 _e1496 = ship_tint(_e1495);
    return (mix(_e1489, (haze_1 * 0.6), (hz * 0.35)) + (_e1496 * exp((-(h.t) / 3000.0))));
}

vec2 ms_air(vec2 uv_3, vec3 cam_3, vec3 p0_, bool sky0_, float stir, float tr, float wake_1, MsFrame base_1, MsFrame f_6, float time_2, float seed_16, float k_6) {
    vec2 off = vec2(0.0);
    bool local_35 = false;
    bool local_36 = false;
    bool local_37 = false;
    bool local_38 = false;
    bool local_39 = false;
    bool local_40 = false;
    bool local_41 = false;
    bool local_42 = false;
    bool local_43 = false;
    if ((stir > 0.001)) {
        local_35 = !(sky0_);
    } else {
        local_35 = false;
    }
    bool _e21 = local_35;
    if (_e21) {
        local_36 = (abs(((p0_.y - CLOUD_Y) - 2.0)) < 6.0);
    } else {
        local_36 = false;
    }
    bool _e33 = local_36;
    if (_e33) {
        float _e41 = gnoise2_(((p0_.xz * 0.012) + vec2((time_2 * 0.35), seed_16)));
        float _e50 = gnoise2_(((p0_.xz * 0.012) + vec2(7.0, (time_2 * 0.3))));
        vec2 sw = (vec2(_e41, _e50) - vec2(0.5));
        vec2 _e55 = off;
        off = (_e55 + ((((sw * 0.014) * stir) * stir) * k_6));
    }
    vec3 _e63 = world_offset(uv_3, RAY_DEPTH);
    vec3 rd0_ = normalize(_e63);
    if ((tr > 0.0)) {
        local_37 = (tr < 6.0);
    } else {
        local_37 = false;
    }
    bool _e72 = local_37;
    if (_e72) {
        local_38 = (abs(rd0_.y) > 0.001);
    } else {
        local_38 = false;
    }
    bool _e80 = local_38;
    if (_e80) {
        float t_cl = ((CLOUD_Y - cam_3.y) / rd0_.y);
        if ((t_cl > 0.0)) {
            if (!(sky0_)) {
                local_40 = (t_cl < (length((p0_ - cam_3)) + 40.0));
            } else {
                local_40 = true;
            }
            bool _e99 = local_40;
            local_39 = _e99;
        } else {
            local_39 = false;
        }
        bool _e101 = local_39;
        if (_e101) {
            float rr = length(((cam_3.xz + (rd0_.xz * t_cl)) - base_1.c));
            float ripple = (exp(-(pow(((rr - (tr * 650.0)) / (40.0 + (tr * 15.0))), 2.0))) * exp((-(tr) * 0.8)));
            vec3 _e133 = project_rel((vec3(base_1.c.x, CLOUD_Y, base_1.c.y) - cam_3));
            vec2 rdir = (uv_3 - _e133.xy);
            vec2 _e136 = off;
            off = (_e136 + (((((rdir / vec2(max(length(rdir), 0.0001))) * ripple) * 0.012) * _e133.z) * k_6));
        }
    }
    if ((wake_1 > 0.0)) {
        local_41 = (wake_1 < 1.2);
    } else {
        local_41 = false;
    }
    bool _e156 = local_41;
    if (_e156) {
        local_42 = (rd0_.y > 0.001);
    } else {
        local_42 = false;
    }
    bool _e163 = local_42;
    if (_e163) {
        local_43 = (cam_3.y < base_1.y0_);
    } else {
        local_43 = false;
    }
    bool _e170 = local_43;
    if (_e170) {
        vec2 _e182 = ms_local(f_6, (cam_3.xz + (rd0_.xz * (((base_1.y0_ + 20.0) - cam_3.y) / rd0_.y))));
        float _e184 = ms_tier(_e182, 2);
        float m_5 = (exp(-(pow((_e184 / 18.0), 2.0))) * (1.0 - (wake_1 / 1.2)));
        if ((m_5 > 0.01)) {
            float _e207 = gnoise2_(((uv_3 * vec2(120.0, 60.0)) + vec2(0.0, (time_2 * 6.0))));
            float _e217 = gnoise2_(((uv_3 * vec2(120.0, 60.0)) + vec2(17.0, (time_2 * 5.0))));
            vec2 hw = (vec2(_e207, _e217) - vec2(0.5));
            vec2 _e222 = off;
            off = (_e222 + (((hw * 0.006) * m_5) * k_6));
        }
    }
    vec2 _e228 = off;
    return _e228;
}

vec3 ms_arrival_fx(MsFrame f_7, MsFrame base_2, vec3 cam_4, vec3 rd_6, bool sky_1, float scene_len_1, float ta, int mode_1, int style_2, bool blurring, bool present, float k_7) {
    vec3 add = vec3(0.0);
    bool local_44 = false;
    bool local_45 = false;
    bool local_46 = false;
    bool local_47 = false;
    bool local_48 = false;
    bool local_49 = false;
    bool local_50 = false;
    bool local_51 = false;
    int j = 0;
    bool local_52 = false;
    if ((style_2 == 1)) {
        local_44 = (ta >= 0.0);
    } else {
        local_44 = false;
    }
    bool _e22 = local_44;
    if (_e22) {
        local_45 = (ta < MS_IN);
    } else {
        local_45 = false;
    }
    bool _e28 = local_45;
    if (_e28) {
        vec2 _e31 = ms_world(f_7, vec2(0.0));
        vec2 _e40 = ms_world(f_7, vec2(0.0));
        vec3 pc_2 = (vec3(_e31.x, (f_7.y0_ + (40.0 * f_7.sy)), _e40.y) - cam_4);
        float tp = dot(pc_2, rd_6);
        if ((tp > 0.0)) {
            if (!(sky_1)) {
                local_47 = (tp < scene_len_1);
            } else {
                local_47 = true;
            }
            bool _e54 = local_47;
            local_46 = _e54;
        } else {
            local_46 = false;
        }
        bool _e56 = local_46;
        if (_e56) {
            float ang_4 = (length((pc_2 - (rd_6 * tp))) / tp);
            float born = pow((1.0 - f_7.sx), 1.5);
            vec3 _e66 = add;
            add = (_e66 + ((((vec3(4.0, 6.0, 4.0) * exp(-(pow((ang_4 / 0.0025), 2.0)))) + ((vec3(0.4, 1.6, 0.5) * exp((-(ang_4) / 0.012))) * 0.5)) * born) * k_7));
        }
    }
    if ((style_2 == 2)) {
        local_48 = (ta > -0.3);
    } else {
        local_48 = false;
    }
    bool _e100 = local_48;
    if (_e100) {
        local_49 = (ta < 0.06);
    } else {
        local_49 = false;
    }
    bool _e106 = local_49;
    if (_e106) {
        bool up_3 = (mode_1 == 4);
        float head = (MS_HL - (30000.0 * pow(clamp((-(ta) / 0.3), 0.0, 1.0), 2.0)));
        vec2 _e123 = ms_world(base_2, vec2((up_3 ? 0.0 : head), 0.0));
        vec2 _e130 = ms_world(base_2, vec2((up_3 ? 0.0 : (head - 30000.0)), 0.0));
        float ya = (base_2.y0_ + (up_3 ? ((MS_TOP - head) + MS_HL) : 30.0));
        vec3 _e151 = ray_seg(rd_6, (vec3(_e123.x, ya, _e123.y) - cam_4), (vec3(_e130.x, (ya + (up_3 ? 30000.0 : 0.0)), _e130.y) - cam_4));
        float w_7 = max(3.0, (_e151.y * 0.0015));
        if (!(sky_1)) {
            local_50 = (_e151.y > scene_len_1);
        } else {
            local_50 = false;
        }
        bool _e163 = local_50;
        float vis_1 = (_e163 ? 0.0 : 1.0);
        vec3 _e167 = add;
        add = (_e167 + (((((((vec3(1.2, 2.6, 1.5) * exp(-(pow((_e151.x / w_7), 2.0)))) * (3.0 / w_7)) * 2.0) * smoothstep(-0.3, -0.1, ta)) * (1.0 - smoothstep(0.0, 0.06, ta))) * vis_1) * k_7));
    }
    if (blurring) {
        local_51 = present;
    } else {
        local_51 = false;
    }
    bool _e200 = local_51;
    if (_e200) {
        bool loop_init_5 = true;
        while(true) {
            if (!loop_init_5) {
                int _e280 = j;
                j = (_e280 + 1);
            }
            loop_init_5 = false;
            int _e203 = j;
            if ((_e203 < 5)) {
            } else {
                break;
            }
            {
                int _e206 = j;
                float zc_1 = ((float(_e206) - 2.0) * 90.0);
                vec2 _e214 = ms_world(f_7, vec2(-560.0, zc_1));
                vec2 _e217 = ms_world(f_7, vec2(-820.0, zc_1));
                vec3 _e236 = ray_seg(rd_6, (vec3(_e214.x, (f_7.y0_ + (103.0 * f_7.sy)), _e214.y) - cam_4), (vec3(_e217.x, (f_7.y0_ + (103.0 * f_7.sy)), _e217.y) - cam_4));
                float w_8 = max((16.0 + (30.0 * _e236.z)), (_e236.y * 0.0015));
                if (!(sky_1)) {
                    local_52 = (_e236.y > scene_len_1);
                } else {
                    local_52 = false;
                }
                bool _e252 = local_52;
                float vis_2 = (_e252 ? 0.0 : 1.0);
                vec3 _e256 = add;
                add = (_e256 + ((((((vec3(0.4, 2.2, 0.6) * exp(-(pow((_e236.x / w_8), 2.0)))) * (16.0 / w_8)) * (1.0 - _e236.z)) * 0.8) * vis_2) * k_7));
            }
        }
    }
    vec3 _e283 = add;
    vec3 _e284 = ship_tint(_e283);
    return _e284;
}

vec3 ms_charge_fx(MsFrame f_8, vec3 cam_5, vec3 rdb, vec3 focus_1, bool sky_2, float scene_len_2, float ship_t, float conv_env, float core_env, bool present_1, float time_3, float k_8) {
    vec3 add_1 = vec3(0.0);
    bool local_53 = false;
    int i_10 = 0;
    bool local_54 = false;
    bool local_55 = false;
    bool local_56 = false;
    bool local_57 = false;
    if ((conv_env > 0.001)) {
        local_53 = present_1;
    } else {
        local_53 = false;
    }
    bool _e20 = local_53;
    if (_e20) {
        bool loop_init_6 = true;
        while(true) {
            if (!loop_init_6) {
                int _e124 = i_10;
                i_10 = (_e124 + 1);
            }
            loop_init_6 = false;
            int _e24 = i_10;
            if ((_e24 < 6)) {
            } else {
                break;
            }
            {
                int _e27 = i_10;
                float a_21 = ((float(_e27) * TAU) / 6.0);
                vec2 _e40 = ms_world(f_8, vec2((MS_EM_X + (cos(a_21) * 30.0)), (sin(a_21) * 30.0)));
                vec3 e3_ = (vec3(_e40.x, (f_8.y0_ + MS_EYE_UP), _e40.y) - cam_5);
                vec3 _e48 = ray_seg(rdb, e3_, focus_1);
                float w_9 = max((1.2 + (0.8 * core_env)), (_e48.y * 0.0012));
                if (!(sky_2)) {
                    local_54 = (_e48.y > scene_len_2);
                } else {
                    local_54 = false;
                }
                bool _e63 = local_54;
                if (!(_e63)) {
                    local_55 = (_e48.y > (ship_t + 1.0));
                } else {
                    local_55 = true;
                }
                bool _e72 = local_55;
                float vis_3 = (_e72 ? 0.0 : 1.0);
                int _e78 = i_10;
                float flick_1 = (0.8 + (0.2 * sin(((time_3 * 40.0) + (float(_e78) * 2.1)))));
                vec3 _e88 = add_1;
                add_1 = (_e88 + (((((((vec3(2.6, 4.8, 2.6) * exp(-(pow((_e48.x / (w_9 * 0.5)), 2.0)))) + (vec3(0.15, 1.4, 0.3) * exp(-(pow((_e48.x / (w_9 * 2.5)), 2.0))))) * (1.2 / w_9)) * conv_env) * flick_1) * vis_3) * k_8));
            }
        }
    }
    if ((core_env > 0.001)) {
        float tc_2 = dot(focus_1, rdb);
        if ((tc_2 > 0.0)) {
            float dc = length((focus_1 - (rdb * tc_2)));
            float R_1 = ((1.0 + (3.5 * core_env)) * (1.0 + (0.08 * sin((time_3 * 33.0)))));
            if (!(sky_2)) {
                local_56 = (tc_2 > scene_len_2);
            } else {
                local_56 = false;
            }
            bool _e152 = local_56;
            if (!(_e152)) {
                local_57 = (tc_2 > (ship_t + 2.0));
            } else {
                local_57 = true;
            }
            bool _e160 = local_57;
            float vis_4 = (_e160 ? 0.2 : 1.0);
            vec3 _e164 = add_1;
            add_1 = (_e164 + ((((((vec3(5.0, 6.0, 5.0) * exp(-(pow((dc / R_1), 2.0)))) + ((vec3(0.6, 2.6, 0.8) * exp((-(dc) / R_1))) * 0.9)) + ((vec3(0.12, 0.7, 0.2) * exp((-(dc) / (R_1 * 5.0)))) * 0.4)) * core_env) * vis_4) * k_8));
        }
    }
    vec3 _e203 = add_1;
    vec3 _e204 = ship_tint(_e203);
    return _e204;
}

float pl_w(uint i_11) {
    uint _e1 = md_len();
    if ((i_11 >= _e1)) {
        return 0.0;
    }
    uint _e4 = md_at(i_11);
    return uintBitsToFloat(_e4);
}

uint pl_u(uint i_12) {
    uint _e1 = md_len();
    if ((i_12 >= _e1)) {
        return 0u;
    }
    uint _e4 = md_at(i_12);
    return _e4;
}

int pl_n() {
    float _e1 = pl_w(0u);
    return int((_e1 + 0.5));
}

vec3 pl_sample(int i_13) {
    int _e3 = pl_n();
    uint b_12 = (PL_P + (3u * uint(min(max(i_13, 0), (_e3 - 1)))));
    float _e11 = pl_w(b_12);
    float _e14 = pl_w((b_12 + 1u));
    float _e17 = pl_w((b_12 + 2u));
    return vec3(_e11, _e14, _e17);
}

vec3 pl_head(float t_4) {
    float _e2 = pl_w(1u);
    float _e5 = pl_w(2u);
    float u_20 = ((t_4 - _e2) / max(_e5, 0.001));
    int i_35 = int(floor(u_20));
    float f_18 = (u_20 - floor(u_20));
    vec3 _e15 = pl_sample((i_35 - 1));
    vec3 _e16 = pl_sample(i_35);
    vec3 _e19 = pl_sample((i_35 + 1));
    vec3 _e22 = pl_sample((i_35 + 2));
    float f2_ = (f_18 * f_18);
    float f3_ = (f2_ * f_18);
    return (0.5 * ((((2.0 * _e16) + ((_e19 - _e15) * f_18)) + (((((2.0 * _e15) - (5.0 * _e16)) + (4.0 * _e19)) - _e22) * f2_)) + (((((3.0 * _e16) - _e15) - (3.0 * _e19)) + _e22) * f3_)));
}

vec3 pl_wind() {
    float _e1 = pl_w(3u);
    float _e3 = pl_w(4u);
    return vec3(_e1, 0.0, _e3);
}

vec3 pl_trail_drift(int i_14, float age, uint seed_17) {
    float fi_10 = float(i_14);
    vec3 wob = vec3(sin(((fi_10 * 0.21) + float((seed_17 % 61u)))), (0.4 * sin(((fi_10 * 0.13) + 2.0))), cos(((fi_10 * 0.17) + float((seed_17 % 37u)))));
    vec3 _e26 = pl_wind();
    return (((_e26 * age) + vec3(0.0, (0.35 * age), 0.0)) + (wob * (0.35 * age)));
}

vec3 pl_trail_at(int i_15, float te, float t_5, uint seed_18) {
    vec3 _e4 = pl_sample(i_15);
    vec3 _e8 = pl_trail_drift(i_15, max((t_5 - te), 0.0), seed_18);
    return (_e4 + _e8);
}

vec3 pl_frag(vec3 p0_1, vec3 v0_1, float k_9, float s_3) {
    float e_4 = ((1.0 - exp((-(k_9) * s_3))) / k_9);
    return ((p0_1 + (v0_1 * e_4)) - vec3(0.0, ((20.0 * (s_3 - e_4)) / k_9), 0.0));
}

vec3 pl_ray_seg(vec3 rd_7, vec3 a_8, vec3 b_6, float lo, float hi) {
    float s_4 = 0.0;
    vec3 ab_4 = (b_6 - a_8);
    float l2_2 = max(dot(ab_4, ab_4), 1e-6);
    float rab_1 = dot(rd_7, ab_4);
    float den_2 = (l2_2 - (rab_1 * rab_1));
    s_4 = clamp(((den_2 > 1e-6) ? (((rab_1 * dot(rd_7, a_8)) - dot(a_8, ab_4)) / den_2) : 0.0), lo, hi);
    float _e23 = s_4;
    float t_9 = max(dot(rd_7, (a_8 + (ab_4 * _e23))), 0.0);
    s_4 = clamp((dot(((rd_7 * t_9) - a_8), ab_4) / l2_2), lo, hi);
    float _e35 = s_4;
    float _e40 = s_4;
    return vec3(length(((rd_7 * t_9) - (a_8 + (ab_4 * _e35)))), t_9, _e40);
}

vec3 pl_trail_pt(int j_1, int last, float thead, float t_6, uint seed_19) {
    if ((j_1 > last)) {
        vec3 _e6 = pl_head(thead);
        return _e6;
    }
    float _e10 = pl_w(1u);
    float _e12 = pl_w(2u);
    vec3 _e18 = pl_trail_at(max(j_1, 0), (_e10 + (_e12 * float(max(j_1, 0)))), t_6, seed_19);
    return _e18;
}

vec2 pl_half(vec3 rd_8, vec3 p_20, vec3 n_2) {
    float r_12 = dot(rd_8, n_2);
    float c_25 = dot(p_20, n_2);
    if ((abs(r_12) < 1e-6)) {
        return ((c_25 <= 0.0) ? vec2(-1000000000.0, 1000000000.0) : vec2(1.0, 0.0));
    }
    float tc_3 = (c_25 / r_12);
    return ((r_12 > 0.0) ? vec2(tc_3, 1000000000.0) : vec2(-1000000000.0, tc_3));
}

float pl_erf(float x_8) {
    float y = clamp(x_8, -4.0, 4.0);
    return tanh(((1.1284 * y) + (((0.1009 * y) * y) * y)));
}

float smin(float a_9, float b_7, float k_10) {
    float h_6 = clamp((0.5 + ((0.5 * (b_7 - a_9)) / k_10)), 0.0, 1.0);
    return (mix(b_7, a_9, h_6) - ((k_10 * h_6) * (1.0 - h_6)));
}

vec4 pl_puff(int i_16, float a_10, vec3 C, float grow) {
    uint b_13 = (PL_PF + (PL_PW * uint(i_16)));
    float _e9 = pl_w(b_13);
    float s_14 = (a_10 - _e9);
    if ((s_14 <= 0.0)) {
        return vec4(C, 0.0);
    }
    float _e16 = pl_w(5u);
    float H_3 = (_e16 * (1.0 + (0.006 * a_10)));
    float _e24 = pl_w((b_13 + 1u));
    float rise = (1.0 - exp((-(s_14) / _e24)));
    float _e32 = pl_w((b_13 + 3u));
    float r_13 = ((_e32 * (0.22 + (0.78 * (1.0 - exp((-(s_14) / (0.45 * _e24))))))) * grow);
    float _e48 = pl_w((b_13 + 2u));
    float h_7 = (5.0 + ((_e48 * H_3) * rise));
    float foot = clamp(((h_7 - 5.0) / (0.45 * H_3)), 0.0, 1.0);
    float spread_1 = ((0.35 + (0.65 * rise)) * (0.15 + ((0.85 * foot) * foot)));
    float _e71 = pl_w((b_13 + 4u));
    float _e75 = pl_w((b_13 + 5u));
    vec3 _e79 = pl_wind();
    vec3 c_26 = ((C + vec3((_e71 * spread_1), h_7, (_e75 * spread_1))) + (_e79 * (a_10 * pow(clamp((h_7 / H_3), 0.0, 1.0), 1.6))));
    return vec4(c_26, r_13);
}

PlCol pl_column(float a_11, vec3 C_1) {
    PlCol o_1 = PlCol(0, vec3(0.0), vec3(0.0), 0.0, 0.0, vec3(0.0), vec4[18](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4(0.0), vec4(0.0), vec4(0.0));
    int i_17 = 0;
    vec4 q_8 = vec4(0.0);
    bool local_58 = false;
    o_1.n = 0;
    o_1.lo = C_1;
    o_1.hi = C_1;
    o_1.a = a_11;
    o_1.C = C_1;
    o_1.s1_ = vec4(C_1, 0.0);
    o_1.grow = ((1.0 + (0.012 * max((a_11 - 6.0), 0.0))) + (0.006 * max((a_11 - PL_SOFT0_), 0.0)));
    bool loop_init_7 = true;
    while(true) {
        if (!loop_init_7) {
            int _e121 = i_17;
            i_17 = (_e121 + 1);
        }
        loop_init_7 = false;
        int _e30 = i_17;
        if ((_e30 < PL_NPUFF)) {
        } else {
            break;
        }
        {
            int _e33 = i_17;
            float _e35 = o_1.grow;
            vec4 _e36 = pl_puff(_e33, a_11, C_1, _e35);
            q_8 = _e36;
            float _e40 = q_8.w;
            int _e41 = i_17;
            q_8.w = (_e40 * ((_e41 < 5) ? 0.8 : 1.0));
            float _e50 = q_8.y;
            float _e52 = q_8.y;
            q_8.y = (_e50 - (12.0 * (1.0 - smoothstep(10.0, 70.0, (_e52 - C_1.y)))));
            int _e64 = i_17;
            vec4 _e66 = q_8;
            float _e71 = q_8.z;
            float _e75 = q_8.w;
            o_1.q[_e64] = vec4((_e66.xy - C_1.xy), (_e71 - C_1.z), _e75);
            float _e78 = q_8.w;
            if ((_e78 <= 0.0)) {
                continue;
            }
            vec3 _e83 = o_1.lo;
            vec4 _e84 = q_8;
            float _e87 = q_8.w;
            o_1.lo = min(_e83, (_e84.xyz - vec3(_e87)));
            vec3 _e93 = o_1.hi;
            vec4 _e94 = q_8;
            float _e97 = q_8.w;
            o_1.hi = max(_e93, (_e94.xyz + vec3(_e97)));
            int _e103 = o_1.n;
            o_1.n = (_e103 + 1);
            int _e106 = i_17;
            if ((_e106 < 5)) {
                float _e112 = q_8.y;
                float _e115 = o_1.s1_.y;
                local_58 = (_e112 >= _e115);
            } else {
                local_58 = false;
            }
            bool _e118 = local_58;
            if (_e118) {
                vec4 _e120 = q_8;
                o_1.s1_ = _e120;
            }
        }
    }
    float _e132 = o_1.s1_.w;
    o_1.s0_ = vec4((C_1 + vec3(0.0, -12.0, 0.0)), min((_e132 * 1.25), (8.0 + (30.0 * clamp((a_11 / 1.2), 0.0, 1.0)))));
    float _e148 = o_1.s1_.w;
    o_1.s1_.w = (_e148 * 0.75);
    o_1.sk = vec4((C_1 + vec3(0.0, -5.0, 0.0)), ((10.0 + (30.0 * clamp((a_11 / 1.5), 0.0, 1.0))) * (1.0 + (0.01 * max((a_11 - 2.0), 0.0)))));
    int _e175 = o_1.n;
    if ((_e175 > 0)) {
        vec3 _e180 = o_1.lo;
        vec4 _e182 = o_1.s0_;
        float _e186 = o_1.s0_.w;
        vec4 _e190 = o_1.sk;
        float _e194 = o_1.sk.w;
        float _e197 = o_1.sk.w;
        o_1.lo = min(_e180, min((_e182.xyz - vec3(_e186)), (_e190.xyz - vec3(_e194, 13.0, _e197))));
        vec3 _e205 = o_1.hi;
        vec4 _e207 = o_1.sk;
        float _e211 = o_1.sk.w;
        float _e214 = o_1.sk.w;
        o_1.hi = max(_e205, (_e207.xyz + vec3(_e211, 13.0, _e214)));
    }
    vec3 _e221 = o_1.lo;
    o_1.lo = (_e221 - vec3(34.0));
    vec3 _e227 = o_1.hi;
    o_1.hi = (_e227 + vec3(34.0));
    PlCol _e231 = o_1;
    return _e231;
}

float pl_col_base(inout PlCol col, vec3 p_21) {
    float d_5 = 1000000.0;
    int i_18 = 0;
    vec3 _e5 = col.C;
    vec3 pc_3 = (p_21 - _e5);
    bool loop_init_8 = true;
    while(true) {
        if (!loop_init_8) {
            int _e52 = i_18;
            i_18 = (_e52 + 1);
        }
        loop_init_8 = false;
        int _e9 = i_18;
        if ((_e9 < PL_NPUFF)) {
        } else {
            break;
        }
        {
            int _e13 = i_18;
            vec4 q_16 = col.q[_e13];
            if ((q_16.w > 0.0)) {
                float low_2 = (1.0 - smoothstep(0.0, 60.0, q_16.y));
                vec3 e_5 = ((pc_3 - q_16.xyz) * vec3((1.0 - (0.25 * low_2)), (1.0 + (0.6 * low_2)), (1.0 - (0.25 * low_2))));
                float _e41 = d_5;
                float _e51 = smin(_e41, ((length(e_5) - q_16.w) / (1.0 + (0.6 * low_2))), 18.0);
                d_5 = _e51;
            }
        }
    }
    vec4 sk_1 = col.sk;
    int _e58 = col.n;
    if ((_e58 > 0)) {
        vec3 r_14 = vec3(sk_1.w, 13.0, sk_1.w);
        vec3 e_6 = ((p_21 - sk_1.xyz) / r_14);
        float k0_ = length(e_6);
        float _e69 = d_5;
        float _e79 = smin(_e69, ((k0_ * (k0_ - 1.0)) / max(length((e_6 / r_14)), 0.0001)), 16.0);
        d_5 = _e79;
    }
    vec4 s0_1 = col.s0_;
    vec4 s1_1 = col.s1_;
    if ((s1_1.w > 0.0)) {
        vec3 ab_5 = (s1_1.xyz - s0_1.xyz);
        float u_21 = clamp((dot((p_21 - s0_1.xyz), ab_5) / max(dot(ab_5, ab_5), 1.0)), 0.0, 1.0);
        float _e98 = d_5;
        float _e109 = smin(_e98, (length(((p_21 - s0_1.xyz) - (ab_5 * u_21))) - mix(s0_1.w, s1_1.w, u_21)), 14.0);
        d_5 = _e109;
    }
    float _e110 = d_5;
    return _e110;
}

float pl_dome(vec3 p_22) {
    float hmax = 0.0;
    uint c_12 = 0u;
    vec3 b_14 = floor((p_22 - vec3(0.5)));
    bool loop_init_9 = true;
    while(true) {
        if (!loop_init_9) {
            uint _e83 = c_12;
            c_12 = (_e83 + 1u);
        }
        loop_init_9 = false;
        uint _e9 = c_12;
        if ((_e9 < 8u)) {
        } else {
            break;
        }
        {
            uint _e12 = c_12;
            uint _e16 = c_12;
            uint _e22 = c_12;
            vec3 o_5 = vec3(float((_e12 & 1u)), float(((_e16 >> 1u) & 1u)), float((_e22 >> 2u)));
            vec3 cell_1 = (b_14 + o_5);
            uvec3 q_17 = uvec3(ivec3(cell_1));
            uint _e35 = pcg((q_17.z + 81u));
            uint _e37 = pcg((q_17.y ^ _e35));
            uint _e39 = pcg((q_17.x ^ _e37));
            vec3 jit = ((vec3(float((_e39 & 1023u)), float(((_e39 >> 10u) & 1023u)), float(((_e39 >> 20u) & 1023u))) * 0.00068426196) + vec3(0.15));
            uint _e59 = pcg(_e39);
            float sz = (0.7 + ((0.55 * float((_e59 & 1023u))) / 1023.0));
            vec3 e_7 = ((cell_1 + jit) - p_22);
            float _e71 = hmax;
            hmax = max(_e71, (sz * sqrt(clamp((1.0 - ((dot(e_7, e_7) * 1.7) / (sz * sz))), 0.0, 1.0))));
        }
    }
    float _e86 = hmax;
    return _e86;
}

vec3 pl_rot(int k_11, vec3 p_23) {
    if ((k_11 == 0)) {
        return (mat3x3(vec3(-0.0014, 0.9977, -0.0674), vec3(-0.2224, -0.066, -0.9727), vec3(-0.975, 0.0136, 0.222)) * p_23);
    }
    if ((k_11 == 1)) {
        return (mat3x3(vec3(-0.6616, 0.1124, 0.7414), vec3(-0.4826, -0.8205, -0.3063), vec3(0.5739, -0.5605, 0.5971)) * p_23);
    }
    return (mat3x3(vec3(-0.9891, -0.1223, 0.0816), vec3(0.0968, -0.9594, -0.2651), vec3(0.1107, -0.2543, 0.9608)) * p_23);
}

vec4 pl_col_sdf(inout PlCol col_1, vec3 p_24, float d0_, bool fine) {
    float d_6 = 0.0;
    float fray = 0.5;
    bool local_59 = false;
    bool local_60 = false;
    float a_22 = col_1.a;
    vec3 _e7 = col_1.C;
    float _e10 = col_1.grow;
    vec3 _e28 = pl_wind();
    vec3 q_18 = ((((p_24 - _e7) * vec3(1.0, (1.0 / _e10), 1.0)) - vec3(0.0, ((2.2 * a_22) + (10.0 * min(a_22, 1.5))), 0.0)) - (_e28 * (a_22 * 0.4)));
    vec3 _e36 = pl_rot(1, (q_18 * 0.018181818));
    float _e37 = gnoise3_(_e36);
    vec3 _e47 = pl_rot(2, ((q_18 * 0.04347826) + vec3(9.2, (-0.12 * a_22), 4.4)));
    float _e48 = gnoise3_(_e47);
    vec3 _e63 = pl_rot(0, (((q_18 * 0.027777778) + vec3(3.1, 0.0, 7.7)) + (0.3 * vec3((_e48 - 0.5)))));
    float _e64 = pl_dome(_e63);
    float _e68 = col_1.C.y;
    float hy = (p_24.y - _e68);
    float lump = (0.7 + (0.3 * smoothstep(15.0, 110.0, hy)));
    float soft = smoothstep(PL_SOFT0_, PL_SOFT1_, a_22);
    float crisp = (1.0 - (0.8 * soft));
    vec3 _e93 = pl_rot(1, ((q_18 * 0.071428575) + vec3(0.0, (-0.3 * a_22), 1.3)));
    float _e94 = pl_dome(_e93);
    float up_4 = smoothstep(25.0, 130.0, hy);
    d_6 = (d0_ - (((((((26.0 * (_e64 - 0.45)) * crisp) * (0.3 + (0.7 * up_4))) + (((6.0 + (6.0 * (1.0 - up_4))) * (_e94 - 0.45)) * (1.0 - (0.7 * soft)))) + ((18.0 + (8.0 * soft)) * (_e37 - 0.5))) + (8.0 * (_e48 - 0.5))) * lump));
    float ew = smoothstep(0.6, 0.82, _e48);
    float edge_2 = (mix(0.8, 3.5, ew) + (6.0 * (1.0 - smoothstep(0.0, 60.0, hy))));
    if (fine) {
        float _e157 = d_6;
        local_59 = (_e157 < 12.0);
    } else {
        local_59 = false;
    }
    bool _e161 = local_59;
    if (_e161) {
        local_60 = (soft < 0.99);
    } else {
        local_60 = false;
    }
    bool _e167 = local_60;
    if (_e167) {
        vec3 _e177 = pl_rot(2, ((q_18 * 0.18181819) + vec3(1.7, (-0.5 * a_22), -2.1)));
        float _e178 = pl_dome(_e177);
        float _e179 = d_6;
        d_6 = (_e179 - (((2.4 * (_e178 - 0.45)) * (1.0 - soft)) * lump));
        vec3 _e192 = pl_rot(0, (q_18 * 0.5555556));
        float _e199 = gnoise3_((_e192 + vec3(5.0, 1.0, (-0.8 * a_22))));
        fray = _e199;
        float _e200 = d_6;
        float _e201 = fray;
        d_6 = (_e200 - (((2.4 * (_e201 - 0.5)) * (1.0 - soft)) * (0.25 + (0.75 * ew))));
    }
    float _e215 = d_6;
    float _e221 = fray;
    return vec4(_e215, (_e64 * (0.45 + (0.55 * _e94))), edge_2, _e221);
}

vec2 pl_box(vec3 rd_9, vec3 lo_1, vec3 hi_1) {
    vec3 inv_1 = (vec3(1.0) / mix(rd_9, vec3(1e-6), lessThan(abs(rd_9), vec3(1e-6))));
    vec3 ta_3 = (lo_1 * inv_1);
    vec3 tb_1 = (hi_1 * inv_1);
    vec3 tmin = min(ta_3, tb_1);
    vec3 tmax = max(ta_3, tb_1);
    return vec2(max(max(tmin.x, tmin.y), max(tmin.z, 0.0)), min(min(tmax.x, tmax.y), tmax.z));
}

float pl_shadow(vec3 o_2, vec3 L_1, float a_12, vec3 C_2, float j_2) {
    PlCol cs = PlCol(0, vec3(0.0), vec3(0.0), 0.0, 0.0, vec3(0.0), vec4[18](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4(0.0), vec4(0.0), vec4(0.0));
    float tau_1 = 0.0;
    int i_19 = 0;
    float cgrow = ((1.0 + (0.012 * max((a_12 - 6.0), 0.0))) + (0.006 * max((a_12 - PL_SOFT0_), 0.0)));
    float _e21 = pl_w(5u);
    vec3 _e36 = pl_wind();
    vec3 ctop = ((C_2 + vec3(0.0, (5.0 + (((1.08 * _e21) * (1.0 + (0.006 * a_12))) * cgrow)), 0.0)) + (_e36 * a_12));
    vec3 _e48 = pl_ray_seg(L_1, ((C_2 - vec3(0.0, 30.0, 0.0)) - o_2), (ctop - o_2), 0.0, 1.0);
    if ((_e48.x > ((130.0 * cgrow) + 40.0))) {
        return 1.0;
    }
    PlCol _e56 = pl_column(a_12, C_2);
    cs = _e56;
    int _e59 = cs.n;
    if ((_e59 == 0)) {
        return 1.0;
    }
    vec3 _e64 = cs.lo;
    vec3 _e67 = cs.hi;
    vec2 _e69 = pl_box(L_1, (_e64 - o_2), (_e67 - o_2));
    if ((_e69.y <= _e69.x)) {
        return 1.0;
    }
    float dt_2 = ((_e69.y - _e69.x) / float(10));
    bool loop_init_10 = true;
    while(true) {
        if (!loop_init_10) {
            int _e102 = i_19;
            i_19 = (_e102 + 1);
        }
        loop_init_10 = false;
        int _e84 = i_19;
        if ((_e84 < 10)) {
        } else {
            break;
        }
        {
            float _e86 = tau_1;
            int _e88 = i_19;
            float _e95 = pl_col_base(cs, (o_2 + (L_1 * (_e69.x + ((float(_e88) + j_2) * dt_2)))));
            tau_1 = (_e86 + clamp((0.35 - (_e95 / 30.0)), 0.0, 1.0));
        }
    }
    float thin = (1.0 - (0.85 * smoothstep(PL_SOFT0_, 44.0, a_12)));
    float _e112 = tau_1;
    return exp(((((-(_e112) * dt_2) * 0.03) * thin) * smoothstep(0.3, 1.5, a_12)));
}

float pl_gref(float r_5, vec3 me, vec3 C_3, float dme) {
    return mix(0.0, (me.y - C_3.y), smoothstep(0.0, max(dme, 1.0), r_5));
}

vec2 pl_land(vec2 q_9, float gref) {
    vec4 hv = vec4(0.0);
    vec4 sv = vec4(0.0);
    uint j_3 = 0u;
    float _e3 = pl_w(PL_HF);
    if ((_e3 < 2.0)) {
        return vec2(gref, 0.0);
    }
    uint n_5 = uint((_e3 + 0.5));
    uint _e11 = md_len();
    if ((_e11 < (1032u + (n_5 * n_5)))) {
        return vec2(gref, 0.0);
    }
    float _e19 = pl_w(1025u);
    float step_ = ((2.0 * _e19) / (_e3 - 1.0));
    vec2 fc_1 = clamp(((q_9 + vec2(_e19)) / vec2(step_)), vec2(0.0), vec2((_e3 - 1.001)));
    uvec2 i0_ = uvec2(floor(fc_1));
    vec2 t_10 = (fc_1 - floor(fc_1));
    bool loop_init_11 = true;
    while(true) {
        if (!loop_init_11) {
            uint _e83 = j_3;
            j_3 = (_e83 + 1u);
        }
        loop_init_11 = false;
        uint _e47 = j_3;
        if ((_e47 < 4u)) {
        } else {
            break;
        }
        {
            uint _e52 = j_3;
            uint _e60 = j_3;
            uint _e64 = md_at((((1032u + ((i0_.y + (_e52 >> 1u)) * n_5)) + i0_.x) + (_e60 & 1u)));
            uint _e65 = j_3;
            hv[_e65] = ((float((_e64 & 65535u)) / 8.0) - 512.0);
            uint _e74 = j_3;
            sv[_e74] = (float(((_e64 >> 16u) & 255u)) / 255.0);
        }
    }
    float _e87 = hv.x;
    float _e89 = hv.y;
    float _e93 = hv.z;
    float _e95 = hv.w;
    float g_2 = mix(mix(_e87, _e89, t_10.x), mix(_e93, _e95, t_10.x), t_10.y);
    float _e101 = sv.x;
    float _e103 = sv.y;
    float _e107 = sv.z;
    float _e109 = sv.w;
    float sh = mix(mix(_e101, _e103, t_10.x), mix(_e107, _e109, t_10.x), t_10.y);
    float e_8 = smoothstep(-(step_), (3.0 * step_), (max(abs(q_9.x), abs(q_9.y)) - _e19));
    return vec2(g_2, (sh * (1.0 - e_8)));
}

vec2 pl_dust(vec3 p_25, vec3 C_4, float a_13, vec3 me_1, float dme_1, float side, vec4 loc) {
    bool local_61 = false;
    vec3 q_19 = (p_25 - C_4);
    float r_15 = length(q_19.xz);
    vec4 _e12 = _group_0_binding_4_fs.camera_position;
    vec3 w_10 = (p_25 + _e12.xyz);
    float _e16 = pl_gref(r_15, me_1, C_4, dme_1);
    vec2 _e17 = pl_land(q_19.xz, _e16);
    vec2 dl = (q_19.xz - loc.xy);
    float h_8 = ((q_19.y - _e17.x) - (loc.z * exp((-(dot(dl, dl)) / loc.w))));
    float sh_1 = _e17.y;
    if (!((h_8 > 70.0))) {
        local_61 = (h_8 < -4.0);
    } else {
        local_61 = true;
    }
    bool _e41 = local_61;
    if (_e41) {
        return vec2(0.0, h_8);
    }
    float rf = (PL_V * a_13);
    float _e57 = gnoise3_(((w_10 * vec3(0.11111111, 0.16666667, 0.11111111)) + vec3(0.0, (-1.2 * a_13), 0.0)));
    float _e66 = gnoise3_(((w_10 * 0.2857143) + vec3(5.0, (-2.0 * a_13), 1.0)));
    float s_15 = (((((rf - r_15) + ((_e57 - 0.5) * 14.0)) + ((_e66 - 0.5) * 5.0)) - (0.25 * max(h_8, 0.0))) - (22.0 * sh_1));
    if ((s_15 < -3.0)) {
        return vec2(0.0, h_8);
    }
    float since = (max(s_15, 0.0) / PL_V);
    float _e102 = gnoise3_(((w_10 * 0.02631579) + vec3(0.0, (-0.3 * a_13), 9.0)));
    float rise_1 = ((1.0 + (0.8 * smoothstep(0.0, 25.0, s_15))) - (0.7 * smoothstep(30.0, 140.0, s_15)));
    float hw_1 = (((((4.5 + (0.006 * r_15)) * rise_1) * (0.35 + (1.2 * _e57))) * (0.6 + (0.8 * _e102))) + (1.5 * min(since, 6.0)));
    float up_5 = (smoothstep(hw_1, (hw_1 * 0.35), h_8) * smoothstep(-4.0, 0.0, h_8));
    float lead_1 = smoothstep(-3.0, 1.5, s_15);
    float wall_1 = (((1.6 * exp((-(s_15) / (9.0 + (0.015 * r_15))))) * (0.75 + (0.25 * side))) * (1.0 - (0.6 * sh_1)));
    float haze_3 = (((0.009 * exp((-(since) / 2.5))) + (0.0025 * exp((-(since) / 6.0)))) * (0.5 + _e66));
    float mid = smoothstep(45.0, 160.0, r_15);
    float low_3 = (((((0.22 * (1.0 - (0.45 * sh_1))) * exp((-(since) / 3.0))) * smoothstep(0.0, 30.0, s_15)) * exp((-(max(h_8, 0.0)) / (2.5 + (2.0 * _e57))))) * smoothstep(0.35, 0.7, _e102));
    return vec2((((((((wall_1 * clamp(((1.5 * _e57) + (0.25 * _e66)), 0.0, 1.0)) * (0.35 + (1.3 * _e102))) + (haze_3 * (1.0 - (0.4 * sh_1)))) * up_5) + low_3) * lead_1) * mid), h_8);
}

PlChunk pl_chunk(int i_20, float a_14, float eka, vec3 C_5) {
    PlChunk o_3 = PlChunk(vec3(0.0), vec3(0.0), 0.0, 0.0);
    uint b_15 = (PL_DB + (PL_DW * uint(i_20)));
    float _e12 = pl_w((b_15 + 5u));
    float tau_3 = (a_14 - _e12);
    float _e17 = pl_w((b_15 + 6u));
    o_3.s = _e17;
    o_3.live = 0.0;
    if ((tau_3 <= 0.0)) {
        PlChunk _e22 = o_3;
        return _e22;
    }
    float _e23 = pl_w(b_15);
    float _e26 = pl_w((b_15 + 1u));
    vec3 dir_2 = vec3(_e23, 0.0, _e26);
    float _e31 = pl_w((b_15 + 3u));
    float _e34 = pl_w((b_15 + 4u));
    float _e38 = pl_w((b_15 + 7u));
    float ek = (eka * _e38);
    float e_9 = ((1.0 - ek) / 0.06);
    float _e47 = pl_w((b_15 + 2u));
    o_3.p = ((C_5 + (dir_2 * (_e47 + (_e31 * e_9)))) + vec3(0.0, ((2.0 + (_e34 * e_9)) - ((9.8 * (tau_3 - e_9)) / 0.06)), 0.0));
    o_3.v = ((dir_2 * (_e31 * ek)) + vec3(0.0, (((_e34 + (9.8 / 0.06)) * ek) - (9.8 / 0.06)), 0.0));
    o_3.live = 1.0;
    PlChunk _e77 = o_3;
    return _e77;
}

float pl_chunk_up(PlChunk ch, vec3 C_6, vec3 me_2, float dme_2) {
    float gref_1 = 0.0;
    float r_16 = length((ch.p - C_6).xz);
    float _e9 = pl_gref(r_16, me_2, C_6, dme_2);
    gref_1 = (C_6.y + _e9);
    float _e14 = gref_1;
    float _e17 = pl_w(1027u);
    if ((ch.p.y < (max(_e14, (C_6.y + _e17)) + 3.0))) {
        float _e27 = gref_1;
        vec2 _e30 = pl_land((ch.p - C_6).xz, (_e27 - C_6.y));
        gref_1 = (C_6.y + _e30.x);
    }
    float _e33 = gref_1;
    float _e36 = gref_1;
    return smoothstep((_e33 - 1.0), (_e36 + 2.0), ch.p.y);
}

void pl_over(inout vec4 h_1, vec3 c_13, float x_9) {
    vec4 _e3 = h_1;
    float _e11 = h_1.w;
    h_1 = vec4(((_e3.xyz * (1.0 - x_9)) + (c_13 * x_9)), (_e11 * (1.0 - x_9)));
    return;
}

PlOut payload(StageIn in_1, uint stage, vec4 up_1, vec2 up_e) {
    vec2 uv_4 = vec2(0.0);
    float d_7 = 0.0;
    vec3 col_2 = vec3(0.0);
    vec4 hc = vec4(0.0, 0.0, 0.0, 1.0);
    bool local_62 = false;
    bool local_63 = false;
    bool local_64 = false;
    bool local_65 = false;
    bool local_66 = false;
    bool local_67 = false;
    vec3 skyl = vec3(0.0);
    float nsk = 1.0;
    int s_5 = 0;
    float flash = 0.0;
    bool local_68 = false;
    bool local_69 = false;
    bool local_70 = false;
    bool local_71 = false;
    bool local_72 = false;
    bool local_73 = false;
    bool local_74 = false;
    bool local_75 = false;
    bool local_76 = false;
    float tau_2 = 0.0;
    vec3 tc = vec3(0.0);
    vec3 glow = vec3(0.0);
    vec3 pa = vec3(0.0);
    vec3 pv = vec3(0.0);
    bool have_pv = true;
    vec3 pc_1 = vec3(0.0);
    bool have_pc = false;
    int i_21 = 0;
    bool local_77 = false;
    bool local_78 = false;
    vec3 pb = vec3(0.0);
    vec3 pn = vec3(0.0);
    vec3 na = vec3(0.0);
    vec3 oa = vec3(0.0);
    vec3 nb = vec3(0.0);
    vec3 ob = vec3(0.0);
    vec3 lb = vec3(0.0);
    float n1_ = 0.0;
    float n2_1 = 0.0;
    float n3_ = 0.0;
    vec3 alb = vec3(0.0);
    vec3 c_14 = vec3(0.0);
    bool local_79 = false;
    bool local_80 = false;
    float ftau = 0.0;
    vec3 ftc = vec3(0.0);
    vec3 fglow = vec3(0.0);
    int f_9 = 0;
    bool local_81 = false;
    bool local_82 = false;
    bool local_83 = false;
    bool local_84 = false;
    vec3 qa = vec3(0.0);
    int j_4 = 0;
    bool local_85 = false;
    bool local_86 = false;
    bool local_87 = false;
    vec3 c_15 = vec3(0.0);
    float col_t = 0.0;
    bool local_88 = false;
    bool local_89 = false;
    bool local_90 = false;
    PlCol cl = PlCol(0, vec3(0.0), vec3(0.0), 0.0, 0.0, vec3(0.0), vec4[18](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4(0.0), vec4(0.0), vec4(0.0));
    float t_7 = 0.0;
    float tr_1 = 1.0;
    vec3 acc_1 = vec3(0.0);
    float tmid = 0.0;
    float wmid = 0.0;
    int nl_2 = 0;
    float lc_face = 0.0;
    float lc_bulk = 1.0;
    int i_22 = 0;
    bool local_91 = false;
    float den = 0.0;
    bool local_92 = false;
    bool local_93 = false;
    vec3 c_16 = vec3(0.0);
    bool local_94 = false;
    bool local_95 = false;
    bool local_96 = false;
    float vis = 1.0;
    bool local_97 = false;
    bool local_98 = false;
    bool local_99 = false;
    bool local_100 = false;
    bool local_101 = false;
    float ylo = 0.0;
    float yhi = 0.0;
    vec4 loc_1 = vec4(0.0, 0.0, 0.0, 1.0);
    float t0_ = 0.0;
    float t1_ = 0.0;
    bool local_102 = false;
    bool local_103 = false;
    vec2 seg[3] = vec2[3](vec2(0.0), vec2(0.0), vec2(0.0));
    int ns[3] = int[3](16, 0, 0);
    bool local_104 = false;
    float tr_2 = 1.0;
    vec3 acc_2 = vec3(0.0);
    int order[3] = int[3](0, 2, 1);
    int si = 0;
    bool local_105 = false;
    bool local_106 = false;
    int i_23 = 0;
    float near = 0.0;
    bool local_107 = false;
    bool local_108 = false;
    float low = 0.0;
    int i_24 = 0;
    bool local_109 = false;
    bool local_110 = false;
    bool local_111 = false;
    bool local_112 = false;
    bool local_113 = false;
    bool local_114 = false;
    float cov = 0.0;
    float smk = 0.0;
    float low_1 = 0.0;
    int i_25 = 0;
    PlChunk ch_1 = PlChunk(vec3(0.0), vec3(0.0), 0.0, 0.0);
    bool local_115 = false;
    bool local_116 = false;
    bool local_117 = false;
    bool local_118 = false;
    bool local_119 = false;
    float keep = 1.0;
    float shine = 0.0;
    uint i_26 = 0u;
    uint j_5 = 0u;
    bool local_120 = false;
    float up_t = up_e.x;
    uv_4 = in_1.uv;
    float _e7 = now();
    vec4 _e10 = _group_0_binding_4_fs.camera_position;
    vec3 cam_6 = _e10.xyz;
    float _e12 = intensity_v();
    float _e13 = seed_v();
    uint seed_20 = uint(_e13);
    float _e18 = _group_0_binding_4_fs.view_params.w;
    float _e22 = _group_0_binding_4_fs.resolution.y;
    float px_a = (_e18 / _e22);
    vec2 _e24 = anchor_xz();
    float _e25 = block_y();
    float gy_1 = (_e25 + 1.0);
    vec3 C_7 = (vec3(_e24.x, gy_1, _e24.y) - cam_6);
    float _e36 = _group_0_binding_4_fs.mod_params[3].x;
    float _e41 = _group_0_binding_4_fs.mod_params[3].y;
    float _e46 = _group_0_binding_4_fs.mod_params[3].z;
    vec3 me_3 = (vec3(_e36, _e41, _e46) - cam_6);
    float dme_3 = length((me_3 - C_7).xz);
    vec4 _e54 = _group_0_binding_4_fs.sun;
    vec3 sun_2 = _e54.xyz;
    float day_2 = clamp(((sun_2.y * 2.5) + 0.35), 0.0, 1.0);
    float sun_up = smoothstep(-0.12, 0.06, sun_2.y);
    float warm = ((1.0 - smoothstep(0.02, 0.4, sun_2.y)) * smoothstep(-0.2, -0.02, sun_2.y));
    float moon = smoothstep(-0.02, -0.2, sun_2.y);
    vec3 L_2 = normalize((((sun_2.y > -0.04) ? sun_2 : -(sun_2)) + vec3(0.0, 0.03, 0.0)));
    if ((stage == 1u)) {
        vec4 _e98 = _group_0_binding_4_fs.resolution;
        ivec2 full = ivec2(_e98.xy);
        ivec2 q_20 = (ivec2(floor(in_1.position.xy)) * 2);
        ivec2 q1_2 = min((q_20 + ivec2(1)), (full - ivec2(1)));
        float _e114 = depth_px(q_20);
        float _e118 = depth_px(ivec2(q1_2.x, q_20.y));
        float _e122 = depth_px(ivec2(q_20.x, q1_2.y));
        float _e123 = depth_px(q1_2);
        ivec2 hq_2 = ivec2(floor(in_1.position.xy));
        d_7 = ((((hq_2.x + hq_2.y) & 1) == 0) ? max(max(_e114, _e118), max(_e122, _e123)) : min(min(_e114, _e118), min(_e122, _e123)));
        vec4 _e148 = _group_0_binding_4_fs.resolution;
        uv_4 = ((vec2(q_20) + vec2(1.0)) * _e148.zw);
    } else {
        vec2 _e151 = uv_4;
        float _e152 = depth_at(_e151);
        d_7 = _e152;
    }
    float _e153 = d_7;
    bool _e154 = is_sky(_e153);
    vec2 _e155 = uv_4;
    float _e156 = d_7;
    vec3 _e159 = world_offset(_e155, (_e154 ? 0.5 : _e156));
    float scene_len_3 = (!(_e154) ? length(_e159) : 1000000000.0);
    vec2 _e164 = uv_4;
    vec3 _e166 = world_offset(_e164, RAY_DEPTH);
    vec3 rd_10 = normalize(_e166);
    vec2 _e170 = uv_4;
    vec4 _e172 = orbitalSceneLod(_group_0_binding_0_fs, vec2(_e170), 0.0);
    vec3 _e174 = srgb_to_linear(_e172.xyz);
    col_2 = _e174;
    if ((stage != 1u)) {
        local_62 = !(_e154);
    } else {
        local_62 = false;
    }
    bool _e188 = local_62;
    if (_e188) {
        local_63 = (_e7 > PL_HIT);
    } else {
        local_63 = false;
    }
    bool _e194 = local_63;
    if (_e194) {
        local_64 = (_e7 < 19.6);
    } else {
        local_64 = false;
    }
    bool _e200 = local_64;
    if (_e200) {
        float rfr = (PL_V * (_e7 - PL_HIT));
        vec2 _e205 = anchor_xz();
        float _e207 = block_y();
        vec2 _e210 = anchor_xz();
        float rs_3 = length((_e159 - (vec3(_e205.x, (_e207 + 1.0), _e210.y) - cam_6)).xz);
        float e_10 = (rfr - rs_3);
        float gust = (exp(-(pow((e_10 / 14.0), 2.0))) + ((0.4 * exp((-(max(e_10, 0.0)) / 50.0))) * step(0.0, e_10)));
        if ((_e174.y > (_e174.x * 1.1))) {
            local_65 = (_e174.y > (_e174.z * 1.05));
        } else {
            local_65 = false;
        }
        bool green_1 = local_65;
        if ((gust > 0.03)) {
            local_66 = green_1;
        } else {
            local_66 = false;
        }
        bool _e255 = local_66;
        if (_e255) {
            float _e259 = _group_0_binding_4_fs.resolution.y;
            float _e263 = _group_0_binding_4_fs.view_params.w;
            float fpx0_ = (_e259 / (2.0 * tan((_e263 * 0.5))));
            float amp_1 = (min(((0.45 * fpx0_) / max(scene_len_3, 1.0)), 7.0) * gust);
            float ph = dot(floor((in_1.position.xy / vec2(6.0))), vec2(0.37, 0.71));
            vec2 off_2 = (vec2(sin(((_e7 * 29.0) + (ph * 5.0))), cos(((_e7 * 23.0) + (ph * 3.0)))) * amp_1);
            vec2 _e304 = uv_4;
            vec4 _e307 = _group_0_binding_4_fs.resolution;
            vec4 _e312 = orbitalSceneLod(_group_0_binding_0_fs, vec2((_e304 + (off_2 * _e307.zw))), 0.0);
            vec3 _e314 = srgb_to_linear(_e312.xyz);
            if ((_e314.y > (_e314.x * 1.1))) {
                local_67 = (_e314.y > (_e314.z * 1.05));
            } else {
                local_67 = false;
            }
            bool _e328 = local_67;
            if (_e328) {
                col_2 = _e314;
            }
        }
    }
    float fade = (1.0 - smoothstep(62.0, PL_LEN, _e7));
    float a_23 = (_e7 - PL_HIT);
    int _e336 = pl_n();
    bool have = (_e336 > 1);
    vec4 _e341 = _group_0_binding_4_fs.sky_color;
    vec3 _e343 = srgb_to_linear(_e341.xyz);
    skyl = _e343;
    bool loop_init_12 = true;
    while(true) {
        if (!loop_init_12) {
            int _e373 = s_5;
            s_5 = (_e373 + 1);
        }
        loop_init_12 = false;
        int _e349 = s_5;
        if ((_e349 < 3)) {
        } else {
            break;
        }
        {
            int _e352 = s_5;
            vec2 su = vec2((0.2 + (0.3 * float(_e352))), 0.04);
            float _e360 = depth_at(su);
            bool _e361 = is_sky(_e360);
            if (_e361) {
                vec3 _e362 = skyl;
                vec4 _e366 = orbitalSceneLod(_group_0_binding_0_fs, vec2(su), 0.0);
                vec3 _e368 = srgb_to_linear(_e366.xyz);
                skyl = (_e362 + _e368);
                float _e370 = nsk;
                nsk = (_e370 + 1.0);
            }
        }
    }
    vec3 _e376 = skyl;
    float _e377 = nsk;
    skyl = (_e376 / vec3(_e377));
    vec3 _e384 = skyl;
    vec3 amb = mix(vec3(0.03, 0.035, 0.05), ((_e384 * 0.85) + vec3(0.04)), day_2);
    vec3 sunc = ((mix(vec3(1.35, 1.24, 1.06), mix(vec3(1.5, 0.68, 0.3), vec3(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun_2.y)), warm) * sun_up) + (vec3(0.07, 0.09, 0.14) * moon));
    vec4 _e418 = _group_0_binding_4_fs.fog_color;
    vec3 _e420 = srgb_to_linear(_e418.xyz);
    vec3 _e425 = skyl;
    vec3 haze_c = mix(vec3(0.02, 0.025, 0.04), (_e425 * 1.05), day_2);
    if ((stage != 1u)) {
        local_68 = (a_23 > 0.0);
    } else {
        local_68 = false;
    }
    bool _e438 = local_68;
    if (_e438) {
        local_69 = (a_23 < 3.0);
    } else {
        local_69 = false;
    }
    bool _e444 = local_69;
    if (_e444) {
        flash = (exp((-(a_23) / 0.16)) + (0.25 * exp((-(a_23) / 0.9))));
        vec3 Pf = (C_7 + vec3(0.0, 10.0, 0.0));
        float df = length(Pf);
        float cth = dot(rd_10, (Pf / vec3(df)));
        float th_1 = sqrt(max((2.0 * (1.0 - cth)), 0.0));
        vec3 fire_c = vec3(3.2, 1.55, 0.5);
        vec3 _e476 = col_2;
        float _e477 = flash;
        col_2 = (_e476 + (((fire_c * _e477) * ((0.12 / (1.0 + pow((th_1 / 0.035), 2.0))) + (0.025 * exp((-(th_1) / 0.4))))) * _e12));
        if (!(_e154)) {
            float dl_1 = length((_e159 - Pf));
            vec3 _e500 = col_2;
            float _e502 = flash;
            col_2 = (_e500 + (((((_e174 * fire_c) * _e502) * 2.0) / vec3((1.0 + pow((dl_1 / 45.0), 2.0)))) * _e12));
        }
    }
    if ((stage != 1u)) {
        local_70 = !(_e154);
    } else {
        local_70 = false;
    }
    bool _e522 = local_70;
    if (_e522) {
        local_71 = have;
    } else {
        local_71 = false;
    }
    bool _e526 = local_71;
    if (_e526) {
        local_72 = (a_23 > 0.3);
    } else {
        local_72 = false;
    }
    bool _e532 = local_72;
    if (_e532) {
        local_73 = (L_2.y > 0.02);
    } else {
        local_73 = false;
    }
    bool _e539 = local_73;
    if (_e539) {
        float _e546 = _group_0_binding_4_fs.mod_params[3].w;
        local_74 = (_e546 < 0.5);
    } else {
        local_74 = false;
    }
    bool _e550 = local_74;
    if (_e550) {
        float _e553 = ign(in_1.position.xy);
        float _e554 = pl_shadow(_e159, L_2, a_23, C_7, _e553);
        vec3 _e555 = col_2;
        col_2 = (_e555 * (1.0 - ((((0.7 * (1.0 - _e554)) * sun_up) * _e12) * fade)));
    }
    if ((stage == 2u)) {
        vec3 _e568 = col_2;
        col_2 = ((_e568 * up_1.w) + up_1.xyz);
    }
    if ((stage != 2u)) {
        local_75 = have;
    } else {
        local_75 = false;
    }
    bool _e578 = local_75;
    if (_e578) {
        local_76 = (_e7 > PL_SEEN);
    } else {
        local_76 = false;
    }
    bool _e584 = local_76;
    if (_e584) {
        int _e585 = pl_n();
        float _e587 = pl_w(1u);
        float _e589 = pl_w(2u);
        float thead_1 = min(_e7, PL_HIT);
        int last_1 = min(int(floor(((thead_1 - _e587) / _e589))), (_e585 - 1));
        vec3 sd = vec3((float((seed_20 % 97u)) * 3.1), (float((seed_20 % 89u)) * 1.7), 0.0);
        vec3 _e620 = pl_trail_pt(0, last_1, thead_1, _e7, seed_20);
        pa = (_e620 + C_7);
        vec3 _e623 = pa;
        pv = _e623;
        vec3 _e627 = pa;
        pc_1 = _e627;
        bool loop_init_13 = true;
        while(true) {
            if (!loop_init_13) {
                int _e1399 = i_21;
                i_21 = (_e1399 + 1);
            }
            loop_init_13 = false;
            int _e633 = i_21;
            if ((_e633 <= last_1)) {
            } else {
                break;
            }
            {
                int _e635 = i_21;
                if (((_e635 % 8) == 0)) {
                    int _e642 = i_21;
                    local_77 = ((_e642 + 8) <= last_1);
                } else {
                    local_77 = false;
                }
                bool _e647 = local_77;
                if (_e647) {
                    int _e648 = i_21;
                    vec3 _e651 = pl_trail_pt((_e648 + 8), last_1, thead_1, _e7, seed_20);
                    vec3 pg = (_e651 + C_7);
                    vec3 _e653 = pa;
                    vec3 cg = (0.5 * (_e653 + pg));
                    int _e657 = i_21;
                    float ag = max((_e7 - (_e587 + (_e589 * float(_e657)))), 0.0);
                    vec3 _e664 = pa;
                    float rg = (((0.65 * length((pg - _e664))) + (3.4 * (7.0 + (5.5 * sqrt(ag))))) + 4.0);
                    float tg = max(dot(cg, rd_10), 0.0);
                    if (!((length((cg - (rd_10 * tg))) > rg))) {
                        local_78 = ((tg - rg) > scene_len_3);
                    } else {
                        local_78 = true;
                    }
                    bool _e692 = local_78;
                    if (_e692) {
                        pa = pg;
                        have_pv = false;
                        have_pc = false;
                        int _e695 = i_21;
                        i_21 = (_e695 + 7);
                        continue;
                    }
                }
                bool _e698 = have_pv;
                if (!(_e698)) {
                    int _e700 = i_21;
                    vec3 _e703 = pl_trail_pt((_e700 - 1), last_1, thead_1, _e7, seed_20);
                    pv = (_e703 + C_7);
                }
                vec3 _e705 = pc_1;
                pb = _e705;
                bool _e707 = have_pc;
                if (!(_e707)) {
                    int _e709 = i_21;
                    vec3 _e712 = pl_trail_pt((_e709 + 1), last_1, thead_1, _e7, seed_20);
                    pb = (_e712 + C_7);
                }
                vec3 _e714 = pb;
                vec3 _e715 = pb;
                vec3 _e716 = pa;
                pn = (_e714 + (_e715 - _e716));
                int _e720 = i_21;
                if ((_e720 < last_1)) {
                    int _e722 = i_21;
                    vec3 _e725 = pl_trail_pt((_e722 + 2), last_1, thead_1, _e7, seed_20);
                    pn = (_e725 + C_7);
                }
                vec3 _e727 = pn;
                pc_1 = _e727;
                have_pc = true;
                vec3 pa_2 = pa;
                vec3 pv_1 = pv;
                vec3 _e731 = pa;
                pv = _e731;
                have_pv = true;
                vec3 _e733 = pb;
                pa = _e733;
                vec3 _e734 = pb;
                vec3 ab_6 = (_e734 - pa_2);
                float len_ab = max(length(ab_6), 0.0001);
                vec3 da = (ab_6 / vec3(len_ab));
                int _e741 = i_21;
                float te_a = (_e587 + (_e589 * float(_e741)));
                float age_a = max((_e7 - te_a), 0.0);
                na = da;
                oa = pa_2;
                int _e750 = i_21;
                if ((_e750 == 0)) {
                    oa = (pa_2 - (da * (2.0 + (2.0 * sqrt(age_a)))));
                } else {
                    na = normalize((da + normalize(((pa_2 - pv_1) + vec3(0.0, 1e-5, 0.0)))));
                }
                nb = da;
                vec3 _e770 = pb;
                ob = _e770;
                int _e772 = i_21;
                if ((_e772 < last_1)) {
                    vec3 _e774 = pn;
                    vec3 _e775 = pb;
                    nb = normalize((da + normalize(((_e774 - _e775) + vec3(0.0, 1e-5, 0.0)))));
                } else {
                    vec3 _e785 = pb;
                    ob = (_e785 + ((da * (12.0 + (8.0 * sqrt(max((_e7 - thead_1), 0.0))))) * step(PL_HIT, _e7)));
                }
                vec3 _e799 = oa;
                vec3 _e800 = na;
                vec2 _e801 = pl_half(rd_10, _e799, _e800);
                vec3 _e802 = ob;
                vec3 _e803 = nb;
                vec2 _e805 = pl_half(rd_10, _e802, -(_e803));
                float t1_1 = max(max(_e801.x, _e805.x), 0.0);
                float t2_ = min(min(_e801.y, _e805.y), scene_len_3);
                if ((t2_ <= t1_1)) {
                    continue;
                }
                vec3 _e816 = pb;
                vec3 _e819 = pl_ray_seg(rd_10, pa_2, _e816, -10000.0, 10000.0);
                float tn_1 = clamp(_e819.y, t1_1, t2_);
                float sz_1 = clamp((dot(((rd_10 * tn_1) - pa_2), da) / len_ab), 0.0, 1.0);
                vec3 cp = ((pa_2 + (ab_6 * sz_1)) + ((rd_10 * _e819.y) - (pa_2 + (ab_6 * _e819.z))));
                float te_1 = clamp((te_a + (_e589 * sz_1)), _e587, thead_1);
                float age_1 = max((_e7 - te_1), 0.0);
                float dive = smoothstep(8.400001, 11.0, te_1);
                float smk_1 = smoothstep(4.0, 7.0, te_1);
                float rad = mix((3.0 + (3.0 * sqrt(age_1))), mix((6.0 + (5.0 * sqrt(age_1))), (7.0 + (5.5 * sqrt(age_1))), dive), smk_1);
                if ((_e819.x < (rad * 3.4))) {
                    float sw_1 = ((2.2 * rad) + 3.0);
                    int _e875 = i_21;
                    vec3 _e876 = pl_trail_drift(_e875, age_a, seed_20);
                    vec3 la = (pa_2 - _e876);
                    vec3 _e878 = pb;
                    lb = _e878;
                    int _e880 = i_21;
                    if ((_e880 < last_1)) {
                        vec3 _e882 = pb;
                        int _e883 = i_21;
                        vec3 _e890 = pl_trail_drift((_e883 + 1), max((_e7 - (te_a + _e589)), 0.0), seed_20);
                        lb = (_e882 - _e890);
                    }
                    vec3 _e892 = lb;
                    vec3 laid = (mix(la, _e892, sz_1) - C_7);
                    vec3 across = (((cp - (pa_2 + (ab_6 * sz_1))) / vec3(sw_1)) + sd);
                    float lv = log2((sw_1 / 8.0));
                    float lk = floor(lv);
                    float lf_1 = (lv - lk);
                    float sA = (8.0 * exp2(lk));
                    vec3 qa_1 = (((laid / vec3(sA)) + across) + vec3((lk * 17.3), (lk * 5.1), 0.0));
                    vec3 qb = (((laid / vec3((2.0 * sA))) + across) + vec3(((lk + 1.0) * 17.3), ((lk + 1.0) * 5.1), 0.0));
                    float lsp = (1.0 / sqrt(((lf_1 * lf_1) + ((1.0 - lf_1) * (1.0 - lf_1)))));
                    float sn = max(length(cross(rd_10, da)), 0.08);
                    float qs = (1.0 / ((2.2 * rad) + 3.0));
                    float along_1 = (((tn_1 * px_a) / sn) * qs);
                    float thru = (((((2.0 * sqrt(max((((2.1 * rad) * rad) - (_e819.x * _e819.x)), 0.0))) * abs(dot(rd_10, da))) / sn) * qs) + 0.001);
                    float w1_ = min(clamp((2.0 * sqrt((1.0 / thru))), 0.0, 1.0), clamp((2.0 - (10.0 * along_1)), 0.0, 1.0));
                    float w2_ = min(clamp((2.0 * sqrt((0.385 / thru))), 0.0, 1.0), clamp((2.0 - ((10.0 * along_1) * 2.6)), 0.0, 1.0));
                    float w3_ = min(clamp((2.0 * sqrt((0.164 / thru))), 0.0, 1.0), clamp((2.0 - ((10.0 * along_1) * 6.1)), 0.0, 1.0));
                    n1_ = 0.5;
                    n2_1 = 0.5;
                    n3_ = 0.5;
                    if ((w1_ > 0.0)) {
                        vec3 o_6 = vec3(0.0, 0.0, (0.06 * age_1));
                        float _e1031 = gnoise3_((qa_1 + o_6));
                        float _e1033 = gnoise3_((qb + o_6));
                        n1_ = (0.5 + ((mix(_e1031, _e1033, lf_1) - 0.5) * lsp));
                    }
                    if ((w2_ > 0.0)) {
                        vec3 o_7 = vec3(4.0, (0.08 * age_1), 1.0);
                        float _e1050 = gnoise3_(((qa_1 * 2.6) + o_7));
                        float _e1054 = gnoise3_(((qb * 2.6) + o_7));
                        n2_1 = (0.5 + ((mix(_e1050, _e1054, lf_1) - 0.5) * lsp));
                    }
                    if ((w3_ > 0.0)) {
                        vec3 o_8 = vec3(1.0, 7.0, (0.15 * age_1));
                        float _e1071 = gnoise3_(((qa_1 * 6.1) + o_8));
                        float _e1075 = gnoise3_(((qb * 6.1) + o_8));
                        n3_ = (0.5 + ((mix(_e1071, _e1075, lf_1) - 0.5) * lsp));
                    }
                    float _e1084 = n1_;
                    float _e1092 = n2_1;
                    float _e1099 = n3_;
                    float puff = (((0.5 + ((0.62 * w1_) * (_e1084 - 0.5))) + ((0.3 * w2_) * (_e1092 - 0.5))) + ((0.08 * w3_) * (_e1099 - 0.5)));
                    float rw = (rad * (0.45 + (1.0 * puff)));
                    float rr_1 = (_e819.x / rw);
                    float prof = (exp(((-(rr_1) * rr_1) * 1.4)) * smoothstep(2.3, 1.5, rr_1));
                    float ka = ((1.183 * sn) / rw);
                    float _e1126 = pl_erf(((t2_ - _e819.y) * ka));
                    float _e1130 = pl_erf(((t1_1 - _e819.y) * ka));
                    float gin = ((0.5 * (_e1126 - _e1130)) / max(sn, 0.5));
                    float thr = (mix(0.32, 0.12, smk_1) + (0.38 * smoothstep(1.5, 18.0, age_1)));
                    float m_6 = (((puff - thr) * 3.2) + (0.3 * exp((-(age_1) / 0.8))));
                    float sl = ((0.448 * sqrt((((0.384 * (1.0 - (w1_ * w1_))) + (0.09 * (1.0 - (w2_ * w2_)))) + (0.0064 * (1.0 - (w3_ * w3_)))))) + 0.001);
                    float dens_1 = clamp((sl * log((1.0 + exp(clamp((m_6 / sl), -30.0, 30.0))))), 0.0, 1.0);
                    float sig = ((((0.26 * exp((-(age_1) / 6.0))) + ((0.25 * exp((-(age_1) / 0.7))) * dive)) * mix(0.35, 1.0, smk_1)) * fade);
                    float dtau = (((((sig * prof) * dens_1) * 1.6) * rad) * gin);
                    vec3 axis = (pa_2 + (ab_6 * sz_1));
                    vec3 nrm_1 = normalize((((cp - axis) - (rd_10 * (0.6 * rad))) + vec3(0.0, 0.0001, 0.0)));
                    float _e1226 = n1_;
                    float ln = (0.5 + (w1_ * (_e1226 - 0.5)));
                    float lit_1 = ((0.35 + (0.65 * clamp(((dot(nrm_1, L_2) * 0.5) + 0.5), 0.0, 1.0))) * (0.6 + ((0.8 * ln) * ln)));
                    alb = mix(vec3(0.5, 0.5, 0.52), vec3(0.17, 0.145, 0.125), smk_1);
                    vec3 _e1258 = alb;
                    vec3 _e1259 = alb;
                    alb = mix(_e1258, ((_e1259 * 1.35) + vec3(0.03)), smoothstep(4.0, 20.0, age_1));
                    vec3 _e1269 = alb;
                    c_14 = (_e1269 * (((sunc * lit_1) * 0.85) + (amb * (0.6 + (0.4 * ln)))));
                    vec3 _e1281 = c_14;
                    c_14 = (_e1281 + ((((vec3(1.9, 0.75, 0.22) * exp((-(age_1) / 0.12))) * dive) * step(_e7, 13.900001)) * (0.4 + (0.6 * ln))));
                    vec3 _e1301 = c_14;
                    c_14 = mix(_e1301, haze_c, ((1.0 - exp((-(tn_1) / 3000.0))) * 0.75));
                    vec3 _e1311 = tc;
                    vec3 _e1312 = c_14;
                    tc = (_e1311 + (_e1312 * dtau));
                    float _e1315 = tau_2;
                    tau_2 = (_e1315 + dtau);
                    float gx = length(((rd_10 * tn_1) - axis));
                    float chord = (2.0 * sqrt(max(((rad * rad) - (gx * gx)), 0.0)));
                    float fl_1 = ((dive * exp((-(age_1) / 0.13))) * step(_e7, 13.650001));
                    float fw = (rad * (0.75 - (0.35 * clamp((age_1 / 0.3), 0.0, 1.0))));
                    float fprof = (exp((-(pow((gx / max(fw, 0.5)), 2.0)) * 1.6)) * min((fw * 0.5), 1.0));
                    vec3 _e1358 = glow;
                    glow = max(_e1358, (((mix(vec3(3.2, 1.0, 0.18), vec3(4.0, 2.6, 1.0), exp((-(age_1) / 0.06))) * fl_1) * 1.6) * fprof));
                    float fh = (((1.0 - dive) * exp((-(age_1) / 0.45))) * step(_e7, PL_HIT));
                    vec3 _e1387 = glow;
                    glow = max(_e1387, ((vec3(2.4, 2.3, 2.1) * fh) * min((chord * 0.6), 1.2)));
                }
            }
        }
        float _e1402 = tau_2;
        if ((_e1402 > 0.0)) {
            float _e1405 = tau_2;
            float al_1 = (1.0 - exp(-(_e1405)));
            if ((stage == 0u)) {
                vec3 _e1412 = col_2;
                vec3 _e1413 = tc;
                float _e1414 = tau_2;
                col_2 = mix(_e1412, (_e1413 / vec3(_e1414)), (al_1 * _e12));
            } else {
                vec3 _e1419 = tc;
                float _e1420 = tau_2;
                pl_over(hc, (_e1419 / vec3(_e1420)), (al_1 * _e12));
            }
        }
        if ((stage == 0u)) {
            vec3 _e1426 = col_2;
            vec3 _e1427 = glow;
            col_2 = (_e1426 + (_e1427 * _e12));
        } else {
            vec4 _e1430 = hc;
            vec3 _e1432 = glow;
            float _e1436 = hc.w;
            hc = vec4((_e1430.xyz + (_e1432 * _e12)), _e1436);
        }
    }
    if (have) {
        local_79 = (_e7 > 6.6000004);
    } else {
        local_79 = false;
    }
    bool _e1443 = local_79;
    if (_e1443) {
        local_80 = (_e7 < 20.6);
    } else {
        local_80 = false;
    }
    bool _e1449 = local_80;
    if (_e1449) {
        float _e1451 = pl_w(7u);
        int nf = min(int((_e1451 + 0.5)), 32);
        bool loop_init_14 = true;
        while(true) {
            if (!loop_init_14) {
                int _e1809 = f_9;
                f_9 = (_e1809 + 1);
            }
            loop_init_14 = false;
            int _e1467 = f_9;
            if ((_e1467 < nf)) {
            } else {
                break;
            }
            {
                int _e1471 = f_9;
                uint b_16 = (PL_FR + (PL_FW * uint(_e1471)));
                float _e1475 = pl_w(b_16);
                float s_16 = (_e7 - _e1475);
                if ((s_16 <= 0.0)) {
                    continue;
                }
                float _e1481 = pl_w((b_16 + 1u));
                float _e1484 = pl_w((b_16 + 2u));
                float _e1487 = pl_w((b_16 + 3u));
                bool spark = (_e1487 > 0.5);
                float _e1492 = pl_w((b_16 + 4u));
                float kd = max(_e1492, 0.05);
                float _e1497 = pl_w((b_16 + 5u));
                float _e1500 = pl_w((b_16 + 6u));
                float _e1503 = pl_w((b_16 + 7u));
                vec3 p0_2 = (vec3(_e1497, _e1500, _e1503) + C_7);
                float _e1508 = pl_w((b_16 + 8u));
                float _e1511 = pl_w((b_16 + 9u));
                float _e1514 = pl_w((b_16 + 10u));
                vec3 v0_2 = vec3(_e1508, _e1511, _e1514);
                if ((stage != 1u)) {
                    local_81 = (s_16 < _e1481);
                } else {
                    local_81 = false;
                }
                bool _e1522 = local_81;
                if (_e1522) {
                    vec3 _e1523 = pl_frag(p0_2, v0_2, kd, s_16);
                    vec3 _e1530 = pl_frag(p0_2, v0_2, kd, max((s_16 - (spark ? 0.05 : 0.03)), 0.0));
                    vec3 _e1531 = ray_seg(rd_10, _e1523, _e1530);
                    if ((_e1531.y < ((stage == 2u) ? min((scene_len_3 + 2.0), up_t) : (scene_len_3 + 2.0)))) {
                        float w_11 = max(_e1484, ((_e1531.y * px_a) * 0.8));
                        float e_11 = min((_e1484 / w_11), 1.0);
                        float u_22 = (s_16 / _e1481);
                        vec3 hot_2 = (spark ? vec3(4.0, 3.2, 1.8) : mix(vec3(4.0, 2.3, 1.0), vec3(2.6, 0.75, 0.12), u_22));
                        int _e1567 = f_9;
                        float fl_2 = (0.75 + (0.25 * sin(((_e7 * 41.0) + (float(_e1567) * 2.3)))));
                        vec3 _e1577 = fglow;
                        fglow = (_e1577 + (((((hot_2 * ((exp(-(pow((_e1531.x / w_11), 2.0))) * 3.0) + (0.25 * exp((-(_e1531.x) / (w_11 * 4.0)))))) * e_11) * e_11) * (1.0 - (u_22 * u_22))) * fl_2));
                    }
                }
                if ((stage != 2u)) {
                    local_82 = !(spark);
                } else {
                    local_82 = false;
                }
                bool _e1610 = local_82;
                if (_e1610) {
                    float s_hi = min(s_16, _e1481);
                    float s_lo = max((s_16 - 3.5), 0.0);
                    vec3 _e1616 = pl_frag(p0_2, v0_2, kd, s_hi);
                    vec3 _e1617 = pl_frag(p0_2, v0_2, kd, s_lo);
                    vec3 cq = (0.5 * (_e1617 + _e1616));
                    float rq = (((0.75 * length((_e1616 - _e1617))) + ((2.0 * _e1484) * (0.6 + (1.1 * sqrt((s_16 - s_lo)))))) + 3.0);
                    float tq_2 = max(dot(cq, rd_10), 0.0);
                    if ((s_hi > s_lo)) {
                        local_83 = (length((cq - (rd_10 * tq_2))) < rq);
                    } else {
                        local_83 = false;
                    }
                    bool _e1648 = local_83;
                    if (_e1648) {
                        local_84 = ((tq_2 - rq) < scene_len_3);
                    } else {
                        local_84 = false;
                    }
                    bool _e1654 = local_84;
                    if (_e1654) {
                        qa = _e1617;
                        j_4 = 1;
                        bool loop_init_15 = true;
                        while(true) {
                            if (!loop_init_15) {
                                int _e1806 = j_4;
                                j_4 = (_e1806 + 1);
                            }
                            loop_init_15 = false;
                            int _e1658 = j_4;
                            if ((_e1658 <= 8)) {
                            } else {
                                break;
                            }
                            {
                                int _e1662 = j_4;
                                float sj = (s_lo + (((s_hi - s_lo) * float(_e1662)) / 8.0));
                                vec3 _e1668 = pl_frag(p0_2, v0_2, kd, sj);
                                vec3 _e1669 = qa;
                                vec3 _e1670 = ray_seg(rd_10, _e1669, _e1668);
                                float age_2 = (s_16 - (sj - (((s_hi - s_lo) / 8.0) * (1.0 - _e1670.z))));
                                float rad_1 = (_e1484 * (0.6 + (1.1 * sqrt(age_2))));
                                if ((_e1670.x < (rad_1 * 2.0))) {
                                    local_85 = (_e1670.y < (scene_len_3 + rad_1));
                                } else {
                                    local_85 = false;
                                }
                                bool _e1696 = local_85;
                                if (_e1696) {
                                    if (!((_e1670.z < 0.9999))) {
                                        int _e1705 = j_4;
                                        local_87 = (_e1705 == 8);
                                    } else {
                                        local_87 = true;
                                    }
                                    bool _e1709 = local_87;
                                    local_86 = _e1709;
                                } else {
                                    local_86 = false;
                                }
                                bool _e1711 = local_86;
                                if (_e1711) {
                                    vec3 cp_1 = (rd_10 * _e1670.y);
                                    int _e1721 = f_9;
                                    float _e1730 = gnoise3_((((cp_1 - C_7) / vec3(((2.5 * rad_1) + 1.0))) + vec3((float(_e1721) * 7.1), 0.0, (0.1 * age_2))));
                                    float prof_1 = exp((-(pow((_e1670.x / (rad_1 * (0.5 + _e1730))), 2.0)) * 1.4));
                                    float dens_2 = clamp((((_e1730 - 0.18) - (0.25 * smoothstep(0.5, 3.5, age_2))) * 3.0), 0.0, 1.0);
                                    float dtau_1 = ((((((0.5 * exp((-(age_2) / 1.8))) * prof_1) * dens_2) * 1.6) * rad_1) * fade);
                                    c_15 = (vec3(0.19, 0.16, 0.14) * ((sunc * 0.75) + (amb * 0.8)));
                                    vec3 _e1776 = c_15;
                                    c_15 = (_e1776 + ((vec3(1.6, 0.6, 0.15) * exp((-(age_2) / 0.1))) * step(s_16, _e1481)));
                                    vec3 _e1789 = c_15;
                                    c_15 = mix(_e1789, haze_c, ((1.0 - exp((-(_e1670.y) / 3000.0))) * 0.75));
                                    vec3 _e1800 = ftc;
                                    vec3 _e1801 = c_15;
                                    ftc = (_e1800 + (_e1801 * dtau_1));
                                    float _e1804 = ftau;
                                    ftau = (_e1804 + dtau_1);
                                }
                                qa = _e1668;
                            }
                        }
                    }
                }
            }
        }
        float _e1812 = ftau;
        if ((_e1812 > 0.0)) {
            if ((stage == 0u)) {
                vec3 _e1817 = col_2;
                vec3 _e1818 = ftc;
                float _e1819 = ftau;
                float _e1822 = ftau;
                col_2 = mix(_e1817, (_e1818 / vec3(_e1819)), ((1.0 - exp(-(_e1822))) * _e12));
            } else {
                vec3 _e1829 = ftc;
                float _e1830 = ftau;
                float _e1833 = ftau;
                pl_over(hc, (_e1829 / vec3(_e1830)), ((1.0 - exp(-(_e1833))) * _e12));
            }
        }
        vec3 _e1839 = col_2;
        vec3 _e1840 = fglow;
        col_2 = (_e1839 + ((_e1840 * _e12) * fade));
    }
    col_t = ((stage == 2u) ? up_t : 1000000000.0);
    float cgrow_1 = ((1.0 + (0.012 * max((a_23 - 6.0), 0.0))) + (0.006 * max((a_23 - PL_SOFT0_), 0.0)));
    float _e1865 = pl_w(5u);
    vec3 _e1880 = pl_wind();
    vec3 ctop_1 = ((C_7 + vec3(0.0, (5.0 + (((1.08 * _e1865) * (1.0 + (0.006 * a_23))) * cgrow_1)), 0.0)) + (_e1880 * a_23));
    vec3 _e1890 = pl_ray_seg(rd_10, (C_7 - vec3(0.0, 30.0, 0.0)), ctop_1, 0.0, 1.0);
    if ((stage != 2u)) {
        local_88 = have;
    } else {
        local_88 = false;
    }
    bool _e1896 = local_88;
    if (_e1896) {
        local_89 = (a_23 > 0.0);
    } else {
        local_89 = false;
    }
    bool _e1902 = local_89;
    if (_e1902) {
        local_90 = (_e1890.x < ((130.0 * cgrow_1) + 50.0));
    } else {
        local_90 = false;
    }
    bool _e1912 = local_90;
    if (_e1912) {
        PlCol _e1913 = pl_column(a_23, C_7);
        cl = _e1913;
        int _e1916 = cl.n;
        if ((_e1916 > 0)) {
            vec3 _e1920 = cl.lo;
            vec3 _e1922 = cl.hi;
            vec2 _e1923 = pl_box(rd_10, _e1920, _e1922);
            float t1_2 = min(_e1923.y, scene_len_3);
            if ((t1_2 > _e1923.x)) {
                t_7 = _e1923.x;
                float _e1945 = ign((in_1.position.xy + vec2((fract((_e7 * 7.0)) * 37.0), 0.0)));
                float _e1947 = pl_w(5u);
                float ph_1 = (0.8 + ((0.5 + (1.6 * warm)) * pow(clamp(dot(rd_10, L_2), 0.0, 1.0), 5.0)));
                float soft_1 = smoothstep(PL_SOFT0_, PL_SOFT1_, a_23);
                float lift_1 = (((_e1947 * 0.4) * smoothstep(PL_SOFT0_, 38.0, a_23)) - 30.0);
                float thin_1 = exp((-(max(((a_23 - PL_SOFT0_) - 8.0), 0.0)) / 4.5));
                bool loop_init_16 = true;
                while(true) {
                    if (!loop_init_16) {
                        int _e2360 = i_22;
                        i_22 = (_e2360 + 1);
                    }
                    loop_init_16 = false;
                    int _e1992 = i_22;
                    if ((_e1992 < 96)) {
                    } else {
                        break;
                    }
                    {
                        float _e1995 = t_7;
                        if (!((_e1995 > t1_2))) {
                            float _e2000 = tr_1;
                            local_91 = (_e2000 < 0.03);
                        } else {
                            local_91 = true;
                        }
                        bool _e2004 = local_91;
                        if (_e2004) {
                            break;
                        }
                        float _e2005 = t_7;
                        vec3 p_27 = (rd_10 * _e2005);
                        float _e2007 = pl_col_base(cl, p_27);
                        if ((_e2007 > 40.0)) {
                            float _e2010 = t_7;
                            t_7 = ((_e2010 + _e2007) - 34.0);
                            continue;
                        }
                        float _e2014 = t_7;
                        float st = (max(3.5, (_e2014 * 0.008)) * (0.75 + (0.5 * _e1945)));
                        vec4 _e2025 = pl_col_sdf(cl, p_27, _e2007, true);
                        float ramp = clamp((-(_e2025.x) / (_e2025.z + (26.0 * soft_1))), 0.0, 1.0);
                        den = ((ramp * mix(clamp((0.15 + (1.7 * _e2025.w)), 0.0, 1.0), 1.0, (ramp * ramp))) * thin_1);
                        float _e2046 = den;
                        den = (_e2046 * smoothstep((lift_1 - 25.0), (lift_1 + 35.0), (p_27.y - C_7.y)));
                        if ((soft_1 > 0.0)) {
                            float _e2060 = den;
                            local_92 = (_e2060 > 0.002);
                        } else {
                            local_92 = false;
                        }
                        bool _e2064 = local_92;
                        if (_e2064) {
                            vec3 _e2068 = pl_wind();
                            float _e2079 = gnoise3_(((((p_27 + cam_6) * 0.09090909) - (_e2068 * (a_23 * 0.09))) + vec3(0.0, (-0.05 * a_23), 0.0)));
                            float _e2080 = den;
                            den = (_e2080 * mix(1.0, clamp((0.2 + (1.6 * _e2079)), 0.0, 1.0), soft_1));
                        }
                        float _e2089 = den;
                        if ((_e2089 > 0.002)) {
                            float _e2092 = tr_1;
                            if (!((_e2092 > 0.25))) {
                                int _e2098 = nl_2;
                                local_93 = (_e2098 == 0);
                            } else {
                                local_93 = true;
                            }
                            bool _e2102 = local_93;
                            if (_e2102) {
                                vec3 fp_3 = (p_27 + (L_2 * 5.0));
                                float _e2106 = pl_col_base(cl, fp_3);
                                vec4 _e2108 = pl_col_sdf(cl, fp_3, _e2106, false);
                                lc_face = (_e2108.x - _e2025.x);
                                float _e2115 = pl_col_base(cl, (p_27 + (L_2 * 11.0)));
                                float s1_2 = clamp(((8.0 - _e2115) / 22.0), 0.0, 1.0);
                                float _e2124 = pl_col_base(cl, (p_27 + (L_2 * 30.0)));
                                float s2_ = clamp(((8.0 - _e2124) / 30.0), 0.0, 1.0);
                                float _e2133 = pl_col_base(cl, (p_27 + (L_2 * 62.0)));
                                float s3_ = clamp(((6.0 - _e2133) / 40.0), 0.0, 1.0);
                                lc_bulk = exp((-((((s1_2 * 10.0) + (s2_ * 18.0)) + (s3_ * 22.0))) * 0.3));
                            }
                            int _e2151 = nl_2;
                            nl_2 = (_e2151 + 1);
                            float _e2154 = lc_face;
                            float lam = mix(clamp((0.2 + (_e2154 / 5.0)), 0.0, 1.0), 0.65, soft_1);
                            float _e2162 = lc_bulk;
                            float tsun = (mix(_e2162, 0.7, soft_1) * lam);
                            float hy_1 = clamp(((p_27.y - C_7.y) / max(_e1947, 1.0)), 0.0, 1.0);
                            float deep = clamp((-(_e2007) / 45.0), 0.0, 1.0);
                            float ao = mix(((0.65 + (0.35 * _e2025.y)) * (1.0 - (0.55 * deep))), 0.75, soft_1);
                            float mv = ((0.9 + (0.2 * (_e2025.w - 0.5))) + (0.25 * (_e2025.y - 0.5)));
                            vec3 alb_1 = (mix(vec3(0.56, 0.48, 0.39), vec3(0.53, 0.49, 0.44), smoothstep(0.05, 0.5, hy_1)) * mv);
                            vec3 _e2215 = skyl;
                            vec3 _e2216 = skyl;
                            vec3 skyg = (mix(mix(_e2215, vec3(dot(_e2216, vec3(0.2126, 0.7152, 0.0722))), 0.45), _e420, 0.15) * (1.0 - (0.35 * warm)));
                            c_16 = (alb_1 * (((skyg * ((0.48 * ao) * (0.3 + (0.7 * hy_1)))) + (((vec3(0.2, 0.17, 0.13) * day_2) * (1.0 - (0.6 * warm))) * ao)) + ((sunc * vec3(0.95, 0.85, 0.72)) * ((1.05 * tsun) * ph_1))));
                            float core_2 = exp((min(_e2007, 0.0) / 26.0));
                            float fire = ((exp((-(a_23) / 0.25)) * exp((-(max((p_27.y - C_7.y), 0.0)) / (16.0 + (40.0 * a_23))))) * core_2);
                            vec3 _e2287 = c_16;
                            c_16 = ((_e2287 * (1.0 - clamp((fire * 2.0), 0.0, 1.0))) + ((vec3(3.6, 1.25, 0.18) * (0.6 + (0.6 * _e2025.y))) * clamp((fire * 1.6), 0.0, 1.0)));
                            float _e2309 = den;
                            float ext = ((_e2309 * 0.4) * st);
                            float al_2 = (1.0 - exp(-(ext)));
                            vec3 _e2317 = acc_1;
                            float _e2318 = tr_1;
                            vec3 _e2320 = c_16;
                            acc_1 = (_e2317 + ((_e2318 * al_2) * _e2320));
                            float _e2323 = tmid;
                            float _e2324 = tr_1;
                            float _e2326 = t_7;
                            tmid = (_e2323 + ((_e2324 * al_2) * _e2326));
                            float _e2329 = wmid;
                            float _e2330 = tr_1;
                            wmid = (_e2329 + (_e2330 * al_2));
                            float _e2333 = tr_1;
                            tr_1 = (_e2333 * (1.0 - al_2));
                        }
                        float _e2337 = t_7;
                        int _e2345 = i_22;
                        t_7 = (_e2337 + ((_e2025.x > 0.0) ? max((0.55 * _e2025.x), (((0.12 * st) + 0.25) * min((1.0 + (0.06 * float(_e2345))), 2.5))) : st));
                    }
                }
                float _e2363 = tr_1;
                if ((_e2363 < 0.999)) {
                    float _e2366 = tmid;
                    float _e2367 = wmid;
                    float dist = (_e2366 / max(_e2367, 0.0001));
                    float _e2371 = tr_1;
                    if ((_e2371 < 0.5)) {
                        col_t = dist;
                    }
                    float ap_1 = (1.0 - exp((-(dist) / 2600.0)));
                    vec3 _e2380 = acc_1;
                    float _e2381 = tr_1;
                    vec3 ccol = mix((_e2380 / vec3(max((1.0 - _e2381), 0.0001))), haze_c, (ap_1 * 0.8));
                    if ((stage == 0u)) {
                        vec3 _e2393 = col_2;
                        float _e2394 = tr_1;
                        col_2 = mix(_e2393, ccol, (((1.0 - _e2394) * _e12) * fade));
                    } else {
                        float _e2400 = tr_1;
                        pl_over(hc, ccol, (((1.0 - _e2400) * _e12) * fade));
                    }
                }
            }
        }
    }
    if ((stage != 1u)) {
        local_94 = have;
    } else {
        local_94 = false;
    }
    bool _e2410 = local_94;
    if (_e2410) {
        local_95 = (_e7 > 2.8);
    } else {
        local_95 = false;
    }
    bool _e2416 = local_95;
    if (_e2416) {
        local_96 = (_e7 < 13.64);
    } else {
        local_96 = false;
    }
    bool _e2422 = local_96;
    if (_e2422) {
        vec3 _e2423 = pl_head(_e7);
        vec3 Hp = (_e2423 + C_7);
        float dh = length(Hp);
        vec3 hn = (Hp / vec3(dh));
        float cth_1 = dot(rd_10, hn);
        float th_2 = sqrt(max((2.0 * (1.0 - cth_1)), 0.0));
        vec3 _e2436 = project_rel(Hp);
        if ((_e2436.z > 0.0)) {
            local_97 = all(greaterThan(_e2436.xy, vec2(0.0)));
        } else {
            local_97 = false;
        }
        bool _e2450 = local_97;
        if (_e2450) {
            local_98 = all(lessThan(_e2436.xy, vec2(1.0)));
        } else {
            local_98 = false;
        }
        bool _e2459 = local_98;
        if (_e2459) {
            float _e2461 = depth_at(_e2436.xy);
            bool _e2462 = is_sky(_e2461);
            if (!(_e2462)) {
                vec3 _e2467 = world_offset(_e2436.xy, _e2461);
                local_99 = (length(_e2467) < (dh - 3.0));
            } else {
                local_99 = false;
            }
            bool _e2473 = local_99;
            if (_e2473) {
                vis = 0.0;
            }
        } else {
            if ((cth_1 < 0.0)) {
                vis = 0.0;
            }
        }
        float dive_1 = smoothstep(9.1, 11.400001, _e7);
        float show = smoothstep(2.8, 4.2, _e7);
        float flick_2 = (0.85 + ((0.15 * sin((_e7 * 37.0))) * sin(((_e7 * 23.0) + 1.0))));
        float size_1 = mix(1.6, 8.0, dive_1);
        float thc = max((size_1 / dh), (px_a * 0.9));
        vec3 hot_3 = mix(vec3(1.0, 0.96, 0.9), vec3(1.0, 0.62, 0.2), dive_1);
        float core_3 = (exp(-(pow((th_2 / thc), 2.0))) * mix(14.0, 9.0, dive_1));
        float bloom = (((0.9 / (1.0 + pow((th_2 / ((thc * 4.0) + 0.004)), 2.0))) + (0.18 * exp((-(th_2) / 0.05)))) * mix(1.0, 0.3, dive_1));
        vec3 sv_1 = (rd_10 - (hn * cth_1));
        vec3 up_6 = normalize((cross(cross(hn, vec3(0.0, 1.0, 0.0)), hn) + vec3(0.0, 1e-5, 0.0)));
        float streak_1 = (((exp((-(abs(dot(sv_1, up_6))) / (px_a * 1.5))) * exp((-(th_2) / 0.12))) * 0.25) * (1.0 - dive_1));
        vec3 _e2575 = col_2;
        float _e2580 = vis;
        col_2 = (_e2575 + (((((hot_3 * ((core_3 + bloom) + streak_1)) * show) * _e2580) * flick_2) * _e12));
    }
    if ((stage != 2u)) {
        local_100 = (a_23 > 0.0);
    } else {
        local_100 = false;
    }
    bool _e2592 = local_100;
    if (_e2592) {
        local_101 = (a_23 < 32.0);
    } else {
        local_101 = false;
    }
    bool _e2598 = local_101;
    if (_e2598) {
        float rf_1 = (PL_V * a_23);
        ylo = (min(C_7.y, me_3.y) - 6.0);
        yhi = (max(C_7.y, me_3.y) + 45.0);
        float _e2614 = pl_w(PL_HF);
        if ((_e2614 > 1.0)) {
            float _e2617 = ylo;
            float _e2620 = pl_w(1026u);
            ylo = min(_e2617, ((C_7.y + _e2620) - 6.0));
            float _e2625 = yhi;
            float _e2628 = pl_w(1027u);
            yhi = max(_e2625, ((C_7.y + _e2628) + 45.0));
        }
        if (!(_e154)) {
            vec3 sq = (_e159 - C_7);
            float _e2645 = pl_gref(length(sq.xz), me_3, C_7, dme_3);
            vec2 _e2646 = pl_land(sq.xz, _e2645);
            float off_3 = (sq.y - _e2646.x);
            float _e2650 = pl_w(1025u);
            float stp = ((2.0 * max(_e2650, 260.0)) / 95.0);
            loc_1 = vec4(sq.xz, clamp(off_3, -30.0, (2.5 + (0.1 * max((off_3 - 2.5), 0.0)))), ((stp * stp) * 0.6));
        }
        float _e2674 = col_t;
        t1_ = min(min(scene_len_3, _e2674), 1600.0);
        if ((abs(rd_10.y) > 1e-5)) {
            float _e2683 = ylo;
            float ya_1 = (_e2683 / rd_10.y);
            float _e2686 = yhi;
            float yb = (_e2686 / rd_10.y);
            float _e2689 = t0_;
            t0_ = max(_e2689, min(ya_1, yb));
            float _e2692 = t1_;
            t1_ = min(_e2692, max(ya_1, yb));
        } else {
            float _e2695 = ylo;
            if (!((_e2695 > 0.0))) {
                float _e2701 = yhi;
                local_102 = (_e2701 < 0.0);
            } else {
                local_102 = true;
            }
            bool _e2705 = local_102;
            if (_e2705) {
                t1_ = -1.0;
            }
        }
        float a2_ = max(dot(rd_10.xz, rd_10.xz), 1e-8);
        float bb = -(dot(rd_10.xz, C_7.xz));
        float cc = dot(C_7.xz, C_7.xz);
        float Ro = (rf_1 + 12.0);
        float Ri = max((rf_1 - 60.0), 0.0);
        float dout = ((bb * bb) - (a2_ * (cc - (Ro * Ro))));
        float din = ((bb * bb) - (a2_ * (cc - (Ri * Ri))));
        float _e2735 = t1_;
        float _e2736 = t0_;
        if ((_e2735 > _e2736)) {
            local_103 = (dout > 0.0);
        } else {
            local_103 = false;
        }
        bool _e2743 = local_103;
        if (_e2743) {
            float oa_2 = ((-(bb) - sqrt(dout)) / a2_);
            float ob_1 = ((-(bb) + sqrt(dout)) / a2_);
            seg = vec2[3](vec2(oa_2, ob_1), vec2(0.0, -1.0), vec2(0.0, -1.0));
            if ((din > 0.0)) {
                local_104 = (Ri > 0.0);
            } else {
                local_104 = false;
            }
            bool _e2773 = local_104;
            if (_e2773) {
                float ia = ((-(bb) - sqrt(din)) / a2_);
                float ib = ((-(bb) + sqrt(din)) / a2_);
                seg[0] = vec2(oa_2, ia);
                seg[1] = vec2(ib, ob_1);
                seg[2] = vec2(ia, ib);
                ns = int[3](12, 10, 6);
            }
            float _e2794 = t0_;
            float _e2795 = t1_;
            float mid_t = clamp((-(bb) / a2_), _e2794, _e2795);
            vec3 pm = ((rd_10 * mid_t) - C_7);
            float side_1 = clamp((abs(dot(normalize(rd_10.xz), (pm.xz / vec2(max(length(pm.xz), 1.0))))) * 1.6), 0.0, 1.0);
            float _e2828 = ign((in_1.position.xy + vec2(0.0, (fract((_e7 * 5.0)) * 53.0))));
            bool loop_init_17 = true;
            while(true) {
                if (!loop_init_17) {
                    int _e2966 = si;
                    si = (_e2966 + 1);
                }
                loop_init_17 = false;
                int _e2836 = si;
                if ((_e2836 < 3)) {
                } else {
                    break;
                }
                {
                    int _e2839 = si;
                    int k2_ = order[_e2839];
                    float _e2844 = seg[k2_].x;
                    float _e2845 = t0_;
                    float sa = max(_e2844, _e2845);
                    float _e2849 = seg[k2_].y;
                    float _e2850 = t1_;
                    float sb = min(_e2849, _e2850);
                    int n_6 = ns[k2_];
                    if (!((n_6 == 0))) {
                        local_105 = (sb <= sa);
                    } else {
                        local_105 = true;
                    }
                    bool _e2861 = local_105;
                    if (!(_e2861)) {
                        float _e2865 = tr_2;
                        local_106 = (_e2865 < 0.02);
                    } else {
                        local_106 = true;
                    }
                    bool _e2869 = local_106;
                    if (_e2869) {
                        continue;
                    }
                    i_23 = 0;
                    bool loop_init_18 = true;
                    while(true) {
                        if (!loop_init_18) {
                            int _e2963 = i_23;
                            i_23 = (_e2963 + 1);
                        }
                        loop_init_18 = false;
                        int _e2872 = i_23;
                        if ((_e2872 < n_6)) {
                        } else {
                            break;
                        }
                        {
                            int _e2874 = i_23;
                            float u0_ = ((float(_e2874) + _e2828) / float(n_6));
                            int _e2879 = i_23;
                            float u1_ = (((float(_e2879) + _e2828) + 1.0) / float(n_6));
                            float t_11 = (sa + (((sb - sa) * u0_) * u0_));
                            float dt_3 = ((sb - sa) * ((u1_ * u1_) - (u0_ * u0_)));
                            vec3 p_28 = (rd_10 * t_11);
                            vec4 _e2896 = loc_1;
                            vec2 _e2897 = pl_dust(p_28, C_7, a_23, me_3, dme_3, side_1, _e2896);
                            float den_3 = (_e2897.x * smoothstep(2.0, 30.0, t_11));
                            if ((den_3 <= 0.001)) {
                                continue;
                            }
                            float al_3 = (1.0 - exp(((-(den_3) * dt_3) * 0.3)));
                            float h_9 = _e2897.y;
                            vec3 wq = (p_28 + cam_6);
                            float _e2927 = gnoise3_(((wq * vec3(0.11111111, 0.16666667, 0.11111111)) + vec3(0.0, ((-1.2 * a_23) + 0.5), 0.0)));
                            float lo_4 = ((0.45 + (0.55 * clamp((h_9 / 8.0), 0.0, 1.0))) * (0.55 + (0.7 * _e2927)));
                            vec3 dc_1 = (vec3(0.62, 0.55, 0.34) * (((sunc * 0.75) * lo_4) + (amb * 0.6)));
                            vec3 _e2951 = acc_2;
                            float _e2952 = tr_2;
                            acc_2 = (_e2951 + ((_e2952 * al_3) * dc_1));
                            float _e2956 = tr_2;
                            tr_2 = (_e2956 * (1.0 - al_3));
                            float _e2960 = tr_2;
                            if ((_e2960 < 0.02)) {
                                break;
                            }
                        }
                    }
                }
            }
            if ((stage == 0u)) {
                vec3 _e2971 = col_2;
                vec3 _e2972 = col_2;
                float _e2973 = tr_2;
                vec3 _e2975 = acc_2;
                col_2 = mix(_e2971, ((_e2972 * _e2973) + _e2975), (_e12 * fade));
            } else {
                float kf = (_e12 * fade);
                vec4 _e2980 = hc;
                float _e2984 = tr_2;
                vec3 _e2988 = acc_2;
                float _e2992 = hc.w;
                float _e2995 = tr_2;
                hc = vec4(((_e2980.xyz * ((1.0 - kf) + (kf * _e2984))) + (_e2988 * kf)), (_e2992 * ((1.0 - kf) + (kf * _e2995))));
            }
        }
    }
    if ((stage == 1u)) {
        if ((a_23 > 0.0)) {
            local_107 = (a_23 < 16.0);
        } else {
            local_107 = false;
        }
        bool _e3011 = local_107;
        if (_e3011) {
            float _e3015 = pl_w(8u);
            local_108 = (_e3015 > 0.5);
        } else {
            local_108 = false;
        }
        bool _e3019 = local_108;
        if (_e3019) {
            low = (min(C_7.y, me_3.y) - 4.0);
            float _e3027 = pl_w(PL_HF);
            if ((_e3027 > 1.0)) {
                float _e3030 = low;
                float _e3033 = pl_w(1026u);
                low = min(_e3030, ((C_7.y + _e3033) - 4.0));
            }
            float _e3041 = _group_0_binding_4_fs.resolution.y;
            float _e3045 = _group_0_binding_4_fs.view_params.w;
            float fpx = (_e3041 / (2.0 * tan((_e3045 * 0.5))));
            float wpx = (1.0 / fpx);
            float eka_1 = exp((-0.06 * a_23));
            vec2 pxy = ((floor(in_1.position.xy) * 2.0) + vec2(1.0));
            bool loop_init_19 = true;
            while(true) {
                if (!loop_init_19) {
                    int _e3168 = i_24;
                    i_24 = (_e3168 + 1);
                }
                loop_init_19 = false;
                int _e3067 = i_24;
                if ((_e3067 < PL_DEBRIS)) {
                } else {
                    break;
                }
                {
                    int _e3070 = i_24;
                    PlChunk _e3071 = pl_chunk(_e3070, a_23, eka_1, C_7);
                    if (!((_e3071.live <= 0.0))) {
                        float _e3080 = low;
                        local_109 = (_e3071.p.y < _e3080);
                    } else {
                        local_109 = true;
                    }
                    bool _e3083 = local_109;
                    if (_e3083) {
                        continue;
                    }
                    float dist_1 = length(_e3071.p);
                    float off_4 = length((_e3071.p - (rd_10 * dot(_e3071.p, rd_10))));
                    if (!((dist_1 < 1.0))) {
                        local_110 = (off_4 > ((((_e3071.s * 4.5) + (length(_e3071.v) * 0.8)) + 1.5) + ((9.0 * dist_1) * wpx)));
                    } else {
                        local_110 = true;
                    }
                    bool _e3113 = local_110;
                    if (_e3113) {
                        continue;
                    }
                    vec3 _e3115 = project_rel(_e3071.p);
                    if ((_e3115.z < 0.0)) {
                        continue;
                    }
                    float rad_2 = max(((_e3071.s * fpx) / dist_1), 0.55);
                    float reach = ((smoothstep(0.45, 0.8, _e3071.s) > 0.0) ? (((rad_2 * 3.0) + (((length(_e3071.v) * 0.6) * fpx) / dist_1)) + 4.0) : (((rad_2 * 1.4) + (((length(_e3071.v) * 0.03) * fpx) / dist_1)) + 2.0));
                    vec4 _e3156 = _group_0_binding_4_fs.resolution;
                    if ((length((pxy - (_e3115.xy * _e3156.xy))) > (reach + 3.0))) {
                        continue;
                    }
                    float _e3164 = pl_chunk_up(_e3071, C_7, me_3, dme_3);
                    if ((_e3164 > 0.0)) {
                        near = 1.0;
                        break;
                    }
                }
            }
        }
        vec4 _e3171 = hc;
        float _e3174 = col_t;
        float _e3177 = near;
        return PlOut(_e3171, vec4(min(scene_len_3, 60000.0), min(_e3174, 60000.0), _e3177, 0.0));
    }
    if (!((stage == 0u))) {
        local_111 = (up_e.y > 0.0);
    } else {
        local_111 = true;
    }
    bool _e3190 = local_111;
    if (_e3190) {
        local_112 = (a_23 > 0.0);
    } else {
        local_112 = false;
    }
    bool _e3196 = local_112;
    if (_e3196) {
        local_113 = (a_23 < 16.0);
    } else {
        local_113 = false;
    }
    bool _e3202 = local_113;
    if (_e3202) {
        float _e3206 = pl_w(8u);
        local_114 = (_e3206 > 0.5);
    } else {
        local_114 = false;
    }
    bool _e3210 = local_114;
    if (_e3210) {
        float _e3214 = _group_0_binding_4_fs.resolution.y;
        float _e3218 = _group_0_binding_4_fs.view_params.w;
        float fpx_1 = (_e3214 / (2.0 * tan((_e3218 * 0.5))));
        vec2 pxy_1 = in_1.position.xy;
        float _e3227 = col_t;
        float lim = min(scene_len_3, _e3227);
        low_1 = (min(C_7.y, me_3.y) - 4.0);
        float _e3240 = pl_w(PL_HF);
        if ((_e3240 > 1.0)) {
            float _e3243 = low_1;
            float _e3246 = pl_w(1026u);
            low_1 = min(_e3243, ((C_7.y + _e3246) - 4.0));
        }
        float wpx_1 = (1.0 / fpx_1);
        float eka_2 = exp((-0.06 * a_23));
        bool loop_init_20 = true;
        while(true) {
            if (!loop_init_20) {
                int _e3513 = i_25;
                i_25 = (_e3513 + 1);
            }
            loop_init_20 = false;
            int _e3258 = i_25;
            if ((_e3258 < PL_DEBRIS)) {
            } else {
                break;
            }
            {
                int _e3261 = i_25;
                PlChunk _e3262 = pl_chunk(_e3261, a_23, eka_2, C_7);
                ch_1 = _e3262;
                float _e3265 = ch_1.live;
                if (!((_e3265 <= 0.0))) {
                    float _e3273 = ch_1.p.y;
                    float _e3274 = low_1;
                    local_115 = (_e3273 < _e3274);
                } else {
                    local_115 = true;
                }
                bool _e3277 = local_115;
                if (_e3277) {
                    continue;
                }
                vec3 _e3279 = ch_1.p;
                float dist_2 = length(_e3279);
                if (!((dist_2 > lim))) {
                    local_116 = (dist_2 < 1.0);
                } else {
                    local_116 = true;
                }
                bool _e3288 = local_116;
                if (_e3288) {
                    continue;
                }
                vec3 _e3290 = ch_1.p;
                vec3 _e3292 = ch_1.p;
                float off_5 = length((_e3290 - (rd_10 * dot(_e3292, rd_10))));
                float _e3298 = ch_1.s;
                vec3 _e3302 = ch_1.v;
                float reach_w = ((((_e3298 * 4.5) + (length(_e3302) * 0.8)) + 1.5) + ((6.0 * dist_2) * wpx_1));
                if ((off_5 > reach_w)) {
                    continue;
                }
                PlChunk _e3315 = ch_1;
                float _e3316 = pl_chunk_up(_e3315, C_7, me_3, dme_3);
                ch_1.live = _e3316;
                float _e3318 = ch_1.live;
                if ((_e3318 <= 0.0)) {
                    continue;
                }
                vec3 _e3322 = ch_1.p;
                vec3 _e3323 = project_rel(_e3322);
                if ((_e3323.z < 0.0)) {
                    continue;
                }
                vec4 _e3330 = _group_0_binding_4_fs.resolution;
                vec2 q0_ = (_e3323.xy * _e3330.xy);
                float _e3334 = ch_1.s;
                float rad_3 = max(((_e3334 * fpx_1) / dist_2), 0.55);
                float _e3340 = ch_1.s;
                float bigc = smoothstep(0.45, 0.8, _e3340);
                vec3 _e3347 = ch_1.v;
                vec3 _e3359 = ch_1.v;
                float reach_1 = ((bigc > 0.0) ? (((rad_3 * 3.0) + (((length(_e3359) * 0.6) * fpx_1) / dist_2)) + 4.0) : (((rad_3 * 1.4) + (((length(_e3347) * 0.03) * fpx_1) / dist_2)) + 2.0));
                if ((length((pxy_1 - q0_)) > reach_1)) {
                    continue;
                }
                vec3 _e3375 = ch_1.p;
                vec3 _e3377 = ch_1.v;
                vec3 _e3381 = project_rel((_e3375 - (_e3377 * 0.03)));
                vec4 _e3385 = _group_0_binding_4_fs.resolution;
                vec2 q1_3 = (_e3381.xy * _e3385.xy);
                vec2 ab_7 = (q1_3 - q0_);
                float w_12 = clamp((dot((pxy_1 - q0_), ab_7) / max(dot(ab_7, ab_7), 0.0001)), 0.0, 1.0);
                float e_12 = length((pxy_1 - (q0_ + (ab_7 * w_12))));
                int _e3402 = i_25;
                float _e3408 = pl_w(((PL_DB + (PL_DW * uint(_e3402))) + 8u));
                float spin = (a_23 * _e3408);
                float th_3 = atan((pxy_1.y - q0_.y), (pxy_1.x - q0_.x));
                int _e3419 = i_25;
                float lump_1 = ((1.0 + (0.28 * sin((((th_3 * 3.0) + float(_e3419)) + spin)))) + (0.12 * sin(((th_3 * 5.0) - (spin * 1.3)))));
                float _e3443 = ch_1.live;
                float c_27 = ((clamp((((rad_3 * lump_1) + 0.5) - e_12), 0.0, 1.0) * _e3443) * clamp((rad_3 / max((length(ab_7) * 0.5), rad_3)), 0.0, 1.0));
                float _e3452 = cov;
                cov = max(_e3452, c_27);
                if ((bigc > 0.0)) {
                    vec3 _e3457 = ch_1.p;
                    vec3 _e3459 = ch_1.v;
                    vec3 _e3468 = project_rel(((_e3457 - (_e3459 * 0.6)) + vec3(0.0, 1.2, 0.0)));
                    vec4 _e3472 = _group_0_binding_4_fs.resolution;
                    vec2 q2_2 = (_e3468.xy * _e3472.xy);
                    vec2 tb_2 = (q2_2 - q0_);
                    float u_23 = clamp((dot((pxy_1 - q0_), tb_2) / max(dot(tb_2, tb_2), 0.0001)), 0.0, 1.0);
                    float wd = ((rad_3 * (0.6 + (1.6 * u_23))) + 0.5);
                    float et = length((pxy_1 - (q0_ + (tb_2 * u_23))));
                    float _e3494 = smk;
                    float _e3506 = ch_1.live;
                    smk = max(_e3494, (((((clamp((1.0 - (et / wd)), 0.0, 1.0) * (1.0 - u_23)) * 0.45) * bigc) * _e3506) * step(0.5, _e3468.z)));
                }
            }
        }
        vec3 dirt = (vec3(0.035, 0.03, 0.026) * ((amb * 1.5) + (sunc * 0.3)));
        vec3 smoke = (vec3(0.28, 0.29, 0.31) * ((amb * 0.8) + (sunc * 0.25)));
        vec3 _e3536 = col_2;
        float _e3537 = smk;
        col_2 = mix(_e3536, smoke, ((_e3537 * _e12) * fade));
        vec3 _e3541 = col_2;
        float _e3542 = cov;
        col_2 = mix(_e3541, dirt, ((_e3542 * _e12) * fade));
    }
    if ((a_23 > 0.0)) {
        local_117 = (a_23 < 30.0);
    } else {
        local_117 = false;
    }
    bool _e3553 = local_117;
    if (_e3553) {
        float rc_1 = length(C_7.xz);
        float tau_4 = (a_23 - (rc_1 / PL_V));
        if ((tau_4 > -0.1)) {
            local_118 = (rc_1 > 50.0);
        } else {
            local_118 = false;
        }
        bool _e3566 = local_118;
        if (_e3566) {
            float _e3569 = pl_gref(rc_1, me_3, C_7, dme_3);
            vec2 _e3570 = pl_land(-(C_7.xz), _e3569);
            float hc_1 = (-(C_7.y) - _e3570.x);
            float E = (((((((smoothstep(-0.08, 0.05, tau_4) * ((0.6 * exp((-(tau_4) / 0.8))) + (0.4 * exp((-(tau_4) / 3.5))))) * smoothstep(40.0, 8.0, hc_1)) * smoothstep(2600.0, 900.0, rc_1)) * smoothstep(50.0, 110.0, rc_1)) * (1.0 - (0.55 * _e3570.y))) * fade) * _e12);
            if ((E > 0.002)) {
                vec3 dust_c = (vec3(0.5, 0.46, 0.4) * ((sunc * 0.55) + (amb * 0.8)));
                vec3 _e3624 = col_2;
                float lum = dot(_e3624, vec3(0.2126, 0.7152, 0.0722));
                vec3 _e3630 = col_2;
                col_2 = mix(_e3630, mix(vec3(lum), dust_c, 0.5), (0.22 * E));
                vec3 _e3637 = col_2;
                col_2 = (_e3637 * mix(vec3(1.0), vec3(1.03, 0.99, 0.93), E));
                vec2 pxy_2 = in_1.position.xy;
                vec4 _e3650 = _group_0_binding_4_fs.resolution;
                vec2 res = _e3650.xy;
                float _e3659 = gnoise3_(vec3((pxy_2 / vec2((0.15 * res.y))), 3.1));
                float _e3669 = gnoise3_(vec3((pxy_2 / vec2((0.07 * res.y))), 7.7));
                float film = ((_e3659 * 0.8) + (_e3669 * 0.2));
                vec3 _e3673 = col_2;
                col_2 = mix(_e3673, dust_c, ((0.12 * E) * smoothstep(0.35, 0.95, film)));
            }
            float vis_5 = ((((smoothstep(40.0, 8.0, hc_1) * smoothstep(2600.0, 900.0, rc_1)) * smoothstep(60.0, 140.0, rc_1)) * (1.0 - (0.5 * _e3570.y))) * _e12);
            if ((vis_5 > 0.0)) {
                local_119 = (tau_4 > 0.2);
            } else {
                local_119 = false;
            }
            bool _e3706 = local_119;
            if (_e3706) {
                vec2 pxy_3 = in_1.position.xy;
                vec4 _e3711 = _group_0_binding_4_fs.resolution;
                vec2 res_1 = _e3711.xy;
                bool loop_init_21 = true;
                while(true) {
                    if (!loop_init_21) {
                        uint _e3963 = i_26;
                        i_26 = (_e3963 + 1u);
                    }
                    loop_init_21 = false;
                    uint _e3719 = i_26;
                    if ((_e3719 < 14u)) {
                    } else {
                        break;
                    }
                    {
                        uint _e3722 = i_26;
                        float _e3724 = mh(_e3722, seed_20, 976u);
                        float t0_2 = (0.25 + (1.4 * _e3724));
                        float age_3 = (tau_4 - t0_2);
                        if ((age_3 <= 0.0)) {
                            continue;
                        }
                        uint _e3732 = i_26;
                        float _e3734 = mh(_e3732, seed_20, 977u);
                        uint _e3739 = i_26;
                        float _e3741 = mh(_e3739, seed_20, 978u);
                        vec2 c_28 = (vec2((0.03 + (0.94 * _e3734)), (0.02 + (0.4 * pow(_e3741, 1.3)))) * res_1);
                        uint _e3750 = i_26;
                        float _e3752 = mh(_e3750, seed_20, 979u);
                        float r_17 = ((0.011 + (0.026 * pow(_e3752, 0.8))) * res_1.y);
                        vec2 d0_1 = (pxy_3 - c_28);
                        if ((dot(d0_1, d0_1) > ((16.0 * r_17) * r_17))) {
                            continue;
                        }
                        uint _e3770 = i_26;
                        float _e3772 = mh(_e3770, seed_20, 980u);
                        float life = (smoothstep(0.0, 0.08, age_3) * (1.0 - smoothstep(6.0, 16.0, (age_3 + (4.0 * _e3772)))));
                        j_5 = 0u;
                        bool loop_init_22 = true;
                        while(true) {
                            if (!loop_init_22) {
                                uint _e3960 = j_5;
                                j_5 = (_e3960 + 1u);
                            }
                            loop_init_22 = false;
                            uint _e3784 = j_5;
                            if ((_e3784 < 4u)) {
                            } else {
                                break;
                            }
                            {
                                uint _e3787 = i_26;
                                uint _e3790 = j_5;
                                float _e3793 = mh(((_e3787 * 7u) + _e3790), seed_20, 992u);
                                uint _e3794 = j_5;
                                if ((_e3794 > 0u)) {
                                    local_120 = (_e3793 > 0.3);
                                } else {
                                    local_120 = false;
                                }
                                bool _e3802 = local_120;
                                if (_e3802) {
                                    continue;
                                }
                                uint _e3803 = i_26;
                                uint _e3806 = j_5;
                                uint k2_1 = ((_e3803 * 7u) + _e3806);
                                float _e3809 = mh(k2_1, seed_20, 993u);
                                uint _e3815 = j_5;
                                float rj = ((_e3815 == 0u) ? r_17 : (r_17 * (0.22 + (0.3 * _e3809))));
                                float _e3821 = mh(k2_1, seed_20, 994u);
                                float ang_5 = (TAU * _e3821);
                                float _e3828 = mh(k2_1, seed_20, 995u);
                                uint _e3835 = j_5;
                                vec2 cj = ((_e3835 == 0u) ? c_28 : (c_28 + ((vec2(cos(ang_5), sin(ang_5)) * r_17) * (1.4 + (0.9 * _e3828)))));
                                vec2 dj = (pxy_3 - cj);
                                float _e3842 = mh(k2_1, seed_20, 996u);
                                float rot_1 = (TAU * _e3842);
                                float cr_1 = cos(rot_1);
                                float sr = sin(rot_1);
                                float _e3857 = mh(k2_1, seed_20, 997u);
                                float stretch_1 = (1.0 + ((mix(0.4, 0.06, smoothstep(0.012, 0.03, (rj / res_1.y))) * 2.0) * _e3857));
                                vec2 e_13 = vec2((((dj.x * cr_1) + (dj.y * sr)) / stretch_1), ((-(dj.x) * sr) + (dj.y * cr_1)));
                                float th_4 = atan(e_13.y, e_13.x);
                                float _e3879 = mh(k2_1, seed_20, 998u);
                                float ph_2 = (TAU * _e3879);
                                float q_21 = ((length(e_13) / rj) * ((1.0 + (0.05 * sin(((3.0 * th_4) + ph_2)))) + (0.035 * sin(((5.0 * th_4) - (2.0 * ph_2))))));
                                if ((q_21 >= 1.4)) {
                                    continue;
                                }
                                float body = (1.0 - smoothstep(0.3, 1.38, q_21));
                                float ring_1 = (body * mix(0.9, 1.15, smoothstep(0.1, 0.8, q_21)));
                                float _e3923 = gnoise3_(vec3((e_13 / vec2((0.8 * rj))), float((k2_1 % 97u))));
                                float mott = (0.94 + (0.12 * _e3923));
                                float _e3929 = mh(k2_1, seed_20, 999u);
                                uint _e3936 = j_5;
                                float op = ((0.14 + (0.34 * pow(_e3929, 0.7))) * ((_e3936 == 0u) ? 1.0 : 0.85));
                                float _e3943 = keep;
                                keep = (_e3943 * (1.0 - (((ring_1 * mott) * op) * life)));
                                float _e3950 = shine;
                                shine = (_e3950 + (((body * smoothstep(0.3, -0.9, (dj.y / rj))) * op) * life));
                            }
                        }
                    }
                }
                vec3 _e3966 = col_2;
                float _e3967 = keep;
                float _e3984 = shine;
                col_2 = ((_e3966 * mix(1.0, _e3967, (vis_5 * fade))) + (((((vec3(0.42, 0.38, 0.33) * ((sunc * 0.45) + (amb * 0.9))) * 0.4) * min(_e3984, 1.0)) * vis_5) * fade));
            }
        }
    }
    vec3 _e3991 = col_2;
    vec3 _e3995 = linear_to_srgb(max(_e3991, vec3(0.0)));
    float _e3996 = capture();
    if ((_e3996 > 2.5)) {
        vec2 sp = floor(in_1.position.xy);
        float chk = fract(((sp.x + sp.y) * 0.5));
        float ycc_y = ((_e3995.y * 0.5) + ((_e3995.x + _e3995.z) * 0.25));
        float ycc_co = (_e3995.x - _e3995.z);
        float ycc_cg = (_e3995.y - ((_e3995.x + _e3995.z) * 0.5));
        return PlOut(vec4(ycc_y, ((((chk < 0.25) ? ycc_co : ycc_cg) * 0.5) + 0.5), 0.0, 1.0), vec4(0.0));
    }
    return PlOut(vec4(_e3995, 1.0), vec4(0.0));
}

void main() {
    StageIn in_ = StageIn(gl_FragCoord, _vs2fs_location0);
    PlOut _e7 = payload(in_, 0u, vec4(0.0), vec2(1000000000.0, 1.0));
    _fs2p_location0 = _e7.c;
    return;
}

