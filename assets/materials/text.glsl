#version 450

// ------------------
// ----- VERTEX -----

#if defined(VERTEX)

#include "$/forward-renderer/default.vert"

// --------------------
// ----- FRAGMENT -----

#elif defined(FRAGMENT)

#include "$/forward-renderer/default-header.frag"

layout(set = MATERIAL_DESCRIPTOR_SET_INDEX, binding = 0) uniform MaterialShaderObject {
    vec3 color;
} material;

layout(set = MATERIAL_DESCRIPTOR_SET_INDEX, binding = 1) uniform sampler2D fontTexture;

vec3 toLinear(vec3 sRGB)
{
    bvec3 cutoff = lessThan(sRGB, vec3(0.04045));
    vec3 higher = pow((sRGB + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = sRGB / vec3(12.92);

    return mix(higher, lower, cutoff);
}

void main() {
    float opacity = texture(fontTexture, uv).r;
    if (opacity < 0.01) discard;
    outColor = vec4(toLinear(material.color), opacity);
}

#endif
