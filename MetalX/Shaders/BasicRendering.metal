#include <metal_stdlib>
#include "Common.metal"
using namespace metal;

// MARK: - Fullscreen Quad Rendering

struct QuadVertex {
    float2 position;
    float2 texCoord;
};

vertex VertexOut vertex_fullscreen_quad(uint vertexID [[vertex_id]]) {
    // Generate fullscreen quad without vertex buffer
    const QuadVertex vertices[4] = {
        {{-1.0, -1.0}, {0.0, 1.0}}, // Bottom-left
        {{ 1.0, -1.0}, {1.0, 1.0}}, // Bottom-right
        {{-1.0,  1.0}, {0.0, 0.0}}, // Top-left
        {{ 1.0,  1.0}, {1.0, 0.0}}  // Top-right
    };
    
    QuadVertex v = vertices[vertexID];
    
    VertexOut out;
    out.position = float4(v.position, 0.0, 1.0);
    out.texCoord = v.texCoord;
    out.color = float4(1.0);
    out.normal = float3(0.0, 0.0, 1.0);
    out.worldPosition = float3(0.0);
    out.tangent = float3(1.0, 0.0, 0.0);
    out.bitangent = float3(0.0, 1.0, 0.0);
    
    return out;
}

// MARK: - Basic Fragment Shaders

fragment float4 fragment_copy(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    return sourceTexture.sample(sourceSampler, in.texCoord);
}

fragment float4 fragment_premultiply_alpha(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    float4 color = sourceTexture.sample(sourceSampler, in.texCoord);
    color.rgb *= color.a;
    return color;
}

fragment float4 fragment_unpremultiply_alpha(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    float4 color = sourceTexture.sample(sourceSampler, in.texCoord);
    if (color.a > 0.0) {
        color.rgb /= color.a;
    }
    return color;
}

// MARK: - Color Adjustment Shaders

struct ColorAdjustmentParams {
    float brightness;
    float contrast;
    float saturation;
    float hue;
    float gamma;
    float exposure;
    float highlights;
    float shadows;
    float whites;
    float blacks;
    float clarity;
    float vibrance;
};

fragment float4 fragment_color_adjustments(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]],
    constant ColorAdjustmentParams& params [[buffer(0)]]
) {
    float4 color = sourceTexture.sample(sourceSampler, in.texCoord);
    
    // Exposure
    color.rgb *= pow(2.0, params.exposure);
    
    // Gamma correction
    color.rgb = pow(color.rgb, 1.0 / params.gamma);
    
    // Brightness
    color.rgb += params.brightness;
    
    // Contrast
    color.rgb = (color.rgb - 0.5) * params.contrast + 0.5;
    
    // Convert to HSV for saturation and hue adjustments
    float3 hsv = rgb2hsv(color.rgb);
    
    // Hue shift
    hsv.x = fract(hsv.x + params.hue);
    
    // Saturation
    hsv.y *= params.saturation;
    
    // Vibrance (selective saturation)
    float maxComponent = max(max(color.r, color.g), color.b);
    float avgComponent = (color.r + color.g + color.b) / 3.0;
    float vibMask = 1.0 - pow(maxComponent - avgComponent, 2.0);
    hsv.y = mix(hsv.y, hsv.y * params.vibrance, vibMask);
    
    // Convert back to RGB
    color.rgb = hsv2rgb(hsv);
    
    // Highlights and Shadows
    float luma = luminance(color.rgb);
    float highlightMask = smoothstep(0.3, 0.7, luma);
    float shadowMask = 1.0 - highlightMask;
    
    color.rgb = mix(color.rgb, color.rgb * params.highlights, highlightMask);
    color.rgb = mix(color.rgb, color.rgb * params.shadows, shadowMask);
    
    // Whites and Blacks
    color.rgb = mix(color.rgb, float3(1.0), (color.rgb - 0.5) * params.whites);
    color.rgb = mix(color.rgb, float3(0.0), (0.5 - color.rgb) * params.blacks);
    
    // Clarity (local contrast)
    if (params.clarity != 0.0) {
        // This would typically require a blurred version of the image
        // For now, we'll use a simple approach
        float3 clarityBoost = color.rgb * params.clarity * 0.1;
        color.rgb += clarityBoost;
    }
    
    return clamp(color, 0.0, 1.0);
}

