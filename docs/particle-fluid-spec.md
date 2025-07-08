# Particle and Fluid Simulation Specification

## Overview
GPU-accelerated particle systems and fluid simulations for creating realistic effects like smoke, fire, water, and magical particles, inspired by Riveo's motion effects.

## Particle System Architecture

### 1. Core Particle Engine

```swift
class ParticleEngine {
    // Particle data structure (GPU-friendly)
    struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var life: Float
        var age: Float
        var size: Float
        var rotation: Float
        var color: SIMD4<Float>
        var textureIndex: Int
    }
    
    // Emitter configuration
    struct EmitterConfig {
        // Emission
        var emissionRate: Float
        var emissionShape: EmissionShape
        var burstCount: Int
        var burstInterval: Float
        
        // Particle properties
        var lifetime: Range<Float>
        var startSize: Range<Float>
        var startSpeed: Range<Float>
        var startRotation: Range<Float>
        var startColor: ColorRange
        
        // Physics
        var gravity: SIMD3<Float>
        var airResistance: Float
        var turbulence: TurbulenceSettings
        var attractors: [Attractor]
        
        // Visual
        var texture: MTLTexture
        var blendMode: BlendMode
        var softParticles: Bool
        var distortion: Float
    }
}
```

### 2. GPU Particle Simulation

```metal
// Particle update compute shader
kernel void updateParticles(device Particle* particles [[buffer(0)]],
                           constant SimulationParams& params [[buffer(1)]],
                           texture3d<float> noiseTexture [[texture(0)]],
                           uint id [[thread_position_in_grid]]) {
    Particle p = particles[id];
    
    // Age particle
    p.age += params.deltaTime;
    if (p.age > p.life) {
        // Respawn particle
        p = respawnParticle(params);
    }
    
    // Apply forces
    float3 acceleration = params.gravity;
    
    // Turbulence from 3D noise
    float3 noiseCoord = p.position * params.noiseScale + params.noiseOffset;
    float3 turbulence = noiseTexture.sample(sampler, noiseCoord).xyz;
    acceleration += turbulence * params.turbulenceStrength;
    
    // Attractors/repulsors
    for (int i = 0; i < params.attractorCount; i++) {
        float3 toAttractor = params.attractors[i].position - p.position;
        float distance = length(toAttractor);
        float strength = params.attractors[i].strength / (distance * distance);
        acceleration += normalize(toAttractor) * strength;
    }
    
    // Air resistance
    acceleration -= p.velocity * params.airResistance;
    
    // Update physics
    p.velocity += acceleration * params.deltaTime;
    p.position += p.velocity * params.deltaTime;
    
    // Update visual properties
    float lifeFactor = p.age / p.life;
    p.size = mix(params.startSize, params.endSize, lifeFactor);
    p.color = mix(params.startColor, params.endColor, lifeFactor);
    p.rotation += params.rotationSpeed * params.deltaTime;
    
    particles[id] = p;
}
```

### 3. Advanced Particle Effects

```swift
// Specialized particle systems
class SpecializedParticles {
    // Fire system
    class FireParticles: ParticleSystem {
        override func configure() {
            emitter.emissionShape = .cone(angle: 30, radius: 10)
            emitter.startSpeed = 50...100
            emitter.startColor = ColorRange(
                start: UIColor(red: 1, green: 0.8, blue: 0),
                end: UIColor(red: 1, green: 0.2, blue: 0)
            )
            emitter.gravity = SIMD3(0, 200, 0) // Fire rises
            emitter.turbulence = TurbulenceSettings(
                strength: 30,
                frequency: 2,
                octaves: 3
            )
        }
    }
    
    // Smoke system
    class SmokeParticles: ParticleSystem {
        var smokeColor: UIColor = .gray
        var dissipationRate: Float = 0.5
        
        override func updateShader() -> String {
            // Custom shader for volumetric smoke
            return """
            float4 smokeColor = sampleSmoke(particle, noiseTexture);
            smokeColor.a *= smoothstep(0.8, 1.0, particle.life);
            return smokeColor;
            """
        }
    }
    
    // Magic particles (butterflies, sparkles, etc.)
    class MagicParticles: ParticleSystem {
        var behavior: MagicBehavior
        
        enum MagicBehavior {
            case butterflies(flutterSpeed: Float)
            case fireflies(glowIntensity: Float)
            case sparkles(twinkleRate: Float)
            case fairyDust(trailLength: Float)
            case energyOrbs(pulseRate: Float)
        }
        
        override func customBehavior(particle: inout Particle, time: Float) {
            switch behavior {
            case .butterflies(let flutter):
                // Figure-8 flight pattern
                particle.velocity.x += sin(time * flutter) * 10
                particle.velocity.y += cos(time * flutter * 2) * 5
                
            case .fireflies(let glow):
                // Pulsing glow
                particle.color.w = abs(sin(time * glow))
                
            case .sparkles(let twinkle):
                // Random twinkle
                let twinklePhase = fract(time * twinkle + particle.seed)
                particle.size *= smoothstep(0.4, 0.5, twinklePhase) *
                               smoothstep(0.6, 0.5, twinklePhase)
            }
        }
    }
}
```

