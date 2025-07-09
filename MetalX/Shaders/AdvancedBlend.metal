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

struct BlendUniforms {
    float opacity;
    int blendMode;
    float2 padding;
};

vertex VertexOut blendVertex(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transform * pos;
    out.texCoord = in.texCoord;
    return out;
}

// Blend mode implementations
float3 blendOverlay(float3 base, float3 blend) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        if (base[i] < 0.5) {
            result[i] = 2.0 * base[i] * blend[i];
        } else {
            result[i] = 1.0 - 2.0 * (1.0 - base[i]) * (1.0 - blend[i]);
        }
    }
    return result;
}

float3 blendSoftLight(float3 base, float3 blend) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        if (blend[i] < 0.5) {
            result[i] = base[i] - (1.0 - 2.0 * blend[i]) * base[i] * (1.0 - base[i]);
        } else {
            float d = (base[i] < 0.25) ? ((16.0 * base[i] - 12.0) * base[i] + 4.0) * base[i] : sqrt(base[i]);
            result[i] = base[i] + (2.0 * blend[i] - 1.0) * (d - base[i]);
        }
    }
    return result;
}

float3 blendHardLight(float3 base, float3 blend) {
    return blendOverlay(blend, base); // Hard light is overlay with inputs swapped
}

float3 blendColorDodge(float3 base, float3 blend) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        if (blend[i] >= 1.0) {
            result[i] = 1.0;
        } else {
            result[i] = min(1.0, base[i] / (1.0 - blend[i]));
        }
    }
    return result;
}

float3 blendColorBurn(float3 base, float3 blend) {
    float3 result;
    for (int i = 0; i < 3; i++) {
        if (blend[i] <= 0.0) {
            result[i] = 0.0;
        } else {
            result[i] = 1.0 - min(1.0, (1.0 - base[i]) / blend[i]);
        }
    }
    return result;
}

float3 blendDarken(float3 base, float3 blend) {
    return min(base, blend);
}

float3 blendLighten(float3 base, float3 blend) {
    return max(base, blend);
}

float3 blendDifference(float3 base, float3 blend) {
    return abs(base - blend);
}

float3 blendExclusion(float3 base, float3 blend) {
    return base + blend - 2.0 * base * blend;
}

fragment float4 advancedBlendFragment(VertexOut in [[stage_in]],
                                     texture2d<float> sourceTexture [[texture(0)]],
                                     texture2d<float> destTexture [[texture(1)]],
                                     sampler textureSampler [[sampler(0)]],
                                     constant BlendUniforms& uniforms [[buffer(0)]]) {
    
    // Sample textures
    float4 src = sourceTexture.sample(textureSampler, in.texCoord);
    
    // For destination, we need to sample at the current fragment position
    // Convert screen position to normalized texture coordinates
    float2 screenPos = in.position.xy;
    float2 destCoord = float2(
        screenPos.x / float(destTexture.get_width()),
        screenPos.y / float(destTexture.get_height())
    );
    float4 dst = destTexture.sample(textureSampler, destCoord);
    
    // Apply opacity to source
    src.a *= uniforms.opacity;
    
    // Skip if source is fully transparent
    if (src.a == 0.0) {
        return dst;
    }
    
    // Unpremultiply colors for blending
    float3 srcColor = src.a > 0.0 ? src.rgb / src.a : src.rgb;
    float3 dstColor = dst.a > 0.0 ? dst.rgb / dst.a : dst.rgb;
    float3 result;
    
    // Apply blend mode
    switch (uniforms.blendMode) {
        case 0: // Overlay
            result = blendOverlay(dstColor, srcColor);
            break;
        case 1: // Soft Light
            result = blendSoftLight(dstColor, srcColor);
            break;
        case 2: // Hard Light
            result = blendHardLight(dstColor, srcColor);
            break;
        case 3: // Color Dodge
            result = blendColorDodge(dstColor, srcColor);
            break;
        case 4: // Color Burn
            result = blendColorBurn(dstColor, srcColor);
            break;
        case 5: // Darken
            result = blendDarken(dstColor, srcColor);
            break;
        case 6: // Lighten
            result = blendLighten(dstColor, srcColor);
            break;
        case 7: // Difference
            result = blendDifference(dstColor, srcColor);
            break;
        case 8: // Exclusion
            result = blendExclusion(dstColor, srcColor);
            break;
        default:
            result = srcColor;
            break;
    }
    
    // Composite with alpha
    result = mix(dstColor, result, src.a);
    float outAlpha = src.a + dst.a * (1.0 - src.a);
    
    // Premultiply result
    return float4(result * outAlpha, outAlpha);
}