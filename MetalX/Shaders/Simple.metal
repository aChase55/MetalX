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

vertex VertexOut simpleVertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 simpleFragment(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]]) {
    return texture.sample(textureSampler, in.texCoord);
}