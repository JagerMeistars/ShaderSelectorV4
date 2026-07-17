#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:oit.glsl>

uniform sampler2D Sampler0;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec2 texCoord0;
in vec4 vertexColor;

#ifndef OIT_ALPHA_ONLY
out vec4 fragColor;
#endif

// ShaderSelector
flat in int isMarker;
flat in ivec4 iColor;
flat in ivec2 markerPixel;

vec4 calculateFinalColor(vec4 color) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif
    return apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
}

void main() {
    // ShaderSelector
    if (isMarker == 1) {
        // Output the marker color only at its exact target pixel.
        // The marker is written with alpha 1.0 so the engine's OIT pipeline treats it
        // as a fully opaque fragment (alpha > OIT_FULLY_OPAQUE_ALPHA) and composites it
        // straight into minecraft:main without fog/accumulation tinting. The data
        // pipeline (post_effect/end_of_frame.json) then reads it back out of main.
        if (ivec2(gl_FragCoord.xy) == markerPixel) {
            #ifdef OIT_ALPHA_ONLY
            executeAlphaOnlyPhase(gl_FragCoord.z, 1.0);
            #else
            fragColor = vec4(iColor.rgb, 255) / 255.0;
            #endif
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
    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}
