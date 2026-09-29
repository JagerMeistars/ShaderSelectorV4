#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:oit.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
layout(location = 2) in vec2 texCoord0;
layout(location = 3) in vec4 vertexColor;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

// ShaderSelector
layout(location = 4) flat in int isMarker;
layout(location = 5) flat in ivec4 iColor;
layout(location = 6) flat in ivec2 markerPixel;

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
