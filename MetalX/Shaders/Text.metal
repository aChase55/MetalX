#include <metal_stdlib>
using namespace metal;

struct TextVertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct TextVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

struct TextUniforms {
    float4x4 transform;
    float4 textColor;
};

// Vertex shader for text
vertex TextVertexOut textVertex(TextVertexIn in [[stage_in]],
                                constant TextUniforms& uniforms [[buffer(1)]]) {
    TextVertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transform * pos;
    out.texCoord = in.texCoord;
    out.color = in.color * uniforms.textColor;
    return out;
}

// Fragment shader for basic text (solid color)
fragment float4 textFragmentSolid(TextVertexOut in [[stage_in]],
                                  constant TextUniforms& uniforms [[buffer(0)]]) {
    // For now, just render solid color
    // Later we'll sample from font atlas
    return in.color;
}

// Fragment shader for textured text (from atlas)
fragment float4 textFragmentTextured(TextVertexOut in [[stage_in]],
                                     texture2d<float> fontAtlas [[texture(0)]],
                                     sampler fontSampler [[sampler(0)]],
                                     constant TextUniforms& uniforms [[buffer(0)]]) {
    // Sample the font atlas
    float alpha = fontAtlas.sample(fontSampler, in.texCoord).a;
    return float4(in.color.rgb, in.color.a * alpha);
}

// Advanced text effects can be added here:
// - Outline/stroke
// - Shadow
// - Gradient fill
// - Distortion effects