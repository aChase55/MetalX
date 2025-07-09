#include <metal_stdlib>
using namespace metal;

// MARK: - Common Structures

struct Vertex2D {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct Vertex3D {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    float3 tangent [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float3 normal;
    float3 worldPosition;
    float3 tangent;
    float3 bitangent;
};

struct InstanceData {
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 color;
    float4 uvTransform; // xy = scale, zw = offset
};

// MARK: - Uniform Structures

struct VertexUniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 normalMatrix;
    float3 cameraPosition;
    float time;
};

struct FragmentUniforms {
    float4 color;
    float4 lightDirection;
    float4 lightColor;
    float2 resolution;
    float time;
    float opacity;
};

struct MaterialUniforms {
    float4 albedo;
    float4 emission;
    float metallic;
    float roughness;
    float normalScale;
    float occlusionStrength;
    float4 uvTransform;
};

// MARK: - Common Constants

constant float PI = 3.14159265359;
constant float TWO_PI = 6.28318530718;
constant float HALF_PI = 1.57079632679;
constant float INV_PI = 0.31830988618;

// MARK: - Utility Functions

static float3 sRGBToLinear(float3 srgb) {
    return select(
        pow((srgb + 0.055) / 1.055, 2.4),
        srgb / 12.92,
        srgb <= 0.04045
    );
}

static float3 linearToSRGB(float3 linear) {
    return select(
        1.055 * pow(linear, 1.0 / 2.4) - 0.055,
        linear * 12.92,
        linear <= 0.0031308
    );
}

static float luminance(float3 color) {
    return dot(color, float3(0.299, 0.587, 0.114));
}

static float3 rgb2hsv(float3 rgb) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(rgb.bg, K.wz), float4(rgb.gb, K.xy), step(rgb.b, rgb.g));
    float4 q = mix(float4(p.xyw, rgb.r), float4(rgb.r, p.yzx), step(p.x, rgb.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

static float3 hsv2rgb(float3 hsv) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(hsv.xxx + K.xyz) * 6.0 - K.www);
    return hsv.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), hsv.y);
}

static float2 transformUV(float2 uv, float4 transform) {
    return uv * transform.xy + transform.zw;
}

static float3 calculateNormal(float3 normal, float3 tangent, float3 bitangent, float3 normalMap) {
    float3 n = normalize(normal);
    float3 t = normalize(tangent);
    float3 b = normalize(bitangent);
    
    float3x3 tbn = float3x3(t, b, n);
    return normalize(tbn * (normalMap * 2.0 - 1.0));
}

static float4 applyColorMatrix(float4 color, float4x4 colorMatrix) {
    return colorMatrix * color;
}

// MARK: - Sampling Functions

static float4 sampleTextureBilinear(texture2d<float> tex, sampler smp, float2 uv) {
    return tex.sample(smp, uv);
}

static float4 cubic(float v) {
    float4 n = float4(1.0, 2.0, 3.0, 4.0) - v;
    float4 s = n * n * n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return float4(x, y, z, w) * (1.0/6.0);
}

static float4 sampleTextureBicubic(texture2d<float> tex, sampler smp, float2 uv) {
    float2 texSize = float2(tex.get_width(), tex.get_height());
    float2 invTexSize = 1.0 / texSize;
    
    uv = uv * texSize - 0.5;
    
    float2 fxy = fract(uv);
    uv -= fxy;
    
    float4 xcubic = cubic(fxy.x);
    float4 ycubic = cubic(fxy.y);
    
    float4 c = uv.xxyy + float2(-0.5, +1.5).xyxy;
    
    float4 s = float4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
    float4 offset = c + float4(xcubic.yw, ycubic.yw) / s;
    
    offset *= invTexSize.xxyy;
    
    float4 sample0 = tex.sample(smp, offset.xz);
    float4 sample1 = tex.sample(smp, offset.yz);
    float4 sample2 = tex.sample(smp, offset.xw);
    float4 sample3 = tex.sample(smp, offset.yw);
    
    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);
    
    return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

