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

void main() {
    float opacity = texture(fontTexture, uv).r;
    outColor = vec4(material.color, opacity);
}

#endif
