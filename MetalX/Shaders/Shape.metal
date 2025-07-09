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
    float4 color0;
    float4 color1;
    float4 color2;
    float4 color3;
    float4 color4;
    float4 color5;
    float4 color6;
    float4 color7;
    float location0;
    float location1;
    float location2;
    float location3;
    float location4;
    float location5;
    float location6;
    float location7;
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
    float4 colors[8] = {uniforms.color0, uniforms.color1, uniforms.color2, uniforms.color3,
                        uniforms.color4, uniforms.color5, uniforms.color6, uniforms.color7};
    float locations[8] = {uniforms.location0, uniforms.location1, uniforms.location2, uniforms.location3,
                          uniforms.location4, uniforms.location5, uniforms.location6, uniforms.location7};
    
    // Handle edge cases
    if (uniforms.colorCount <= 1) {
        return colors[0];
    }
    
    // Find the appropriate color segment
    float4 color = colors[0];
    
    // Handle t before first stop
    if (t <= locations[0]) {
        return colors[0];
    }
    
    // Handle t after last stop
    if (t >= locations[uniforms.colorCount - 1]) {
        return colors[uniforms.colorCount - 1];
    }
    
    // Find the segment
    for (int i = 1; i < uniforms.colorCount; i++) {
        float prevLoc = locations[i - 1];
        float currLoc = locations[i];
        
        if (t >= prevLoc && t <= currLoc) {
            float localT = (currLoc - prevLoc) > 0.0 ? (t - prevLoc) / (currLoc - prevLoc) : 0.0;
            color = mix(colors[i - 1], colors[i], localT);
            break;
        }
    }
    
    return color;
}

// Radial gradient fill
fragment float4 shapeRadialGradient(ShapeVertexOut in [[stage_in]],
                                    constant GradientUniforms& uniforms [[buffer(0)]],
                                    constant float2& shapeSize [[buffer(1)]]) {
    // Calculate gradient position - normalize to 0-1 coordinate space
    float2 normalizedPos = (in.localPosition + shapeSize * 0.5) / shapeSize;
    
    // Distance from center
    float2 center = uniforms.startPoint;
    float radius = length(uniforms.endPoint - uniforms.startPoint);
    
    // Ensure we have a valid radius
    if (radius <= 0.0) {
        radius = 0.5; // Default radius
    }
    
    float t = length(normalizedPos - center) / radius;
    t = saturate(t);
    
    // Find color stops
    float4 colors[8] = {uniforms.color0, uniforms.color1, uniforms.color2, uniforms.color3,
                        uniforms.color4, uniforms.color5, uniforms.color6, uniforms.color7};
    float locations[8] = {uniforms.location0, uniforms.location1, uniforms.location2, uniforms.location3,
                          uniforms.location4, uniforms.location5, uniforms.location6, uniforms.location7};
    
    // Handle edge cases
    if (uniforms.colorCount <= 1) {
        return colors[0];
    }
    
    // Find the appropriate color segment
    float4 color = colors[0];
    
    // Handle t before first stop
    if (t <= locations[0]) {
        return colors[0];
    }
    
    // Handle t after last stop
    if (t >= locations[uniforms.colorCount - 1]) {
        return colors[uniforms.colorCount - 1];
    }
    
    // Find the segment
    for (int i = 1; i < uniforms.colorCount; i++) {
        float prevLoc = locations[i - 1];
        float currLoc = locations[i];
        
        if (t >= prevLoc && t <= currLoc) {
            float localT = (currLoc - prevLoc) > 0.0 ? (t - prevLoc) / (currLoc - prevLoc) : 0.0;
            color = mix(colors[i - 1], colors[i], localT);
            break;
        }
    }
    
    return color;
}

// Angular gradient fill
fragment float4 shapeAngularGradient(ShapeVertexOut in [[stage_in]],
                                      constant GradientUniforms& uniforms [[buffer(0)]],
                                      constant float2& shapeSize [[buffer(1)]]) {
    // Calculate gradient position
    float2 normalizedPos = (in.localPosition + shapeSize * 0.5) / shapeSize;
    
    // Calculate angle from center
    float2 center = uniforms.startPoint;
    float2 delta = normalizedPos - center;
    float angle = atan2(delta.y, delta.x);
    
    // Normalize angle to 0-1 range
    float t = (angle + M_PI_F) / (2.0 * M_PI_F);
    
    // Find color stops
    float4 colors[8] = {uniforms.color0, uniforms.color1, uniforms.color2, uniforms.color3,
                        uniforms.color4, uniforms.color5, uniforms.color6, uniforms.color7};
    float locations[8] = {uniforms.location0, uniforms.location1, uniforms.location2, uniforms.location3,
                          uniforms.location4, uniforms.location5, uniforms.location6, uniforms.location7};
    
    // Handle edge cases
    if (uniforms.colorCount <= 1) {
        return colors[0];
    }
    
    // Find the appropriate color segment
    float4 color = colors[0];
    
    // Handle t before first stop
    if (t <= locations[0]) {
        return colors[0];
    }
    
    // Handle t after last stop
    if (t >= locations[uniforms.colorCount - 1]) {
        return colors[uniforms.colorCount - 1];
    }
    
    // Find the segment
    for (int i = 1; i < uniforms.colorCount; i++) {
        float prevLoc = locations[i - 1];
        float currLoc = locations[i];
        
        if (t >= prevLoc && t <= currLoc) {
            float localT = (currLoc - prevLoc) > 0.0 ? (t - prevLoc) / (currLoc - prevLoc) : 0.0;
            color = mix(colors[i - 1], colors[i], localT);
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