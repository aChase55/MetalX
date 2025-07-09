#include <metal_stdlib>
using namespace metal;

// MARK: - Shape Vertex Data

struct ShapeVertexIn {
    float2 position [[attribute(0)]];
};

struct ShapeVertexOut {
    float4 position [[position]];
    float2 localPosition;
};

// MARK: - Shape Uniforms

struct ShapeUniforms {
    float4x4 transform;
    float4 fillColor;
    float4 strokeColor;
    float strokeWidth;
    float2 shapeSize;
    float time;
};

struct GradientUniforms {
    float4x4 transform;
    float4 colors[8];       // Up to 8 color stops
    float locations[8];     // Color stop locations
    int colorCount;
    int gradientType;       // 0: linear, 1: radial, 2: angular
    float2 startPoint;
    float2 endPoint;
};

// MARK: - Vertex Shaders

vertex ShapeVertexOut shapeVertex(ShapeVertexIn in [[stage_in]],
                                  constant ShapeUniforms& uniforms [[buffer(1)]]) {
    ShapeVertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.transform * pos;
    out.localPosition = in.position;
    return out;
}

// MARK: - Fragment Shaders

// Solid color fill
fragment float4 shapeSolidFill(ShapeVertexOut in [[stage_in]],
                               constant ShapeUniforms& uniforms [[buffer(0)]]) {
    return uniforms.fillColor;
}

// Linear gradient fill
fragment float4 shapeLinearGradient(ShapeVertexOut in [[stage_in]],
                                    constant GradientUniforms& uniforms [[buffer(0)]],
                                    constant float2& shapeSize [[buffer(1)]]) {
    // Calculate gradient position
    float2 normalizedPos = (in.localPosition + shapeSize * 0.5) / shapeSize;
    
    // Project position onto gradient line
    float2 gradientVector = uniforms.endPoint - uniforms.startPoint;
    float2 posVector = normalizedPos - uniforms.startPoint;
    float t = dot(posVector, gradientVector) / dot(gradientVector, gradientVector);
    t = saturate(t);
    
    // Find color stops
    float4 color = uniforms.colors[0];
    for (int i = 1; i < uniforms.colorCount; i++) {
        float prevLoc = uniforms.locations[i - 1];
        float currLoc = uniforms.locations[i];
        
        if (t >= prevLoc && t <= currLoc) {
            float localT = (t - prevLoc) / (currLoc - prevLoc);
            color = mix(uniforms.colors[i - 1], uniforms.colors[i], localT);
            break;
        }
    }
    
    return color;
}

// Radial gradient fill
fragment float4 shapeRadialGradient(ShapeVertexOut in [[stage_in]],
                                    constant GradientUniforms& uniforms [[buffer(0)]],
                                    constant float2& shapeSize [[buffer(1)]]) {
    // Calculate gradient position
    float2 normalizedPos = (in.localPosition + shapeSize * 0.5) / shapeSize;
    
    // Distance from center
    float2 center = uniforms.startPoint;
    float radius = length(uniforms.endPoint - uniforms.startPoint);
    float t = length(normalizedPos - center) / radius;
    t = saturate(t);
    
    // Find color stops
    float4 color = uniforms.colors[0];
    for (int i = 1; i < uniforms.colorCount; i++) {
        float prevLoc = uniforms.locations[i - 1];
        float currLoc = uniforms.locations[i];
        
        if (t >= prevLoc && t <= currLoc) {
            float localT = (t - prevLoc) / (currLoc - prevLoc);
            color = mix(uniforms.colors[i - 1], uniforms.colors[i], localT);
            break;
        }
    }
    
    return color;
}

// Stroke rendering (for line shapes)
fragment float4 shapeStroke(ShapeVertexOut in [[stage_in]],
                            constant ShapeUniforms& uniforms [[buffer(0)]]) {
    return uniforms.strokeColor;
}