#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:globals.glsl>

in vec3 Position;
in vec2 UV0;
in vec4 Color;
in ivec2 UV2;

uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec2 texCoord0;
out vec4 vertexColor;

// ShaderSelector
#moj_import <shader_selector:marker_settings.glsl>

flat out int isMarker;
flat out ivec4 iColor;
flat out ivec2 markerPixel;

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
        gl_Position = vec4(-1.0 + corners[gl_VertexID % 4] * quadSize, 0.0, 1.0);

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
    vertexColor = Color * texelFetch(Sampler2, UV2 / 16, 0);
}
