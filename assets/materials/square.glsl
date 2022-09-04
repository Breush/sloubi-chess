#version 450

// ------------------
// ----- VERTEX -----

#if defined(VERTEX)

#include "$/forward-renderer/default.vert"

// --------------------
// ----- FRAGMENT -----

#elif defined(FRAGMENT)

#include "$/forward-renderer/default-header.frag"

layout(std140, set = MATERIAL_DESCRIPTOR_SET_INDEX, binding = 0) uniform MaterialShaderObject {
    vec4 highlightColor;
    vec4 color;
    float pieceTranslucency;
    bool flipped;
    bool hovered;
    bool selected;
    bool moved;      // A piece moved or moved from there.
    bool targetable; // A piece can move there
    bool capturable; // The square has a piece or is the en-passant square.
} material;

layout(set = MATERIAL_DESCRIPTOR_SET_INDEX, binding = 1) uniform sampler2D pieceTexture;

vec3 toLinear(vec3 sRGB)
{
    bvec3 cutoff = lessThan(sRGB, vec3(0.04045));
    vec3 higher = pow((sRGB + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = sRGB / vec3(12.92);

    return mix(higher, lower, cutoff);
}

void main() {
    outColor = material.color;

    // Highlighted square
    float f = 0.40 + 0.40 * length(uv - 0.5);
    float v = floor(40 * (uv.x + uv.y));
    f *= mod(v, 4) / 3;
    outColor.rgb = mix(outColor.rgb, material.highlightColor.rgb, f * material.highlightColor.a);

    // @todo Add config for these colors?
    outColor.rgb = mix(outColor.rgb, vec3(0.98, 0.70, 0.50), float(material.selected));
    outColor.rgb = mix(outColor.rgb, vec3(0.8, 0.8, 0.8), float(material.moved) * 0.4);

    if (material.targetable) {
        float factor = material.hovered ? 0.8 : 0.4;

        if (material.capturable) {
            if (abs((2 * uv.x - 1) * (2 * uv.y - 1)) >= 0.75) {
                outColor.rgb = mix(outColor.rgb, vec3(0.4), factor);
            }
        } else {
            vec2 t = (2 * uv - 1) * (2 * uv - 1);
            if (sqrt(t.x + t.y) < 0.33) {
                outColor.rgb = mix(outColor.rgb, vec3(0.4), factor);
            }
        }
    }

    // Alpha compositing to opaque background
    vec2 pieceUv = uv;
    if (material.flipped) pieceUv = 1 - pieceUv;
    vec4 pieceColor = texture(pieceTexture, pieceUv);
    outColor.rgb = mix(outColor.rgb, pieceColor.rgb, (1 - material.pieceTranslucency) * pieceColor.a);
    outColor.a = pieceColor.a + outColor.a * (1 - pieceColor.a);

    // @fixme Clarify, why would going to linear space needed?
    outColor = vec4(toLinear(outColor.rgb), outColor.a);
}

#endif
