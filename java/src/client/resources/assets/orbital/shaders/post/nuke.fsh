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
struct PlChunk {
    vec3 p;
    vec3 v;
    float s;
    float live;
};
struct PlCol {
    float a;
    vec3 C;
    float hc;
    float Rt;
    float rt;
    float st;
    vec3 sr;
    vec3 ring;
    vec3 surge;
    vec3 lo;
    vec3 hi;
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
const float PL_SEEN = 0.8;
const float PL_COOL = 6.0;
const float PL_DIVE = 8.0;
const float PL_HIT = 11.0;
const float PL_BURST = 12.0;
const float PL_LEN = 90.0;
const float PL_FADE = 10.0;
const float PL_SOFT0_ = 48.0;
const float PL_SOFT1_ = 72.0;
const float PL_CHURN = 7.0;
const float PL_V = 343.0;
const uint PL_P = 16u;
const uint PL_PF = 400u;
const uint PL_PW = 8u;
const uint PL_HF = 1024u;
const uint PL_FR = 560u;
const uint PL_FW = 12u;
const int PL_DEBRIS = 160;
const uint PL_DB = 10496u;
const uint PL_DW = 10u;
const float NK_BS = 1.3;
const float PL_DM = 70.0;

uniform sampler2D _group_0_binding_0_fs;

uniform sampler2D _group_0_binding_1_fs;


vec4 orbitalSceneLod(sampler2D s, vec2 uv, float lod) {
    return textureLod(s, vec2(uv.x, 1.0 - uv.y), lod);
}

layout(std140) uniform Frame_block_0Fragment { Frame _group_0_binding_4_fs; };

uniform usampler2D _group_0_binding_5_fs;

vec2 pl_px = vec2(0.0);

layout(location = 0) in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

uint md_len() {
    uvec2 d_9 = uvec2(textureSize(_group_0_binding_5_fs, 0).xy);
    return (d_9.x * d_9.y);
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
    float n_4 = _group_0_binding_4_fs.view_params.x;
    float f_11 = _group_0_binding_4_fs.view_params.y;
    return ((n_4 * f_11) / ((depth_1 * (f_11 - n_4)) + n_4));
}

vec3 view_position(vec2 uv_1, float depth_2) {
    vec4 ndc = vec4(((uv_1.x * 2.0) - 1.0), (1.0 - (uv_1.y * 2.0)), depth_2, 1.0);
    mat4x4 _e16 = _group_0_binding_4_fs.inverse_projection;
    vec4 p_28 = (_e16 * ndc);
    return (p_28.xyz / vec3(p_28.w));
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
    int i_26 = int((_e5 + 0.5));
    if ((i_26 <= 0)) {
        return c_3;
    }
    switch(i_26) {
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
    vec2 i_27 = floor(p_2);
    vec2 f_12 = fract(p_2);
    vec2 u_7 = ((f_12 * f_12) * (vec2(3.0) - (2.0 * f_12)));
    float _e10 = hash21_(i_27);
    float _e15 = hash21_((i_27 + vec2(1.0, 0.0)));
    float _e20 = hash21_((i_27 + vec2(0.0, 1.0)));
    float _e25 = hash21_((i_27 + vec2(1.0, 1.0)));
    return mix(mix(_e10, _e15, u_7.x), mix(_e20, _e25, u_7.x), u_7.y);
}

float fbm(vec2 p_3) {
    vec2 o_6 = vec2(17.3, 9.1);
    vec2 q1_ = ((p_3 * 2.03) + o_6);
    vec2 q2_ = ((q1_ * 2.03) + o_6);
    vec2 q3_ = ((q2_ * 2.03) + o_6);
    vec2 q4_ = ((q3_ * 2.03) + o_6);
    float _e16 = vnoise(p_3);
    float _e19 = vnoise(q1_);
    float _e23 = vnoise(q2_);
    float _e27 = vnoise(q3_);
    float _e31 = vnoise(q4_);
    return (((((0.5 * _e16) + (0.25 * _e19)) + (0.125 * _e23)) + (0.0625 * _e27)) + (0.03125 * _e31));
}

float vnoise3_(vec3 p_4) {
    vec3 i_28 = floor(p_4);
    vec3 f_13 = fract(p_4);
    vec3 u_8 = ((f_13 * f_13) * (vec3(3.0) - (2.0 * f_13)));
    float _e10 = hash31_(i_28);
    float _e16 = hash31_((i_28 + vec3(1.0, 0.0, 0.0)));
    float a_18 = mix(_e10, _e16, u_8.x);
    float _e24 = hash31_((i_28 + vec3(0.0, 1.0, 0.0)));
    float _e30 = hash31_((i_28 + vec3(1.0, 1.0, 0.0)));
    float b_8 = mix(_e24, _e30, u_8.x);
    float _e38 = hash31_((i_28 + vec3(0.0, 0.0, 1.0)));
    float _e44 = hash31_((i_28 + vec3(1.0, 0.0, 1.0)));
    float c_18 = mix(_e38, _e44, u_8.x);
    float _e52 = hash31_((i_28 + vec3(0.0, 1.0, 1.0)));
    float _e58 = hash31_((i_28 + vec3(1.0, 1.0, 1.0)));
    float d_10 = mix(_e52, _e58, u_8.x);
    return mix(mix(a_18, b_8, u_8.y), mix(c_18, d_10, u_8.y), u_8.z);
}

float fbm3_(vec3 p_5) {
    vec3 q_11 = ((p_5 * 2.07) + vec3(5.1, 1.3, 7.7));
    vec3 r_6 = ((q_11 * 2.11) + vec3(2.9, 8.3, 4.1));
    float _e15 = vnoise3_(p_5);
    float _e18 = vnoise3_(q_11);
    float _e22 = vnoise3_(r_6);
    return (((0.55 * _e15) + (0.3 * _e18)) + (0.15 * _e22));
}

uint pcg(uint x) {
    uint s_6 = ((x * 747796405u) + 2891336453u);
    uint w_4 = (((s_6 >> ((s_6 >> 28u) + 4u)) ^ s_6) * 277803737u);
    return ((w_4 >> 22u) ^ w_4);
}

float fh21_(vec2 p_6) {
    uvec2 q_12 = uvec2(ivec2(floor(p_6)));
    uint _e6 = pcg(q_12.y);
    uint _e8 = pcg((q_12.x ^ _e6));
    return (float(_e8) * 2.3283064e-10);
}

float fh31_(vec3 p_7) {
    uvec3 q_13 = uvec3(ivec3(floor(p_7)));
    uint _e7 = pcg(q_13.z);
    uint _e9 = pcg((q_13.y ^ _e7));
    uint _e11 = pcg((q_13.x ^ _e9));
    return (float(_e11) * 2.3283064e-10);
}

float fvnoise(vec2 p_8) {
    vec2 i_29 = floor(p_8);
    vec2 f_14 = fract(p_8);
    vec2 u_9 = ((f_14 * f_14) * (vec2(3.0) - (2.0 * f_14)));
    float _e10 = fh21_(i_29);
    float _e15 = fh21_((i_29 + vec2(1.0, 0.0)));
    float _e22 = fh21_((i_29 + vec2(0.0, 1.0)));
    float _e27 = fh21_((i_29 + vec2(1.0, 1.0)));
    return mix(mix(_e10, _e15, u_9.x), mix(_e22, _e27, u_9.x), u_9.y);
}

float ffbm(vec2 p_9) {
    float _e1 = fvnoise(p_9);
    float _e10 = fvnoise(((p_9 * 2.03) + vec2(17.3, 9.1)));
    float _e20 = fvnoise(((p_9 * 4.1) + vec2(3.1, 5.7)));
    return (((0.55 * _e1) + (0.3 * _e10)) + (0.15 * _e20));
}

float fvnoise3_(vec3 p_10) {
    vec3 i_30 = floor(p_10);
    vec3 f_15 = fract(p_10);
    vec3 u_10 = ((f_15 * f_15) * (vec3(3.0) - (2.0 * f_15)));
    float _e10 = fh31_(i_30);
    float _e16 = fh31_((i_30 + vec3(1.0, 0.0, 0.0)));
    float a_19 = mix(_e10, _e16, u_10.x);
    float _e24 = fh31_((i_30 + vec3(0.0, 1.0, 0.0)));
    float _e30 = fh31_((i_30 + vec3(1.0, 1.0, 0.0)));
    float b_9 = mix(_e24, _e30, u_10.x);
    float _e38 = fh31_((i_30 + vec3(0.0, 0.0, 1.0)));
    float _e44 = fh31_((i_30 + vec3(1.0, 0.0, 1.0)));
    float c_19 = mix(_e38, _e44, u_10.x);
    float _e52 = fh31_((i_30 + vec3(0.0, 1.0, 1.0)));
    float _e58 = fh31_((i_30 + vec3(1.0, 1.0, 1.0)));
    float d_11 = mix(_e52, _e58, u_10.x);
    return mix(mix(a_19, b_9, u_10.y), mix(c_19, d_11, u_10.y), u_10.z);
}

float ffbm3_(vec3 p_11) {
    float _e1 = fvnoise3_(p_11);
    float _e11 = fvnoise3_(((p_11 * 2.07) + vec3(5.1, 1.3, 7.7)));
    return ((0.62 * _e1) + (0.38 * _e11));
}

vec3 lava_ramp(float x_1) {
    vec3 c_4 = vec3(0.0);
    float h_3 = clamp(x_1, 0.0, 1.0);
    c_4 = mix(vec3(0.02, 0.0, 0.0), vec3(0.7, 0.05, 0.0), smoothstep(0.0, 0.3, h_3));
    vec3 _e15 = c_4;
    c_4 = mix(_e15, vec3(1.0, 0.38, 0.02), smoothstep(0.25, 0.55, h_3));
    vec3 _e24 = c_4;
    c_4 = mix(_e24, vec3(1.0, 0.85, 0.35), smoothstep(0.5, 0.8, h_3));
    vec3 _e33 = c_4;
    c_4 = mix(_e33, vec3(1.0, 1.0, 1.0), smoothstep(0.8, 1.0, h_3));
    vec3 _e42 = c_4;
    return _e42;
}

vec3 gold_ramp(float x_2) {
    vec3 c_5 = vec3(0.0);
    float h_4 = clamp(x_2, 0.0, 1.0);
    c_5 = mix(vec3(0.12, 0.05, 0.0), vec3(0.85, 0.45, 0.05), smoothstep(0.0, 0.3, h_4));
    vec3 _e15 = c_5;
    c_5 = mix(_e15, vec3(1.0, 0.82, 0.3), smoothstep(0.25, 0.6, h_4));
    vec3 _e24 = c_5;
    c_5 = mix(_e24, vec3(1.0, 0.98, 0.9), smoothstep(0.6, 1.0, h_4));
    vec3 _e33 = c_5;
    return _e33;
}

vec3 plasma_ramp(float x_3) {
    vec3 c_6 = vec3(0.0);
    float h_5 = clamp(x_3, 0.0, 1.0);
    c_6 = mix(vec3(0.0), vec3(0.35, 0.08, 0.6), smoothstep(0.05, 0.3, h_5));
    vec3 _e13 = c_6;
    c_6 = mix(_e13, vec3(0.3, 0.6, 2.2), smoothstep(0.25, 0.55, h_5));
    vec3 _e22 = c_6;
    c_6 = mix(_e22, vec3(1.2, 2.0, 3.0), smoothstep(0.5, 0.8, h_5));
    vec3 _e31 = c_6;
    c_6 = mix(_e31, vec3(4.0, 4.0, 4.2), smoothstep(0.8, 1.0, h_5));
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
    float c_20 = cos(_e0);
    float s_7 = sin(_e0);
    return vec4(c_20, s_7, -(s_7), c_20);
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
    float n2_3 = ((_e23 - 0.5) * 2.0);
    float _e36 = vnoise(vec2(((u * 41.0) + (seed * 5.3)), (tq * 2.3)));
    float n3_1 = ((_e36 - 0.5) * 2.0);
    return ((((n1_1 * amp) + ((n2_3 * amp) * 0.38)) + ((n3_1 * amp) * 0.12)) * smoothstep(0.0, 0.1, u));
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
    float d_12 = length(vec2(off_1, along));
    float w_5 = (wid * (1.0 - (0.75 * u_11)));
    float core_1 = exp(-(pow((d_12 / w_5), 2.0)));
    float g_1 = (1.0 / (1.0 + pow((d_12 / (w_5 * 3.0)), 2.0)));
    return vec3(core_1, (g_1 * g_1), u_11);
}

vec2 seg_soft(vec2 p_14, vec2 a_2, vec2 b_2, float w) {
    vec2 ab_1 = (b_2 - a_2);
    float l2_ = max(dot(ab_1, ab_1), 1e-8);
    float u_12 = clamp((dot((p_14 - a_2), ab_1) / l2_), 0.0, 1.0);
    float d_13 = length((p_14 - (a_2 + (ab_1 * u_12))));
    float ww = (w * (1.0 - (0.65 * u_12)));
    return vec2(exp(-(pow((d_13 / ww), 2.0))), (1.0 / (1.0 + pow((d_13 / (ww * 4.0)), 2.0))));
}

float tri_line(float r, float ang, float R, float w_1) {
    float a_20 = (ang - (floor(((ang / 2.0943952) + 0.5)) * 2.0943952));
    float d_14 = ((r * cos(a_20)) - (R * 0.5));
    return (exp(-(pow((d_14 / w_1), 2.0))) * (1.0 - smoothstep((R * 0.98), (R * 1.04), r)));
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
    vec3 q_14 = (d_1 * 140.0);
    vec3 f_16 = (fract(q_14) - vec3(0.5));
    float _e11 = fh31_((floor(q_14) + vec3(seed_2)));
    float star = ((step(0.975, _e11) * exp((-(dot(f_16, f_16)) * 40.0))) * (0.5 + (4.0 * fract((_e11 * 37.0)))));
    vec3 tint = mix(vec3(0.7, 0.8, 1.25), vec3(1.25, 0.9, 0.7), fract((_e11 * 91.0)));
    float _e46 = ffbm3_(((d_1 * 2.6) + vec3((seed_2 * 0.01))));
    float _e54 = ffbm3_(((d_1 * 6.0) - vec3(2.0, 0.0, 1.0)));
    vec3 haze_2 = ((vec3(0.1, 0.02, 0.17) * smoothstep(0.4, 0.85, _e46)) + (vec3(0.02, 0.04, 0.13) * smoothstep(0.5, 0.9, _e54)));
    return ((tint * star) + haze_2);
}

vec3 disk_ramp(float x_5) {
    vec3 c_8 = vec3(0.0);
    float h_6 = clamp(x_5, 0.0, 1.0);
    c_8 = mix(vec3(0.0), vec3(0.7, 0.07, 0.02), smoothstep(0.0, 0.25, h_6));
    vec3 _e13 = c_8;
    c_8 = mix(_e13, vec3(2.4, 0.75, 0.12), smoothstep(0.2, 0.5, h_6));
    vec3 _e22 = c_8;
    c_8 = mix(_e22, vec3(3.4, 2.5, 1.35), smoothstep(0.45, 0.75, h_6));
    vec3 _e31 = c_8;
    c_8 = mix(_e31, vec3(3.2, 3.6, 5.0), smoothstep(0.75, 1.0, h_6));
    vec3 _e40 = c_8;
    return _e40;
}

vec3 bh_scene(vec2 uvs, vec3 dir, float seed_3, float sky_env, float dim) {
    vec4 _e8 = orbitalSceneLod(_group_0_binding_0_fs, vec2(uvs), 0.0);
    vec3 _e10 = srgb_to_linear(_e8.xyz);
    vec3 c_21 = (_e10 * dim);
    float _e12 = depth_at(uvs);
    bool _e13 = is_sky(_e12);
    if (_e13) {
        vec3 _e14 = bh_sky(dir, seed_3);
        return mix(c_21, _e14, (sky_env * 0.94));
    }
    return c_21;
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
    float c_22 = cos(ang_1);
    float s_8 = sin(ang_1);
    return (((v_3 * c_22) + (cross(a_3, v_3) * s_8)) + ((a_3 * dot(a_3, v_3)) * (1.0 - c_22)));
}

float bh_fall(float r0_, float u_1) {
    return (r0_ * pow(max((1.0 - (u_1 * u_1)), 0.0), 0.6667));
}

float bh_tide(float r0_1, float l0_, float r_1, float u_2, float lag) {
    float _e7 = bh_fall((r0_1 + l0_), (u_2 / lag));
    return clamp(((_e7 - r_1) / l0_), 1.0, 6.0);
}

float bh_tide_max(float r0_2, float l0_1, float r_2, float u_3, float lag_1) {
    float rt_2 = ((((r0_2 + l0_1) / r0_2) * r_2) * (1.0 + ((((1.3333 * u_3) * u_3) * (1.0 - (1.0 / lag_1))) / max((1.0 - (u_3 * u_3)), 0.0001))));
    return ((u_3 > 0.97) ? 6.0 : clamp(((rt_2 - r_2) / l0_1), 1.0, 6.0));
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
    float th_1 = (_e31 - (((3.0 + (3.0 * _e37)) * u_13) * u_13));
    float lift = smoothstep(0.0, 0.45, u_13);
    vec2 src = (floor((tgt.xz + (vec2(cos(_e31), sin(_e31)) * _e32))) + (_e33 ? vec2(0.0) : vec2(0.5)));
    float _e113 = block_y();
    float gy = (_e113 + (_e33 ? 0.0 : 0.5));
    vec3 ground = (vec3(src.x, gy, src.y) - cam);
    vec3 ground_r = (vec3((tgt.x - cam.x), (gy - cam.y), (tgt.z - cam.z)) + (vec3(cos(th_1), 0.0, sin(th_1)) * _e89));
    vec3 gp = mix(ground, ground_r, smoothstep(0.0, 0.15, u_13));
    vec3 dp = (H_1 + (((E1_ * cos(th_1)) + (E2_ * sin(th_1))) * _e89));
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
        vec3 tdir = ((E1_ * sin(th_1)) - (E2_ * cos(th_1)));
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
                float r2_1 = (r_7 * r_7);
                vec3 _e116 = v_4;
                vec3 _e119 = pp;
                v_4 = normalize((_e116 - ((((1.5 * h2_) * _e119) / vec3(((r2_1 * r2_1) * r_7))) * dt_1)));
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
                    float dr_1 = length(x_10);
                    if ((dr_1 > 2.34)) {
                        local_12 = (dr_1 < DISK_OUT);
                    } else {
                        local_12 = false;
                    }
                    bool _e167 = local_12;
                    if (_e167) {
                        vec2 dx = vec2(dot(x_10, e1_), dot(x_10, e2_));
                        float rot = ((-(time) * 5.5) / pow(dr_1, 1.5));
                        vec2 q_15 = vec2(((dx.x * cos(rot)) - (dx.y * sin(rot))), ((dx.x * sin(rot)) + (dx.y * cos(rot))));
                        float _e197 = fbm(((q_15 * 0.9) + vec2(seed_9, 3.0)));
                        float bands = (0.55 + (0.45 * sin(((dr_1 * 7.0) + (_e197 * 7.0)))));
                        float dens = clamp((bands * (0.35 + (1.1 * _e197))), 0.0, 1.0);
                        float edge = (smoothstep(2.34, 2.9899998, dr_1) * (1.0 - smoothstep(4.9500003, DISK_OUT, dr_1)));
                        vec3 tdir_1 = normalize(cross(n_1, x_10));
                        float beta = (0.62 * sqrt((DISK_IN / dr_1)));
                        vec3 _e234 = v_4;
                        float g_2 = (sqrt((1.0 - (beta * beta))) / (1.0 - (beta * dot(tdir_1, -(_e234)))));
                        float temp = ((((pow((DISK_IN / dr_1), 0.85) * (0.7 + (0.4 * _e197))) * g_2) * 0.95) * hot);
                        float a_d = (clamp(((dens * edge) * 1.1), 0.0, 1.0) * disk_env);
                        vec3 _e259 = acc;
                        float _e260 = trans;
                        vec3 _e262 = disk_ramp(temp);
                        acc = (_e259 + ((((_e260 * a_d) * _e262) * min(((g_2 * g_2) * g_2), 4.0)) * 1.6));
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
    vec3 i_31 = floor(p_15);
    vec3 f_17 = (p_15 - i_31);
    vec3 u_14 = (((f_17 * f_17) * f_17) * ((f_17 * ((f_17 * 6.0) - vec3(15.0))) + vec3(10.0)));
    vec3 _e15 = grad3_(i_31);
    float n000_ = dot(_e15, f_17);
    vec3 _e22 = grad3_((i_31 + vec3(1.0, 0.0, 0.0)));
    float n100_ = dot(_e22, (f_17 - vec3(1.0, 0.0, 0.0)));
    vec3 _e34 = grad3_((i_31 + vec3(0.0, 1.0, 0.0)));
    float n010_ = dot(_e34, (f_17 - vec3(0.0, 1.0, 0.0)));
    vec3 _e46 = grad3_((i_31 + vec3(1.0, 1.0, 0.0)));
    float n110_ = dot(_e46, (f_17 - vec3(1.0, 1.0, 0.0)));
    vec3 _e58 = grad3_((i_31 + vec3(0.0, 0.0, 1.0)));
    float n001_ = dot(_e58, (f_17 - vec3(0.0, 0.0, 1.0)));
    vec3 _e70 = grad3_((i_31 + vec3(1.0, 0.0, 1.0)));
    float n101_ = dot(_e70, (f_17 - vec3(1.0, 0.0, 1.0)));
    vec3 _e82 = grad3_((i_31 + vec3(0.0, 1.0, 1.0)));
    float n011_ = dot(_e82, (f_17 - vec3(0.0, 1.0, 1.0)));
    vec3 _e94 = grad3_((i_31 + vec3(1.0, 1.0, 1.0)));
    float n111_ = dot(_e94, (f_17 - vec3(1.0, 1.0, 1.0)));
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
    mat3x3 m_2 = mat3x3(vec3(0.0, 0.8, 0.6), vec3(-0.8, 0.36, -0.48), vec3(-0.6, -0.48, 0.64));
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
            q_1 = (((m_2 * _e35) * 2.03) + vec3(1.7, 9.2, 5.3));
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
    vec2 i_32 = floor(p_17);
    vec2 f_18 = (p_17 - i_32);
    vec2 u_15 = (((f_18 * f_18) * f_18) * ((f_18 * ((f_18 * 6.0) - vec2(15.0))) + vec2(10.0)));
    vec2 _e15 = grad2_(i_32);
    float a_21 = dot(_e15, f_18);
    vec2 _e21 = grad2_((i_32 + vec2(1.0, 0.0)));
    float b_11 = dot(_e21, (f_18 - vec2(1.0, 0.0)));
    vec2 _e31 = grad2_((i_32 + vec2(0.0, 1.0)));
    float c_23 = dot(_e31, (f_18 - vec2(0.0, 1.0)));
    vec2 _e41 = grad2_((i_32 + vec2(1.0, 1.0)));
    float d_15 = dot(_e41, (f_18 - vec2(1.0, 1.0)));
    return ((mix(mix(a_21, b_11, u_15.x), mix(c_23, d_15, u_15.x), u_15.y) * 0.9) + 0.5);
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

float mh(uint i_7, uint seed_10, uint k_2) {
    uint _e3 = pcg(k_2);
    uint _e5 = pcg((seed_10 ^ _e3));
    uint _e7 = pcg((i_7 ^ _e5));
    return (float(_e7) * 2.3283064e-10);
}

vec3 met_where(float fi_4, float seed_11) {
    uint i_33 = uint(fi_4);
    uint s_10 = uint(seed_11);
    float _e5 = mh(i_33, s_10, 5u);
    if ((_e5 < 0.33)) {
        float _e10 = mh(i_33, s_10, 6u);
        uint c_24 = (100u + min(uint((_e10 * 6.0)), 5u));
        float _e18 = mh(c_24, s_10, 1u);
        float ca = (_e18 * TAU);
        float _e23 = mh(c_24, s_10, 2u);
        float cr = (24.0 + (90.0 * sqrt(_e23)));
        float _e29 = mh(i_33, s_10, 7u);
        float oa_1 = (_e29 * TAU);
        float _e33 = mh(i_33, s_10, 8u);
        float orr = (3.0 + (11.0 * _e33));
        vec2 pos = ((vec2(cos(ca), sin(ca)) * cr) + (vec2(cos(oa_1), sin(oa_1)) * orr));
        float _e48 = mh(c_24, s_10, 3u);
        float _e54 = mh(i_33, s_10, 9u);
        return vec3(pos, ((3.0 + (8.5 * _e48)) + (1.4 * _e54)));
    }
    float _e60 = mh(i_33, s_10, 1u);
    float a_22 = (_e60 * TAU);
    float _e65 = mh(i_33, s_10, 2u);
    float r_8 = (14.0 + (106.0 * sqrt(_e65)));
    float _e75 = mh(i_33, s_10, 3u);
    return vec3((cos(a_22) * r_8), (sin(a_22) * r_8), (2.5 + (9.5 * _e75)));
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
    vec2 a_23 = abs(q_3);
    float _e11 = ms_sponson(q_3.x);
    d_2 = max(((a_23.x - MS_HL) + inset), (((a_23.y - MS_HW) - _e11) + inset));
    float _e16 = d_2;
    d_2 = max(_e16, ((((a_23.x + a_23.y) - 760.0) + (inset * 1.4142)) * 0.7071));
    float _e29 = d_2;
    return max(_e29, ((((a_23.y + (0.8181818 * (q_3.x - 340.0))) - MS_HW) / sqrt((1.0 + (0.8181818 * 0.8181818)))) + inset));
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
            float m_4 = (0.5 * (_e44 + _e45));
            vec2 _e53 = ms_local(f_3, (cam_1.xz + (rd_3.xz * m_4)));
            float _e54 = ms_hangar(_e53);
            float _e55 = ms_eye(_e53);
            if ((((which == 0) ? _e55 : _e54) < 0.0)) {
                a_6 = m_4;
            } else {
                b_4 = m_4;
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
                        float m_5 = (0.5 * (_e163 + _e164));
                        vec2 _e172 = ms_local(f_4, (cam_2.xz + (rd_4.xz * m_5)));
                        int _e173 = k_5;
                        float _e174 = ms_tier(_e172, _e173);
                        if ((_e174 < 0.0)) {
                            b_5 = m_5;
                        } else {
                            a_7 = m_5;
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
    vec2 c_25 = floor((q_7 / size));
    vec2 fr = (q_7 - (c_25 * size));
    float e_1 = min(min(fr.x, (size.x - fr.x)), min(fr.y, (size.y - fr.y)));
    float seam = ((1.0 - smoothstep((0.45 * 0.5), (0.45 + fp), e_1)) * min(1.0, ((2.0 * 0.45) / max(fp, 0.001))));
    float _e59 = fh21_(((c_25 * vec2(1.0, 1.7)) + (size * 0.37)));
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
    vec2 q_16 = h.q;
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
    float _e78 = fh21_((floor((q_16 / vec2(23.0))) + vec2(77.0, 1.0)));
    float on_at = ((0.35 + ((0.25 * (q_16.x + MS_HL)) / 1120.0)) + (0.06 * _e78));
    float on_1 = smoothstep(on_at, (on_at + 0.05), wake);
    float chase = (pow((0.5 + (0.5 * sin(((q_16.x * 0.025) - (time_1 * 7.0))))), 6.0) * chase_on);
    float glow_1 = ((((0.25 + (0.9 * lit)) + (1.6 * chase)) * boost) * on_1);
    if ((h.kind <= 2)) {
        vec4 _e123 = ms_plates(q_16, fp_2);
        uvec3 _e131 = pcg3d(uvec3(ivec3(ivec2(floor((q_16 / _e123.zw))), 9)));
        vec3 hv_2 = (vec3(_e131) * 2.3283064e-10);
        nl_1 = normalize(vec3(((hv_2.x - 0.5) * 0.45), -1.0, ((hv_2.y - 0.5) * 0.45)));
        rough = (0.15 + (0.6 * hv_2.z));
        tone = (((0.55 + (0.7 * _e123.y)) * mix(1.0, 0.25, _e123.x)) * ((h.kind == 0) ? 0.85 : ((h.kind == 1) ? 1.0 : 1.1)));
        float _e175 = tone;
        float _e182 = gnoise2_(((q_16 * 0.006) + vec2(3.1, 7.7)));
        tone = (_e175 * (0.65 + (0.7 * _e182)));
        float _e198 = fh21_((floor((q_16 / vec2(6.0))) + vec2((_e123.y * 91.0), 5.0)));
        float _e199 = tone;
        tone = (_e199 * mix(1.0, (0.65 + ((0.7 * _e198) * _e198)), clamp((2.0 - (fp_2 / 3.0)), 0.0, 1.0)));
        float seam_d = (12.0 - (abs((fract((q_16.y / 24.0)) - 0.5)) * 24.0));
        float _e231 = gnoise2_(vec2((q_16.x * 0.015), (q_16.y * 0.45)));
        float streak = smoothstep(0.45, 0.75, _e231);
        float _e235 = tone;
        tone = (_e235 * (1.0 - (((0.45 * exp((-(seam_d) / 2.5))) * streak) * clamp((2.0 - (fp_2 / 2.0)), 0.0, 1.0))));
        if ((_e123.y > 0.82)) {
            vec2 rdl = vec2(dot(rd_5.xz, f_5.ax), dot(rd_5.xz, f_5.sd));
            vec2 qd = (q_16 + (rdl * (4.0 / max(rd_5.y, 0.2))));
            if (any(notEqual(floor((qd / _e123.zw)), floor((q_16 / _e123.zw))))) {
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
                tone = (_e313 * mix(1.0, (0.75 + (0.5 * smoothstep(0.15, 0.35, abs((fract((q_16.y / 2.5)) - 0.5))))), clamp((1.5 - fp_2), 0.0, 1.0)));
            } else {
                if ((_e123.y < 0.12)) {
                    float slot = (step(abs((fract((q_16.x / 4.0)) - 0.5)), 0.3) * step(abs((fract((q_16.y / _e123.w)) - 0.5)), 0.3));
                    float _e356 = tone;
                    tone = (_e356 * mix(1.0, (1.0 - (0.85 * slot)), clamp((2.0 - (fp_2 / 1.5)), 0.0, 1.0)));
                }
            }
        }
        if ((h.kind == 1)) {
            local_24 = (abs(q_16.y) > 70.0);
        } else {
            local_24 = false;
        }
        bool _e379 = local_24;
        if (_e379) {
            float lz = ((abs(q_16.y) - 70.0) / 34.0);
            float fl = fract(lz);
            float _e387 = tone;
            float _e391 = fh21_(vec2(floor(lz), 61.0));
            tone = (_e387 * (0.85 + (0.3 * _e391)));
            float _e397 = tone;
            tone = ((_e397 * (1.0 - (0.5 * exp(((-(fl) * 34.0) / 2.5))))) + (0.9 * exp(((-((1.0 - fl)) * 34.0) / max(1.0, fp_2)))));
        }
        if ((h.kind == 2)) {
            vec2 fc = floor((q_16 / vec2(80.0, 60.0)));
            float _e433 = fh21_((fc + vec2(13.0, 29.0)));
            if ((_e433 > 0.62)) {
                local_25 = (abs(q_16.x) < 440.0);
            } else {
                local_25 = false;
            }
            bool _e443 = local_25;
            if (_e443) {
                float rdl_1 = dot(rd_5.xz, f_5.ax);
                float fin = smoothstep(0.3, 0.7, fract(((q_16.x / 3.0) + (0.2 * sign(rdl_1)))));
                float _e458 = tone;
                tone = (_e458 * mix(0.8, (0.45 + (0.7 * fin)), clamp((1.6 - (fp_2 / 1.5)), 0.0, 1.0)));
                rough = 0.5;
            }
        }
        if ((q_16.x > 310.0)) {
            local_26 = (h.kind > 0);
        } else {
            local_26 = false;
        }
        bool _e481 = local_26;
        if (_e481) {
            vec2 sc = floor((q_16 / vec2(16.0)));
            float _e490 = fh21_((sc + vec2(5.0, 83.0)));
            vec2 dv = (q_16 - ((sc + vec2(0.5)) * 16.0));
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
        float _e579 = ms_tier(q_16, h.kind);
        float edge_1 = -(_e579);
        if ((h.kind == 0)) {
            float _e592 = ms_eye(q_16);
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
        float _e620 = ms_line((abs((fract(((q_16.x / 120.0) + 0.5)) - 0.5)) * 120.0), 0.5, fp_2);
        float _e636 = fh21_(vec2(floor(((q_16.x / 120.0) + 0.5)), (floor((q_16.y / 70.0)) + 40.0)));
        s_2 = ((_e620 * 0.35) * step(0.4, _e636));
        if ((h.kind == 0)) {
            float _e644 = s_2;
            float _e651 = ms_line(abs((abs(q_16.y) - 20.0)), 0.5, fp_2);
            s_2 = (_e644 + (_e651 * 0.6));
        } else {
            float _e655 = s_2;
            float _e659 = ms_tier(q_16, (h.kind - 1));
            float _e663 = ms_line((_e659 - 1.4), 0.6, fp_2);
            s_2 = (_e655 + (_e663 * 1.3));
        }
        vec3 _e667 = emit;
        float _e668 = s_2;
        emit = (_e667 + ((green * _e668) * glow_1));
        if ((h.kind > 0)) {
            float row = floor((q_16.y / 6.0));
            float _e688 = fh21_((vec2(row, floor((q_16.x / 90.0))) + vec2(3.0, 17.0)));
            float wx = floor((q_16.x / 2.0));
            float _e698 = fh21_((vec2(wx, row) + vec2(41.0, 5.0)));
            if ((_e688 > 0.64)) {
                local_30 = (_e698 > 0.72);
            } else {
                local_30 = false;
            }
            bool _e706 = local_30;
            if (_e706) {
                float d_16 = length((q_16 - vec2(((wx * 2.0) + 1.0), ((row * 6.0) + 3.0))));
                float flick = (0.6 + (0.4 * step(0.2, fract(((_e698 * 13.0) + (floor((time_1 * 0.5)) * 0.37))))));
                vec3 _e733 = emit;
                float _e739 = ms_line(d_16, 0.45, fp_2);
                emit = (_e733 + (((((vec3(0.55, 1.5, 0.6) * _e739) * flick) * boost) * on_1) * 0.6));
            }
        }
        if ((h.kind == 2)) {
            float cx = floor((q_16.x / 40.0));
            float lx = ((cx * 40.0) + 20.0);
            float _e760 = ms_half_w(lx);
            float d_17 = length((q_16 - vec2(lx, (sign(q_16.y) * (_e760 - 14.0)))));
            float blink = step(0.82, fract(((time_1 * 0.9) - (cx * 0.11))));
            vec3 rc = ((q_16.y > 0.0) ? vec3(0.08, 1.1, 0.18) : vec3(0.4, 2.6, 0.5));
            vec3 _e787 = emit;
            float _e794 = ms_line(d_17, 1.3, fp_2);
            emit = (_e787 + (((mix(rc, vec3(3.5, 4.0, 3.5), blink) * _e794) * (0.6 + (1.4 * blink))) * boost));
        }
    } else {
        if ((h.kind == 4)) {
            vec2 e_3 = (q_16 - vec2(70.0, 0.0));
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
                vec2 hq = (q_16 - vec2(-290.0, 0.0));
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
                    int k_13 = ((h.h > MS_TIER_B) ? ((h.h > MS_TIER_C) ? 2 : 1) : 0);
                    float _e1012 = ms_tier((q_16 + vec2(1.0, 0.0)), k_13);
                    float _e1017 = ms_tier((q_16 - vec2(1.0, 0.0)), k_13);
                    float _e1023 = ms_tier((q_16 + vec2(0.0, 1.0)), k_13);
                    float _e1028 = ms_tier((q_16 - vec2(0.0, 1.0)), k_13);
                    n2_ = vec2((_e1012 - _e1017), (_e1023 - _e1028));
                } else {
                    if ((h.kind == 5)) {
                        n2_ = (vec2(70.0, 0.0) - q_16);
                    } else {
                        vec2 hq_1 = (q_16 - vec2(-290.0, 0.0));
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
                float u_19 = ((h.kind == 5) ? (atan(q_16.y, (q_16.x - MS_EM_X)) * MS_EYE_R) : dot(q_16, vec2(-(_e1076), _e1079)));
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
                    local_32 = (q_16.x > 556.0);
                } else {
                    local_32 = false;
                }
                bool _e1228 = local_32;
                if (_e1228) {
                    float rib = (abs((fract((q_16.y / 14.0)) - 0.5)) * 14.0);
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
                    float zc = ((floor((q_16.y / pitch)) + 0.5) * pitch);
                    float vc_1 = (big ? 103.0 : 14.0);
                    float d_18 = length(vec2((q_16.y - zc), (h.h - vc_1)));
                    if ((abs(zc) < (big ? 200.0 : 160.0))) {
                        local_34 = (d_18 < (r_10 * 1.3));
                    } else {
                        local_34 = false;
                    }
                    bool _e1314 = local_34;
                    if (_e1314) {
                        float _e1315 = tone;
                        tone = (_e1315 * mix(1.0, 0.25, step(d_18, r_10)));
                        float _e1323 = ms_line((d_18 - r_10), 1.5, fp_2);
                        float bell = ((_e1323 * 1.5) + ((1.0 - smoothstep((r_10 * 0.2), r_10, d_18)) * 1.2));
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
    vec3 n_5 = normalize((((vec3(f_5.ax.x, 0.0, f_5.ax.y) * _e1357) + vec3(0.0, _e1360, 0.0)) + (vec3(f_5.sd.x, 0.0, f_5.sd.y) * _e1372)));
    vec3 r_11 = reflect(rd_5, n_5);
    float cosv = max(dot(-(rd_5), n_5), 0.0);
    float fres = (0.45 + (0.55 * pow((1.0 - cosv), 5.0)));
    vec3 _e1389 = ms_env(r_11, haze_1, sun_1, day_1);
    float _e1390 = luminance(haze_1);
    float _e1404 = rough;
    vec3 env = mix(_e1389, (((mix(haze_1, vec3(_e1390), 0.65) * 0.6) + (vec3(0.08, 0.085, 0.07) * day_1)) * 0.6), (_e1404 * 0.8));
    vec3 sun_c = ((vec3(2.5, 2.3, 2.0) * day_1) * step(0.0, sun_1.y));
    float _e1420 = rough;
    float _e1426 = rough;
    vec3 glint = ((((sun_c * pow(max(dot(r_11, sun_1), 0.0), mix(300.0, 20.0, _e1420))) * (1.0 - _e1426)) * max(dot(n_5, sun_1), 0.0)) * 4.0);
    float _e1440 = tone;
    vec3 metal = (vec3(0.42, 0.43, 0.44) * _e1440);
    c_11 = ((metal * ((env * fres) + glint)) + (((metal * 0.04) * (haze_1 + (vec3(0.1) * day_1))) * max(dot(n_5, sun_1), 0.0)));
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
        float m_6 = (exp(-(pow((_e184 / 18.0), 2.0))) * (1.0 - (wake_1 / 1.2)));
        if ((m_6 > 0.01)) {
            float _e207 = gnoise2_(((uv_3 * vec2(120.0, 60.0)) + vec2(0.0, (time_2 * 6.0))));
            float _e217 = gnoise2_(((uv_3 * vec2(120.0, 60.0)) + vec2(17.0, (time_2 * 5.0))));
            vec2 hw = (vec2(_e207, _e217) - vec2(0.5));
            vec2 _e222 = off;
            off = (_e222 + (((hw * 0.006) * m_6) * k_6));
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
                float a_24 = ((float(_e27) * TAU) / 6.0);
                vec2 _e40 = ms_world(f_8, vec2((MS_EM_X + (cos(a_24) * 30.0)), (sin(a_24) * 30.0)));
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
            float R_2 = ((1.0 + (3.5 * core_env)) * (1.0 + (0.08 * sin((time_3 * 33.0)))));
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
            add_1 = (_e164 + ((((((vec3(5.0, 6.0, 5.0) * exp(-(pow((dc / R_2), 2.0)))) + ((vec3(0.6, 2.6, 0.8) * exp((-(dc) / R_2))) * 0.9)) + ((vec3(0.12, 0.7, 0.2) * exp((-(dc) / (R_2 * 5.0)))) * 0.4)) * core_env) * vis_4) * k_8));
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
    int i_34 = int(floor(u_20));
    float f_19 = (u_20 - floor(u_20));
    vec3 _e15 = pl_sample((i_34 - 1));
    vec3 _e16 = pl_sample(i_34);
    vec3 _e19 = pl_sample((i_34 + 1));
    vec3 _e22 = pl_sample((i_34 + 2));
    float f2_ = (f_19 * f_19);
    float f3_ = (f2_ * f_19);
    return (0.5 * ((((2.0 * _e16) + ((_e19 - _e15) * f_19)) + (((((2.0 * _e15) - (5.0 * _e16)) + (4.0 * _e19)) - _e22) * f2_)) + (((((3.0 * _e16) - _e15) - (3.0 * _e19)) + _e22) * f3_)));
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
    float c_26 = dot(p_20, n_2);
    if ((abs(r_12) < 1e-6)) {
        return ((c_26 <= 0.0) ? vec2(-1000000000.0, 1000000000.0) : vec2(1.0, 0.0));
    }
    float tc_3 = (c_26 / r_12);
    return ((r_12 > 0.0) ? vec2(tc_3, 1000000000.0) : vec2(-1000000000.0, tc_3));
}

float pl_erf(float x_8) {
    float y = clamp(x_8, -4.0, 4.0);
    return tanh(((1.1284 * y) + (((0.1009 * y) * y) * y)));
}

float smin(float a_9, float b_7, float k_10) {
    float h_7 = clamp((0.5 + ((0.5 * (b_7 - a_9)) / k_10)), 0.0, 1.0);
    return (mix(b_7, a_9, h_7) - ((k_10 * h_7) * (1.0 - h_7)));
}

float nk_rcone(vec3 p_21, float r1_, float r2_, float h_1) {
    vec2 q_17 = vec2(length(p_21.xz), p_21.y);
    float b_13 = ((r1_ - r2_) / h_1);
    float a_25 = sqrt((1.0 - (b_13 * b_13)));
    float k_14 = dot(q_17, vec2(-(b_13), a_25));
    if ((k_14 < 0.0)) {
        return (length(q_17) - r1_);
    }
    if ((k_14 > (a_25 * h_1))) {
        return (length((q_17 - vec2(0.0, h_1))) - r2_);
    }
    return (dot(q_17, vec2(a_25, b_13)) - r1_);
}

vec2 nk_bomb(vec3 p0_2, float spin, float vc) {
    float d_5 = 0.0;
    float m_1 = 0.0;
    vec2 f_9 = vec2(0.0);
    vec3 p_29 = (p0_2 / vec3(1.3));
    float _e14 = nk_rcone((p_29 - vec3(0.0, -4.2, 0.0)), 1.3, 1.3, 7.4);
    d_5 = _e14;
    float _e16 = d_5;
    float _e25 = nk_rcone((p_29 - vec3(0.0, -6.0, 0.0)), 0.75, 1.3, 1.8);
    d_5 = min(_e16, _e25);
    float _e37 = nk_rcone((p_29 - vec3(0.0, 3.2, 0.0)), 1.3, 0.28, 2.9);
    float _e38 = d_5;
    if ((_e37 < _e38)) {
        m_1 = 2.0;
        d_5 = _e37;
    }
    float cs_1 = cos(spin);
    float sn = sin(spin);
    f_9 = abs(vec2(((p_29.x * cs_1) - (p_29.z * sn)), ((p_29.x * sn) + (p_29.z * cs_1))));
    float _e57 = f_9.y;
    float _e59 = f_9.x;
    if ((_e57 > _e59)) {
        vec2 _e61 = f_9;
        f_9 = _e61.yx;
    }
    float _e64 = f_9.y;
    float _e68 = f_9.x;
    float _e79 = f_9.x;
    float df = max(max((_e64 - 0.09), (_e68 - 2.9)), max((-6.5 - p_29.y), ((p_29.y + 3.4) + (0.6 * (_e79 - 1.0)))));
    float _e87 = d_5;
    if ((df < _e87)) {
        m_1 = 1.0;
        d_5 = df;
    }
    float _e90 = d_5;
    d_5 = (_e90 * NK_BS);
    if ((vc > 0.0)) {
        float yc = (3.1200001 - p0_2.y);
        float rc_1 = length(p0_2.xz);
        float ln = (9.0 * vc);
        float dcn = (abs(dot(vec2(rc_1, yc), vec2(0.82, -0.57))) - 0.25);
        float dv_1 = max(dcn, max(-(yc), (yc - ln)));
        float _e114 = d_5;
        if ((dv_1 < _e114)) {
            m_1 = 3.0;
            d_5 = dv_1;
        }
    }
    float _e117 = d_5;
    float _e118 = m_1;
    return vec2(_e117, _e118);
}

float pl_cap_shade(vec3 o_1, vec3 L_1, float a_10, vec3 C, float hc, float R_1) {
    bool local_58 = false;
    float capy = (C.y + hc);
    if (!((L_1.y < 0.02))) {
        local_58 = (o_1.y > capy);
    } else {
        local_58 = true;
    }
    bool _e17 = local_58;
    if (_e17) {
        return 1.0;
    }
    float s_14 = ((capy - o_1.y) / L_1.y);
    vec3 _e26 = pl_wind();
    float r_13 = length((((o_1 + (L_1 * s_14)) - C) - (_e26 * a_10)).xz);
    float thin = (1.0 - (0.8 * smoothstep(PL_SOFT0_, PL_LEN, a_10)));
    return (1.0 - (((0.8 * (1.0 - smoothstep((0.55 * R_1), (1.1 * R_1), r_13))) * smoothstep(2.0, 6.0, a_10)) * thin));
}

float pl_gref(float r_5, vec3 me, vec3 C_1, float dme) {
    return mix(0.0, (me.y - C_1.y), smoothstep(0.0, max(dme, 1.0), r_5));
}

vec2 pl_land(vec2 q_8, float gref) {
    vec4 hv = vec4(0.0);
    vec4 sv = vec4(0.0);
    uint j_2 = 0u;
    float _e3 = pl_w(PL_HF);
    if ((_e3 < 2.0)) {
        return vec2(gref, 0.0);
    }
    uint n_6 = uint((_e3 + 0.5));
    uint _e11 = md_len();
    if ((_e11 < (1032u + (n_6 * n_6)))) {
        return vec2(gref, 0.0);
    }
    float _e19 = pl_w(1025u);
    float step_ = ((2.0 * _e19) / (_e3 - 1.0));
    vec2 fc_1 = clamp(((q_8 + vec2(_e19)) / vec2(step_)), vec2(0.0), vec2((_e3 - 1.001)));
    uvec2 i0_ = uvec2(floor(fc_1));
    vec2 t_10 = (fc_1 - floor(fc_1));
    bool loop_init_7 = true;
    while(true) {
        if (!loop_init_7) {
            uint _e83 = j_2;
            j_2 = (_e83 + 1u);
        }
        loop_init_7 = false;
        uint _e47 = j_2;
        if ((_e47 < 4u)) {
        } else {
            break;
        }
        {
            uint _e52 = j_2;
            uint _e60 = j_2;
            uint _e64 = md_at((((1032u + ((i0_.y + (_e52 >> 1u)) * n_6)) + i0_.x) + (_e60 & 1u)));
            uint _e65 = j_2;
            hv[_e65] = ((float((_e64 & 65535u)) / 8.0) - 512.0);
            uint _e74 = j_2;
            sv[_e74] = (float(((_e64 >> 16u) & 255u)) / 255.0);
        }
    }
    float _e87 = hv.x;
    float _e89 = hv.y;
    float _e93 = hv.z;
    float _e95 = hv.w;
    float g_3 = mix(mix(_e87, _e89, t_10.x), mix(_e93, _e95, t_10.x), t_10.y);
    float _e101 = sv.x;
    float _e103 = sv.y;
    float _e107 = sv.z;
    float _e109 = sv.w;
    float sh = mix(mix(_e101, _e103, t_10.x), mix(_e107, _e109, t_10.x), t_10.y);
    float e_5 = smoothstep(-(step_), (3.0 * step_), (max(abs(q_8.x), abs(q_8.y)) - _e19));
    return vec2(g_3, (sh * (1.0 - e_5)));
}

float pl_g0_() {
    float g = 0.0;
    int i_16 = 0;
    vec2 _e3 = pl_land(vec2(0.0), 0.0);
    g = _e3.x;
    bool loop_init_8 = true;
    while(true) {
        if (!loop_init_8) {
            int _e27 = i_16;
            i_16 = (_e27 + 1);
        }
        loop_init_8 = false;
        int _e8 = i_16;
        if ((_e8 < 4)) {
        } else {
            break;
        }
        {
            int _e11 = i_16;
            float an = ((1.5708 * float(_e11)) + 0.785);
            float _e17 = g;
            vec2 _e24 = pl_land((vec2(cos(an), sin(an)) * 14.0), 0.0);
            g = (_e17 + _e24.x);
        }
    }
    float _e30 = g;
    return clamp((_e30 / 5.0), -40.0, 0.0);
}

float pl_foot_k(float a_11) {
    return (1.0 - smoothstep(1.2, 3.8, a_11));
}

float pl_foot(float a_12, float rt, float rho, float hy) {
    float _e4 = pl_foot_k(a_12);
    float rf = ((1.3 * rt) + 6.0);
    float hf = (((hy < 0.0) ? rf : ((0.55 * rt) + 4.0)) * (0.35 + (0.65 * _e4)));
    vec2 e_6 = vec2((rho / rf), (hy / hf));
    return (((length(e_6) - 1.0) * min(rf, hf)) + ((1.0 - _e4) * ((0.6 * rt) + 40.0)));
}

float pl_foot_low(float a_13, float rt_1) {
    float _e6 = pl_foot_k(a_13);
    return ((_e6 > 0.0) ? ((1.3 * rt_1) + 6.0) : 0.0);
}

vec2 pl_dust(vec3 p_22, vec3 C_2, float a_14, vec3 me_1, float dme_1, float side, vec4 loc) {
    bool local_59 = false;
    float n2_1 = 0.5;
    vec3 q_18 = (p_22 - C_2);
    float r_14 = length(q_18.xz);
    vec4 _e12 = _group_0_binding_4_fs.camera_position;
    vec3 w_10 = (p_22 + _e12.xyz);
    float _e16 = pl_gref(r_14, me_1, C_2, dme_1);
    vec2 _e17 = pl_land(q_18.xz, _e16);
    vec2 dl = (q_18.xz - loc.xy);
    float h_8 = ((q_18.y - _e17.x) - (loc.z * exp((-(dot(dl, dl)) / loc.w))));
    float sh_1 = _e17.y;
    if (!((h_8 > 120.0))) {
        local_59 = (h_8 < -4.0);
    } else {
        local_59 = true;
    }
    bool _e41 = local_59;
    if (_e41) {
        return vec2(0.0, h_8);
    }
    float rf_1 = (PL_V * a_14);
    float _e57 = gnoise3_(((w_10 * vec3(0.11111111, 0.16666667, 0.11111111)) + vec3(0.0, (-1.2 * a_14), 0.0)));
    if (((((rf_1 - r_14) - (0.25 * max(h_8, 0.0))) - (22.0 * sh_1)) < 170.0)) {
        float _e79 = gnoise3_(((w_10 * 0.2857143) + vec3(5.0, (-2.0 * a_14), 1.0)));
        n2_1 = _e79;
    }
    float _e86 = n2_1;
    float s_15 = (((((rf_1 - r_14) + ((_e57 - 0.5) * 14.0)) + ((_e86 - 0.5) * 5.0)) - (0.25 * max(h_8, 0.0))) - (22.0 * sh_1));
    if ((s_15 < -3.0)) {
        return vec2(0.0, h_8);
    }
    float since = (max(s_15, 0.0) / PL_V);
    float _e116 = gnoise3_(((w_10 * 0.02631579) + vec3(0.0, (-0.3 * a_14), 9.0)));
    float rise = ((1.0 + (0.8 * smoothstep(0.0, 25.0, s_15))) - (0.7 * smoothstep(30.0, 140.0, s_15)));
    float hw_1 = (((((9.0 + (0.012 * r_14)) * rise) * (0.35 + (1.2 * _e57))) * (0.6 + (0.8 * _e116))) + (1.5 * min(since, 6.0)));
    float up_4 = (smoothstep(hw_1, (hw_1 * 0.35), h_8) * smoothstep(-4.0, 0.0, h_8));
    float lead_1 = smoothstep(-3.0, 1.5, s_15);
    float wall_1 = (((1.6 * exp((-(s_15) / (18.0 + (0.02 * r_14))))) * (0.75 + (0.25 * side))) * (1.0 - (0.6 * sh_1)));
    float _e192 = n2_1;
    float haze_3 = (((0.009 * exp((-(since) / 2.5))) + (0.0025 * exp((-(since) / 6.0)))) * (0.5 + _e192));
    float mid = smoothstep(80.0, 230.0, r_14);
    float low_2 = (((((0.22 * (1.0 - (0.45 * sh_1))) * exp((-(since) / 3.0))) * smoothstep(0.0, 30.0, s_15)) * exp((-(max(h_8, 0.0)) / (2.5 + (2.0 * _e57))))) * smoothstep(0.35, 0.7, _e116));
    float _e230 = n2_1;
    return vec2((((((((wall_1 * clamp(((1.5 * _e57) + (0.25 * _e230)), 0.0, 1.0)) * (0.35 + (1.3 * _e116))) + (haze_3 * (1.0 - (0.4 * sh_1)))) * up_4) + low_2) * lead_1) * mid), h_8);
}

PlChunk pl_chunk(int i_17, float a_15, float eka, vec3 C_3) {
    PlChunk o_2 = PlChunk(vec3(0.0), vec3(0.0), 0.0, 0.0);
    uint b_14 = (PL_DB + (PL_DW * uint(i_17)));
    float _e12 = pl_w((b_14 + 5u));
    float tau_3 = (a_15 - _e12);
    float _e17 = pl_w((b_14 + 6u));
    o_2.s = _e17;
    o_2.live = 0.0;
    if ((tau_3 <= 0.0)) {
        PlChunk _e22 = o_2;
        return _e22;
    }
    float _e23 = pl_w(b_14);
    float _e26 = pl_w((b_14 + 1u));
    vec3 dir_2 = vec3(_e23, 0.0, _e26);
    float _e31 = pl_w((b_14 + 3u));
    float _e34 = pl_w((b_14 + 4u));
    float _e38 = pl_w((b_14 + 7u));
    float ek = (eka * _e38);
    float e_7 = ((1.0 - ek) / 0.06);
    float _e47 = pl_w((b_14 + 2u));
    o_2.p = ((C_3 + (dir_2 * (_e47 + (_e31 * e_7)))) + vec3(0.0, ((2.0 + (_e34 * e_7)) - ((9.8 * (tau_3 - e_7)) / 0.06)), 0.0));
    o_2.v = ((dir_2 * (_e31 * ek)) + vec3(0.0, (((_e34 + (9.8 / 0.06)) * ek) - (9.8 / 0.06)), 0.0));
    o_2.live = 1.0;
    PlChunk _e77 = o_2;
    return _e77;
}

float pl_chunk_up(PlChunk ch, vec3 C_4, vec3 me_2, float dme_2) {
    float gref_1 = 0.0;
    float r_15 = length((ch.p - C_4).xz);
    float _e9 = pl_gref(r_15, me_2, C_4, dme_2);
    gref_1 = (C_4.y + _e9);
    float _e14 = gref_1;
    float _e17 = pl_w(1027u);
    if ((ch.p.y < (max(_e14, (C_4.y + _e17)) + 3.0))) {
        float _e27 = gref_1;
        vec2 _e30 = pl_land((ch.p - C_4).xz, (_e27 - C_4.y));
        gref_1 = (C_4.y + _e30.x);
    }
    float _e33 = gref_1;
    float _e36 = gref_1;
    return smoothstep((_e33 - 1.0), (_e36 + 2.0), ch.p.y);
}

PlCol pl_column(float a_16, vec3 C_5) {
    PlCol o_3 = PlCol(0.0, vec3(0.0), 0.0, 0.0, 0.0, 0.0, vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
    o_3.a = a_16;
    vec3 _e5 = pl_wind();
    o_3.C = (C_5 + (_e5 * (0.0 * a_16)));
    o_3.rt = (((56.0 * (1.0 - exp((-(a_16) / 0.45)))) + (26.0 * (1.0 - exp((-(a_16) / 14.0))))) + (0.15 * a_16));
    o_3.hc = (PL_BURST + ((385.0 * (1.0 - exp((-(a_16) / 15.0)))) * smoothstep(0.0, 2.5, (a_16 + 0.5))));
    o_3.Rt = (((80.0 * (1.0 - exp((-(a_16) / 6.0)))) + (70.0 * (1.0 - exp((-(a_16) / 28.0))))) + (0.3 * a_16));
    float _e71 = o_3.hc;
    float _e73 = o_3.rt;
    o_3.st = min((_e71 - (0.15 * _e73)), (max((a_16 - 1.0), 0.0) * 55.0));
    float _e100 = o_3.Rt;
    o_3.sr = vec3((34.0 + (30.0 * clamp((a_16 / 6.0), 0.0, 1.0))), (20.0 + (8.0 * clamp((a_16 / 20.0), 0.0, 1.0))), (26.0 + (0.3 * _e100)));
    float _e108 = o_3.hc;
    float _e115 = o_3.sr.y;
    o_3.ring = vec3(((0.42 * _e108) + 10.0), (((_e115 * 2.0) + 30.0) + (0.6 * a_16)), (smoothstep(4.0, 9.0, a_16) * (1.0 - smoothstep(16.0, 30.0, a_16))));
    o_3.surge = vec3((30.0 + (160.0 * (1.0 - exp((-(a_16) / 12.0))))), (24.0 + (0.1 * a_16)), (8.0 + (9.0 * clamp((a_16 / 12.0), 0.0, 1.0))));
    float _e157 = o_3.hc;
    float _e159 = o_3.rt;
    float top_1 = (_e157 + (1.4 * _e159));
    float _e164 = o_3.Rt;
    float _e166 = o_3.rt;
    float _e172 = o_3.surge.x;
    float _e175 = o_3.surge.y;
    float w_11 = (max((_e164 + (_e166 * 1.6)), (_e172 + _e175)) + 90.0);
    vec3 _e180 = pl_wind();
    vec3 lean = (_e180 * a_16);
    float _e189 = o_3.rt;
    float _e190 = pl_foot_low(a_16, _e189);
    o_3.lo = (C_5 + vec3((-(w_11) + min(lean.x, 0.0)), (-20.0 - _e190), (-(w_11) + min(lean.z, 0.0))));
    o_3.hi = (C_5 + vec3((w_11 + max(lean.x, 0.0)), (top_1 + 90.0), (w_11 + max(lean.z, 0.0))));
    PlCol _e213 = o_3;
    return _e213;
}

vec3 pl_lean(inout PlCol col, float hy_1) {
    vec3 _e2 = pl_wind();
    float _e4 = col.a;
    float _e6 = col.hc;
    return (_e2 * (_e4 * pow(clamp((hy_1 / max(_e6, 1.0)), 0.0, 1.0), 1.5)));
}

vec2 pl_col_base2_(inout PlCol col_1, vec3 p_23) {
    float d_6 = 0.0;
    float dome = 0.0;
    float dr = 1000000.0;
    vec3 C_7 = col_1.C;
    float hy0_ = (p_23.y - C_7.y);
    vec3 _e8 = pl_lean(col_1, hy0_);
    vec3 q_19 = ((p_23 - C_7) - _e8);
    float hy_2 = q_19.y;
    float rho_1 = length(q_19.xz);
    float Rt = col_1.Rt;
    float rt_3 = col_1.rt;
    float hc_2 = col_1.hc;
    float _e20 = col_1.a;
    float fold = smoothstep(3.0, 14.0, _e20);
    float lo_k = mix(1.6, mix(1.9, 1.12, smoothstep((-0.4 * rt_3), (0.6 * rt_3), (rho_1 - Rt))), fold);
    vec2 tq_2 = vec2((rho_1 - Rt), ((hy_2 - hc_2) * ((hy_2 < hc_2) ? lo_k : 1.6)));
    d_6 = (length(tq_2) - rt_3);
    vec3 er = vec3((Rt + (0.8 * rt_3)), (1.0 * rt_3), (Rt + (0.8 * rt_3)));
    vec3 eq = vec3(q_19.x, ((hy_2 - hc_2) - (0.3 * rt_3)), q_19.z);
    float ek0_ = length((eq / er));
    dome = ((ek0_ * (ek0_ - 1.0)) / max(length((eq / (er * er))), 1e-6));
    float _e73 = dome;
    dome = max(_e73, ((hc_2 - (mix(0.9, 0.12, fold) * rt_3)) - hy_2));
    float _e81 = d_6;
    float _e82 = dome;
    float _e85 = smin(_e81, _e82, (0.35 * rt_3));
    d_6 = _e85;
    float _e86 = d_6;
    float _e88 = col_1.a;
    float _e89 = pl_foot(_e88, rt_3, rho_1, hy_2);
    float _e94 = smin(_e86, _e89, ((0.3 * rt_3) + 4.0));
    d_6 = _e94;
    float _e96 = col_1.st;
    if ((_e96 > 0.0)) {
        float _e100 = col_1.st;
        float u_21 = clamp((hy_2 / max(_e100, 1.0)), 0.0, 1.0);
        vec3 sr = col_1.sr;
        float rs_3 = (mix(mix(sr.x, sr.y, smoothstep(0.0, 0.3, u_21)), sr.z, smoothstep(0.65, 1.0, u_21)) * (0.92 + (0.16 * sin(((hy_2 * 0.045) + 1.3)))));
        float _e130 = col_1.st;
        float ds = max((rho_1 - rs_3), max((hy_2 - _e130), (-(hy_2) - 20.0)));
        float _e137 = d_6;
        float _e139 = smin(_e137, ds, 26.0);
        d_6 = _e139;
    }
    vec3 sg = col_1.surge;
    float _e143 = col_1.a;
    if ((_e143 > 0.2)) {
        vec2 e_8 = vec2(((rho_1 - sg.x) / sg.y), ((hy_2 - (0.3 * sg.z)) / sg.z));
        vec2 inner_1 = vec2((max((sg.x - rho_1), 0.0) / (sg.x * 0.9)), 0.0);
        float k0_ = length(e_8);
        float ds_1 = ((k0_ - 1.0) * min(sg.y, sg.z));
        float _e175 = col_1.a;
        float _e182 = col_1.a;
        float settle = ((22.0 * smoothstep(18.0, 70.0, _e175)) + (40.0 * (1.0 - smoothstep(0.2, 2.5, _e182))));
        float _e191 = d_6;
        float _e201 = smin(_e191, ((ds_1 + (14.0 * smoothstep(0.0, 0.6, inner_1.x))) + settle), 22.0);
        d_6 = _e201;
        float sheet = max((rho_1 - sg.x), (abs((hy_2 - (0.2 * sg.z))) - (0.32 * sg.z)));
        float _e214 = d_6;
        float _e219 = smin(_e214, ((sheet + 11.0) + settle), 18.0);
        d_6 = _e219;
    }
    vec3 rg = col_1.ring;
    if ((rg.z > 0.01)) {
        vec2 e_9 = vec2(((rho_1 - rg.y) / 34.0), ((hy_2 - rg.x) / 13.0));
        dr = ((length(e_9) - 1.0) * 13.0);
    }
    float _e241 = d_6;
    float _e242 = dr;
    return vec2(_e241, _e242);
}

float pl_col_base(inout PlCol col_2, vec3 p_24) {
    vec2 _e2 = pl_col_base2_(col_2, p_24);
    return min(_e2.x, _e2.y);
}

float pl_dome(vec3 p_25) {
    float hmax = 0.0;
    uint c_12 = 0u;
    vec3 b_15 = floor((p_25 - vec3(0.5)));
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
            vec3 o_7 = vec3(float((_e12 & 1u)), float(((_e16 >> 1u) & 1u)), float((_e22 >> 2u)));
            vec3 cell_1 = (b_15 + o_7);
            uvec3 q_20 = uvec3(ivec3(cell_1));
            uint _e35 = pcg((q_20.z + 81u));
            uint _e37 = pcg((q_20.y ^ _e35));
            uint _e39 = pcg((q_20.x ^ _e37));
            vec3 jit = ((vec3(float((_e39 & 1023u)), float(((_e39 >> 10u) & 1023u)), float(((_e39 >> 20u) & 1023u))) * 0.00068426196) + vec3(0.15));
            uint _e59 = pcg(_e39);
            float sz = (0.7 + ((0.55 * float((_e59 & 1023u))) / 1023.0));
            vec3 e_10 = ((cell_1 + jit) - p_25);
            float _e71 = hmax;
            hmax = max(_e71, (sz * sqrt(clamp((1.0 - ((dot(e_10, e_10) * 1.7) / (sz * sz))), 0.0, 1.0))));
        }
    }
    float _e86 = hmax;
    return _e86;
}

vec3 pl_rot(int k_11, vec3 p_26) {
    if ((k_11 == 0)) {
        return (mat3x3(vec3(-0.0014, 0.9977, -0.0674), vec3(-0.2224, -0.066, -0.9727), vec3(-0.975, 0.0136, 0.222)) * p_26);
    }
    if ((k_11 == 1)) {
        return (mat3x3(vec3(-0.6616, 0.1124, 0.7414), vec3(-0.4826, -0.8205, -0.3063), vec3(0.5739, -0.5605, 0.5971)) * p_26);
    }
    return (mat3x3(vec3(-0.9891, -0.1223, 0.0816), vec3(0.0968, -0.9594, -0.2651), vec3(0.1107, -0.2543, 0.9608)) * p_26);
}

vec4 pl_col_sdf(inout PlCol col_3, vec3 p_27, float d0_, bool fine) {
    vec3 q_9 = vec3(0.0);
    float b1_ = 0.0;
    float wsum = 0.0;
    int k_12 = 0;
    float d_7 = 0.0;
    float fray = 0.5;
    bool local_60 = false;
    bool local_61 = false;
    float a_26 = col_3.a;
    vec3 C_8 = col_3.C;
    vec3 _e12 = pl_lean(col_3, (p_27.y - C_8.y));
    q_9 = ((p_27 - C_8) - _e12);
    vec3 _e15 = q_9;
    float rho_2 = max(length(_e15.xz), 0.001);
    vec3 _e20 = q_9;
    vec2 dir_3 = (_e20.xz / vec2(rho_2));
    float _e25 = col_3.Rt;
    float _e28 = q_9.y;
    float _e30 = col_3.hc;
    vec2 uv_5 = vec2((rho_2 - _e25), (_e28 - _e30));
    float _e35 = col_3.rt;
    float wq = (dot(uv_5, uv_5) / pow((1.6 * _e35), 2.0));
    float _e45 = col_3.Rt;
    float wr = (exp((-(wq) * wq)) * smoothstep(0.0, ((0.8 * _e45) + 10.0), rho_2));
    float om = (((0.25 * (1.0 - exp((-(a_26) / 2.0)))) * exp((-(a_26) / 12.0))) + 0.04);
    float ph = fract((a_26 / PL_CHURN));
    float wA = (1.0 - abs(((2.0 * ph) - 1.0)));
    float _e80 = q_9.y;
    float _e92 = col_3.hc;
    float _e94 = col_3.rt;
    float _e99 = col_3.hc;
    float _e101 = col_3.rt;
    float _e106 = q_9.y;
    q_9.y = (_e80 - (((3.5 * min(a_26, 18.0)) * (1.0 - exp((-(wq) * wq)))) * (1.0 - smoothstep((_e92 - (1.7 * _e94)), (_e99 - (0.5 * _e101)), _e106))));
    vec3 _e114 = q_9;
    vec3 _e120 = pl_rot(1, (_e114 * (1.0 / (55.0 * 2.2))));
    float _e121 = gnoise3_(_e120);
    vec3 _e123 = q_9;
    vec3 _e135 = pl_rot(2, ((_e123 * (1.0 / (23.0 * 2.2))) + vec3(9.2, (-0.05 * a_26), 4.4)));
    float _e136 = gnoise3_(_e135);
    int kd = ((wA < 0.5) ? 1 : 0);
    k_12 = (fine ? 0 : kd);
    bool loop_init_10 = true;
    while(true) {
        if (!loop_init_10) {
            int _e252 = k_12;
            k_12 = (_e252 + 1);
        }
        loop_init_10 = false;
        int _e149 = k_12;
        if ((_e149 < (fine ? 2 : (kd + 1)))) {
        } else {
            break;
        }
        {
            int _e155 = k_12;
            float tk = (fract((ph + (0.5 * float(_e155)))) * PL_CHURN);
            float ang_5 = ((om * tk) * wr);
            float cs_2 = cos(ang_5);
            float sn_1 = sin(ang_5);
            vec2 uv2_1 = vec2(((uv_5.x * cs_2) - (uv_5.y * sn_1)), ((uv_5.x * sn_1) + (uv_5.y * cs_2)));
            float _e181 = col_3.Rt;
            float _e185 = q_9.y;
            float _e193 = col_3.Rt;
            vec3 qk = vec3((dir_3.x * (uv2_1.x + _e181)), ((_e185 + uv2_1.y) - uv_5.y), (dir_3.y * (uv2_1.x + _e193)));
            int _e199 = k_12;
            float cyc = floor(((a_26 / PL_CHURN) + (0.5 * float(_e199))));
            float _e205 = wsum;
            int _e208 = k_12;
            wsum = (_e205 + ((_e208 == 0) ? wA : (1.0 - wA)));
            float _e213 = b1_;
            int _e216 = k_12;
            int _e234 = k_12;
            vec3 _e248 = pl_rot(0, (((qk * (1.0 / (36.0 * 2.2))) + vec3((3.1 + (7.3 * cyc)), 0.0, ((7.7 - (4.1 * cyc)) + (2.9 * float(_e234))))) + (0.3 * vec3((_e136 - 0.5)))));
            float _e249 = pl_dome(_e248);
            b1_ = (_e213 + (((_e216 == 0) ? wA : (1.0 - wA)) * _e249));
        }
    }
    float _e255 = b1_;
    float _e256 = wsum;
    float _e260 = b1_;
    b1_ = (fine ? (0.62 + ((_e260 - 0.62) / sqrt(((wA * wA) + ((1.0 - wA) * (1.0 - wA)))))) : (_e255 / max(_e256, 0.001)));
    float hy_3 = (p_27.y - C_8.y);
    float lump = (1.6 * (0.6 + (0.4 * smoothstep(20.0, 160.0, hy_3))));
    float soft = smoothstep(PL_SOFT0_, PL_SOFT1_, a_26);
    float crisp = (1.0 - (0.8 * soft));
    vec3 _e295 = q_9;
    vec3 _e307 = pl_rot(1, ((_e295 * (1.0 / (14.0 * 2.2))) + vec3(0.0, (-0.15 * a_26), 1.3)));
    float _e308 = pl_dome(_e307);
    float up_5 = smoothstep(40.0, 200.0, hy_3);
    float _e313 = col_3.Rt;
    float _e317 = col_3.Rt;
    float _e319 = col_3.rt;
    float _e327 = col_3.hc;
    float _e329 = col_3.hc;
    float _e331 = col_3.rt;
    float crown = ((1.0 - smoothstep((0.3 * _e313), (_e317 + (0.3 * _e319)), rho_2)) * smoothstep(_e327, (_e329 + (0.5 * _e331)), hy_3));
    float _e337 = b1_;
    d_7 = (d0_ - ((((((((26.0 * (_e337 - 0.45)) * crisp) * (0.4 + (0.6 * up_5))) * (1.0 - (0.2 * crown))) + ((9.0 * (_e308 - 0.45)) * (1.0 - (0.7 * soft)))) + (((18.0 + (8.0 * soft)) * (_e121 - 0.5)) * (1.0 - (0.35 * crown)))) + (8.0 * (_e136 - 0.5))) * lump));
    float ew = smoothstep(0.6, 0.82, _e136);
    float edge_2 = (mix(1.5, 6.0, ew) + (10.0 * (1.0 - smoothstep(0.0, 60.0, hy_3))));
    if (fine) {
        float _e402 = d_7;
        local_60 = (_e402 < 20.0);
    } else {
        local_60 = false;
    }
    bool _e406 = local_60;
    if (_e406) {
        local_61 = (soft < 0.99);
    } else {
        local_61 = false;
    }
    bool _e412 = local_61;
    if (_e412) {
        vec3 _e414 = q_9;
        vec3 _e426 = pl_rot(2, ((_e414 * (1.0 / (5.5 * 2.2))) + vec3(1.7, (-0.25 * a_26), -2.1)));
        float _e427 = pl_dome(_e426);
        float _e428 = d_7;
        d_7 = (_e428 - (((4.0 * (_e427 - 0.45)) * (1.0 - soft)) * lump));
        vec3 _e439 = q_9;
        vec3 _e445 = pl_rot(0, (_e439 * (1.0 / (1.8 * 2.2))));
        float _e452 = gnoise3_((_e445 + vec3(5.0, 1.0, (-0.4 * a_26))));
        fray = _e452;
        float _e453 = d_7;
        float _e454 = fray;
        d_7 = (_e453 - (((3.5 * (_e454 - 0.5)) * (1.0 - soft)) * (0.25 + (0.75 * ew))));
    }
    float _e468 = d_7;
    float bump = max((d0_ - _e468), 0.0);
    float _e482 = d_7;
    d_7 = ((d0_ - (bump / sqrt(sqrt((1.0 + pow((bump / PL_DM), 4.0)))))) + max((_e482 - d0_), 0.0));
    float _e487 = d_7;
    float _e488 = b1_;
    float _e494 = fray;
    return vec4(_e487, (_e488 * (0.45 + (0.55 * _e308))), edge_2, _e494);
}

vec2 pl_box(vec3 rd_9, vec3 lo_1, vec3 hi_1) {
    vec3 inv_1 = (vec3(1.0) / mix(rd_9, vec3(1e-6), lessThan(abs(rd_9), vec3(1e-6))));
    vec3 ta_3 = (lo_1 * inv_1);
    vec3 tb_1 = (hi_1 * inv_1);
    vec3 tmin = min(ta_3, tb_1);
    vec3 tmax = max(ta_3, tb_1);
    return vec2(max(max(tmin.x, tmin.y), max(tmin.z, 0.0)), min(min(tmax.x, tmax.y), tmax.z));
}

float pl_shadow(vec3 o_4, vec3 L_2, float a_17, vec3 C_6, float j_3) {
    PlCol cs = PlCol(0.0, vec3(0.0), 0.0, 0.0, 0.0, 0.0, vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
    float tau_1 = 0.0;
    int i_18 = 0;
    PlCol _e5 = pl_column(a_17, C_6);
    cs = _e5;
    vec3 _e8 = cs.lo;
    vec3 _e11 = cs.hi;
    vec2 _e13 = pl_box(L_2, (_e8 - o_4), (_e11 - o_4));
    if ((_e13.y <= _e13.x)) {
        return 1.0;
    }
    float _e19 = cs.hc;
    vec3 _e24 = pl_wind();
    vec3 ctop = ((C_6 + vec3(0.0, _e19, 0.0)) + (_e24 * a_17));
    vec3 _e31 = pl_ray_seg(L_2, (C_6 - o_4), (ctop - o_4), 0.0, 1.0);
    float _e34 = cs.Rt;
    float _e36 = cs.rt;
    float _e40 = cs.surge.x;
    float _e43 = cs.surge.y;
    if ((_e31.x > (max((_e34 + _e36), (_e40 + _e43)) + 40.0))) {
        return 1.0;
    }
    float dt_2 = ((_e13.y - _e13.x) / float(14));
    bool loop_init_11 = true;
    while(true) {
        if (!loop_init_11) {
            int _e79 = i_18;
            i_18 = (_e79 + 1);
        }
        loop_init_11 = false;
        int _e60 = i_18;
        if ((_e60 < 14)) {
        } else {
            break;
        }
        {
            int _e63 = i_18;
            vec2 _e70 = pl_col_base2_(cs, (o_4 + (L_2 * (_e13.x + ((float(_e63) + j_3) * dt_2)))));
            float d_19 = _e70.x;
            float _e72 = tau_1;
            tau_1 = (_e72 + clamp((0.35 - (d_19 / 45.0)), 0.0, 1.0));
        }
    }
    float thin_1 = (1.0 - (0.8 * smoothstep(PL_SOFT0_, PL_LEN, a_17)));
    float _e89 = tau_1;
    return exp(((((-(_e89) * dt_2) * 0.022) * thin_1) * smoothstep(0.3, 2.0, a_17)));
}

void pl_over(inout vec4 h_2, vec3 c_13, float x_9) {
    vec4 _e3 = h_2;
    float _e11 = h_2.w;
    h_2 = vec4(((_e3.xyz * (1.0 - x_9)) + (c_13 * x_9)), (_e11 * (1.0 - x_9)));
    return;
}

PlOut nuke(StageIn in_, uint stage, vec4 up_1, vec3 up_e) {
    vec2 uv_4 = vec2(0.0);
    float d_8 = 0.0;
    vec3 col_4 = vec3(0.0);
    vec4 hc_1 = vec4(0.0, 0.0, 0.0, 1.0);
    bool local_62 = false;
    bool local_63 = false;
    bool local_64 = false;
    bool local_65 = false;
    bool local_66 = false;
    bool local_67 = false;
    vec3 skyl = vec3(0.0);
    float nsk = 1.0;
    int s_5 = 0;
    bool local_68 = false;
    bool local_69 = false;
    float th = 0.0;
    bool local_70 = false;
    bool local_71 = false;
    vec2 dirs = vec2(0.0);
    bool local_72 = false;
    bool local_73 = false;
    bool local_74 = false;
    bool local_75 = false;
    bool local_76 = false;
    bool local_77 = false;
    bool local_78 = false;
    bool local_79 = false;
    float tau_2 = 0.0;
    vec3 tc = vec3(0.0);
    vec3 glow = vec3(0.0);
    vec3 pa = vec3(0.0);
    vec3 pv = vec3(0.0);
    bool have_pv = true;
    vec3 pc_1 = vec3(0.0);
    bool have_pc = false;
    int i_19 = 0;
    bool local_80 = false;
    bool local_81 = false;
    vec3 pb = vec3(0.0);
    vec3 pn = vec3(0.0);
    vec3 na = vec3(0.0);
    vec3 oa = vec3(0.0);
    vec3 nb = vec3(0.0);
    vec3 ob = vec3(0.0);
    bool local_82 = false;
    vec3 lb = vec3(0.0);
    float n1_ = 0.0;
    float n2_2 = 0.0;
    float n3_ = 0.0;
    vec3 alb = vec3(0.0);
    vec3 c_14 = vec3(0.0);
    bool local_83 = false;
    bool local_84 = false;
    float ftau = 0.0;
    vec3 ftc = vec3(0.0);
    vec3 fglow = vec3(0.0);
    int f_10 = 0;
    bool local_85 = false;
    bool local_86 = false;
    bool local_87 = false;
    bool local_88 = false;
    bool local_89 = false;
    vec3 qa = vec3(0.0);
    int j_4 = 0;
    bool local_90 = false;
    bool local_91 = false;
    bool local_92 = false;
    vec3 c_15 = vec3(0.0);
    float col_t = 0.0;
    bool local_93 = false;
    bool local_94 = false;
    PlCol cl = PlCol(0.0, vec3(0.0), 0.0, 0.0, 0.0, 0.0, vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
    bool local_95 = false;
    float t_7 = 0.0;
    float tr_1 = 1.0;
    vec3 acc_1 = vec3(0.0);
    float tmid = 0.0;
    float wmid = 0.0;
    int nl_2 = 0;
    float lc_face = 0.0;
    float lc_bulk = 1.0;
    float sky_occ = 0.0;
    float em_y = 0.5;
    float em_k = 0.0;
    int i_20 = 0;
    bool local_96 = false;
    float den = 0.0;
    float ringw = 0.0;
    vec4 sd = vec4(0.0);
    bool local_97 = false;
    bool local_98 = false;
    vec3 alb_1 = vec3(0.0);
    vec3 c_16 = vec3(0.0);
    bool local_99 = false;
    bool local_100 = false;
    bool local_101 = false;
    float vis = 1.0;
    bool local_102 = false;
    bool local_103 = false;
    bool local_104 = false;
    bool local_105 = false;
    float tt = 0.0;
    float best = 1000000000.0;
    float bt = 0.0;
    float bm = 0.0;
    int i_21 = 0;
    float cov = 0.0;
    vec3 n_3 = vec3(0.0);
    vec3 alb_2 = vec3(0.4, 0.41, 0.42);
    float spec = 1.0;
    vec3 c_17 = vec3(0.0);
    bool local_106 = false;
    bool local_107 = false;
    bool local_108 = false;
    float ylo = 0.0;
    float yhi = 0.0;
    vec4 loc_1 = vec4(0.0, 0.0, 0.0, 1.0);
    float t0_ = 0.0;
    float t1_ = 0.0;
    bool local_109 = false;
    bool local_110 = false;
    vec2 seg[3] = vec2[3](vec2(0.0), vec2(0.0), vec2(0.0));
    int ns[3] = int[3](16, 0, 0);
    bool local_111 = false;
    float tr_2 = 1.0;
    vec3 acc_2 = vec3(0.0);
    int order[3] = int[3](0, 2, 1);
    int si = 0;
    bool local_112 = false;
    bool local_113 = false;
    int i_22 = 0;
    float near = 0.0;
    float near_hi = 0.0;
    bool local_114 = false;
    bool local_115 = false;
    float low = 0.0;
    int i_23 = 0;
    bool local_116 = false;
    bool local_117 = false;
    bool local_118 = false;
    bool local_119 = false;
    bool local_120 = false;
    bool local_121 = false;
    float cov_1 = 0.0;
    float smk = 0.0;
    float low_1 = 0.0;
    int i_24 = 0;
    PlChunk ch_1 = PlChunk(vec3(0.0), vec3(0.0), 0.0, 0.0);
    bool local_122 = false;
    bool local_123 = false;
    bool local_124 = false;
    bool local_125 = false;
    bool local_126 = false;
    float keep = 1.0;
    float shine = 0.0;
    uint i_25 = 0u;
    uint j_5 = 0u;
    bool local_127 = false;
    bool local_128 = false;
    bool local_129 = false;
    float up_t = up_e.x;
    uv_4 = in_.uv;
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
    vec3 C_9 = (vec3(_e24.x, gy_1, _e24.y) - cam_6);
    float _e32 = pl_g0_();
    vec3 C_10 = (C_9 + vec3(0.0, _e32, 0.0));
    float _e41 = _group_0_binding_4_fs.mod_params[3].x;
    float _e46 = _group_0_binding_4_fs.mod_params[3].y;
    float _e51 = _group_0_binding_4_fs.mod_params[3].z;
    vec3 me_3 = (vec3(_e41, _e46, _e51) - cam_6);
    float dme_3 = length((me_3 - C_9).xz);
    vec4 _e59 = _group_0_binding_4_fs.sun;
    vec3 sun_2 = _e59.xyz;
    float day_2 = clamp(((sun_2.y * 2.5) + 0.35), 0.0, 1.0);
    float sun_up = smoothstep(-0.12, 0.06, sun_2.y);
    float warm = ((1.0 - smoothstep(0.02, 0.4, sun_2.y)) * smoothstep(-0.2, -0.02, sun_2.y));
    float moon = smoothstep(-0.02, -0.2, sun_2.y);
    vec3 L_3 = normalize((((sun_2.y > -0.04) ? sun_2 : -(sun_2)) + vec3(0.0, 0.03, 0.0)));
    if ((stage == 1u)) {
        vec4 _e103 = _group_0_binding_4_fs.resolution;
        ivec2 full = ivec2(_e103.xy);
        ivec2 q_21 = (ivec2(floor(in_.position.xy)) * 2);
        ivec2 q1_2 = min((q_21 + ivec2(1)), (full - ivec2(1)));
        float _e119 = depth_px(q_21);
        float _e123 = depth_px(ivec2(q1_2.x, q_21.y));
        float _e127 = depth_px(ivec2(q_21.x, q1_2.y));
        float _e128 = depth_px(q1_2);
        ivec2 hq_2 = ivec2(floor(in_.position.xy));
        d_8 = ((((hq_2.x + hq_2.y) & 1) == 0) ? max(max(_e119, _e123), max(_e127, _e128)) : min(min(_e119, _e123), min(_e127, _e128)));
        vec4 _e153 = _group_0_binding_4_fs.resolution;
        uv_4 = ((vec2(q_21) + vec2(1.0)) * _e153.zw);
    } else {
        vec2 _e156 = uv_4;
        float _e157 = depth_at(_e156);
        d_8 = _e157;
    }
    float _e158 = d_8;
    bool _e159 = is_sky(_e158);
    vec2 _e160 = uv_4;
    float _e161 = d_8;
    vec3 _e164 = world_offset(_e160, (_e159 ? 0.5 : _e161));
    float scene_len_3 = (!(_e159) ? length(_e164) : 1000000000.0);
    vec2 _e169 = uv_4;
    vec3 _e171 = world_offset(_e169, RAY_DEPTH);
    vec3 rd_10 = normalize(_e171);
    vec2 _e175 = uv_4;
    vec4 _e177 = orbitalSceneLod(_group_0_binding_0_fs, vec2(_e175), 0.0);
    vec3 _e179 = srgb_to_linear(_e177.xyz);
    col_4 = _e179;
    if ((stage != 1u)) {
        local_62 = !(_e159);
    } else {
        local_62 = false;
    }
    bool _e193 = local_62;
    if (_e193) {
        local_63 = (_e7 > PL_HIT);
    } else {
        local_63 = false;
    }
    bool _e199 = local_63;
    if (_e199) {
        local_64 = (_e7 < 17.0);
    } else {
        local_64 = false;
    }
    bool _e205 = local_64;
    if (_e205) {
        float rfr = (PL_V * (_e7 - PL_HIT));
        vec2 _e210 = anchor_xz();
        float _e212 = block_y();
        vec2 _e215 = anchor_xz();
        float rs_4 = length((_e164 - (vec3(_e210.x, (_e212 + 1.0), _e215.y) - cam_6)).xz);
        float e_11 = (rfr - rs_4);
        float gust = (exp(-(pow((e_11 / 14.0), 2.0))) + ((0.4 * exp((-(max(e_11, 0.0)) / 50.0))) * step(0.0, e_11)));
        if ((_e179.y > (_e179.x * 1.1))) {
            local_65 = (_e179.y > (_e179.z * 1.05));
        } else {
            local_65 = false;
        }
        bool green_1 = local_65;
        if ((gust > 0.03)) {
            local_66 = green_1;
        } else {
            local_66 = false;
        }
        bool _e260 = local_66;
        if (_e260) {
            float _e264 = _group_0_binding_4_fs.resolution.y;
            float _e268 = _group_0_binding_4_fs.view_params.w;
            float fpx0_ = (_e264 / (2.0 * tan((_e268 * 0.5))));
            float amp_1 = (min(((0.45 * fpx0_) / max(scene_len_3, 1.0)), 7.0) * gust);
            float ph_1 = dot(floor((in_.position.xy / vec2(6.0))), vec2(0.37, 0.71));
            vec2 off_2 = (vec2(sin(((_e7 * 29.0) + (ph_1 * 5.0))), cos(((_e7 * 23.0) + (ph_1 * 3.0)))) * amp_1);
            vec2 _e309 = uv_4;
            vec4 _e312 = _group_0_binding_4_fs.resolution;
            vec4 _e317 = orbitalSceneLod(_group_0_binding_0_fs, vec2((_e309 + (off_2 * _e312.zw))), 0.0);
            vec3 _e319 = srgb_to_linear(_e317.xyz);
            if ((_e319.y > (_e319.x * 1.1))) {
                local_67 = (_e319.y > (_e319.z * 1.05));
            } else {
                local_67 = false;
            }
            bool _e333 = local_67;
            if (_e333) {
                col_4 = _e319;
            }
        }
    }
    float fade = (1.0 - smoothstep(80.0, PL_LEN, _e7));
    float a_27 = (_e7 - PL_HIT);
    int _e341 = pl_n();
    bool have = (_e341 > 1);
    vec4 _e346 = _group_0_binding_4_fs.sky_color;
    vec3 _e348 = srgb_to_linear(_e346.xyz);
    skyl = _e348;
    bool loop_init_12 = true;
    while(true) {
        if (!loop_init_12) {
            int _e378 = s_5;
            s_5 = (_e378 + 1);
        }
        loop_init_12 = false;
        int _e354 = s_5;
        if ((_e354 < 3)) {
        } else {
            break;
        }
        {
            int _e357 = s_5;
            vec2 su = vec2((0.2 + (0.3 * float(_e357))), 0.04);
            float _e365 = depth_at(su);
            bool _e366 = is_sky(_e365);
            if (_e366) {
                vec3 _e367 = skyl;
                vec4 _e371 = orbitalSceneLod(_group_0_binding_0_fs, vec2(su), 0.0);
                vec3 _e373 = srgb_to_linear(_e371.xyz);
                skyl = (_e367 + _e373);
                float _e375 = nsk;
                nsk = (_e375 + 1.0);
            }
        }
    }
    vec3 _e381 = skyl;
    float _e382 = nsk;
    skyl = (_e381 / vec3(_e382));
    vec3 _e389 = skyl;
    vec3 amb = mix(vec3(0.03, 0.035, 0.05), ((_e389 * 0.85) + vec3(0.04)), day_2);
    vec3 sunc = ((mix(vec3(1.35, 1.24, 1.06), mix(vec3(1.5, 0.68, 0.3), vec3(1.3, 0.38, 0.14), smoothstep(0.0, -0.1, sun_2.y)), warm) * sun_up) + (vec3(0.07, 0.09, 0.14) * moon));
    vec4 _e423 = _group_0_binding_4_fs.fog_color;
    vec3 _e425 = srgb_to_linear(_e423.xyz);
    vec3 _e430 = skyl;
    vec3 haze_c = mix(vec3(0.02, 0.025, 0.04), (_e430 * 1.05), day_2);
    vec3 Pb = (C_10 + vec3(0.0, 12.0, 0.0));
    if ((stage != 1u)) {
        local_68 = (a_27 > 0.0);
    } else {
        local_68 = false;
    }
    bool _e446 = local_68;
    if (_e446) {
        local_69 = (a_27 < 9.0);
    } else {
        local_69 = false;
    }
    bool _e452 = local_69;
    if (_e452) {
        float Rs = (PL_V * a_27);
        float bq = dot(rd_10, Pb);
        float cq = (dot(Pb, Pb) - (Rs * Rs));
        float disc = ((bq * bq) - cq);
        if ((disc > 0.0)) {
            float sq = sqrt(disc);
            th = (bq - sq);
            float _e466 = th;
            if ((_e466 < 0.0)) {
                th = (bq + sq);
            }
            float _e470 = th;
            vec3 hp = (rd_10 * _e470);
            float _e472 = th;
            if ((_e472 > 0.0)) {
                float _e477 = th;
                local_70 = (_e477 < (scene_len_3 + 4.0));
            } else {
                local_70 = false;
            }
            bool _e482 = local_70;
            if (_e482) {
                local_71 = (hp.y > (C_10.y - 4.0));
            } else {
                local_71 = false;
            }
            bool _e491 = local_71;
            if (_e491) {
                float edge_3 = exp((-(sq) / ((0.045 * Rs) + 8.0)));
                float sf = ((1.0 - smoothstep(4.0, 9.0, a_27)) * _e12);
                vec3 _e505 = project_rel(Pb);
                vec2 _e506 = uv_4;
                dirs = (_e506 - _e505.xy);
                if ((_e505.z < 0.0)) {
                    vec2 _e513 = dirs;
                    dirs = -(_e513);
                }
                vec2 _e515 = dirs;
                vec2 off_3 = ((normalize((_e515 + vec2(1e-5))) * ((0.012 * edge_3) + (0.003 * exp((-(sq) / (0.25 * Rs)))))) * sf);
                vec2 _e534 = uv_4;
                vec4 _e537 = orbitalSceneLod(_group_0_binding_0_fs, vec2((_e534 - off_3)), 0.0);
                vec3 _e539 = srgb_to_linear(_e537.xyz);
                vec3 _e540 = col_4;
                col_4 = mix(_e540, _e539, (clamp(((edge_3 * 4.0) + 0.5), 0.0, 1.0) * sf));
                vec3 _e548 = col_4;
                col_4 = (_e548 + ((((vec3(0.9, 0.93, 1.0) * ((0.22 * edge_3) + (0.03 * exp((-(sq) / (0.3 * Rs)))))) * exp((-(a_27) / 1.6))) * sf) * (0.3 + (0.7 * day_2))));
            }
        }
    }
    float fl_1 = (((a_27 > 0.0) ? (((9.0 * exp((-(a_27) / 0.15))) + (1.0 * exp((-(a_27) / 1.2)))) + (0.15 * exp((-(a_27) / 10.0)))) : 0.0) * fade);
    if ((stage != 1u)) {
        local_72 = (a_27 > 0.0);
    } else {
        local_72 = false;
    }
    bool _e608 = local_72;
    if (_e608) {
        vec3 Pf = (C_10 + vec3(0.0, (PL_BURST + (80.0 * clamp((a_27 / 15.0), 0.0, 1.0))), 0.0));
        float df_1 = length(Pf);
        float cth = dot(rd_10, (Pf / vec3(df_1)));
        float th_2 = sqrt(max((2.0 * (1.0 - cth)), 0.0));
        vec3 fire_c = mix(vec3(3.0, 1.35, 0.42), vec3(3.2, 3.0, 2.8), exp((-(a_27) / 0.6)));
        vec3 _e644 = col_4;
        col_4 = (_e644 + (((fire_c * fl_1) * ((0.05 / (1.0 + pow((th_2 / 0.08), 2.0))) + (0.012 * exp((-(th_2) / 0.7))))) * _e12));
        if (_e159) {
            vec3 _e664 = col_4;
            col_4 = (_e664 + ((((vec3(1.0, 0.78, 0.52) * ((0.25 * exp((-(a_27) / 0.8))) + (0.025 * exp((-(a_27) / 8.0))))) * (0.35 + (0.65 * (1.0 - day_2)))) * _e12) * fade));
        } else {
            float dl_1 = length((_e164 - Pf));
            vec3 _e695 = col_4;
            col_4 = (_e695 + (((((_e179 * fire_c) * fl_1) * 0.9) / vec3((1.0 + pow((dl_1 / 320.0), 2.0)))) * _e12));
            float rg_1 = length((_e164 - C_10).xz);
            float rtg = (56.0 * (1.0 - exp((-(a_27) / 0.45))));
            float hot_2 = ((((2.0 * exp((-(a_27) / 0.8))) + (0.5 * exp((-(a_27) / 3.0)))) * (1.0 - smoothstep(((0.9 * rtg) + 6.0), ((1.7 * rtg) + 24.0), rg_1))) * (1.0 - smoothstep(10.0, 40.0, abs((_e164.y - C_10.y)))));
            vec3 _e756 = col_4;
            col_4 = (_e756 + ((((_e179 * vec3(3.0, 1.15, 0.32)) * hot_2) * _e12) * fade));
        }
    }
    if ((stage != 1u)) {
        local_73 = !(_e159);
    } else {
        local_73 = false;
    }
    bool _e772 = local_73;
    if (_e772) {
        local_74 = have;
    } else {
        local_74 = false;
    }
    bool _e776 = local_74;
    if (_e776) {
        local_75 = (a_27 > 0.3);
    } else {
        local_75 = false;
    }
    bool _e782 = local_75;
    if (_e782) {
        local_76 = (L_3.y > 0.02);
    } else {
        local_76 = false;
    }
    bool _e789 = local_76;
    if (_e789) {
        float _e796 = _group_0_binding_4_fs.mod_params[3].w;
        local_77 = (_e796 < 0.5);
    } else {
        local_77 = false;
    }
    bool _e800 = local_77;
    if (_e800) {
        float _e803 = ign(in_.position.xy);
        float _e804 = pl_shadow(_e164, L_3, a_27, C_10, _e803);
        vec3 _e805 = col_4;
        col_4 = (_e805 * (1.0 - ((((0.72 * (1.0 - _e804)) * sun_up) * _e12) * fade)));
    }
    if ((stage == 2u)) {
        vec3 _e818 = col_4;
        col_4 = ((_e818 * up_1.w) + up_1.xyz);
    }
    if ((stage != 2u)) {
        local_78 = have;
    } else {
        local_78 = false;
    }
    bool _e828 = local_78;
    if (_e828) {
        local_79 = (_e7 > PL_SEEN);
    } else {
        local_79 = false;
    }
    bool _e834 = local_79;
    if (_e834) {
        int _e835 = pl_n();
        float _e837 = pl_w(1u);
        float _e839 = pl_w(2u);
        float thead_1 = min(_e7, PL_HIT);
        int last_1 = min(int(floor(((thead_1 - _e837) / _e839))), (_e835 - 1));
        vec3 sd_1 = vec3((float((seed_20 % 97u)) * 3.1), (float((seed_20 % 89u)) * 1.7), 0.0);
        vec3 _e870 = pl_trail_pt(0, last_1, thead_1, _e7, seed_20);
        pa = (_e870 + C_9);
        vec3 _e873 = pa;
        pv = _e873;
        vec3 _e877 = pa;
        pc_1 = _e877;
        bool loop_init_13 = true;
        while(true) {
            if (!loop_init_13) {
                int _e1733 = i_19;
                i_19 = (_e1733 + 1);
            }
            loop_init_13 = false;
            int _e883 = i_19;
            if ((_e883 <= last_1)) {
            } else {
                break;
            }
            {
                int _e885 = i_19;
                if (((_e885 % 8) == 0)) {
                    int _e892 = i_19;
                    local_80 = ((_e892 + 8) <= last_1);
                } else {
                    local_80 = false;
                }
                bool _e897 = local_80;
                if (_e897) {
                    int _e898 = i_19;
                    vec3 _e901 = pl_trail_pt((_e898 + 8), last_1, thead_1, _e7, seed_20);
                    vec3 pg = (_e901 + C_9);
                    vec3 _e903 = pa;
                    vec3 cg = (0.5 * (_e903 + pg));
                    int _e907 = i_19;
                    float ag = max((_e7 - (_e837 + (_e839 * float(_e907)))), 0.0);
                    float tg = max(dot(cg, rd_10), 0.0);
                    vec3 _e917 = pa;
                    float rg_2 = (((0.65 * length((pg - _e917))) + (3.4 * ((6.0 + (4.8 * sqrt(ag))) + (tg * px_a)))) + 4.0);
                    if (!((length((cg - (rd_10 * tg))) > rg_2))) {
                        local_81 = ((tg - rg_2) > scene_len_3);
                    } else {
                        local_81 = true;
                    }
                    bool _e944 = local_81;
                    if (_e944) {
                        pa = pg;
                        have_pv = false;
                        have_pc = false;
                        int _e947 = i_19;
                        i_19 = (_e947 + 7);
                        continue;
                    }
                }
                bool _e950 = have_pv;
                if (!(_e950)) {
                    int _e952 = i_19;
                    vec3 _e955 = pl_trail_pt((_e952 - 1), last_1, thead_1, _e7, seed_20);
                    pv = (_e955 + C_9);
                }
                vec3 _e957 = pc_1;
                pb = _e957;
                bool _e959 = have_pc;
                if (!(_e959)) {
                    int _e961 = i_19;
                    vec3 _e964 = pl_trail_pt((_e961 + 1), last_1, thead_1, _e7, seed_20);
                    pb = (_e964 + C_9);
                }
                vec3 _e966 = pb;
                vec3 _e967 = pb;
                vec3 _e968 = pa;
                pn = (_e966 + (_e967 - _e968));
                int _e972 = i_19;
                if ((_e972 < last_1)) {
                    int _e974 = i_19;
                    vec3 _e977 = pl_trail_pt((_e974 + 2), last_1, thead_1, _e7, seed_20);
                    pn = (_e977 + C_9);
                }
                vec3 _e979 = pn;
                pc_1 = _e979;
                have_pc = true;
                vec3 pa_2 = pa;
                vec3 pv_1 = pv;
                vec3 _e983 = pa;
                pv = _e983;
                have_pv = true;
                vec3 _e985 = pb;
                pa = _e985;
                vec3 _e986 = pb;
                vec3 ab_5 = (_e986 - pa_2);
                float len_ab = max(length(ab_5), 0.0001);
                vec3 da = (ab_5 / vec3(len_ab));
                int _e993 = i_19;
                float te_a = (_e837 + (_e839 * float(_e993)));
                float age_a = max((_e7 - te_a), 0.0);
                na = da;
                oa = pa_2;
                int _e1002 = i_19;
                if ((_e1002 == 0)) {
                    oa = (pa_2 - (da * (2.0 + (2.0 * sqrt(age_a)))));
                } else {
                    na = normalize((da + normalize(((pa_2 - pv_1) + vec3(0.0, 1e-5, 0.0)))));
                }
                nb = da;
                vec3 _e1022 = pb;
                ob = _e1022;
                int _e1024 = i_19;
                if ((_e1024 < last_1)) {
                    vec3 _e1026 = pn;
                    vec3 _e1027 = pb;
                    nb = normalize((da + normalize(((_e1026 - _e1027) + vec3(0.0, 1e-5, 0.0)))));
                } else {
                    vec3 _e1037 = pb;
                    ob = (_e1037 + ((da * (12.0 + (8.0 * sqrt(max((_e7 - thead_1), 0.0))))) * step(PL_HIT, _e7)));
                }
                vec3 _e1051 = oa;
                vec3 _e1052 = na;
                vec2 _e1053 = pl_half(rd_10, _e1051, _e1052);
                vec3 _e1054 = ob;
                vec3 _e1055 = nb;
                vec2 _e1057 = pl_half(rd_10, _e1054, -(_e1055));
                float t1_1 = max(max(_e1053.x, _e1057.x), 0.0);
                float t2_ = min(min(_e1053.y, _e1057.y), scene_len_3);
                if ((t2_ <= t1_1)) {
                    continue;
                }
                vec3 _e1068 = pb;
                vec3 _e1071 = pl_ray_seg(rd_10, pa_2, _e1068, -10000.0, 10000.0);
                float tn_1 = clamp(_e1071.y, t1_1, t2_);
                float sz_1 = clamp((dot(((rd_10 * tn_1) - pa_2), da) / len_ab), 0.0, 1.0);
                vec3 cp = ((pa_2 + (ab_5 * sz_1)) + ((rd_10 * _e1071.y) - (pa_2 + (ab_5 * _e1071.z))));
                float te_1 = clamp((te_a + (_e839 * sz_1)), _e837, thead_1);
                float age_1 = max((_e7 - te_1), 0.0);
                float heat = (1.0 - smoothstep(5.4, 7.0, te_1));
                float dv_2 = smoothstep(7.0, PL_HIT, te_1);
                float rad0_ = (mix((1.2 + (3.0 * dv_2)), 5.5, heat) + (mix((1.5 + (1.5 * dv_2)), 4.5, heat) * sqrt(age_1)));
                float rad = max(rad0_, ((tn_1 * px_a) * 0.9));
                float thin_2 = (rad0_ / rad);
                if ((_e1071.x < (rad * 3.4))) {
                    local_82 = (0.0 < 1.0);
                } else {
                    local_82 = false;
                }
                bool _e1136 = local_82;
                if (_e1136) {
                    float sw_1 = ((2.2 * rad) + 3.0);
                    int _e1141 = i_19;
                    vec3 _e1142 = pl_trail_drift(_e1141, age_a, seed_20);
                    vec3 la = (pa_2 - _e1142);
                    vec3 _e1144 = pb;
                    lb = _e1144;
                    int _e1146 = i_19;
                    if ((_e1146 < last_1)) {
                        vec3 _e1148 = pb;
                        int _e1149 = i_19;
                        vec3 _e1156 = pl_trail_drift((_e1149 + 1), max((_e7 - (te_a + _e839)), 0.0), seed_20);
                        lb = (_e1148 - _e1156);
                    }
                    vec3 _e1158 = lb;
                    vec3 laid = (mix(la, _e1158, sz_1) - C_9);
                    vec3 across = (((cp - (pa_2 + (ab_5 * sz_1))) / vec3(sw_1)) + sd_1);
                    float lv = log2((sw_1 / 8.0));
                    float lk = floor(lv);
                    float lf_1 = (lv - lk);
                    float sA = (8.0 * exp2(lk));
                    vec3 qa_1 = (((laid / vec3(sA)) + across) + vec3((lk * 17.3), (lk * 5.1), 0.0));
                    vec3 qb = (((laid / vec3((2.0 * sA))) + across) + vec3(((lk + 1.0) * 17.3), ((lk + 1.0) * 5.1), 0.0));
                    float lsp = (1.0 / sqrt(((lf_1 * lf_1) + ((1.0 - lf_1) * (1.0 - lf_1)))));
                    float sn_2 = max(length(cross(rd_10, da)), 0.08);
                    float qs = (1.0 / ((2.2 * rad) + 3.0));
                    float along_1 = (((tn_1 * px_a) / sn_2) * qs);
                    float thru = (((((2.0 * sqrt(max((((2.1 * rad) * rad) - (_e1071.x * _e1071.x)), 0.0))) * abs(dot(rd_10, da))) / sn_2) * qs) + 0.001);
                    float w1_ = min(clamp((2.0 * sqrt((1.0 / thru))), 0.0, 1.0), clamp((2.0 - (10.0 * along_1)), 0.0, 1.0));
                    float w2_ = min(clamp((2.0 * sqrt((0.385 / thru))), 0.0, 1.0), clamp((2.0 - ((10.0 * along_1) * 2.6)), 0.0, 1.0));
                    float w3_ = min(clamp((2.0 * sqrt((0.164 / thru))), 0.0, 1.0), clamp((2.0 - ((10.0 * along_1) * 6.1)), 0.0, 1.0));
                    n1_ = 0.5;
                    n2_2 = 0.5;
                    n3_ = 0.5;
                    if ((w1_ > 0.0)) {
                        vec3 o_8 = vec3(0.0, 0.0, (0.06 * age_1));
                        float _e1297 = gnoise3_((qa_1 + o_8));
                        float _e1299 = gnoise3_((qb + o_8));
                        n1_ = (0.5 + ((mix(_e1297, _e1299, lf_1) - 0.5) * lsp));
                    }
                    if ((w2_ > 0.0)) {
                        vec3 o_9 = vec3(4.0, (0.08 * age_1), 1.0);
                        float _e1316 = gnoise3_(((qa_1 * 2.6) + o_9));
                        float _e1320 = gnoise3_(((qb * 2.6) + o_9));
                        n2_2 = (0.5 + ((mix(_e1316, _e1320, lf_1) - 0.5) * lsp));
                    }
                    if ((w3_ > 0.0)) {
                        vec3 o_10 = vec3(1.0, 7.0, (0.15 * age_1));
                        float _e1337 = gnoise3_(((qa_1 * 6.1) + o_10));
                        float _e1341 = gnoise3_(((qb * 6.1) + o_10));
                        n3_ = (0.5 + ((mix(_e1337, _e1341, lf_1) - 0.5) * lsp));
                    }
                    float _e1350 = n1_;
                    float _e1358 = n2_2;
                    float _e1365 = n3_;
                    float puff = (((0.5 + ((0.62 * w1_) * (_e1350 - 0.5))) + ((0.3 * w2_) * (_e1358 - 0.5))) + ((0.08 * w3_) * (_e1365 - 0.5)));
                    float rw = (rad * (0.45 + (1.0 * puff)));
                    float rr_1 = (_e1071.x / rw);
                    float prof = (exp(((-(rr_1) * rr_1) * 1.4)) * smoothstep(2.3, 1.5, rr_1));
                    float ka = ((1.183 * sn_2) / rw);
                    float _e1392 = pl_erf(((t2_ - _e1071.y) * ka));
                    float _e1396 = pl_erf(((t1_1 - _e1071.y) * ka));
                    float gin = ((0.5 * (_e1392 - _e1396)) / max(sn_2, 0.5));
                    float thr = ((mix(0.32, 0.12, 0.0) - (0.1 * heat)) + (0.38 * smoothstep(1.5, 18.0, age_1)));
                    float m_7 = (((puff - thr) * 3.2) + (0.3 * exp((-(age_1) / 0.8))));
                    float sl = ((0.448 * sqrt((((0.384 * (1.0 - (w1_ * w1_))) + (0.09 * (1.0 - (w2_ * w2_)))) + (0.0064 * (1.0 - (w3_ * w3_)))))) + 0.001);
                    float dens_1 = clamp((sl * log((1.0 + exp(clamp((m_7 / sl), -30.0, 30.0))))), 0.0, 1.0);
                    float sig = (((((mix((0.45 + (0.35 * dv_2)), 0.8, heat) * exp((-(age_1) / mix(9.0, 16.0, heat)))) * exp((-(max((_e7 - PL_HIT), 0.0)) / 2.5))) * fade) * thin_2) * (1.0 - 0.0));
                    float dtau = (((((sig * prof) * dens_1) * 1.6) * rad) * gin);
                    vec3 axis = (pa_2 + (ab_5 * sz_1));
                    vec3 nrm_1 = normalize((((cp - axis) - (rd_10 * (0.6 * rad))) + vec3(0.0, 0.0001, 0.0)));
                    float _e1503 = n1_;
                    float ln_1 = (0.5 + (w1_ * (_e1503 - 0.5)));
                    float lit_1 = ((0.35 + (0.65 * clamp(((dot(nrm_1, L_3) * 0.5) + 0.5), 0.0, 1.0))) * (0.6 + ((0.8 * ln_1) * ln_1)));
                    alb = mix(mix(mix(vec3(0.5, 0.5, 0.52), vec3(0.72, 0.72, 0.74), dv_2), vec3(0.74, 0.71, 0.66), heat), vec3(0.17, 0.145, 0.125), 0.0);
                    vec3 _e1545 = alb;
                    vec3 _e1546 = alb;
                    alb = mix(_e1545, ((_e1546 * 1.35) + vec3(0.03)), smoothstep(4.0, 20.0, age_1));
                    vec3 _e1556 = alb;
                    c_14 = (_e1556 * (((sunc * lit_1) * 0.85) + (amb * (0.6 + (0.4 * ln_1)))));
                    vec3 _e1568 = c_14;
                    c_14 = (_e1568 + ((((vec3(1.9, 0.75, 0.22) * exp((-(age_1) / 0.12))) * 0.0) * step(_e7, 11.3)) * (0.4 + (0.6 * ln_1))));
                    vec3 _e1588 = c_14;
                    c_14 = (_e1588 + (((vec3(2.2, 0.9, 0.35) * exp((-(age_1) / 0.35))) * heat) * (0.5 + (0.5 * ln_1))));
                    vec3 _e1605 = c_14;
                    c_14 = mix(_e1605, haze_c, ((1.0 - exp((-(tn_1) / 3000.0))) * 0.75));
                    vec3 _e1615 = tc;
                    vec3 _e1616 = c_14;
                    tc = (_e1615 + (_e1616 * dtau));
                    float _e1619 = tau_2;
                    tau_2 = (_e1619 + dtau);
                    float gx = length(((rd_10 * tn_1) - axis));
                    float chord = (2.0 * sqrt(max(((rad * rad) - (gx * gx)), 0.0)));
                    float fl_2 = ((0.0 * exp((-(age_1) / 0.13))) * step(_e7, 11.05));
                    float fw = (rad * (0.75 - (0.35 * clamp((age_1 / 0.3), 0.0, 1.0))));
                    float fprof = (exp((-(pow((gx / max(fw, 0.5)), 2.0)) * 1.6)) * min((fw * 0.5), 1.0));
                    vec3 _e1662 = glow;
                    glow = max(_e1662, (((mix(vec3(3.2, 1.0, 0.18), vec3(4.0, 2.6, 1.0), exp((-(age_1) / 0.06))) * fl_2) * 1.6) * fprof));
                    float fh = ((max(heat, ((0.1 * dv_2) * dv_2)) * exp((-(age_1) / mix(0.45, 0.25, dv_2)))) * step(_e7, PL_HIT));
                    float gr = (rad * 0.5);
                    float gch = sqrt(max((1.0 - ((gx * gx) / (gr * gr))), 0.0));
                    vec3 gcol = mix(mix(vec3(1.3, 0.35, 0.3), vec3(2.6, 0.95, 0.3), exp((-(age_1) / 0.4))), vec3(3.4, 3.0, 2.3), exp((-(age_1) / 0.1)));
                    vec3 _e1727 = glow;
                    glow = max(_e1727, (((gcol * fh) * gch) * 1.4));
                }
            }
        }
        float _e1736 = tau_2;
        if ((_e1736 > 0.0)) {
            float _e1739 = tau_2;
            float al_1 = (1.0 - exp(-(_e1739)));
            if ((stage == 0u)) {
                vec3 _e1746 = col_4;
                vec3 _e1747 = tc;
                float _e1748 = tau_2;
                col_4 = mix(_e1746, (_e1747 / vec3(_e1748)), (al_1 * _e12));
            } else {
                vec3 _e1753 = tc;
                float _e1754 = tau_2;
                pl_over(hc_1, (_e1753 / vec3(_e1754)), (al_1 * _e12));
            }
        }
        if ((stage == 0u)) {
            vec3 _e1760 = col_4;
            vec3 _e1761 = glow;
            col_4 = (_e1760 + (_e1761 * _e12));
        } else {
            vec4 _e1764 = hc_1;
            vec3 _e1766 = glow;
            float _e1770 = hc_1.w;
            hc_1 = vec4((_e1764.xyz + (_e1766 * _e12)), _e1770);
        }
    }
    if (have) {
        local_83 = (_e7 > PL_SEEN);
    } else {
        local_83 = false;
    }
    bool _e1777 = local_83;
    if (_e1777) {
        local_84 = (_e7 < 18.0);
    } else {
        local_84 = false;
    }
    bool _e1783 = local_84;
    if (_e1783) {
        float _e1785 = pl_w(7u);
        int nf = min(int((_e1785 + 0.5)), 32);
        bool loop_init_14 = true;
        while(true) {
            if (!loop_init_14) {
                int _e2151 = f_10;
                f_10 = (_e2151 + 1);
            }
            loop_init_14 = false;
            int _e1801 = f_10;
            if ((_e1801 < nf)) {
            } else {
                break;
            }
            {
                int _e1805 = f_10;
                uint b_16 = (PL_FR + (PL_FW * uint(_e1805)));
                float _e1809 = pl_w(b_16);
                float s_16 = (_e7 - _e1809);
                float _e1813 = pl_w((b_16 + 1u));
                if (!((s_16 <= 0.0))) {
                    local_85 = (s_16 > (_e1813 + 3.6));
                } else {
                    local_85 = true;
                }
                bool _e1823 = local_85;
                if (_e1823) {
                    continue;
                }
                float _e1826 = pl_w((b_16 + 2u));
                float _e1829 = pl_w((b_16 + 3u));
                bool spark = (_e1829 > 0.5);
                float _e1834 = pl_w((b_16 + 4u));
                float kd_1 = max(_e1834, 0.05);
                float _e1839 = pl_w((b_16 + 5u));
                float _e1842 = pl_w((b_16 + 6u));
                float _e1845 = pl_w((b_16 + 7u));
                vec3 p0_3 = (vec3(_e1839, _e1842, _e1845) + C_9);
                float _e1850 = pl_w((b_16 + 8u));
                float _e1853 = pl_w((b_16 + 9u));
                float _e1856 = pl_w((b_16 + 10u));
                vec3 v0_2 = vec3(_e1850, _e1853, _e1856);
                if ((stage != 1u)) {
                    local_86 = (s_16 < _e1813);
                } else {
                    local_86 = false;
                }
                bool _e1864 = local_86;
                if (_e1864) {
                    vec3 _e1865 = pl_frag(p0_3, v0_2, kd_1, s_16);
                    vec3 _e1872 = pl_frag(p0_3, v0_2, kd_1, max((s_16 - (spark ? 0.05 : 0.03)), 0.0));
                    vec3 _e1873 = ray_seg(rd_10, _e1865, _e1872);
                    if ((_e1873.y < ((stage == 2u) ? min((scene_len_3 + 2.0), up_t) : (scene_len_3 + 2.0)))) {
                        float w_12 = max(_e1826, ((_e1873.y * px_a) * 0.8));
                        float e_12 = min((_e1826 / w_12), 1.0);
                        float u_22 = (s_16 / _e1813);
                        vec3 hot_3 = (spark ? vec3(4.0, 3.2, 1.8) : mix(vec3(4.0, 2.3, 1.0), vec3(2.6, 0.75, 0.12), u_22));
                        int _e1909 = f_10;
                        float fl_3 = (0.75 + (0.25 * sin(((_e7 * 41.0) + (float(_e1909) * 2.3)))));
                        vec3 _e1919 = fglow;
                        fglow = (_e1919 + (((((hot_3 * ((exp(-(pow((_e1873.x / w_12), 2.0))) * 3.0) + (0.25 * exp((-(_e1873.x) / (w_12 * 4.0)))))) * e_12) * e_12) * (1.0 - (u_22 * u_22))) * fl_3));
                    }
                }
                if ((stage != 2u)) {
                    local_87 = !(spark);
                } else {
                    local_87 = false;
                }
                bool _e1952 = local_87;
                if (_e1952) {
                    float s_hi = min(s_16, _e1813);
                    float s_lo = max((s_16 - 3.5), 0.0);
                    vec3 _e1958 = pl_frag(p0_3, v0_2, kd_1, s_hi);
                    vec3 _e1959 = pl_frag(p0_3, v0_2, kd_1, s_lo);
                    vec3 cq_1 = (0.5 * (_e1959 + _e1958));
                    float rq = (((0.75 * length((_e1958 - _e1959))) + ((2.0 * _e1826) * (0.6 + (1.1 * sqrt((s_16 - s_lo)))))) + 3.0);
                    float tq_3 = max(dot(cq_1, rd_10), 0.0);
                    if ((s_hi > s_lo)) {
                        local_88 = (length((cq_1 - (rd_10 * tq_3))) < rq);
                    } else {
                        local_88 = false;
                    }
                    bool _e1990 = local_88;
                    if (_e1990) {
                        local_89 = ((tq_3 - rq) < scene_len_3);
                    } else {
                        local_89 = false;
                    }
                    bool _e1996 = local_89;
                    if (_e1996) {
                        qa = _e1959;
                        j_4 = 1;
                        bool loop_init_15 = true;
                        while(true) {
                            if (!loop_init_15) {
                                int _e2148 = j_4;
                                j_4 = (_e2148 + 1);
                            }
                            loop_init_15 = false;
                            int _e2000 = j_4;
                            if ((_e2000 <= 8)) {
                            } else {
                                break;
                            }
                            {
                                int _e2004 = j_4;
                                float sj = (s_lo + (((s_hi - s_lo) * float(_e2004)) / 8.0));
                                vec3 _e2010 = pl_frag(p0_3, v0_2, kd_1, sj);
                                vec3 _e2011 = qa;
                                vec3 _e2012 = ray_seg(rd_10, _e2011, _e2010);
                                float age_2 = (s_16 - (sj - (((s_hi - s_lo) / 8.0) * (1.0 - _e2012.z))));
                                float rad_1 = (_e1826 * (0.6 + (1.1 * sqrt(age_2))));
                                if ((_e2012.x < (rad_1 * 2.0))) {
                                    local_90 = (_e2012.y < (scene_len_3 + rad_1));
                                } else {
                                    local_90 = false;
                                }
                                bool _e2038 = local_90;
                                if (_e2038) {
                                    if (!((_e2012.z < 0.9999))) {
                                        int _e2047 = j_4;
                                        local_92 = (_e2047 == 8);
                                    } else {
                                        local_92 = true;
                                    }
                                    bool _e2051 = local_92;
                                    local_91 = _e2051;
                                } else {
                                    local_91 = false;
                                }
                                bool _e2053 = local_91;
                                if (_e2053) {
                                    vec3 cp_1 = (rd_10 * _e2012.y);
                                    int _e2063 = f_10;
                                    float _e2072 = gnoise3_((((cp_1 - C_9) / vec3(((2.5 * rad_1) + 1.0))) + vec3((float(_e2063) * 7.1), 0.0, (0.1 * age_2))));
                                    float prof_1 = exp((-(pow((_e2012.x / (rad_1 * (0.5 + _e2072))), 2.0)) * 1.4));
                                    float dens_2 = clamp((((_e2072 - 0.18) - (0.25 * smoothstep(0.5, 3.5, age_2))) * 3.0), 0.0, 1.0);
                                    float dtau_1 = ((((((0.5 * exp((-(age_2) / 1.8))) * prof_1) * dens_2) * 1.6) * rad_1) * fade);
                                    c_15 = (vec3(0.45, 0.43, 0.4) * ((sunc * 0.75) + (amb * 0.8)));
                                    vec3 _e2118 = c_15;
                                    c_15 = (_e2118 + ((vec3(1.6, 0.6, 0.15) * exp((-(age_2) / 0.1))) * step(s_16, _e1813)));
                                    vec3 _e2131 = c_15;
                                    c_15 = mix(_e2131, haze_c, ((1.0 - exp((-(_e2012.y) / 3000.0))) * 0.75));
                                    vec3 _e2142 = ftc;
                                    vec3 _e2143 = c_15;
                                    ftc = (_e2142 + (_e2143 * dtau_1));
                                    float _e2146 = ftau;
                                    ftau = (_e2146 + dtau_1);
                                }
                                qa = _e2010;
                            }
                        }
                    }
                }
            }
        }
        float _e2154 = ftau;
        if ((_e2154 > 0.0)) {
            if ((stage == 0u)) {
                vec3 _e2159 = col_4;
                vec3 _e2160 = ftc;
                float _e2161 = ftau;
                float _e2164 = ftau;
                col_4 = mix(_e2159, (_e2160 / vec3(_e2161)), ((1.0 - exp(-(_e2164))) * _e12));
            } else {
                vec3 _e2171 = ftc;
                float _e2172 = ftau;
                float _e2175 = ftau;
                pl_over(hc_1, (_e2171 / vec3(_e2172)), ((1.0 - exp(-(_e2175))) * _e12));
            }
        }
        vec3 _e2181 = col_4;
        vec3 _e2182 = fglow;
        col_4 = (_e2181 + ((_e2182 * _e12) * fade));
    }
    col_t = ((stage == 2u) ? up_t : 1000000000.0);
    {
        float heat_1 = exp((-(a_27) / 0.6));
        float glow_2 = ((1.0 * (1.0 - smoothstep(4.5, 9.0, a_27))) + (0.12 * exp((-(a_27) / 10.0))));
        if ((stage != 2u)) {
            local_93 = have;
        } else {
            local_93 = false;
        }
        bool _e2214 = local_93;
        if (_e2214) {
            local_94 = (a_27 > 0.0);
        } else {
            local_94 = false;
        }
        bool _e2220 = local_94;
        if (_e2220) {
            PlCol _e2221 = pl_column(a_27, C_10);
            cl = _e2221;
            float _e2224 = cl.hc;
            vec3 _e2229 = pl_wind();
            vec3 ctop_1 = ((C_10 + vec3(0.0, _e2224, 0.0)) + (_e2229 * a_27));
            vec3 _e2239 = pl_ray_seg(rd_10, (C_10 - vec3(0.0, 20.0, 0.0)), ctop_1, 0.0, 1.0);
            float _e2241 = cl.Rt;
            float _e2243 = cl.rt;
            float _e2247 = cl.surge.x;
            float _e2250 = cl.surge.y;
            float _e2253 = cl.rt;
            float _e2257 = cl.rt;
            vec3 _e2267 = pl_wind();
            float crad = (((max((_e2241 + _e2243), max((_e2247 + _e2250), ((0.8 * _e2253) + (0.15 * _e2257)))) + PL_DM) + 30.0) + ((0.2 * length(_e2267)) * a_27));
            vec3 _e2274 = cl.lo;
            vec3 _e2276 = cl.hi;
            vec2 _e2277 = pl_box(rd_10, _e2274, _e2276);
            float t1_2 = min(_e2277.y, scene_len_3);
            if ((_e2239.x < crad)) {
                local_95 = (t1_2 > _e2277.x);
            } else {
                local_95 = false;
            }
            bool _e2287 = local_95;
            if (_e2287) {
                t_7 = _e2277.x;
                float _e2305 = ign((in_.position.xy + vec2((fract((_e7 * 7.0)) * 37.0), 0.0)));
                float ph_2 = (0.8 + ((0.5 + (1.6 * warm)) * pow(clamp(dot(rd_10, L_3), 0.0, 1.0), 5.0)));
                float soft_1 = smoothstep(PL_SOFT0_, PL_SOFT1_, a_27);
                float thin_3 = exp((-(max(((a_27 - PL_SOFT0_) - 12.0), 0.0)) / 7.0));
                vec3 sootc = mix(mix(vec3(0.2, 0.14, 0.1), vec3(0.44, 0.37, 0.31), smoothstep(9.0, 20.0, a_27)), vec3(0.56, 0.51, 0.46), smoothstep(20.0, 45.0, a_27));
                bool loop_init_16 = true;
                while(true) {
                    if (!loop_init_16) {
                        int _e3122 = i_20;
                        i_20 = (_e3122 + 1);
                    }
                    loop_init_16 = false;
                    int _e2368 = i_20;
                    if ((_e2368 < 128)) {
                    } else {
                        break;
                    }
                    {
                        float _e2371 = t_7;
                        if (!((_e2371 > t1_2))) {
                            float _e2376 = tr_1;
                            local_96 = (_e2376 < 0.03);
                        } else {
                            local_96 = true;
                        }
                        bool _e2380 = local_96;
                        if (_e2380) {
                            break;
                        }
                        float _e2381 = t_7;
                        vec3 p_30 = (rd_10 * _e2381);
                        vec2 _e2383 = pl_col_base2_(cl, p_30);
                        float d0_1 = _e2383.x;
                        float dr_2 = _e2383.y;
                        float db = min(d0_1, dr_2);
                        if ((db > 84.0)) {
                            float _e2389 = t_7;
                            t_7 = (_e2389 + (((db - PL_DM) - 4.0) * 0.52));
                            continue;
                        }
                        float _e2397 = t_7;
                        float st = (max(5.0, (_e2397 * 0.009)) * (0.75 + (0.5 * _e2305)));
                        den = 0.0;
                        ringw = 0.0;
                        sd = vec4(d0_1, 0.5, 4.0, 0.5);
                        if ((d0_1 < -76.0)) {
                            sd = vec4(d0_1, 0.45, 4.0, 0.5);
                            den = thin_3;
                        } else {
                            if ((d0_1 < 74.0)) {
                                vec4 _e2425 = pl_col_sdf(cl, p_30, d0_1, true);
                                sd = _e2425;
                                float _e2427 = sd.x;
                                float _e2430 = sd.z;
                                float ramp = clamp((-(_e2427) / (_e2430 + (40.0 * soft_1))), 0.0, 1.0);
                                float _e2437 = sd.w;
                                den = ((ramp * mix(clamp((0.15 + (1.7 * _e2437)), 0.0, 1.0), 1.0, (ramp * ramp))) * thin_3);
                            }
                        }
                        if ((dr_2 < 12.0)) {
                            float _e2459 = gnoise3_((((p_30 + cam_6) * 0.14285715) + vec3(0.0, 0.0, (0.15 * a_27))));
                            float _e2472 = gnoise3_((((p_30 + cam_6) * vec3(0.025, 0.071428575, 0.025)) + vec3(3.0, 0.0, (0.05 * a_27))));
                            float _e2488 = cl.ring.z;
                            float rd0_1 = (((clamp(((-(dr_2) + (12.0 * (_e2459 - 0.5))) / 14.0), 0.0, 1.0) * smoothstep(0.3, 0.7, _e2472)) * _e2488) * 0.12);
                            float _e2492 = den;
                            ringw = (rd0_1 / max((rd0_1 + _e2492), 0.0001));
                            float _e2497 = den;
                            den = (_e2497 + rd0_1);
                        }
                        float _e2509 = cl.sr.x;
                        float _e2514 = cl.sr.x;
                        float sw_2 = ((1.0 - smoothstep(25.0, 70.0, (p_30.y - C_10.y))) * smoothstep((0.8 * _e2509), (1.6 * _e2514), length((p_30 - C_10).xz)));
                        float _e2522 = den;
                        den = (_e2522 * (1.0 - (0.7 * sw_2)));
                        if ((soft_1 > 0.0)) {
                            float _e2532 = den;
                            local_97 = (_e2532 > 0.002);
                        } else {
                            local_97 = false;
                        }
                        bool _e2536 = local_97;
                        if (_e2536) {
                            vec3 _e2540 = pl_wind();
                            float _e2551 = gnoise3_(((((p_30 + cam_6) * 0.05) - (_e2540 * (a_27 * 0.09))) + vec3(0.0, (-0.05 * a_27), 0.0)));
                            float _e2552 = den;
                            den = (_e2552 * mix(1.0, clamp((0.2 + (1.6 * _e2551)), 0.0, 1.0), soft_1));
                        }
                        float _e2561 = den;
                        if ((_e2561 > 0.002)) {
                            int _e2564 = nl_2;
                            if ((_e2564 == 0)) {
                                float _e2568 = sd.y;
                                em_y = _e2568;
                                vec3 _e2573 = pl_lean(cl, (p_30.y - C_10.y));
                                vec3 qs_1 = ((p_30 - C_10) - _e2573);
                                float _e2583 = gnoise3_(((qs_1 * 0.020833334) + vec3(2.3, (-0.03 * a_27), 5.1)));
                                em_k = smoothstep(0.42, 0.68, _e2583);
                            }
                            float _e2587 = tr_1;
                            if (!((_e2587 > 0.25))) {
                                int _e2593 = nl_2;
                                local_98 = (_e2593 == 0);
                            } else {
                                local_98 = true;
                            }
                            bool _e2597 = local_98;
                            if (_e2597) {
                                vec3 fp_3 = (p_30 + (L_3 * 9.0));
                                vec2 _e2601 = pl_col_base2_(cl, fp_3);
                                vec4 _e2604 = pl_col_sdf(cl, fp_3, _e2601.x, false);
                                float _e2607 = sd.x;
                                lc_face = (_e2604.x - _e2607);
                                float _e2612 = pl_col_base(cl, (p_30 + (L_3 * 20.0)));
                                float s1_1 = clamp(((10.0 - _e2612) / 34.0), 0.0, 1.0);
                                float _e2621 = pl_col_base(cl, (p_30 + (L_3 * 55.0)));
                                float s2_ = clamp(((10.0 - _e2621) / 46.0), 0.0, 1.0);
                                float _e2630 = pl_col_base(cl, (p_30 + (L_3 * 120.0)));
                                float s3_ = clamp(((8.0 - _e2630) / 60.0), 0.0, 1.0);
                                lc_bulk = exp((-((((s1_1 * 10.0) + (s2_ * 18.0)) + (s3_ * 22.0))) * 0.3));
                                float _e2653 = pl_col_base(cl, (p_30 + vec3(0.0, 80.0, 0.0)));
                                sky_occ = clamp(((12.0 - _e2653) / 70.0), 0.0, 1.0);
                            }
                            int _e2659 = nl_2;
                            nl_2 = (_e2659 + 1);
                            float _e2662 = lc_face;
                            float lam = mix(clamp((0.25 + (_e2662 / 7.0)), 0.0, 1.0), 0.65, soft_1);
                            float _e2671 = cl.hc;
                            float _e2673 = cl.rt;
                            float _e2678 = cl.Rt;
                            float _e2680 = cl.rt;
                            float _e2682 = pl_cap_shade(p_30, L_3, a_27, C_10, (_e2671 - (0.3 * _e2673)), (_e2678 + _e2680));
                            float _e2683 = lc_bulk;
                            float _e2688 = ringw;
                            float tsun = max(((mix(_e2683, 0.7, soft_1) * lam) * _e2682), ((0.45 * _e2688) * _e2682));
                            float _e2697 = cl.hc;
                            float _e2699 = cl.rt;
                            float hy_4 = clamp(((p_30.y - C_10.y) / max((_e2697 + _e2699), 1.0)), 0.0, 1.0);
                            float deep = clamp((-(d0_1) / 70.0), 0.0, 1.0);
                            float _e2710 = sd.y;
                            float _e2720 = sky_occ;
                            float ao = mix((((0.55 + (0.45 * _e2710)) * (1.0 - (0.6 * deep))) * (1.0 - (0.6 * _e2720))), 0.75, soft_1);
                            float _e2728 = em_k;
                            float _e2729 = em_y;
                            float kb = (_e2728 * clamp((1.5 - (1.6 * _e2729)), 0.0, 1.0));
                            float _e2737 = sd.w;
                            float _e2745 = sd.y;
                            float mv = (((0.9 + (0.2 * (_e2737 - 0.5))) + (0.25 * (_e2745 - 0.5))) * (1.0 - (0.35 * kb)));
                            alb_1 = (mix(vec3(0.43, 0.38, 0.32), sootc, smoothstep(0.08, 0.45, hy_4)) * mv);
                            vec3 _e2766 = alb_1;
                            float _e2771 = ringw;
                            alb_1 = mix(_e2766, vec3(0.85, 0.86, 0.88), _e2771);
                            vec3 _e2773 = alb_1;
                            alb_1 = (_e2773 * (1.0 - (0.3 * sw_2)));
                            vec3 _e2779 = skyl;
                            vec3 _e2780 = skyl;
                            vec3 skyg = (mix(mix(_e2779, vec3(dot(_e2780, vec3(0.2126, 0.7152, 0.0722))), 0.45), _e425, 0.15) * (1.0 - (0.35 * warm)));
                            float lift_1 = smoothstep(5.0, 10.0, a_27);
                            vec3 _e2799 = alb_1;
                            c_16 = (_e2799 * ((((skyg * ((mix(0.48, 0.75, lift_1) * ao) * (0.35 + (0.65 * hy_4)))) + (((mix(vec3(0.2, 0.17, 0.13), vec3(0.3, 0.26, 0.2), lift_1) * day_2) * (1.0 - (0.6 * warm))) * ao)) * mix(0.55, 1.0, _e2682)) + ((sunc * vec3(0.95, 0.85, 0.72)) * ((1.05 * tsun) * ph_2))));
                            float _e2844 = cl.hc;
                            float _e2846 = cl.rt;
                            float _e2851 = cl.hc;
                            float _e2853 = cl.rt;
                            float capw = smoothstep((_e2844 - (1.8 * _e2846)), (_e2851 - (0.6 * _e2853)), (p_30.y - C_10.y));
                            vec3 _e2865 = pl_lean(cl, (p_30.y - C_10.y));
                            vec3 qg = ((p_30 - C_10) - _e2865);
                            float _e2870 = cl.Rt;
                            float _e2874 = cl.hc;
                            vec2 gv = vec2((length(qg.xz) - _e2870), ((qg.y - _e2874) * 1.2));
                            float _e2882 = cl.rt;
                            float ringc = exp((-(dot(gv, gv)) / pow((0.55 * _e2882), 2.0)));
                            float _e2892 = cl.rt;
                            float core_2 = mix((1.0 - exp((min(d0_1, 0.0) / ((0.22 * _e2892) + 6.0)))), ringc, smoothstep(2.0, 9.0, a_27));
                            float _e2906 = cl.hc;
                            float _e2908 = cl.rt;
                            float _e2913 = cl.hc;
                            float _e2915 = cl.rt;
                            float under = (1.0 - smoothstep((_e2906 - (0.6 * _e2908)), (_e2913 + (0.5 * _e2915)), (p_30.y - C_10.y)));
                            float surf = ((1.5 * (1.0 - smoothstep(4.5, 8.5, a_27))) + (0.6 * exp((-(a_27) / 1.2))));
                            float _e2962 = ringw;
                            float _e2967 = sd.y;
                            float _e2973 = sd.y;
                            float _e2979 = em_y;
                            float e_13 = ((((((heat_1 * 5.0) + surf) + ((glow_2 * (0.06 + (((3.2 * core_2) * core_2) * (exp((-(a_27) / 6.0)) + 0.12)))) * (0.3 + (1.4 * under)))) * capw) * (1.0 - _e2962)) * mix((0.1 + ((2.3 * (1.0 - _e2967)) * (1.0 - _e2973))), ((0.05 + (0.75 * smoothstep(0.2, 1.0, _e2979))) * (1.0 - (0.6 * kb))), smoothstep(0.3, 1.3, a_27)));
                            vec3 tcol = mix(mix(vec3(0.9, 0.13, 0.03), vec3(2.8, 0.95, 0.16), clamp(((glow_2 * 1.3) + (0.15 * core_2)), 0.0, 1.0)), vec3(3.4, 3.0, 2.4), heat_1);
                            float lowlit = ((((1.0 - capw) * ((heat_1 * 2.0) + (0.6 * glow_2))) * exp((-(max((p_30.y - C_10.y), 0.0)) / 90.0))) * 0.4);
                            float en = (e_13 * (1.0 + (1.6 * (1.0 - day_2))));
                            vec3 _e3044 = c_16;
                            c_16 = (((_e3044 * (1.0 - ((0.6 * capw) * (1.0 - smoothstep(4.0, 8.0, a_27))))) * (1.0 - clamp((en * 1.2), 0.0, 1.0))) + (tcol * ((en * 0.6) + lowlit)));
                            float _e3067 = den;
                            float ext = ((_e3067 * 0.32) * st);
                            float al_2 = (1.0 - exp(-(ext)));
                            vec3 _e3075 = acc_1;
                            float _e3076 = tr_1;
                            vec3 _e3078 = c_16;
                            acc_1 = (_e3075 + ((_e3076 * al_2) * _e3078));
                            float _e3081 = tmid;
                            float _e3082 = tr_1;
                            float _e3084 = t_7;
                            tmid = (_e3081 + ((_e3082 * al_2) * _e3084));
                            float _e3087 = wmid;
                            float _e3088 = tr_1;
                            wmid = (_e3087 + (_e3088 * al_2));
                            float _e3091 = tr_1;
                            tr_1 = (_e3091 * (1.0 - al_2));
                        }
                        float _e3095 = t_7;
                        float _e3097 = sd.x;
                        int _e3105 = i_20;
                        float _e3116 = sd.x;
                        t_7 = (_e3095 + ((min(_e3116, dr_2) > 0.0) ? max((0.55 * min(_e3097, dr_2)), (((0.12 * st) + 0.25) * min((1.0 + (0.06 * float(_e3105))), 2.5))) : st));
                    }
                }
                float _e3125 = tr_1;
                if ((_e3125 < 0.999)) {
                    float _e3128 = tmid;
                    float _e3129 = wmid;
                    float dist = (_e3128 / max(_e3129, 0.0001));
                    float _e3133 = tr_1;
                    if ((_e3133 < 0.5)) {
                        col_t = dist;
                    }
                    float ap_1 = (1.0 - exp((-(dist) / 4000.0)));
                    vec3 _e3142 = acc_1;
                    float _e3143 = tr_1;
                    vec3 ccol = mix((_e3142 / vec3(max((1.0 - _e3143), 0.0001))), haze_c, ((ap_1 * 0.75) * mix(0.25, 1.0, smoothstep(5.0, 9.0, a_27))));
                    if ((stage == 0u)) {
                        vec3 _e3162 = col_4;
                        float _e3163 = tr_1;
                        col_4 = mix(_e3162, ccol, (((1.0 - _e3163) * _e12) * fade));
                    } else {
                        float _e3169 = tr_1;
                        pl_over(hc_1, ccol, (((1.0 - _e3169) * _e12) * fade));
                    }
                }
            }
        }
    }
    if ((stage != 1u)) {
        local_99 = have;
    } else {
        local_99 = false;
    }
    bool _e3179 = local_99;
    if (_e3179) {
        local_100 = (_e7 > 0.7);
    } else {
        local_100 = false;
    }
    bool _e3185 = local_100;
    if (_e3185) {
        local_101 = (_e7 < 11.03);
    } else {
        local_101 = false;
    }
    bool _e3191 = local_101;
    if (_e3191) {
        float tb_2 = min(_e7, PL_HIT);
        vec3 _e3194 = pl_head(tb_2);
        vec3 cen = (_e3194 + C_9);
        float dh = length(cen);
        vec3 hn = (cen / vec3(dh));
        float cth_1 = dot(rd_10, hn);
        float th_3 = sqrt(max((2.0 * (1.0 - cth_1)), 0.0));
        vec3 _e3207 = project_rel(cen);
        if ((_e3207.z > 0.0)) {
            local_102 = all(greaterThan(_e3207.xy, vec2(0.0)));
        } else {
            local_102 = false;
        }
        bool _e3221 = local_102;
        if (_e3221) {
            local_103 = all(lessThan(_e3207.xy, vec2(1.0)));
        } else {
            local_103 = false;
        }
        bool _e3230 = local_103;
        if (_e3230) {
            float _e3232 = depth_at(_e3207.xy);
            bool _e3233 = is_sky(_e3232);
            if (!(_e3233)) {
                vec3 _e3238 = world_offset(_e3207.xy, _e3232);
                local_104 = (length(_e3238) < (dh - 3.0));
            } else {
                local_104 = false;
            }
            bool _e3244 = local_104;
            if (_e3244) {
                vis = 0.0;
            }
        } else {
            if ((cth_1 < 0.0)) {
                vis = 0.0;
            }
        }
        float _e3252 = vis;
        float show = ((smoothstep(0.7, 1.15, _e7) * _e3252) * _e12);
        vec3 _e3257 = pl_head((tb_2 - 0.06));
        vec3 vd = normalize(((_e3194 - _e3257) + vec3(0.0, -0.0001, 0.0)));
        float heat_2 = (1.0 - smoothstep(5.4, 7.0, _e7));
        float dive = smoothstep(PL_DIVE, PL_HIT, _e7);
        float vc_2 = smoothstep(8.8, 10.7, _e7);
        vec2 sw_3 = (vec2(sin((_e7 * 1.7)), cos((_e7 * 1.3))) * mix(0.04, 0.012, dive));
        vec3 e1_1 = normalize(cross(vd, ((abs(vd.y) > 0.9) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0))));
        vec3 e2_1 = cross(vd, e1_1);
        vec3 ay = normalize(((vd + (e1_1 * sw_3.x)) + (e2_1 * sw_3.y)));
        vec3 ax_2 = normalize(cross(ay, e2_1));
        vec3 az = cross(ax_2, ay);
        float sd8_ = max((_e7 - PL_COOL), 0.0);
        float spin_1 = ((_e7 * 2.3) + ((0.32 * sd8_) * sd8_));
        float bq_1 = dot(rd_10, cen);
        float disc_1 = (((bq_1 * bq_1) - dot(cen, cen)) + (13.0 * 13.0));
        if ((disc_1 > 0.0)) {
            local_105 = (show > 0.0);
        } else {
            local_105 = false;
        }
        bool _e3337 = local_105;
        if (_e3337) {
            float sq_1 = sqrt(disc_1);
            tt = max((bq_1 - sq_1), 0.0);
            float t1_3 = min((bq_1 + sq_1), scene_len_3);
            float _e3347 = tt;
            bt = _e3347;
            bool loop_init_17 = true;
            while(true) {
                if (!loop_init_17) {
                    int _e3384 = i_21;
                    i_21 = (_e3384 + 1);
                }
                loop_init_17 = false;
                int _e3353 = i_21;
                if ((_e3353 < 56)) {
                } else {
                    break;
                }
                {
                    float _e3356 = tt;
                    if ((_e3356 > t1_3)) {
                        break;
                    }
                    float _e3358 = tt;
                    float pw = (_e3358 * px_a);
                    float _e3360 = tt;
                    vec3 w_13 = ((rd_10 * _e3360) - cen);
                    vec2 _e3367 = nk_bomb(vec3(dot(w_13, ax_2), dot(w_13, ay), dot(w_13, az)), spin_1, vc_2);
                    float rr_2 = (_e3367.x / pw);
                    float _e3370 = best;
                    if ((rr_2 < _e3370)) {
                        best = rr_2;
                        float _e3372 = tt;
                        bt = _e3372;
                        bm = _e3367.y;
                    }
                    if ((_e3367.x < (0.02 * pw))) {
                        break;
                    }
                    float _e3378 = tt;
                    tt = (_e3378 + max(_e3367.x, (0.35 * pw)));
                }
            }
            float _e3387 = best;
            cov = (clamp((0.6 - _e3387), 0.0, 1.0) / 0.6);
            float _e3394 = bt;
            float pw_1 = (_e3394 * px_a);
            float _e3396 = cov;
            if ((_e3396 > 0.0)) {
                float _e3399 = bt;
                vec3 w_14 = ((rd_10 * _e3399) - cen);
                vec3 q_22 = vec3(dot(w_14, ax_2), dot(w_14, ay), dot(w_14, az));
                float ep = max(0.05, (0.4 * pw_1));
                vec2 ex = vec2(1.0, -1.0);
                vec2 _e3417 = nk_bomb((q_22 + (ex.xyy * ep)), spin_1, vc_2);
                vec2 _e3424 = nk_bomb((q_22 + (ex.yyx * ep)), spin_1, vc_2);
                vec2 _e3432 = nk_bomb((q_22 + (ex.yxy * ep)), spin_1, vc_2);
                vec2 _e3440 = nk_bomb((q_22 + (ex.xxx * ep)), spin_1, vc_2);
                vec3 nl_3 = normalize(((((ex.xyy * _e3417.x) + (ex.yyx * _e3424.x)) + (ex.yxy * _e3432.x)) + (ex.xxx * _e3440.x)));
                n_3 = normalize((((ax_2 * nl_3.x) + (ay * nl_3.y)) + (az * nl_3.z)));
                float _e3462 = bm;
                if ((_e3462 < 0.5)) {
                    float yb = (q_22.y / NK_BS);
                    vec3 _e3468 = alb_2;
                    alb_2 = ((abs((yb - 0.9)) < 0.3) ? vec3(0.07) : _e3468);
                    vec3 _e3477 = alb_2;
                    alb_2 = (_e3477 * (0.9 + (0.1 * step(0.06, abs((fract((yb / 2.2)) - 0.5))))));
                } else {
                    float _e3491 = bm;
                    if ((_e3491 < 1.5)) {
                        alb_2 = vec3(0.12, 0.12, 0.13);
                    } else {
                        float _e3498 = bm;
                        if ((_e3498 < 2.5)) {
                            alb_2 = vec3(0.09, 0.085, 0.08);
                        } else {
                            float fade_v = (1.0 - clamp(((3.1200001 - q_22.y) / ((9.0 * vc_2) + 0.01)), 0.0, 1.0));
                            alb_2 = vec3(0.95, 0.96, 1.0);
                            spec = 0.0;
                            float _e3521 = cov;
                            cov = ((((_e3521 * vc_2) * 0.35) * fade_v) * (0.75 + (0.25 * sin(((_e7 * 53.0) + (q_22.y * 3.0))))));
                            vec3 _e3538 = n_3;
                            if ((dot(_e3538, rd_10) > 0.0)) {
                                vec3 _e3542 = n_3;
                                n_3 = -(_e3542);
                            }
                        }
                    }
                }
                vec3 _e3544 = n_3;
                float ndl = dot(_e3544, L_3);
                float _e3553 = bm;
                float dif = ((_e3553 > 2.5) ? (0.5 + (0.5 * abs(ndl))) : max(ndl, 0.0));
                vec3 _e3557 = alb_2;
                float _e3562 = n_3.y;
                c_17 = (_e3557 * (((sunc * dif) * 0.95) + (amb * (0.55 + (0.45 * _e3562)))));
                vec3 _e3571 = c_17;
                float _e3572 = spec;
                vec3 _e3574 = n_3;
                vec3 _e3583 = n_3;
                c_17 = (_e3571 + ((sunc * _e3572) * ((pow(max(dot(reflect(rd_10, _e3574), L_3), 0.0), 90.0) * 5.0) + (pow(max(dot(reflect(rd_10, _e3583), L_3), 0.0), 8.0) * 0.15))));
                float warmb = max(smoothstep(8.2, 5.6, _e7), ((0.8 * dive) * dive));
                float _e3612 = bm;
                if ((_e3612 > 1.5)) {
                    float _e3617 = bm;
                    local_106 = (_e3617 < 2.5);
                } else {
                    local_106 = false;
                }
                bool _e3621 = local_106;
                float _e3624 = bm;
                float wn = ((_e3621 ? 1.0 : (0.35 * clamp((((q_22.y / NK_BS) + 3.0) / 6.0), 0.0, 1.0))) * ((_e3624 > 2.5) ? 0.0 : 1.0));
                vec3 _e3631 = c_17;
                c_17 = (_e3631 + (((mix(vec3(1.6, 0.28, 0.06), vec3(3.0, 1.6, 0.6), max(heat_2, ((0.6 * dive) * dive))) * warmb) * warmb) * wn));
                vec3 _e3649 = c_17;
                float _e3650 = bt;
                c_17 = mix(_e3649, haze_c, ((1.0 - exp((-(_e3650) / 3000.0))) * 0.75));
                vec3 _e3660 = col_4;
                vec3 _e3661 = c_17;
                float _e3662 = cov;
                col_4 = mix(_e3660, _e3661, (_e3662 * show));
            }
        }
        float thc = max((4.0 / dh), (px_a * 0.9));
        float far_2 = (smoothstep(1.2, 0.35, (((16.0 / dh) / px_a) / 6.0)) * (1.0 - heat_2));
        vec3 _e3681 = col_4;
        col_4 = mix(_e3681, (vec3(0.05, 0.05, 0.055) + (sunc * 0.05)), (((exp(-(pow((th_3 / thc), 2.0))) * far_2) * 0.85) * show));
        if ((heat_2 > 0.001)) {
            float fl_4 = (0.86 + ((0.14 * sin((_e7 * 41.0))) * sin(((_e7 * 27.0) + 1.0))));
            float tc0_ = max((3.0 / dh), (px_a * 0.9));
            float core_3 = (exp(-(pow((th_3 / tc0_), 2.0))) * 16.0);
            float bloom = ((1.1 / (1.0 + pow((th_3 / ((tc0_ * 4.0) + 0.004)), 2.0))) + (0.22 * exp((-(th_3) / 0.05))));
            float lw = (16.0 + (100.0 * heat_2));
            vec3 _e3750 = ray_seg(rd_10, cen, (cen - (vd * lw)));
            float ww_2 = mix(1.6, 6.0, sqrt(_e3750.z));
            float wpx = max(ww_2, ((_e3750.y * px_a) * 0.8));
            float sheath = (((exp(-(pow((_e3750.x / wpx), 2.0))) * pow((1.0 - _e3750.z), 1.6)) * (ww_2 / wpx)) * 5.0);
            vec3 sv_1 = (rd_10 - (hn * cth_1));
            vec3 upv = normalize((cross(cross(hn, vec3(0.0, 1.0, 0.0)), hn) + vec3(0.0, 1e-5, 0.0)));
            float streak_1 = ((exp((-(abs(dot(sv_1, upv))) / (px_a * 1.2))) * exp((-(th_3) / 0.035))) * 0.3);
            vec3 hot_4 = ((vec3(1.0, 0.95, 0.88) * ((core_3 + bloom) + streak_1)) + (mix(vec3(1.0, 0.9, 0.75), vec3(1.0, 0.42, 0.16), sqrt(_e3750.z)) * sheath));
            vec3 _e3825 = col_4;
            col_4 = (_e3825 + (((hot_4 * heat_2) * fl_4) * show));
        }
        if ((dive > 0.001)) {
            vec3 _e3841 = ray_seg(rd_10, (cen + (vd * 9.0)), (cen - (vd * (4.0 + (22.0 * dive)))));
            float ww_3 = mix(0.8, 2.2, _e3841.z);
            float wpx_1 = max(ww_3, ((_e3841.y * px_a) * 0.8));
            float wake_2 = ((exp(-(pow((_e3841.x / wpx_1), 2.0))) * pow((1.0 - _e3841.z), 2.0)) * (ww_3 / wpx_1));
            float tc1_ = max((2.0 / dh), (px_a * 0.9));
            float nose = ((exp(-(pow((th_3 / tc1_), 2.0))) * 1.2) + (0.15 / (1.0 + pow((th_3 / ((tc1_ * 4.0) + 0.002)), 2.0))));
            vec3 _e3889 = col_4;
            col_4 = (_e3889 + ((((vec3(2.4, 0.95, 0.3) * (nose + (wake_2 * 0.8))) * dive) * dive) * show));
        }
        float gph = (pow((0.5 + (0.5 * sin(((spin_1 * 2.0) + 0.7)))), 30.0) + (0.5 * pow((0.5 + (0.5 * sin(((spin_1 * 2.0) + 2.6)))), 40.0)));
        float gtc = max((2.0 / dh), (px_a * 1.0));
        float glint_1 = ((((exp(-(pow((th_3 / (gtc * 0.6)), 2.0))) * 2.5) + (0.1 / (1.0 + pow((th_3 / (gtc * 3.0)), 2.0)))) * gph) * sun_up);
        float blink_1 = ((step(fract(((_e7 * 1.1) + ((0.25 * sd8_) * sd8_))), 0.14) * (1.0 - day_2)) * 0.8);
        float red = ((exp(-(pow((th_3 / max((px_a * 1.2), (0.8 / dh))), 2.0))) * 2.0) + (0.2 / (1.0 + pow((th_3 / (px_a * 5.0)), 2.0))));
        vec3 _e3989 = col_4;
        col_4 = (_e3989 + (((((sunc * glint_1) * (1.0 + dive)) + ((vec3(2.4, 0.12, 0.05) * red) * blink_1)) * (1.0 - heat_2)) * show));
        float pin = pow(clamp(((_e7 - 10.78) / 0.22), 0.0, 1.0), 3.0);
        if ((pin > 0.0)) {
            float pc_3 = max((2.0 / dh), (px_a * 0.9));
            vec3 _e4020 = col_4;
            col_4 = (_e4020 + (((vec3(1.0, 0.98, 0.95) * ((exp(-(pow((th_3 / pc_3), 2.0))) * 30.0) + (2.5 / (1.0 + pow((th_3 / ((0.012 * pin) + 0.002)), 2.0))))) * pin) * show));
        }
    }
    if ((stage != 2u)) {
        local_107 = (a_27 > 0.0);
    } else {
        local_107 = false;
    }
    bool _e4055 = local_107;
    if (_e4055) {
        local_108 = (a_27 < 45.0);
    } else {
        local_108 = false;
    }
    bool _e4061 = local_108;
    if (_e4061) {
        float rf_2 = (PL_V * a_27);
        ylo = (min(C_9.y, me_3.y) - 6.0);
        yhi = (max(C_9.y, me_3.y) + 90.0);
        float _e4077 = pl_w(PL_HF);
        if ((_e4077 > 1.0)) {
            float _e4080 = ylo;
            float _e4083 = pl_w(1026u);
            ylo = min(_e4080, ((C_9.y + _e4083) - 6.0));
            float _e4088 = yhi;
            float _e4091 = pl_w(1027u);
            yhi = max(_e4088, ((C_9.y + _e4091) + 90.0));
        }
        if (!(_e159)) {
            vec3 sq_2 = (_e164 - C_9);
            float _e4108 = pl_gref(length(sq_2.xz), me_3, C_9, dme_3);
            vec2 _e4109 = pl_land(sq_2.xz, _e4108);
            float off_4 = (sq_2.y - _e4109.x);
            float _e4113 = pl_w(1025u);
            float stp = ((2.0 * max(_e4113, 260.0)) / 95.0);
            loc_1 = vec4(sq_2.xz, clamp(off_4, -30.0, (2.5 + (0.1 * max((off_4 - 2.5), 0.0)))), ((stp * stp) * 0.6));
        }
        float _e4137 = col_t;
        t1_ = min(min(scene_len_3, _e4137), 3200.0);
        if ((abs(rd_10.y) > 1e-5)) {
            float _e4146 = ylo;
            float ya_1 = (_e4146 / rd_10.y);
            float _e4149 = yhi;
            float yb_1 = (_e4149 / rd_10.y);
            float _e4152 = t0_;
            t0_ = max(_e4152, min(ya_1, yb_1));
            float _e4155 = t1_;
            t1_ = min(_e4155, max(ya_1, yb_1));
        } else {
            float _e4158 = ylo;
            if (!((_e4158 > 0.0))) {
                float _e4164 = yhi;
                local_109 = (_e4164 < 0.0);
            } else {
                local_109 = true;
            }
            bool _e4168 = local_109;
            if (_e4168) {
                t1_ = -1.0;
            }
        }
        float a2_ = max(dot(rd_10.xz, rd_10.xz), 1e-8);
        float bb = -(dot(rd_10.xz, C_9.xz));
        float cc = dot(C_9.xz, C_9.xz);
        float Ro = (rf_2 + 20.0);
        float Ri = max((rf_2 - 110.0), 0.0);
        float dout = ((bb * bb) - (a2_ * (cc - (Ro * Ro))));
        float din = ((bb * bb) - (a2_ * (cc - (Ri * Ri))));
        float _e4198 = t1_;
        float _e4199 = t0_;
        if ((_e4198 > _e4199)) {
            local_110 = (dout > 0.0);
        } else {
            local_110 = false;
        }
        bool _e4206 = local_110;
        if (_e4206) {
            float oa_2 = ((-(bb) - sqrt(dout)) / a2_);
            float ob_1 = ((-(bb) + sqrt(dout)) / a2_);
            seg = vec2[3](vec2(oa_2, ob_1), vec2(0.0, -1.0), vec2(0.0, -1.0));
            if ((din > 0.0)) {
                local_111 = (Ri > 0.0);
            } else {
                local_111 = false;
            }
            bool _e4236 = local_111;
            if (_e4236) {
                float ia = ((-(bb) - sqrt(din)) / a2_);
                float ib = ((-(bb) + sqrt(din)) / a2_);
                seg[0] = vec2(oa_2, ia);
                seg[1] = vec2(ib, ob_1);
                seg[2] = vec2(ia, ib);
                ns = int[3](12, 10, 6);
            }
            float _e4257 = t0_;
            float _e4258 = t1_;
            float mid_t = clamp((-(bb) / a2_), _e4257, _e4258);
            vec3 pm = ((rd_10 * mid_t) - C_9);
            float side_1 = clamp((abs(dot(normalize(rd_10.xz), (pm.xz / vec2(max(length(pm.xz), 1.0))))) * 1.6), 0.0, 1.0);
            float _e4291 = ign((in_.position.xy + vec2(0.0, (fract((_e7 * 5.0)) * 53.0))));
            PlCol _e4294 = pl_column(max(a_27, 0.01), C_10);
            bool loop_init_18 = true;
            while(true) {
                if (!loop_init_18) {
                    int _e4442 = si;
                    si = (_e4442 + 1);
                }
                loop_init_18 = false;
                int _e4302 = si;
                if ((_e4302 < 3)) {
                } else {
                    break;
                }
                {
                    int _e4305 = si;
                    int k2_ = order[_e4305];
                    float _e4310 = seg[k2_].x;
                    float _e4311 = t0_;
                    float sa = max(_e4310, _e4311);
                    float _e4315 = seg[k2_].y;
                    float _e4316 = t1_;
                    float sb = min(_e4315, _e4316);
                    int n_7 = ns[k2_];
                    if (!((n_7 == 0))) {
                        local_112 = (sb <= sa);
                    } else {
                        local_112 = true;
                    }
                    bool _e4327 = local_112;
                    if (!(_e4327)) {
                        float _e4331 = tr_2;
                        local_113 = (_e4331 < 0.02);
                    } else {
                        local_113 = true;
                    }
                    bool _e4335 = local_113;
                    if (_e4335) {
                        continue;
                    }
                    i_22 = 0;
                    bool loop_init_19 = true;
                    while(true) {
                        if (!loop_init_19) {
                            int _e4439 = i_22;
                            i_22 = (_e4439 + 1);
                        }
                        loop_init_19 = false;
                        int _e4338 = i_22;
                        if ((_e4338 < n_7)) {
                        } else {
                            break;
                        }
                        {
                            int _e4340 = i_22;
                            float u0_ = ((float(_e4340) + _e4291) / float(n_7));
                            int _e4345 = i_22;
                            float u1_ = (((float(_e4345) + _e4291) + 1.0) / float(n_7));
                            float t_11 = (sa + (((sb - sa) * u0_) * u0_));
                            float dt_3 = ((sb - sa) * ((u1_ * u1_) - (u0_ * u0_)));
                            vec3 p_31 = (rd_10 * t_11);
                            vec4 _e4362 = loc_1;
                            vec2 _e4363 = pl_dust(p_31, C_9, a_27, me_3, dme_3, side_1, _e4362);
                            float den_3 = (_e4363.x * smoothstep(2.0, 30.0, t_11));
                            if ((den_3 <= 0.001)) {
                                continue;
                            }
                            float al_3 = (1.0 - exp(((-(den_3) * dt_3) * 0.3)));
                            float h_9 = _e4363.y;
                            vec3 wq_1 = (p_31 + cam_6);
                            float _e4393 = gnoise3_(((wq_1 * vec3(0.11111111, 0.16666667, 0.11111111)) + vec3(0.0, ((-1.2 * a_27) + 0.5), 0.0)));
                            float lo_4 = ((0.45 + (0.55 * clamp((h_9 / 8.0), 0.0, 1.0))) * (0.55 + (0.7 * _e4393)));
                            float _e4421 = pl_cap_shade(p_31, L_3, a_27, C_9, (_e4294.hc - (0.3 * _e4294.rt)), (_e4294.Rt + _e4294.rt));
                            vec3 dc_1 = (vec3(0.56, 0.49, 0.37) * ((((sunc * 0.75) * lo_4) * _e4421) + (amb * 0.6)));
                            vec3 _e4427 = acc_2;
                            float _e4428 = tr_2;
                            acc_2 = (_e4427 + ((_e4428 * al_3) * dc_1));
                            float _e4432 = tr_2;
                            tr_2 = (_e4432 * (1.0 - al_3));
                            float _e4436 = tr_2;
                            if ((_e4436 < 0.02)) {
                                break;
                            }
                        }
                    }
                }
            }
            if ((stage == 0u)) {
                vec3 _e4447 = col_4;
                vec3 _e4448 = col_4;
                float _e4449 = tr_2;
                vec3 _e4451 = acc_2;
                col_4 = mix(_e4447, ((_e4448 * _e4449) + _e4451), (_e12 * fade));
            } else {
                float kf = (_e12 * fade);
                vec4 _e4456 = hc_1;
                float _e4460 = tr_2;
                vec3 _e4464 = acc_2;
                float _e4468 = hc_1.w;
                float _e4471 = tr_2;
                hc_1 = vec4(((_e4456.xyz * ((1.0 - kf) + (kf * _e4460))) + (_e4464 * kf)), (_e4468 * ((1.0 - kf) + (kf * _e4471))));
            }
        }
    }
    if ((stage == 1u)) {
        if ((a_27 > 0.0)) {
            local_114 = (a_27 < 24.0);
        } else {
            local_114 = false;
        }
        bool _e4489 = local_114;
        if (_e4489) {
            float _e4493 = pl_w(8u);
            local_115 = (_e4493 > 0.5);
        } else {
            local_115 = false;
        }
        bool _e4497 = local_115;
        if (_e4497) {
            low = (min(C_9.y, me_3.y) - 4.0);
            float _e4505 = pl_w(PL_HF);
            if ((_e4505 > 1.0)) {
                float _e4508 = low;
                float _e4511 = pl_w(1026u);
                low = min(_e4508, ((C_9.y + _e4511) - 4.0));
            }
            float _e4519 = _group_0_binding_4_fs.resolution.y;
            float _e4523 = _group_0_binding_4_fs.view_params.w;
            float fpx = (_e4519 / (2.0 * tan((_e4523 * 0.5))));
            float wpx_2 = (1.0 / fpx);
            float eka_1 = exp((-0.06 * a_27));
            vec2 pxy = ((floor(in_.position.xy) * 2.0) + vec2(1.0));
            bool loop_init_20 = true;
            while(true) {
                if (!loop_init_20) {
                    int _e4658 = i_23;
                    i_23 = (_e4658 + 1);
                }
                loop_init_20 = false;
                int _e4545 = i_23;
                if ((_e4545 < PL_DEBRIS)) {
                } else {
                    break;
                }
                {
                    int _e4548 = i_23;
                    PlChunk _e4549 = pl_chunk(_e4548, a_27, eka_1, C_9);
                    if (!((_e4549.live <= 0.0))) {
                        float _e4558 = low;
                        local_116 = (_e4549.p.y < _e4558);
                    } else {
                        local_116 = true;
                    }
                    bool _e4561 = local_116;
                    if (_e4561) {
                        continue;
                    }
                    float dist_1 = length(_e4549.p);
                    float off_5 = length((_e4549.p - (rd_10 * dot(_e4549.p, rd_10))));
                    if (!((dist_1 < 1.0))) {
                        local_117 = (off_5 > ((((_e4549.s * 4.5) + (length(_e4549.v) * 0.8)) + 1.5) + ((9.0 * dist_1) * wpx_2)));
                    } else {
                        local_117 = true;
                    }
                    bool _e4591 = local_117;
                    if (_e4591) {
                        continue;
                    }
                    vec3 _e4593 = project_rel(_e4549.p);
                    if ((_e4593.z < 0.0)) {
                        continue;
                    }
                    float rad_2 = max(((_e4549.s * fpx) / dist_1), 0.55);
                    float reach = ((smoothstep(0.45, 0.8, _e4549.s) > 0.0) ? (((rad_2 * 3.0) + (((length(_e4549.v) * 0.6) * fpx) / dist_1)) + 4.0) : (((rad_2 * 1.4) + (((length(_e4549.v) * 0.03) * fpx) / dist_1)) + 2.0));
                    vec4 _e4634 = _group_0_binding_4_fs.resolution;
                    if ((length((pxy - (_e4593.xy * _e4634.xy))) > (reach + 3.0))) {
                        continue;
                    }
                    float _e4642 = pl_chunk_up(_e4549, C_9, me_3, dme_3);
                    if ((_e4642 > 0.0)) {
                        float _e4645 = near;
                        int _e4646 = i_23;
                        float _e4650 = near;
                        near = ((_e4650 == 0.0) ? float((_e4646 + 1)) : _e4645);
                        int _e4654 = i_23;
                        near_hi = float((_e4654 + 1));
                    }
                }
            }
        }
        vec4 _e4661 = hc_1;
        float _e4664 = col_t;
        float _e4667 = near;
        float _e4668 = near_hi;
        return PlOut(_e4661, vec4(min(scene_len_3, 60000.0), min(_e4664, 60000.0), _e4667, _e4668));
    }
    if (!((stage == 0u))) {
        local_118 = (up_e.y > 0.0);
    } else {
        local_118 = true;
    }
    bool _e4680 = local_118;
    if (_e4680) {
        local_119 = (a_27 > 0.0);
    } else {
        local_119 = false;
    }
    bool _e4686 = local_119;
    if (_e4686) {
        local_120 = (a_27 < 24.0);
    } else {
        local_120 = false;
    }
    bool _e4692 = local_120;
    if (_e4692) {
        float _e4696 = pl_w(8u);
        local_121 = (_e4696 > 0.5);
    } else {
        local_121 = false;
    }
    bool _e4700 = local_121;
    if (_e4700) {
        int i_lo = ((stage == 2u) ? (int((up_e.y + 0.5)) - 1) : 0);
        int i_hi = ((stage == 2u) ? int((up_e.z + 0.5)) : PL_DEBRIS);
        float _e4722 = _group_0_binding_4_fs.resolution.y;
        float _e4726 = _group_0_binding_4_fs.view_params.w;
        float fpx_1 = (_e4722 / (2.0 * tan((_e4726 * 0.5))));
        vec2 pxy_1 = in_.position.xy;
        float _e4735 = col_t;
        float lim = min(scene_len_3, _e4735);
        low_1 = (min(C_9.y, me_3.y) - 4.0);
        float _e4748 = pl_w(PL_HF);
        if ((_e4748 > 1.0)) {
            float _e4751 = low_1;
            float _e4754 = pl_w(1026u);
            low_1 = min(_e4751, ((C_9.y + _e4754) - 4.0));
        }
        float wpx_3 = (1.0 / fpx_1);
        float eka_2 = exp((-0.06 * a_27));
        i_24 = i_lo;
        bool loop_init_21 = true;
        while(true) {
            if (!loop_init_21) {
                int _e5019 = i_24;
                i_24 = (_e5019 + 1);
            }
            loop_init_21 = false;
            int _e4765 = i_24;
            if ((_e4765 < i_hi)) {
            } else {
                break;
            }
            {
                int _e4767 = i_24;
                PlChunk _e4768 = pl_chunk(_e4767, a_27, eka_2, C_9);
                ch_1 = _e4768;
                float _e4771 = ch_1.live;
                if (!((_e4771 <= 0.0))) {
                    float _e4779 = ch_1.p.y;
                    float _e4780 = low_1;
                    local_122 = (_e4779 < _e4780);
                } else {
                    local_122 = true;
                }
                bool _e4783 = local_122;
                if (_e4783) {
                    continue;
                }
                vec3 _e4785 = ch_1.p;
                float dist_2 = length(_e4785);
                if (!((dist_2 > lim))) {
                    local_123 = (dist_2 < 1.0);
                } else {
                    local_123 = true;
                }
                bool _e4794 = local_123;
                if (_e4794) {
                    continue;
                }
                vec3 _e4796 = ch_1.p;
                vec3 _e4798 = ch_1.p;
                float off_6 = length((_e4796 - (rd_10 * dot(_e4798, rd_10))));
                float _e4804 = ch_1.s;
                vec3 _e4808 = ch_1.v;
                float reach_w = ((((_e4804 * 4.5) + (length(_e4808) * 0.8)) + 1.5) + ((6.0 * dist_2) * wpx_3));
                if ((off_6 > reach_w)) {
                    continue;
                }
                PlChunk _e4821 = ch_1;
                float _e4822 = pl_chunk_up(_e4821, C_9, me_3, dme_3);
                ch_1.live = _e4822;
                float _e4824 = ch_1.live;
                if ((_e4824 <= 0.0)) {
                    continue;
                }
                vec3 _e4828 = ch_1.p;
                vec3 _e4829 = project_rel(_e4828);
                if ((_e4829.z < 0.0)) {
                    continue;
                }
                vec4 _e4836 = _group_0_binding_4_fs.resolution;
                vec2 q0_ = (_e4829.xy * _e4836.xy);
                float _e4840 = ch_1.s;
                float rad_3 = max(((_e4840 * fpx_1) / dist_2), 0.55);
                float _e4846 = ch_1.s;
                float bigc = smoothstep(0.45, 0.8, _e4846);
                vec3 _e4853 = ch_1.v;
                vec3 _e4865 = ch_1.v;
                float reach_1 = ((bigc > 0.0) ? (((rad_3 * 3.0) + (((length(_e4865) * 0.6) * fpx_1) / dist_2)) + 4.0) : (((rad_3 * 1.4) + (((length(_e4853) * 0.03) * fpx_1) / dist_2)) + 2.0));
                if ((length((pxy_1 - q0_)) > reach_1)) {
                    continue;
                }
                vec3 _e4881 = ch_1.p;
                vec3 _e4883 = ch_1.v;
                vec3 _e4887 = project_rel((_e4881 - (_e4883 * 0.03)));
                vec4 _e4891 = _group_0_binding_4_fs.resolution;
                vec2 q1_3 = (_e4887.xy * _e4891.xy);
                vec2 ab_6 = (q1_3 - q0_);
                float w_15 = clamp((dot((pxy_1 - q0_), ab_6) / max(dot(ab_6, ab_6), 0.0001)), 0.0, 1.0);
                float e_14 = length((pxy_1 - (q0_ + (ab_6 * w_15))));
                int _e4908 = i_24;
                float _e4914 = pl_w(((PL_DB + (PL_DW * uint(_e4908))) + 8u));
                float spin_2 = (a_27 * _e4914);
                float th_4 = atan((pxy_1.y - q0_.y), (pxy_1.x - q0_.x));
                int _e4925 = i_24;
                float lump_1 = ((1.0 + (0.28 * sin((((th_4 * 3.0) + float(_e4925)) + spin_2)))) + (0.12 * sin(((th_4 * 5.0) - (spin_2 * 1.3)))));
                float _e4949 = ch_1.live;
                float c_27 = ((clamp((((rad_3 * lump_1) + 0.5) - e_14), 0.0, 1.0) * _e4949) * clamp((rad_3 / max((length(ab_6) * 0.5), rad_3)), 0.0, 1.0));
                float _e4958 = cov_1;
                cov_1 = max(_e4958, c_27);
                if ((bigc > 0.0)) {
                    vec3 _e4963 = ch_1.p;
                    vec3 _e4965 = ch_1.v;
                    vec3 _e4974 = project_rel(((_e4963 - (_e4965 * 0.6)) + vec3(0.0, 1.2, 0.0)));
                    vec4 _e4978 = _group_0_binding_4_fs.resolution;
                    vec2 q2_2 = (_e4974.xy * _e4978.xy);
                    vec2 tb_3 = (q2_2 - q0_);
                    float u_23 = clamp((dot((pxy_1 - q0_), tb_3) / max(dot(tb_3, tb_3), 0.0001)), 0.0, 1.0);
                    float wd = ((rad_3 * (0.6 + (1.6 * u_23))) + 0.5);
                    float et = length((pxy_1 - (q0_ + (tb_3 * u_23))));
                    float _e5000 = smk;
                    float _e5012 = ch_1.live;
                    smk = max(_e5000, (((((clamp((1.0 - (et / wd)), 0.0, 1.0) * (1.0 - u_23)) * 0.45) * bigc) * _e5012) * step(0.5, _e4974.z)));
                }
            }
        }
        vec3 dirt = (vec3(0.035, 0.03, 0.026) * ((amb * 1.5) + (sunc * 0.3)));
        vec3 smoke = (vec3(0.28, 0.29, 0.31) * ((amb * 0.8) + (sunc * 0.25)));
        vec3 _e5042 = col_4;
        float _e5043 = smk;
        col_4 = mix(_e5042, smoke, ((_e5043 * _e12) * fade));
        vec3 _e5047 = col_4;
        float _e5048 = cov_1;
        col_4 = mix(_e5047, dirt, ((_e5048 * _e12) * fade));
    }
    if ((a_27 > 0.0)) {
        local_124 = (a_27 < 40.0);
    } else {
        local_124 = false;
    }
    bool _e5059 = local_124;
    if (_e5059) {
        float rc_2 = length(C_9.xz);
        float tau_4 = (a_27 - (rc_2 / PL_V));
        if ((tau_4 > -0.1)) {
            local_125 = (rc_2 > 100.0);
        } else {
            local_125 = false;
        }
        bool _e5072 = local_125;
        if (_e5072) {
            float _e5075 = pl_gref(rc_2, me_3, C_9, dme_3);
            vec2 _e5076 = pl_land(-(C_9.xz), _e5075);
            float hc_3 = (-(C_9.y) - _e5076.x);
            float E = (((((((smoothstep(-0.08, 0.05, tau_4) * ((0.6 * exp((-(tau_4) / 0.8))) + (0.4 * exp((-(tau_4) / 3.5))))) * smoothstep(60.0, 10.0, hc_3)) * smoothstep(6000.0, 2500.0, rc_2)) * smoothstep(100.0, 200.0, rc_2)) * (1.0 - (0.55 * _e5076.y))) * fade) * _e12);
            if ((E > 0.002)) {
                vec3 dust_c = (vec3(0.5, 0.46, 0.4) * ((sunc * 0.55) + (amb * 0.8)));
                vec3 _e5130 = col_4;
                float lum = dot(_e5130, vec3(0.2126, 0.7152, 0.0722));
                vec3 _e5136 = col_4;
                col_4 = mix(_e5136, mix(vec3(lum), dust_c, 0.5), (0.22 * E));
                vec3 _e5143 = col_4;
                col_4 = (_e5143 * mix(vec3(1.0), vec3(1.03, 0.99, 0.93), E));
                vec2 pxy_2 = pl_px;
                vec4 _e5156 = _group_0_binding_4_fs.resolution;
                vec2 res = _e5156.xy;
                float _e5165 = gnoise3_(vec3((pxy_2 / vec2((0.15 * res.y))), 3.1));
                float _e5175 = gnoise3_(vec3((pxy_2 / vec2((0.07 * res.y))), 7.7));
                float film = ((_e5165 * 0.8) + (_e5175 * 0.2));
                vec3 _e5179 = col_4;
                col_4 = mix(_e5179, dust_c, ((0.12 * E) * smoothstep(0.35, 0.95, film)));
            }
            float vis_5 = ((((smoothstep(60.0, 10.0, hc_3) * smoothstep(6000.0, 2500.0, rc_2)) * smoothstep(120.0, 260.0, rc_2)) * (1.0 - (0.5 * _e5076.y))) * _e12);
            if ((vis_5 > 0.0)) {
                local_126 = (tau_4 > 0.2);
            } else {
                local_126 = false;
            }
            bool _e5212 = local_126;
            if (_e5212) {
                vec2 pxy_3 = pl_px;
                vec4 _e5217 = _group_0_binding_4_fs.resolution;
                vec2 res_1 = _e5217.xy;
                bool loop_init_22 = true;
                while(true) {
                    if (!loop_init_22) {
                        uint _e5469 = i_25;
                        i_25 = (_e5469 + 1u);
                    }
                    loop_init_22 = false;
                    uint _e5225 = i_25;
                    if ((_e5225 < 14u)) {
                    } else {
                        break;
                    }
                    {
                        uint _e5228 = i_25;
                        float _e5230 = mh(_e5228, seed_20, 976u);
                        float t0_2 = (0.25 + (1.4 * _e5230));
                        float age_3 = (tau_4 - t0_2);
                        if ((age_3 <= 0.0)) {
                            continue;
                        }
                        uint _e5238 = i_25;
                        float _e5240 = mh(_e5238, seed_20, 977u);
                        uint _e5245 = i_25;
                        float _e5247 = mh(_e5245, seed_20, 978u);
                        vec2 c_28 = (vec2((0.03 + (0.94 * _e5240)), (0.02 + (0.4 * pow(_e5247, 1.3)))) * res_1);
                        uint _e5256 = i_25;
                        float _e5258 = mh(_e5256, seed_20, 979u);
                        float r_16 = ((0.011 + (0.026 * pow(_e5258, 0.8))) * res_1.y);
                        vec2 d0_2 = (pxy_3 - c_28);
                        if ((dot(d0_2, d0_2) > ((16.0 * r_16) * r_16))) {
                            continue;
                        }
                        uint _e5276 = i_25;
                        float _e5278 = mh(_e5276, seed_20, 980u);
                        float life = (smoothstep(0.0, 0.08, age_3) * (1.0 - smoothstep(6.0, 16.0, (age_3 + (4.0 * _e5278)))));
                        j_5 = 0u;
                        bool loop_init_23 = true;
                        while(true) {
                            if (!loop_init_23) {
                                uint _e5466 = j_5;
                                j_5 = (_e5466 + 1u);
                            }
                            loop_init_23 = false;
                            uint _e5290 = j_5;
                            if ((_e5290 < 4u)) {
                            } else {
                                break;
                            }
                            {
                                uint _e5293 = i_25;
                                uint _e5296 = j_5;
                                float _e5299 = mh(((_e5293 * 7u) + _e5296), seed_20, 992u);
                                uint _e5300 = j_5;
                                if ((_e5300 > 0u)) {
                                    local_127 = (_e5299 > 0.3);
                                } else {
                                    local_127 = false;
                                }
                                bool _e5308 = local_127;
                                if (_e5308) {
                                    continue;
                                }
                                uint _e5309 = i_25;
                                uint _e5312 = j_5;
                                uint k2_1 = ((_e5309 * 7u) + _e5312);
                                float _e5315 = mh(k2_1, seed_20, 993u);
                                uint _e5321 = j_5;
                                float rj = ((_e5321 == 0u) ? r_16 : (r_16 * (0.22 + (0.3 * _e5315))));
                                float _e5327 = mh(k2_1, seed_20, 994u);
                                float ang_6 = (TAU * _e5327);
                                float _e5334 = mh(k2_1, seed_20, 995u);
                                uint _e5341 = j_5;
                                vec2 cj = ((_e5341 == 0u) ? c_28 : (c_28 + ((vec2(cos(ang_6), sin(ang_6)) * r_16) * (1.4 + (0.9 * _e5334)))));
                                vec2 dj = (pxy_3 - cj);
                                float _e5348 = mh(k2_1, seed_20, 996u);
                                float rot_1 = (TAU * _e5348);
                                float cr_1 = cos(rot_1);
                                float sr_1 = sin(rot_1);
                                float _e5363 = mh(k2_1, seed_20, 997u);
                                float stretch_1 = (1.0 + ((mix(0.4, 0.06, smoothstep(0.012, 0.03, (rj / res_1.y))) * 2.0) * _e5363));
                                vec2 e_15 = vec2((((dj.x * cr_1) + (dj.y * sr_1)) / stretch_1), ((-(dj.x) * sr_1) + (dj.y * cr_1)));
                                float th_5 = atan(e_15.y, e_15.x);
                                float _e5385 = mh(k2_1, seed_20, 998u);
                                float ph_3 = (TAU * _e5385);
                                float q_23 = ((length(e_15) / rj) * ((1.0 + (0.05 * sin(((3.0 * th_5) + ph_3)))) + (0.035 * sin(((5.0 * th_5) - (2.0 * ph_3))))));
                                if ((q_23 >= 1.4)) {
                                    continue;
                                }
                                float body = (1.0 - smoothstep(0.3, 1.38, q_23));
                                float ring_1 = (body * mix(0.9, 1.15, smoothstep(0.1, 0.8, q_23)));
                                float _e5429 = gnoise3_(vec3((e_15 / vec2((0.8 * rj))), float((k2_1 % 97u))));
                                float mott = (0.94 + (0.12 * _e5429));
                                float _e5435 = mh(k2_1, seed_20, 999u);
                                uint _e5442 = j_5;
                                float op = ((0.14 + (0.34 * pow(_e5435, 0.7))) * ((_e5442 == 0u) ? 1.0 : 0.85));
                                float _e5449 = keep;
                                keep = (_e5449 * (1.0 - (((ring_1 * mott) * op) * life)));
                                float _e5456 = shine;
                                shine = (_e5456 + (((body * smoothstep(0.3, -0.9, (dj.y / rj))) * op) * life));
                            }
                        }
                    }
                }
                vec3 muck = (vec3(0.42, 0.38, 0.33) * ((sunc * 0.45) + (amb * 0.9)));
                vec3 _e5482 = col_4;
                vec3 _e5483 = col_4;
                float _e5484 = keep;
                float _e5486 = keep;
                float _e5497 = shine;
                col_4 = (mix(_e5482, ((_e5483 * _e5484) + ((muck * (1.0 - _e5486)) * 0.7)), (vis_5 * fade)) + ((((muck * 0.4) * min(_e5497, 1.0)) * vis_5) * fade));
            }
        }
    }
    if ((stage != 1u)) {
        local_128 = (a_27 > -0.02);
    } else {
        local_128 = false;
    }
    bool _e5511 = local_128;
    if (_e5511) {
        local_129 = (a_27 < 4.0);
    } else {
        local_129 = false;
    }
    bool _e5517 = local_129;
    if (_e5517) {
        float wo = (clamp((1.6 * exp((-(max(a_27, 0.0)) / 0.11))), 0.0, 1.0) * smoothstep(-0.02, 0.02, a_27));
        vec3 _e5531 = col_4;
        col_4 = (_e5531 * (1.0 + (0.4 * exp((-(max(a_27, 0.0)) / 0.22)))));
        float ow = (smoothstep(0.04, 0.14, a_27) * (1.0 - smoothstep(0.3, 0.6, a_27)));
        vec3 _e5552 = col_4;
        vec3 _e5553 = col_4;
        col_4 = mix(_e5552, ((_e5553 * vec3(1.5, 0.8, 0.35)) + vec3(0.38, 0.14, 0.02)), ((ow * _e12) * 0.7));
        vec3 _e5568 = col_4;
        col_4 = (_e5568 * (1.0 - ((0.18 * exp(-(pow(((a_27 - 0.75) / 0.25), 2.0)))) * _e12)));
        vec3 _e5583 = col_4;
        col_4 = mix(_e5583, vec3(1.4, 1.24, 1.32), (wo * _e12));
    }
    vec3 _e5590 = col_4;
    vec3 _e5594 = linear_to_srgb(max(_e5590, vec3(0.0)));
    float _e5595 = capture();
    if ((_e5595 > 2.5)) {
        vec2 _e5599 = pl_px;
        vec2 sp = floor(_e5599);
        float chk = fract(((sp.x + sp.y) * 0.5));
        float ycc_y = ((_e5594.y * 0.5) + ((_e5594.x + _e5594.z) * 0.25));
        float ycc_co = (_e5594.x - _e5594.z);
        float ycc_cg = (_e5594.y - ((_e5594.x + _e5594.z) * 0.5));
        return PlOut(vec4(ycc_y, ((((chk < 0.25) ? ycc_co : ycc_cg) * 0.5) + 0.5), 0.0, 1.0), vec4(0.0));
    }
    return PlOut(vec4(_e5594, 1.0), vec4(0.0));
}

StageIn pl_jolt(StageIn in_1) {
    bool local_130 = false;
    bool local_131 = false;
    vec2 q_10 = vec2(0.0);
    StageIn o_5 = StageIn(vec4(0.0), vec2(0.0));
    pl_px = in_1.position.xy;
    vec2 _e4 = anchor_xz();
    float _e6 = block_y();
    vec2 _e11 = anchor_xz();
    vec3 tgt_1 = vec3(_e4.x, ((_e6 + 1.0) + PL_BURST), _e11.y);
    float _e18 = _group_0_binding_4_fs.mod_params[3].x;
    float _e23 = _group_0_binding_4_fs.mod_params[3].y;
    float _e28 = _group_0_binding_4_fs.mod_params[3].z;
    vec3 me_4 = vec3(_e18, _e23, _e28);
    float dist_3 = length((me_4 - tgt_1));
    float _e32 = now();
    float s_17 = ((_e32 - PL_HIT) - (dist_3 / PL_V));
    if (!((s_17 <= 0.0))) {
        local_130 = (s_17 > 10.0);
    } else {
        local_130 = true;
    }
    bool _e46 = local_130;
    if (!(_e46)) {
        float _e50 = intensity_v();
        local_131 = (_e50 <= 0.0);
    } else {
        local_131 = true;
    }
    bool _e54 = local_131;
    if (_e54) {
        return in_1;
    }
    float g_4 = clamp((1.7 / (1.0 + (dist_3 / 450.0))), 0.2, 1.0);
    float hit_3 = (((0.03 * g_4) * exp((-(s_17) / 0.3))) * smoothstep(0.0, 0.02, s_17));
    vec2 ring_2 = vec2(((0.65 * sin(((s_17 * 47.0) + 0.6))) + (0.35 * sin(((s_17 * 83.0) + 2.1)))), ((0.65 * cos(((s_17 * 41.0) + 1.3))) + (0.35 * sin(((s_17 * 71.0) + 0.4)))));
    float shud = (((0.0065 * g_4) * exp((-(s_17) / 2.6))) * smoothstep(0.1, 0.5, s_17));
    vec2 sh_2 = vec2((((0.55 * sin(((s_17 * 17.0) + 0.3))) + (0.3 * sin(((s_17 * 29.0) + 1.9)))) + (0.15 * sin((s_17 * 53.0)))), (((0.55 * cos(((s_17 * 15.0) + 2.2))) + (0.3 * sin(((s_17 * 31.0) + 0.7)))) + (0.15 * cos((s_17 * 59.0)))));
    vec2 off_7 = ((ring_2 * hit_3) + (sh_2 * shud));
    float roll = ((((0.018 * g_4) * exp((-(s_17) / 0.4))) * sin(((s_17 * 37.0) + 0.9))) + (((0.003 * g_4) * exp((-(s_17) / 2.6))) * sin((s_17 * 11.0))));
    vec4 _e190 = _group_0_binding_4_fs.resolution;
    vec2 res_2 = _e190.xy;
    float asp = (res_2.x / res_2.y);
    float zoom = ((1.0 + (2.2 * (hit_3 + shud))) + ((1.1 * abs(roll)) * asp));
    q_10 = (((in_1.uv - vec2(0.5)) * vec2(asp, 1.0)) / vec2(zoom));
    float _e216 = q_10.x;
    float _e220 = q_10.y;
    float _e225 = q_10.x;
    float _e229 = q_10.y;
    q_10 = (vec2(((_e216 * cos(roll)) - (_e220 * sin(roll))), ((_e225 * sin(roll)) + (_e229 * cos(roll)))) + off_7);
    o_5 = in_1;
    vec2 _e237 = q_10;
    o_5.uv = clamp(((_e237 / vec2(asp, 1.0)) + vec2(0.5)), vec2(0.0), vec2(1.0));
    vec2 _e251 = o_5.uv;
    o_5.position = vec4((_e251 * res_2), in_1.position.zw);
    StageIn _e256 = o_5;
    return _e256;
}

void main() {
    StageIn in0_ = StageIn(gl_FragCoord, _vs2fs_location0);
    StageIn _e1 = pl_jolt(in0_);
    PlOut _e9 = nuke(_e1, 0u, vec4(0.0), vec3(1000000000.0, 1.0, 0.0));
    _fs2p_location0 = _e9.c;
    return;
}