### 4. Fluid Simulation System

```swift
class FluidSimulation {
    // SPH (Smoothed Particle Hydrodynamics) implementation
    struct FluidParticle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var density: Float
        var pressure: Float
        var viscosity: Float
    }
    
    struct FluidConfig {
        var particleRadius: Float = 0.5
        var restDensity: Float = 1000.0
        var gasConstant: Float = 2000.0
        var viscosity: Float = 0.01
        var surfaceTension: Float = 0.0728
        var gravity: SIMD3<Float> = SIMD3(0, -9.8, 0)
    }
    
    // Neighbor finding acceleration structure
    class SpatialHashGrid {
        private var grid: [Int: [Int]] = [:]
        private let cellSize: Float
        
        func findNeighbors(particle: Int, 
                          radius: Float) -> [Int] {
            // Efficient spatial hashing for neighbor queries
        }
    }
}

// GPU Fluid simulation kernel
kernel void computeFluidDensity(device FluidParticle* particles [[buffer(0)]],
                               device float* densities [[buffer(1)]],
                               constant FluidParams& params [[buffer(2)]],
                               uint id [[thread_position_in_grid]]) {
    float3 pos = particles[id].position;
    float density = 0;
    
    // Sum density from neighbors
    for (uint i = 0; i < params.particleCount; i++) {
        float3 diff = pos - particles[i].position;
        float dist2 = dot(diff, diff);
        
        if (dist2 < params.smoothingRadius2) {
            // Poly6 kernel
            float w = params.poly6 * pow(params.smoothingRadius2 - dist2, 3);
            density += params.particleMass * w;
        }
    }
    
    densities[id] = density;
}
```

### 5. Interactive Fluid Effects

```swift
class InteractiveFluidEffects {
    // Liquid metal effect
    class LiquidMetal: FluidSimulation {
        override func configure() {
            config.viscosity = 0.5
            config.surfaceTension = 0.436 // Mercury-like
            
            // Metallic rendering
            renderConfig.metallic = 1.0
            renderConfig.roughness = 0.1
            renderConfig.reflectivity = 0.95
        }
    }
    
    // Water simulation
    class WaterSimulation: FluidSimulation {
        var waveHeight: Float = 1.0
        var waveFrequency: Float = 2.0
        var foamThreshold: Float = 0.5
        
        func addRipple(at point: CGPoint, strength: Float) {
            // Propagate ripple through fluid
        }
        
        func addSplash(at point: CGPoint, velocity: SIMD3<Float>) {
            // Create splash particles
        }
    }
    
    // Viscous fluids (honey, oil, etc.)
    class ViscousFluid: FluidSimulation {
        var stretchiness: Float = 0.8
        var stickiness: Float = 0.6
        
        override func renderPass() -> MTLTexture {
            // Special rendering for stringy, viscous behavior
        }
    }
}
```

### 6. Particle Collision System

