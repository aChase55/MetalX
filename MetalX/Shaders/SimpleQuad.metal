#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut simpleQuadVertex(uint vertexID [[vertex_id]]) {
    // Define quad vertices
    const float2 positions[] = {
        float2(-0.5, -0.5),  // bottom left
        float2( 0.5, -0.5),  // bottom right
        float2(-0.5,  0.5),  // top left
        float2( 0.5,  0.5),  // top right
    };
    
    const float2 uvs[] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0),
    };
    
    // Triangle strip indices
    const uint indices[] = { 0, 1, 2, 2, 1, 3 };
    uint index = indices[vertexID];
    
    VertexOut out;
    out.position = float4(positions[index], 0.0, 1.0);
    out.uv = uvs[index];
    return out;
}

fragment float4 simpleQuadFragment(VertexOut in [[stage_in]]) {
    // Simple gradient based on UV coordinates
    return float4(in.uv.x, in.uv.y, 0.5, 1.0);
}