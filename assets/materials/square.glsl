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

void main() {
    outColor = material.color;

    vec2 pieceUv = uv;
    if (material.flipped) pieceUv = 1 - pieceUv;

    // Highlighted square
    float f = 0.40 + 0.40 * length(uv - 0.5);
    float v = floor(40 * (uv.x + uv.y));
    f *= mod(v, 4) / 3;
    outColor.rgb = mix(outColor.rgb, material.highlightColor.rgb, f * material.highlightColor.a);

    // @todo Add config for these colors?
    const float selectionHighlightThickness = 0.025;
    float selectionHighlight = texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(1, 0)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(-1, 0)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(0, 1)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(0, -1)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(1, 1)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(-1, 1)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(1, -1)).a;
    selectionHighlight += texture(pieceTexture, pieceUv + selectionHighlightThickness * vec2(-1, -1)).a;
    selectionHighlight = clamp(selectionHighlight, 0, 1);
    selectionHighlight *= float(material.selected);

    outColor.rgb = mix(outColor.rgb, vec3(0.6, 0.6, 0.8), float(material.moved) * 0.6);

    if (material.targetable) {
        float factor = material.hovered ? 0.8 : 0.4;
        const float blurThickness = 0.02;

        if (material.capturable) {
            float value = abs((2 * uv.x - 1) * (2 * uv.y - 1));
            if (value >= 0.75) {
                outColor.rgb = mix(outColor.rgb, vec3(0.4), factor * clamp((value - 0.75) / blurThickness, 0.0, 1.0));
            }
        } else {
            vec2 t = (2 * uv - 1) * (2 * uv - 1);
            float value = sqrt(t.x + t.y);
            if (value < 0.33) {
                outColor.rgb = mix(outColor.rgb, vec3(0.4), factor * clamp((0.33 - value) / blurThickness, 0.0, 1.0));
            }
        }
    }

    // Alpha compositing to opaque background
    vec4 pieceTextureColor = texture(pieceTexture, pieceUv);
    vec4 pieceColor = vec4(0.88, 0.70, 0.50, selectionHighlight);
    pieceColor.rgb = mix(pieceColor.rgb, pieceTextureColor.rgb, pieceTextureColor.a);
    pieceColor.a = max(pieceColor.a, pieceTextureColor.a);
    outColor.rgb = mix(outColor.rgb, pieceColor.rgb, (1 - material.pieceTranslucency) * pieceColor.a);
    outColor.a = pieceColor.a + outColor.a * (1 - pieceColor.a);
}

#endif