```swift
class ParticleCollisionSystem {
    // Collision shapes
    enum CollisionShape {
        case plane(normal: SIMD3<Float>, distance: Float)
        case sphere(center: SIMD3<Float>, radius: Float)
        case box(min: SIMD3<Float>, max: SIMD3<Float>)
        case mesh(vertices: [SIMD3<Float>], triangles: [Int])
        case heightField(texture: MTLTexture, scale: Float)
    }
    
    struct CollisionResponse {
        var bounce: Float = 0.5
        var friction: Float = 0.3
        var absorption: Float = 0.0
        var callback: ((Particle, CollisionInfo) -> Void)?
    }
    
    // GPU collision detection
    func detectCollisions(particles: MTLBuffer,
                         shapes: [CollisionShape]) -> MTLBuffer
}
```

### 7. Particle Rendering

```swift
class ParticleRenderer {
    // Rendering modes
    enum RenderMode {
        case billboard          // Always face camera
        case velocityAligned    // Stretch along velocity
        case mesh              // 3D mesh particles
        case ribbon            // Connected trail
        case volumetric        // Volume rendering
    }
    
    // Advanced rendering features
    struct RenderConfig {
        var softParticles: Bool = true
        var depthFade: Float = 1.0
        var distortion: Float = 0.0
        var motionBlur: Bool = true
        var heatDistortion: Bool = false
        var lightInteraction: Bool = true
    }
    
    // Particle lighting
    func illuminateParticles(particles: ParticleBuffer,
                           lights: [Light]) -> MTLTexture {
        // Per-particle lighting calculation
        // Support for emissive particles
        // Shadow casting/receiving
    }
}
```

### 8. Particle Animation Curves

```swift
class ParticleAnimationCurves {
    // Lifetime curves
    struct LifetimeCurves {
        var size: AnimationCurve
        var color: GradientCurve
        var opacity: AnimationCurve
        var rotation: AnimationCurve
        var velocity: AnimationCurve
    }
    
    // Curve evaluation on GPU
    func packCurvesForGPU(_ curves: LifetimeCurves) -> MTLTexture {
        // Pack curves into texture for GPU sampling
    }
}
```

### 9. Force Field System

```swift
class ForceFieldSystem {
    // Force field types
    enum ForceFieldType {
        case directional(direction: SIMD3<Float>)
        case radial(center: SIMD3<Float>, strength: Float)
        case vortex(axis: SIMD3<Float>, strength: Float)
        case turbulence(frequency: Float, octaves: Int)
        case noise(scale: Float, speed: Float)
        case custom(shader: String)
    }
    
    struct ForceField {
        var type: ForceFieldType
        var bounds: Bounds
        var falloff: FalloffType
        var strength: Float
        var enabled: Bool
    }
    
    // Combine multiple force fields
    func combineForceFields(_ fields: [ForceField]) -> ForceTexture3D
}
```

### 10. Performance Optimizations

```swift
class ParticleOptimizations {
    // LOD system for particles
    struct ParticleLOD {
        var distance: Float
        var particleRatio: Float    // Percentage to render
        var simplifyShader: Bool
        var disableCollisions: Bool
        var reducedTextureSize: Bool
    }
    
    // GPU sorting for transparency
    class GPUParticleSorter {
        func bitonicSort(particles: MTLBuffer,
                        camera: Camera) -> MTLBuffer
    }
    
    // Culling
    func frustumCull(particles: MTLBuffer,
                    frustum: Frustum) -> MTLBuffer
    
    // Instancing for similar particles
    func instancedRender(particleGroups: [ParticleGroup]) -> MTLTexture
}
```

## Integration Examples

```swift
// Fire and smoke combo
let fireSystem = FireParticles()
let smokeSystem = SmokeParticles()
smokeSystem.emitter.position = fireSystem.emitter.position + SIMD3(0, 20, 0)

// Interactive water
let water = WaterSimulation()
renderView.addGestureRecognizer(UITapGestureRecognizer { gesture in
    let point = gesture.location(in: renderView)
    water.addRipple(at: point, strength: 1.0)
})

// Magic butterfly effect
let butterflies = MagicParticles(behavior: .butterflies(flutterSpeed: 2.0))
butterflies.emitter.emissionShape = .sphere(radius: 50)
butterflies.followPath(splinePath)
```