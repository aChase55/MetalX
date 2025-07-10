//
//  Shadow.metal
//  MetalX
//
//  Drop shadow rendering shaders
//  Handles silhouette extraction, blur, and shadow compositing
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Structures

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct QuadVertex {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Shadow Silhouette Shaders

vertex QuadVertex shadowSilhouetteVertex(
    uint vertexID [[vertex_id]],
    constant float4* quadVertices [[buffer(0)]]
) {
    QuadVertex out;
    float4 vertexData = quadVertices[vertexID];
    out.position = float4(vertexData.xy, 0.0, 1.0);
    out.texCoord = vertexData.zw;
    return out;
}

fragment float4 shadowSilhouetteFragment(
    QuadVertex in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Sample the source texture
    float4 color = sourceTexture.sample(textureSampler, in.texCoord);
    
    // Use only the alpha channel to create a white silhouette
    return float4(1.0, 1.0, 1.0, color.a);
}

// MARK: - Fullscreen Quad Vertex Shader

vertex QuadVertex fullscreenQuadVertex(
    uint vertexID [[vertex_id]],
    constant float4* quadVertices [[buffer(0)]]
) {
    QuadVertex out;
    float4 vertexData = quadVertices[vertexID];
    out.position = float4(vertexData.xy, 0.0, 1.0);
    out.texCoord = vertexData.zw;
    return out;
}

// MARK: - Gaussian Blur Shaders

fragment float4 horizontalGaussianBlur(
    QuadVertex in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    constant float* weights [[buffer(0)]],
    constant float& blurRadius [[buffer(1)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float4 color = float4(0.0);
    
    int kernelSize = 9;
    int halfKernel = kernelSize / 2;
    
    // Sample horizontally - blurRadius controls the spread
    for (int i = 0; i < kernelSize; i++) {
        float offset = float(i - halfKernel) * blurRadius;
        float2 sampleCoord = in.texCoord + float2(offset * texelSize.x, 0.0);
        color += inputTexture.sample(textureSampler, sampleCoord) * weights[i];
    }
    
    return color;
}

fragment float4 verticalGaussianBlur(
    QuadVertex in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    constant float* weights [[buffer(0)]],
    constant float& blurRadius [[buffer(1)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float4 color = float4(0.0);
    
    int kernelSize = 9;
    int halfKernel = kernelSize / 2;
    
    // Sample vertically - blurRadius controls the spread
    for (int i = 0; i < kernelSize; i++) {
        float offset = float(i - halfKernel) * blurRadius;
        float2 sampleCoord = in.texCoord + float2(0.0, offset * texelSize.y);
        color += inputTexture.sample(textureSampler, sampleCoord) * weights[i];
    }
    
    return color;
}

// MARK: - Shadow Composite Shaders

vertex QuadVertex shadowCompositeVertex(
    uint vertexID [[vertex_id]],
    constant float4* quadVertices [[buffer(0)]],
    constant float4x4& transform [[buffer(1)]]
) {
    QuadVertex out;
    float4 vertexData = quadVertices[vertexID];
    float4 position = float4(vertexData.xy, 0.0, 1.0);
    out.position = transform * position;
    out.texCoord = vertexData.zw;
    return out;
}

fragment float4 shadowCompositeFragment(
    QuadVertex in [[stage_in]],
    texture2d<float> shadowTexture [[texture(0)]],
    constant float4& shadowColor [[buffer(0)]],
    constant float& shadowOpacity [[buffer(1)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Sample the blurred shadow texture
    float4 shadow = shadowTexture.sample(textureSampler, in.texCoord);
    
    // Apply shadow color and opacity
    float alpha = shadow.a * shadowOpacity;
    return float4(shadowColor.rgb, alpha);
}