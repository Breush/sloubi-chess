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
    float fadeInX;
    float fadeOutX;
} material;

void main() {
    float translucency = smoothstep(0, material.fadeInX, uv.x) * (1 - smoothstep(material.fadeOutX, 1, uv.x));
    vec3 color = mix(material.fadeColor, material.color, translucency);

    outColor = vec4(color, 1.0);
}

#endif
