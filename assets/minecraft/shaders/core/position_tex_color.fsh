#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in vec2 texCoord0;
layout(location = 1) in vec4 vertexColor;
layout(location = 2) flat in int isPerspective;

layout(location = 0) out vec4 fragColor;

// ShaderSelector
#include <shader_selector:marker_settings.glsl>

void main() {
    // ShaderSelector
    // Detects 3D first-person overlays (e.g. underwater) and discards them at candidate marker pixels
    if (isPerspective == 1) {
        ivec2 iCoord = ivec2(gl_FragCoord.xy);
        if (false
            #define ADD_MARKER(i, green, alpha, op, r) || MARKER_POS(i) == iCoord
            LIST_MARKERS
        ) discard;
    }

    // Vanilla code
    vec4 color = texture(Sampler0, texCoord0) * vertexColor;
    if (color.a == 0.0) {
        discard;
    }
    fragColor = color * ColorModulator;
}