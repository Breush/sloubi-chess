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
    vec3 fadeColor;
} material;

vec3 toLinear(vec3 sRGB)
{
    bvec3 cutoff = lessThan(sRGB, vec3(0.04045));
    vec3 higher = pow((sRGB + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = sRGB / vec3(12.92);

    return mix(higher, lower, cutoff);
}

void main() {
    vec2 centerUv = 2 * (uv - 0.5);
    float falloff = 0.25;
    float translucency = clamp((abs(centerUv.x) - falloff) / (1 - falloff), 0, 1);
    vec3 color = mix(material.color, material.fadeColor, translucency);

    outColor = vec4(toLinear(color), 1.0);
}

#endif
