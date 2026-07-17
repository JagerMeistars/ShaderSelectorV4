#version 330

#moj_import <shader_selector:marker_settings.glsl>

// Reads minecraft:main (which now contains the composited marker pixels) and hides the
// tiny marker dots by replacing them with their right-hand neighbour before display.
uniform sampler2D MainSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

in vec2 texCoord;

out vec4 fragColor;

void main() {
    ivec2 iCoord = ivec2(gl_FragCoord.xy);
    fragColor = texture(MainSampler, texCoord);
    ivec4 iColor = ivec4(round(fragColor * 255.));
    if (false
        #define ADD_MARKER(i, green, alpha, op, r) || MARKER_POS(i) == iCoord && iColor.rga == ivec3(MARKER_RED, green, 255)
        LIST_MARKERS
    ) {
        fragColor = texture(MainSampler, texCoord + vec2(1./OutSize.x, 0.0));
    }
}
