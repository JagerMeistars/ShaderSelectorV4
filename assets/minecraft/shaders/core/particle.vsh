#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:sample_lightmap.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec2 UV0;
layout(location = 2) in vec4 Color;
layout(location = 3) in ivec2 UV2;

uniform sampler2D Sampler2;

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
layout(location = 2) out vec2 texCoord0;
layout(location = 3) out vec4 vertexColor;

// ShaderSelector
#include <shader_selector:marker_settings.glsl>

layout(location = 4) flat out int isMarker;
layout(location = 5) flat out ivec4 iColor;
layout(location = 6) flat out ivec2 markerPixel;

vec2[] corners = vec2[](
    vec2(0.0, 1.0),
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0)
);

void main() {
    // ShaderSelector
    iColor = ivec4(round(Color * 255.));
    isMarker = int(iColor.r == MARKER_RED);
    ivec2 markerPos = ivec2(0, 0);
    markerPixel = ivec2(0);
    if (isMarker == 1) {
        isMarker = 0;
        #define ADD_MARKER(row, green, alpha, op, rate) if (ivec2(green, alpha) == iColor.ga) {isMarker = 1; markerPos = MARKER_POS(row);}
        LIST_MARKERS
    }
    if (isMarker == 1 && (markerPos.x+markerPos.y)%2 == 0) {
        markerPixel = markerPos;
        // Sodium-safe: fixed NDC quad covering all marker pixel positions.
        // MARKER_POS values reach max ~(6,4). A 0.03 NDC quad covers ~19px at 720p.
        // Fragment shader uses gl_FragCoord to output at the exact target pixel.
        vec2 quadSize = vec2(0.03);
        // z=1.0: nearest depth under the reversed depth buffer used since 26.2,
        // so the marker always passes the depth test.
        gl_Position = vec4(-1.0 + corners[gl_VertexIndex % 4] * quadSize, 1.0, 1.0);

        sphericalVertexDistance = 0.0;
        cylindricalVertexDistance = 0.0;
        texCoord0 = vec2(0.0);
        vertexColor = vec4(0.0);
        return;
    }
    // Vanilla code
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    texCoord0 = UV0;
    vertexColor = Color * sample_lightmap(Sampler2, UV2);
}
