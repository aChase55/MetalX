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

// MARK: - Pixellate Effect

kernel void pixellateEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float2 &params [[buffer(0)]],  // pixelSize, textureWidth
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float pixelSize = params.x;
    float textureWidth = params.y;
    
    // Calculate pixelated coordinates
    float2 coord = float2(gid);
    float2 pixelatedCoord = floor(coord / pixelSize) * pixelSize;
    uint2 sampleCoord = uint2(pixelatedCoord);
    
    // Clamp to texture bounds
    sampleCoord.x = min(sampleCoord.x, uint(inTexture.get_width() - 1));
    sampleCoord.y = min(sampleCoord.y, uint(inTexture.get_height() - 1));
    
    float4 color = inTexture.read(sampleCoord);
    outTexture.write(color, gid);
}

// MARK: - Noise Effect

float random(float2 co, float seed) {
    return fract(sin(dot(co.xy + seed, float2(12.9898, 78.233))) * 43758.5453);
}

kernel void noiseEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float3 &params [[buffer(0)]],  // amount, seed, time
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 color = inTexture.read(gid);
    
    float amount = params.x;
    float seed = params.y;
    float time = params.z;
    
    // Generate noise
    float2 coord = float2(gid) + time;
    float noise = random(coord, seed) * 2.0 - 1.0;
    
    // Apply noise
    color.rgb += noise * amount;
    color.rgb = clamp(color.rgb, 0.0, 1.0);
    
    outTexture.write(color, gid);
}

// MARK: - Threshold Effect

kernel void thresholdEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float3 &params [[buffer(0)]],  // threshold, smoothness, intensity
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 originalColor = inTexture.read(gid);
    float4 color = originalColor;
    
    float threshold = params.x;
    float smoothness = params.y;
    float intensity = params.z;
    
    // Calculate luminance
    float luminance = dot(color.rgb, float3(0.299, 0.587, 0.114));
    
    // Apply threshold with smoothstep for anti-aliasing
    float thresholdValue = smoothstep(threshold - smoothness, threshold + smoothness, luminance);
    
    // Create black/white result
    float3 thresholdColor = float3(thresholdValue);
    
    // Mix with original based on intensity
    color.rgb = mix(originalColor.rgb, thresholdColor, intensity);
    
    outTexture.write(color, gid);
}

// MARK: - Chromatic Aberration Effect

kernel void chromaticAberrationEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float4 &params [[buffer(0)]],  // redOffset, blueOffset, width, height
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float redOffset = params.x;
    float blueOffset = params.y;
    float width = params.z;
    float height = params.w;
    
    float2 coord = float2(gid);
    float2 center = float2(width * 0.5, height * 0.5);
    float2 direction = normalize(coord - center);
    
    // Sample red channel with offset
    float2 redCoord = coord + direction * redOffset;
    uint2 redSample = uint2(clamp(redCoord, float2(0), float2(width - 1, height - 1)));
    float red = inTexture.read(redSample).r;
    
    // Sample green channel (no offset)
    float green = inTexture.read(gid).g;
    
    // Sample blue channel with offset
    float2 blueCoord = coord + direction * blueOffset;
    uint2 blueSample = uint2(clamp(blueCoord, float2(0), float2(width - 1, height - 1)));
    float blue = inTexture.read(blueSample).b;
    
    float4 color = float4(red, green, blue, inTexture.read(gid).a);
    outTexture.write(color, gid);
}

// MARK: - VHS Effect

