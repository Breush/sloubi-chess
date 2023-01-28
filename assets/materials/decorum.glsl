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
    float height;
    bool collapsed;
} material;

void main() {
    float alpha = material.collapsed ? 2 * abs(fract(uv.y * material.height) - 0.5) : 1.0;
    outColor = vec4(material.color, alpha);
}

#endif
