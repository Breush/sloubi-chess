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
    float translucency;
    vec4 scissor; // minX, minY, maxX, maxY
} material;

layout(set = MATERIAL_DESCRIPTOR_SET_INDEX, binding = 1) uniform sampler2D fontTexture;

void main() {
    float opacity = texture(fontTexture, uv).r * (1.0 - material.translucency);

    float scissorBorder = 5.0;
    if (material.scissor.x < material.scissor.z) {
        opacity *= 1 - smoothstep(0.0, scissorBorder, material.scissor.x - localPosition.x);
        opacity *= 1 - smoothstep(0.0, scissorBorder, localPosition.x - material.scissor.z);
    }
    if (material.scissor.y < material.scissor.w) {
        opacity *= 1 - smoothstep(0.0, scissorBorder, material.scissor.y - localPosition.y);
        opacity *= 1 - smoothstep(0.0, scissorBorder, localPosition.y - material.scissor.w);
    }

    if (opacity < 0.01) discard;
    outColor = vec4(material.color, opacity);
}

#endif