// MARK: - Blend Mode Shaders

fragment float4 fragment_blend_normal(
    VertexOut in [[stage_in]],
    texture2d<float> baseTexture [[texture(0)]],
    texture2d<float> overlayTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant float& opacity [[buffer(0)]]
) {
    float4 base = baseTexture.sample(textureSampler, in.texCoord);
    float4 overlay = overlayTexture.sample(textureSampler, in.texCoord);
    
    float4 result = blendNormal(base, overlay);
    return mix(base, result, opacity * overlay.a);
}

fragment float4 fragment_blend_multiply(
    VertexOut in [[stage_in]],
    texture2d<float> baseTexture [[texture(0)]],
    texture2d<float> overlayTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant float& opacity [[buffer(0)]]
) {
    float4 base = baseTexture.sample(textureSampler, in.texCoord);
    float4 overlay = overlayTexture.sample(textureSampler, in.texCoord);
    
    float4 result = blendMultiply(base, overlay);
    return mix(base, result, opacity * overlay.a);
}

fragment float4 fragment_blend_screen(
    VertexOut in [[stage_in]],
    texture2d<float> baseTexture [[texture(0)]],
    texture2d<float> overlayTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant float& opacity [[buffer(0)]]
) {
    float4 base = baseTexture.sample(textureSampler, in.texCoord);
    float4 overlay = overlayTexture.sample(textureSampler, in.texCoord);
    
    float4 result = blendScreen(base, overlay);
    return mix(base, result, opacity * overlay.a);
}

fragment float4 fragment_blend_overlay(
    VertexOut in [[stage_in]],
    texture2d<float> baseTexture [[texture(0)]],
    texture2d<float> overlayTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant float& opacity [[buffer(0)]]
) {
    float4 base = baseTexture.sample(textureSampler, in.texCoord);
    float4 overlay = overlayTexture.sample(textureSampler, in.texCoord);
    
    float4 result = blendOverlay(base, overlay);
    return mix(base, result, opacity * overlay.a);
}

// MARK: - Transform Shaders

struct TransformParams {
    float2 scale;
    float2 translate;
    float rotation;
    float2 anchor;
    float2 skew;
};

float2 transformPoint(float2 point, TransformParams transform) {
    // Translate to anchor
    point -= transform.anchor;
    
    // Apply scale
    point *= transform.scale;
    
    // Apply skew
    point.x += point.y * transform.skew.x;
    point.y += point.x * transform.skew.y;
    
    // Apply rotation
    float cosR = cos(transform.rotation);
    float sinR = sin(transform.rotation);
    float2 rotated = float2(
        point.x * cosR - point.y * sinR,
        point.x * sinR + point.y * cosR
    );
    
    // Translate back and apply translation
    return rotated + transform.anchor + transform.translate;
}

