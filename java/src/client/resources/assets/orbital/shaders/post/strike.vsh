#version 330
#extension GL_ARB_separate_shader_objects : require

layout(location = 0) out vec2 _vs2fs_location0;

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    // the original's shader has v = 0 at the top of the picture
    _vs2fs_location0 = vec2(uv.x, 1.0 - uv.y);
}
