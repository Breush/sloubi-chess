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
    bool hovered;
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

    // @todo Make the highlight be of a inversed-round shape
    if (material.hovered) {
        outColor.rgb -= 0.1;
    }

    // Alpha compositing to opaque background
    vec4 pieceColor = texture(pieceTexture, uv);
    outColor.rgb = mix(outColor.rgb, pieceColor.rgb, pieceColor.a);

    // @fixme Clarify, why would going to linear space needed?
    outColor = vec4(toLinear(outColor.rgb), 1.0);
}

#endif
