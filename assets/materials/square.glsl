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
    vec3 color;
    bool flipped;
    bool hovered;
    vec4 highlightColor;
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
    outColor = vec4(material.color, 1.0);

    // Highlighted square
    float f = 0.40 + 0.40 * length(uv - 0.5);
    float v = floor(40 * (uv.x + uv.y));
    f *= mod(v, 4) / 3;
    outColor.rgb = mix(outColor.rgb, material.highlightColor.rgb, f * material.highlightColor.a);

    // Hovering
    if (material.hovered) {
        const float lineSize = 0.02;
        if (uv.x < lineSize || uv.x > 1 - lineSize ||
            uv.y < lineSize || uv.y > 1 - lineSize) {
            outColor.rgb = mix(outColor.rgb, material.highlightColor.rgb, 0.8);
        }
    }

    // Alpha compositing to opaque background
    vec2 pieceUv = uv;
    if (material.flipped) pieceUv = 1 - pieceUv;
    vec4 pieceColor = texture(pieceTexture, pieceUv);
    outColor.rgb = mix(outColor.rgb, pieceColor.rgb, pieceColor.a);

    // @fixme Clarify, why would going to linear space needed?
    outColor = vec4(toLinear(outColor.rgb), 1.0);
}

#endif
