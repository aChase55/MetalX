//
//  MetalX-Bridging-Header.h
//  MetalX Metal/Swift Interoperability Header
//

#ifndef MetalX_Bridging_Header_h
#define MetalX_Bridging_Header_h

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

// MARK: - Metal Common Structures

typedef struct {
    simd_float2 position;
    simd_float2 texCoord;
} Vertex2D;

typedef struct {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 texCoord;
} Vertex3D;

typedef struct {
    simd_float4x4 modelViewProjectionMatrix;
    simd_float4x4 modelMatrix;
    simd_float4x4 normalMatrix;
} VertexUniforms;

typedef struct {
    simd_float4 color;
    float time;
    simd_float2 resolution;
    float _padding;
} FragmentUniforms;

// MARK: - Render Pipeline Constants

typedef enum {
    VertexInputIndexVertices = 0,
    VertexInputIndexUniforms = 1,
    VertexInputIndexInstanceData = 2,
} VertexInputIndex;

typedef enum {
    FragmentInputIndexUniforms = 0,
    FragmentInputIndexTexture = 1,
    FragmentInputIndexSampler = 2,
    FragmentInputIndexLUT = 3,
} FragmentInputIndex;

typedef enum {
    TextureIndexColor = 0,
    TextureIndexNormal = 1,
    TextureIndexDepth = 2,
    TextureIndexMask = 3,
    TextureIndexLUT = 4,
} TextureIndex;

typedef enum {
    SamplerIndexLinear = 0,
    SamplerIndexNearest = 1,
    SamplerIndexMipmapped = 2,
} SamplerIndex;

// MARK: - Effect Parameters

typedef struct {
    float brightness;
    float contrast;
    float saturation;
    float hue;
} ColorAdjustmentParams;

typedef struct {
    simd_float2 center;
    float radius;
    float strength;
    simd_float2 offset;
    float feather;
    float _padding;
} BlurParams;

typedef struct {
    simd_float4x4 transform;
    simd_float4 tint;
    float opacity;
    float blendMode;
    simd_float2 _padding;
} LayerParams;

// MARK: - Compute Shader Constants

#define MAX_PARTICLES 10000
#define THREADGROUP_SIZE 32
#define MAX_BLUR_RADIUS 64
#define MAX_CONVOLUTION_SIZE 15

typedef struct {
    simd_float2 position;
    simd_float2 velocity;
    simd_float4 color;
    float life;
    float size;
    simd_float2 _padding;
} Particle;

typedef struct {
    float deltaTime;
    simd_float2 gravity;
    float damping;
    simd_float4 bounds;
} ParticleUniforms;

// MARK: - Image Processing

typedef struct {
    float kernel[MAX_CONVOLUTION_SIZE * MAX_CONVOLUTION_SIZE];
    int kernelSize;
    float divisor;
    float bias;
    int _padding;
} ConvolutionParams;

typedef struct {
    simd_float3x3 colorMatrix;
    simd_float3 colorOffset;
} ColorMatrixParams;

// MARK: - 3D Text Rendering

typedef struct {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 texCoord;
    simd_float3 tangent;
    float depth;
} TextVertex;

typedef struct {
    simd_float4x4 modelViewProjectionMatrix;
    simd_float4x4 modelMatrix;
    simd_float4x4 normalMatrix;
    simd_float3 lightPosition;
    float extrusion;
    simd_float4 frontColor;
    simd_float4 sideColor;
    simd_float4 bevelColor;
} TextUniforms;

// MARK: - Utility Functions

static inline simd_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ) {
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    return (simd_float4x4) {{
        { xs,  0,  0,         0 },
        { 0,   ys, 0,         0 },
        { 0,   0,  zs,       -1 },
        { 0,   0,  zs * nearZ, 0 }
    }};
}

static inline simd_float4x4 matrix_look_at_right_hand(simd_float3 eye, simd_float3 target, simd_float3 up) {
    simd_float3 zAxis = simd_normalize(eye - target);
    simd_float3 xAxis = simd_normalize(simd_cross(up, zAxis));
    simd_float3 yAxis = simd_cross(zAxis, xAxis);
    
    return (simd_float4x4) {{
        { xAxis.x, yAxis.x, zAxis.x, 0 },
        { xAxis.y, yAxis.y, zAxis.y, 0 },
        { xAxis.z, yAxis.z, zAxis.z, 0 },
        { -simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye), 1 }
    }};
}

static inline simd_float3 rgb_to_hsv(simd_float3 rgb) {
    float r = rgb.x, g = rgb.y, b = rgb.z;
    float maxVal = fmaxf(r, fmaxf(g, b));
    float minVal = fminf(r, fminf(g, b));
    float diff = maxVal - minVal;
    
    float h = 0, s = (maxVal == 0) ? 0 : diff / maxVal, v = maxVal;
    
    if (diff != 0) {
        if (maxVal == r) {
            h = (g - b) / diff + (g < b ? 6 : 0);
        } else if (maxVal == g) {
            h = (b - r) / diff + 2;
        } else {
            h = (r - g) / diff + 4;
        }
        h /= 6;
    }
    
    return (simd_float3){ h, s, v };
}

static inline simd_float3 hsv_to_rgb(simd_float3 hsv) {
    float h = hsv.x * 6;
    float s = hsv.y;
    float v = hsv.z;
    
    float c = v * s;
    float x = c * (1 - fabsf(fmodf(h, 2) - 1));
    float m = v - c;
    
    simd_float3 rgb;
    if (h < 1) {
        rgb = (simd_float3){ c, x, 0 };
    } else if (h < 2) {
        rgb = (simd_float3){ x, c, 0 };
    } else if (h < 3) {
        rgb = (simd_float3){ 0, c, x };
    } else if (h < 4) {
        rgb = (simd_float3){ 0, x, c };
    } else if (h < 5) {
        rgb = (simd_float3){ x, 0, c };
    } else {
        rgb = (simd_float3){ c, 0, x };
    }
    
    return rgb + m;
}

#endif /* MetalX_Bridging_Header_h */