// MARK: - Blend Modes

static float4 blendNormal(float4 base, float4 overlay) {
    return overlay;
}

static float4 blendMultiply(float4 base, float4 overlay) {
    return base * overlay;
}

static float4 blendScreen(float4 base, float4 overlay) {
    return 1.0 - (1.0 - base) * (1.0 - overlay);
}

static float4 blendOverlay(float4 base, float4 overlay) {
    float4 result;
    result.rgb = select(
        2.0 * base.rgb * overlay.rgb,
        1.0 - 2.0 * (1.0 - base.rgb) * (1.0 - overlay.rgb),
        base.rgb > 0.5
    );
    result.a = overlay.a;
    return result;
}

static float4 blendSoftLight(float4 base, float4 overlay) {
    float4 result;
    result.rgb = select(
        2.0 * base.rgb * overlay.rgb + base.rgb * base.rgb * (1.0 - 2.0 * overlay.rgb),
        sqrt(base.rgb) * (2.0 * overlay.rgb - 1.0) + 2.0 * base.rgb * (1.0 - overlay.rgb),
        overlay.rgb > 0.5
    );
    result.a = overlay.a;
    return result;
}

static float4 blendHardLight(float4 base, float4 overlay) {
    float4 result;
    result.rgb = select(
        2.0 * base.rgb * overlay.rgb,
        1.0 - 2.0 * (1.0 - base.rgb) * (1.0 - overlay.rgb),
        overlay.rgb > 0.5
    );
    result.a = overlay.a;
    return result;
}

static float4 blendColorDodge(float4 base, float4 overlay) {
    float4 result;
    result.rgb = select(
        base.rgb / (1.0 - overlay.rgb),
        float3(1.0),
        overlay.rgb >= 1.0
    );
    result.a = overlay.a;
    return result;
}

static float4 blendColorBurn(float4 base, float4 overlay) {
    float4 result;
    result.rgb = select(
        1.0 - (1.0 - base.rgb) / overlay.rgb,
        float3(0.0),
        overlay.rgb <= 0.0
    );
    result.a = overlay.a;
    return result;
}

static float4 blendDarken(float4 base, float4 overlay) {
    return float4(min(base.rgb, overlay.rgb), overlay.a);
}

static float4 blendLighten(float4 base, float4 overlay) {
    return float4(max(base.rgb, overlay.rgb), overlay.a);
}

static float4 blendDifference(float4 base, float4 overlay) {
    return float4(abs(base.rgb - overlay.rgb), overlay.a);
}

static float4 blendExclusion(float4 base, float4 overlay) {
    return float4(base.rgb + overlay.rgb - 2.0 * base.rgb * overlay.rgb, overlay.a);
}

// MARK: - Noise Functions

static float random(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

static float noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    
    float a = random(i);
    float b = random(i + float2(1.0, 0.0));
    float c = random(i + float2(0.0, 1.0));
    float d = random(i + float2(1.0, 1.0));
    
    float2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

static float fbm(float2 st, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(st);
        st *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// MARK: - Distance Functions (for SDF)

static float sdCircle(float2 p, float r) {
    return length(p) - r;
}

static float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

static float sdRoundedBox(float2 p, float2 b, float r) {
    float2 d = abs(p) - b + r;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// MARK: - Filter Functions

static float4 gaussianBlur(texture2d<float> tex, sampler smp, float2 uv, float2 direction, float sigma) {
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    
    int kernelSize = int(ceil(3.0 * sigma));
    
    for (int i = -kernelSize; i <= kernelSize; i++) {
        float weight = exp(-0.5 * pow(float(i) / sigma, 2.0));
        float2 offset = direction * float(i) / float2(tex.get_width(), tex.get_height());
        
        result += tex.sample(smp, uv + offset) * weight;
        totalWeight += weight;
    }
    
    return result / totalWeight;
}

// MARK: - Basic Vertex Shaders
// NOTE: These are moved to BasicRendering.metal to avoid duplicates