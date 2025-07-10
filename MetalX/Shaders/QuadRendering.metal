//
//  QuadRendering.metal
//  MetalX
//
//  Basic quad rendering shaders for textures and layers
//  Handles texture sampling, opacity, and transformations
//

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

vertex VertexOut quadVertex(VertexIn in [[stage_in]],
                            constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transform * pos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 quadFragment(VertexOut in [[stage_in]],
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

// Textured quad fragment shader (no opacity modification)
fragment float4 texturedQuadFragment(VertexOut in [[stage_in]],
                                     texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    return texture.sample(textureSampler, in.texCoord);
}