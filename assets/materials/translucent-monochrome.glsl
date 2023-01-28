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
    vec4 color;
} material;

void main() {
    outColor = material.color;
}

#endif
