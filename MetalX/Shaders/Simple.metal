#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float4x4 transform;
};

vertex VertexOut simpleVertex(VertexIn in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transform * pos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 simpleFragment(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]],
                               constant float4& fragmentUniforms [[buffer(1)]]) {
    float4 color = texture.sample(textureSampler, in.texCoord);
    
    // Apply opacity
    color.a *= fragmentUniforms.x;
    
    // Premultiply alpha for proper blending
    color.rgb *= color.a;
    
    return color;
}

// Simple shadow fragment shader
struct SimpleShadowFragmentUniforms {
    float4 shadowColor;
    float shadowOpacity;
    float3 padding; // For alignment
};

fragment float4 simpleShadowFragment(VertexOut in [[stage_in]],
                                     texture2d<float> texture [[texture(0)]],
                                     sampler textureSampler [[sampler(0)]],
                                     constant SimpleShadowFragmentUniforms& uniforms [[buffer(1)]]) {
    // Sample the texture to get the alpha channel
    float4 texColor = texture.sample(textureSampler, in.texCoord);
    
    // Use the texture's alpha to determine shadow opacity
    float shadowAlpha = texColor.a * uniforms.shadowOpacity;
    
    // Create shadow color with proper alpha
    float4 shadowColor = uniforms.shadowColor;
    shadowColor.a *= shadowAlpha;
    
    // Premultiply alpha for proper blending
    shadowColor.rgb *= shadowColor.a;
    
    return shadowColor;
}

// Simple pass-through fragment shader (no opacity modification)
fragment float4 simplePassthroughFragment(VertexOut in [[stage_in]],
                                         texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    return texture.sample(textureSampler, in.texCoord);
}