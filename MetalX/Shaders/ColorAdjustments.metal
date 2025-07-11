#include <metal_stdlib>
using namespace metal;

// MARK: - Brightness/Contrast Shader

kernel void brightnessContrast(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &brightness [[buffer(0)]],
    constant float &contrast [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 color = inTexture.read(gid);
    
    // Apply brightness (-1 to 1)
    color.rgb += brightness;
    
    // Apply contrast (0 to 2, where 1 is normal)
    color.rgb = ((color.rgb - 0.5) * contrast) + 0.5;
    
    // Clamp values
    color.rgb = clamp(color.rgb, 0.0, 1.0);
    
    outTexture.write(color, gid);
}

// MARK: - HSB (Hue/Saturation/Brightness) Shader

float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

kernel void hueSaturationBrightness(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &hueShift [[buffer(0)]],      // -180 to 180 degrees
    constant float &saturation [[buffer(1)]],    // 0 to 2, where 1 is normal
    constant float &brightness [[buffer(2)]],    // -1 to 1
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 color = inTexture.read(gid);
    
    // Convert to HSV
    float3 hsv = rgb2hsv(color.rgb);
    
    // Apply hue shift (convert degrees to 0-1 range)
    hsv.x += hueShift / 360.0;
    hsv.x = fract(hsv.x); // Wrap around
    
    // Apply saturation
    hsv.y *= saturation;
    hsv.y = clamp(hsv.y, 0.0, 1.0);
    
    // Apply brightness (value)
    hsv.z += brightness;
    hsv.z = clamp(hsv.z, 0.0, 1.0);
    
    // Convert back to RGB
    color.rgb = hsv2rgb(hsv);
    
    outTexture.write(color, gid);
}

// MARK: - Combined Color Adjustment Shader

kernel void colorAdjustment(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &brightness [[buffer(0)]],
    constant float &contrast [[buffer(1)]],
    constant float &hueShift [[buffer(2)]],
    constant float &saturation [[buffer(3)]],
    constant float &intensity [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 originalColor = inTexture.read(gid);
    float4 color = originalColor;
    
    // Apply brightness and contrast
    color.rgb += brightness;
    color.rgb = ((color.rgb - 0.5) * contrast) + 0.5;
    
    // Convert to HSV for hue/saturation adjustments
    float3 hsv = rgb2hsv(color.rgb);
    
    // Apply hue shift
    hsv.x += hueShift / 360.0;
    hsv.x = fract(hsv.x);
    
    // Apply saturation
    hsv.y *= saturation;
    hsv.y = clamp(hsv.y, 0.0, 1.0);
    
    // Convert back to RGB
    color.rgb = hsv2rgb(hsv);
    color.rgb = clamp(color.rgb, 0.0, 1.0);
    
    // Mix with original based on intensity
    color.rgb = mix(originalColor.rgb, color.rgb, intensity);
    
    outTexture.write(color, gid);
}