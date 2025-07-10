#include <metal_stdlib>
using namespace metal;

// MARK: - Gaussian Blur Shaders

struct BlurVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Simple vertex shader for full-screen quad
vertex BlurVertexOut blurVertex(uint vertexID [[vertex_id]]) {
    BlurVertexOut out;
    
    // Create a full-screen triangle
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(-1.0,  3.0),
        float2( 3.0, -1.0)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = (positions[vertexID] + 1.0) * 0.5;
    out.texCoord.y = 1.0 - out.texCoord.y; // Flip Y for texture coordinates
    
    return out;
}

// Vertex shader with transform for shadow composite
vertex BlurVertexOut blurVertexWithTransform(uint vertexID [[vertex_id]],
                                            constant float4x4& transform [[buffer(0)]]) {
    BlurVertexOut out;
    
    // Create a quad using triangle strip
    float2 positions[4] = {
        float2(-1.0, -1.0),  // bottom-left
        float2( 1.0, -1.0),  // bottom-right
        float2(-1.0,  1.0),  // top-left
        float2( 1.0,  1.0)   // top-right
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    // Apply transform to position
    float4 pos = float4(positions[vertexID], 0.0, 1.0);
    out.position = transform * pos;
    out.texCoord = texCoords[vertexID];
    
    return out;
}

// Gaussian weights for 9-tap filter
constant float gaussianWeights[9] = {
    0.0162, 0.0540, 0.1216, 0.1945, 0.2270, 0.1945, 0.1216, 0.0540, 0.0162
};

// Horizontal blur pass
fragment float4 gaussianBlurHorizontal(BlurVertexOut in [[stage_in]],
                                       texture2d<float> inputTexture [[texture(0)]],
                                       constant float& blurRadius [[buffer(0)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float4 color = float4(0.0);
    
    // 9-tap Gaussian blur
    for (int i = -4; i <= 4; i++) {
        float2 offset = float2(float(i) * blurRadius * texelSize.x, 0.0);
        float4 sample = inputTexture.sample(textureSampler, in.texCoord + offset);
        color += sample * gaussianWeights[i + 4];
    }
    
    return color;
}

// Vertical blur pass
fragment float4 gaussianBlurVertical(BlurVertexOut in [[stage_in]],
                                    texture2d<float> inputTexture [[texture(0)]],
                                    constant float& blurRadius [[buffer(0)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    
    float2 texelSize = 1.0 / float2(inputTexture.get_width(), inputTexture.get_height());
    float4 color = float4(0.0);
    
    // 9-tap Gaussian blur
    for (int i = -4; i <= 4; i++) {
        float2 offset = float2(0.0, float(i) * blurRadius * texelSize.y);
        float4 sample = inputTexture.sample(textureSampler, in.texCoord + offset);
        color += sample * gaussianWeights[i + 4];
    }
    
    return color;
}

// Shadow composite shader - combines blurred shadow with tint color
fragment float4 shadowComposite(BlurVertexOut in [[stage_in]],
                               texture2d<float> shadowTexture [[texture(0)]],
                               constant float4& shadowColor [[buffer(0)]],
                               constant float& shadowOpacity [[buffer(1)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    
    float4 shadow = shadowTexture.sample(textureSampler, in.texCoord);
    
    // Use the alpha channel from the blurred texture and apply shadow color
    float alpha = shadow.a * shadowOpacity;
    return float4(shadowColor.rgb, alpha);
}