fragment float4 fragment_transform(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]],
    constant TransformParams& transform [[buffer(0)]]
) {
    float2 uv = in.texCoord;
    
    // Inverse transform to get source coordinates
    TransformParams inverseTransform;
    inverseTransform.scale = 1.0 / transform.scale;
    inverseTransform.translate = -transform.translate / transform.scale;
    inverseTransform.rotation = -transform.rotation;
    inverseTransform.anchor = transform.anchor;
    inverseTransform.skew = -transform.skew;
    
    float2 sourceUV = transformPoint(uv, inverseTransform);
    
    // Sample texture if coordinates are valid
    if (sourceUV.x >= 0.0 && sourceUV.x <= 1.0 && sourceUV.y >= 0.0 && sourceUV.y <= 1.0) {
        return sourceTexture.sample(sourceSampler, sourceUV);
    } else {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
}

// MARK: - Mask Shaders

fragment float4 fragment_apply_mask(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant float& maskStrength [[buffer(0)]]
) {
    float4 source = sourceTexture.sample(textureSampler, in.texCoord);
    float4 mask = maskTexture.sample(textureSampler, in.texCoord);
    
    float maskValue = mix(1.0, luminance(mask.rgb), maskStrength);
    source.a *= maskValue;
    
    return source;
}

fragment float4 fragment_create_luminance_mask(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]],
    constant float2& range [[buffer(0)]] // min, max luminance
) {
    float4 color = sourceTexture.sample(sourceSampler, in.texCoord);
    float luma = luminance(color.rgb);
    
    float mask = smoothstep(range.x, range.y, luma);
    return float4(mask, mask, mask, 1.0);
}

// MARK: - Utility Shaders

fragment float4 fragment_generate_mipmap(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    // Simple 2x2 box filter for mipmap generation
    float2 texelSize = 1.0 / float2(sourceTexture.get_width(), sourceTexture.get_height());
    float2 uv = in.texCoord;
    
    float4 samples[4];
    samples[0] = sourceTexture.sample(sourceSampler, uv + float2(-0.5, -0.5) * texelSize);
    samples[1] = sourceTexture.sample(sourceSampler, uv + float2( 0.5, -0.5) * texelSize);
    samples[2] = sourceTexture.sample(sourceSampler, uv + float2(-0.5,  0.5) * texelSize);
    samples[3] = sourceTexture.sample(sourceSampler, uv + float2( 0.5,  0.5) * texelSize);
    
    return (samples[0] + samples[1] + samples[2] + samples[3]) * 0.25;
}

fragment float4 fragment_downsample(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    return sourceTexture.sample(sourceSampler, in.texCoord);
}

fragment float4 fragment_upsample(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    return sampleTextureBilinear(sourceTexture, sourceSampler, in.texCoord);
}

// MARK: - Debug Shaders

fragment float4 fragment_debug_uv(VertexOut in [[stage_in]]) {
    return float4(in.texCoord, 0.0, 1.0);
}

fragment float4 fragment_debug_normal(VertexOut in [[stage_in]]) {
    return float4(normalize(in.normal) * 0.5 + 0.5, 1.0);
}

fragment float4 fragment_debug_depth(
    VertexOut in [[stage_in]],
    constant float2& depthRange [[buffer(0)]] // near, far
) {
    float depth = (in.position.z - depthRange.x) / (depthRange.y - depthRange.x);
    return float4(depth, depth, depth, 1.0);
}

fragment float4 fragment_debug_wireframe(VertexOut in [[stage_in]]) {
    return float4(1.0, 1.0, 1.0, 1.0);
}

// MARK: - Performance Test Shaders

fragment float4 fragment_performance_simple(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
) {
    return sourceTexture.sample(sourceSampler, in.texCoord);
}

fragment float4 fragment_performance_complex(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]],
    constant float& time [[buffer(0)]]
) {
    float4 color = sourceTexture.sample(sourceSampler, in.texCoord);
    
    // Add some computational complexity for performance testing
    for (int i = 0; i < 10; i++) {
        color.rgb = mix(color.rgb, sin(color.rgb * 3.14159 + time), 0.1);
    }
    
    return color;
}

// MARK: - Additional Vertex Shaders (from Common.metal)

vertex VertexOut vertex_passthrough(
    Vertex2D in [[stage_in]],
    constant VertexUniforms& uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.color = float4(1.0);
    out.normal = float3(0.0, 0.0, 1.0);
    out.worldPosition = float3(0.0);
    out.tangent = float3(1.0, 0.0, 0.0);
    out.bitangent = float3(0.0, 1.0, 0.0);
    return out;
}

