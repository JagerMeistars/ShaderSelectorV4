#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec2 UV0;
layout(location = 2) in vec4 Color;

layout(location = 0) out vec2 texCoord0;
layout(location = 1) out vec4 vertexColor;

// ShaderSelector
layout(location = 2) flat out int isPerspective;

void main() {
    // ShaderSelector
    // Isolates 3D first-person overlays (e.g. underwater) from 2D overlays (e.g. vignette and HUD elements), which should not be discarded
    isPerspective = (ProjMat[3][3] == 0.0) ? 1 : 0;

    // Vanilla code
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    texCoord0 = UV0;
    vertexColor = Color;
}