kernel void vhsEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float4 &params1 [[buffer(0)]],  // lineIntensity, noiseIntensity, colorBleed, distortion
    constant float4 &params2 [[buffer(1)]],  // width, height, time, unused
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float lineIntensity = params1.x;
    float noiseIntensity = params1.y;
    float colorBleed = params1.z;
    float distortion = params1.w;
    
    float width = params2.x;
    float height = params2.y;
    float time = params2.z;
    
    float2 coord = float2(gid);
    
    // Horizontal distortion based on scanlines
    float distortionAmount = sin(coord.y * 0.1 + time * 0.01) * distortion;
    coord.x += distortionAmount;
    
    // Clamp coordinates
    coord = clamp(coord, float2(0), float2(width - 1, height - 1));
    uint2 sampleCoord = uint2(coord);
    
    float4 color = inTexture.read(sampleCoord);
    
    // Add scanlines
    float scanline = sin(coord.y * 0.5) * 0.5 + 0.5;
    color.rgb *= 1.0 - (1.0 - scanline) * lineIntensity;
    
    // Add noise
    float noise = random(coord + time, time) * 2.0 - 1.0;
    color.rgb += noise * noiseIntensity;
    
    // Color bleeding effect
    if (gid.x > 0) {
        float4 leftColor = inTexture.read(uint2(gid.x - 1, gid.y));
        color.r = mix(color.r, leftColor.r, colorBleed * 0.3);
    }
    
    // Slight desaturation for VHS look
    float luminance = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, float3(luminance), 0.2);
    
    color.rgb = clamp(color.rgb, 0.0, 1.0);
    outTexture.write(color, gid);
}

// MARK: - Posterize Effect

kernel void posterizeEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float2 &params [[buffer(0)]],  // levels, intensity
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 originalColor = inTexture.read(gid);
    float4 color = originalColor;
    
    float levels = params.x;
    float intensity = params.y;
    
    // Posterize each channel
    color.rgb = floor(color.rgb * levels) / levels;
    
    // Mix with original based on intensity
    color.rgb = mix(originalColor.rgb, color.rgb, intensity);
    
    outTexture.write(color, gid);
}

// MARK: - Vignette Effect

kernel void vignetteEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float4 &params [[buffer(0)]],  // size, smoothness, darkness, unused
    constant float2 &dimensions [[buffer(1)]],  // width, height
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 color = inTexture.read(gid);
    
    float size = params.x;
    float smoothness = params.y;
    float darkness = params.z;
    
    float width = dimensions.x;
    float height = dimensions.y;
    
    // Calculate distance from center
    float2 coord = float2(gid);
    float2 center = float2(width * 0.5, height * 0.5);
    float2 relativeCoord = (coord - center) / min(width, height);
    float distance = length(relativeCoord);
    
    // Create vignette mask
    float vignette = smoothstep(size, size + smoothness, distance);
    vignette = 1.0 - vignette * darkness;
    
    color.rgb *= vignette;
    outTexture.write(color, gid);
}

// MARK: - Halftone Effect

kernel void halftoneEffect(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float4 &params [[buffer(0)]],  // dotSize, angle, sharpness, intensity
    constant float2 &dimensions [[buffer(1)]],  // width, height
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    float4 originalColor = inTexture.read(gid);
    float4 color = originalColor;
    
    float dotSize = params.x;
    float angle = params.y;
    float sharpness = params.z;
    float intensity = params.w;
    
    float width = dimensions.x;
    float height = dimensions.y;
    
    // Rotate coordinates
    float2 coord = float2(gid);
    float cosAngle = cos(angle);
    float sinAngle = sin(angle);
    float2 rotatedCoord = float2(
        coord.x * cosAngle - coord.y * sinAngle,
        coord.x * sinAngle + coord.y * cosAngle
    );
    
    // Create halftone pattern
    float2 grid = fmod(rotatedCoord, dotSize) / dotSize;
    float2 center = float2(0.5);
    float distanceFromCenter = length(grid - center);
    
    // Calculate luminance
    float luminance = dot(color.rgb, float3(0.299, 0.587, 0.114));
    
    // Create dot based on luminance
    float dotRadius = sqrt(1.0 - luminance) * 0.5;
    float dot = 1.0 - smoothstep(dotRadius - 0.1 * sharpness, dotRadius + 0.1 * sharpness, distanceFromCenter);
    
    // Apply halftone effect
    float3 halftoneColor = float3(dot);
    color.rgb = mix(originalColor.rgb, halftoneColor, intensity);
    
    outTexture.write(color, gid);
}