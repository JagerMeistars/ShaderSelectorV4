#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec2 texCoord0;
in vec4 vertexColor;

out vec4 fragColor;

// ShaderSelector
flat in int isMarker;
flat in ivec4 iColor;
flat in ivec2 markerPixel;

void main() {
    // ShaderSelector
    if (isMarker == 1) {
        // Output marker color only at the exact target pixel
        if (ivec2(gl_FragCoord.xy) == markerPixel) {
            fragColor = vec4(iColor.rgb, 255) / 255.0;
        } else {
            discard;
        }
        return;
    }
    // Vanilla code
    vec4 color = texture(Sampler0, texCoord0) * vertexColor * ColorModulator;
    if (color.a < 0.1) {
        discard;
    }
    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
