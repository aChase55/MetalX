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
    float2 viewportSize;
    float time;
};

vertex VertexOut selectionVertex(VertexIn in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transform * pos;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 selectionFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]]) {
    // Create outline effect by checking distance from edge
    float2 uv = in.texCoord;
    
    // Distance from edges
    float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    
    // Thinner outline with sharper edges
    float thickness = 0.015; // Thinner
    float outline = smoothstep(thickness - 0.002, thickness, d); // Sharp transition
    outline = 1.0 - outline;
    
    // Animated selection color
    float pulse = sin(uniforms.time * 3.0) * 0.3 + 0.7;
    float3 color = float3(0.0, 0.5, 1.0) * pulse;
    
    // Full opacity for clean edges
    return float4(color, outline);
}