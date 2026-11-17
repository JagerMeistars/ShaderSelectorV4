#version 330
#extension GL_ARB_separate_shader_objects : require

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

uniform sampler2D InSampler;
uniform sampler2D MainSampler;

#include <shader_selector:marker_settings.glsl>

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = texture(InSampler, texCoord);
    ivec2 iCoord = ivec2(gl_FragCoord.xy);
    if (false
        #define ADD_MARKER(i, green, alpha, op, r) || MARKER_POS(i) == iCoord
        LIST_MARKERS
    ) fragColor = texture(MainSampler, texCoord);
}