vertex VertexOut vertex_standard(
    Vertex3D in [[stage_in]],
    constant VertexUniforms& uniforms [[buffer(1)]],
    uint instanceID [[instance_id]],
    constant InstanceData* instanceData [[buffer(2)]]
) {
    VertexOut out;
    
    float4x4 modelMatrix = instanceData ? instanceData[instanceID].modelMatrix : uniforms.modelMatrix;
    float4x4 normalMatrix = instanceData ? instanceData[instanceID].normalMatrix : uniforms.normalMatrix;
    
    float4 worldPosition = modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    out.worldPosition = worldPosition.xyz;
    
    out.normal = normalize((normalMatrix * float4(in.normal, 0.0)).xyz);
    out.tangent = normalize((normalMatrix * float4(in.tangent, 0.0)).xyz);
    out.bitangent = cross(out.normal, out.tangent);
    
    if (instanceData) {
        out.texCoord = transformUV(in.texCoord, instanceData[instanceID].uvTransform);
        out.color = instanceData[instanceID].color;
    } else {
        out.texCoord = in.texCoord;
        out.color = float4(1.0);
    }
    
    return out;
}

// MARK: - Additional Fragment Shaders (from Common.metal)

fragment float4 fragment_texture(
    VertexOut in [[stage_in]],
    texture2d<float> baseTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant FragmentUniforms& uniforms [[buffer(0)]]
) {
    float4 color = baseTexture.sample(textureSampler, in.texCoord);
    return color * uniforms.color * in.color;
}

fragment float4 fragment_color(
    VertexOut in [[stage_in]],
    constant FragmentUniforms& uniforms [[buffer(0)]]
) {
    return uniforms.color * in.color;
}

fragment float4 fragment_lit(
    VertexOut in [[stage_in]],
    texture2d<float> baseTexture [[texture(0)]],
    texture2d<float> normalTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    constant FragmentUniforms& uniforms [[buffer(0)]],
    constant MaterialUniforms& material [[buffer(1)]]
) {
    float4 albedo = baseTexture.sample(textureSampler, in.texCoord) * material.albedo;
    float3 normalMap = normalTexture.sample(textureSampler, in.texCoord).xyz;
    
    float3 normal = calculateNormal(in.normal, in.tangent, in.bitangent, normalMap);
    float3 lightDir = normalize(-uniforms.lightDirection.xyz);
    
    float ndotl = max(dot(normal, lightDir), 0.0);
    float3 diffuse = albedo.rgb * uniforms.lightColor.rgb * ndotl;
    
    float3 ambient = albedo.rgb * 0.1;
    float3 finalColor = ambient + diffuse + material.emission.rgb;
    
    return float4(finalColor, albedo.a * uniforms.opacity);
}

// MARK: - Compute Shaders (from Common.metal)

kernel void compute_image_process(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant FragmentUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    float4 color = inputTexture.read(gid);
    color *= uniforms.color;
    
    outputTexture.write(color, gid);
}

kernel void compute_blur_horizontal(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float& sigma [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    
    int kernelSize = int(ceil(3.0 * sigma));
    
    for (int i = -kernelSize; i <= kernelSize; i++) {
        int x = int(gid.x) + i;
        if (x >= 0 && x < int(inputTexture.get_width())) {
            float weight = exp(-0.5 * pow(float(i) / sigma, 2.0));
            result += inputTexture.read(uint2(x, gid.y)) * weight;
            totalWeight += weight;
        }
    }
    
    outputTexture.write(result / totalWeight, gid);
}

kernel void compute_blur_vertical(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float& sigma [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    
    int kernelSize = int(ceil(3.0 * sigma));
    
    for (int i = -kernelSize; i <= kernelSize; i++) {
        int y = int(gid.y) + i;
        if (y >= 0 && y < int(inputTexture.get_height())) {
            float weight = exp(-0.5 * pow(float(i) / sigma, 2.0));
            result += inputTexture.read(uint2(gid.x, y)) * weight;
            totalWeight += weight;
        }
    }
    
    outputTexture.write(result / totalWeight, gid);
}