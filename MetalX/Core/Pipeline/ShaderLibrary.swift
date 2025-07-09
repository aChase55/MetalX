import Metal
import Foundation
import os.log

public enum ShaderError: Error, LocalizedError {
    case libraryNotFound
    case functionNotFound(String)
    case compilationFailed(String, Error)
    case invalidSource
    case unsupportedFunction(String)
    
    public var errorDescription: String? {
        switch self {
        case .libraryNotFound:
            return "Metal shader library not found"
        case .functionNotFound(let name):
            return "Shader function not found: \(name)"
        case .compilationFailed(let name, let error):
            return "Shader compilation failed for \(name): \(error.localizedDescription)"
        case .invalidSource:
            return "Invalid shader source code"
        case .unsupportedFunction(let name):
            return "Shader function not supported on this device: \(name)"
        }
    }
}

public struct FunctionConstant {
    public let index: Int
    public let value: Any
    public let type: MTLDataType
    
    public init(index: Int, value: Any, type: MTLDataType) {
        self.index = index
        self.value = value
        self.type = type
    }
}

public struct ShaderFunctionDescriptor {
    public let name: String
    public let constants: [FunctionConstant]
    public let library: String?
    
    public init(name: String, constants: [FunctionConstant] = [], library: String? = nil) {
        self.name = name
        self.constants = constants
        self.library = library
    }
    
    public var cacheKey: String {
        var key = name
        if !constants.isEmpty {
            let constantsKey = constants.map { "\($0.index):\($0.value)" }.joined(separator: ",")
            key += "[\(constantsKey)]"
        }
        if let library = library {
            key += "@\(library)"
        }
        return key
    }
}

public class ShaderLibrary {
    private let device: MetalDevice
    private let logger = Logger(subsystem: "com.metalx.engine", category: "ShaderLibrary")
    
    private var libraries: [String: MTLLibrary] = [:]
    private var functions: [String: MTLFunction] = [:]
    private var compilationOptions: MTLCompileOptions
    
    private let accessQueue = DispatchQueue(label: "com.metalx.shader.library", attributes: .concurrent)
    
    public var defaultLibrary: MTLLibrary? {
        return libraries["default"]
    }
    
    public init(device: MetalDevice) {
        self.device = device
        self.compilationOptions = MTLCompileOptions()
        
        #if DEBUG
        compilationOptions.fastMathEnabled = false
        #else
        compilationOptions.fastMathEnabled = true
        #endif
        
        loadDefaultLibrary()
        loadBuiltinShaders()
    }
    
    public func loadLibrary(from url: URL, name: String) throws {
        let library = try device.device.makeLibrary(URL: url)
        
        accessQueue.async(flags: .barrier) {
            self.libraries[name] = library
        }
        
        logger.info("Loaded shader library: \(name)")
    }
    
    public func loadLibrary(source: String, name: String) async throws {
        let library = try await withCheckedThrowingContinuation { continuation in
            device.device.makeLibrary(source: source, options: compilationOptions) { library, error in
                if let library = library {
                    continuation.resume(returning: library)
                } else if let error = error {
                    continuation.resume(throwing: ShaderError.compilationFailed(name, error))
                } else {
                    continuation.resume(throwing: ShaderError.invalidSource)
                }
            }
        }
        
        accessQueue.async(flags: .barrier) {
            self.libraries[name] = library
        }
        
        logger.info("Compiled and loaded shader library: \(name)")
    }
    
    public func getFunction(_ descriptor: ShaderFunctionDescriptor) throws -> MTLFunction {
        let cacheKey = descriptor.cacheKey
        
        if let cachedFunction = accessQueue.sync(execute: { functions[cacheKey] }) {
            return cachedFunction
        }
        
        return try accessQueue.sync(flags: .barrier) {
            if let cachedFunction = functions[cacheKey] {
                return cachedFunction
            }
            
            let function = try createFunction(descriptor)
            functions[cacheKey] = function
            return function
        }
    }
    
    public func getFunction(name: String, library: String? = nil) throws -> MTLFunction {
        let descriptor = ShaderFunctionDescriptor(name: name, library: library)
        return try getFunction(descriptor)
    }
    
    public func preloadFunction(_ descriptor: ShaderFunctionDescriptor) {
        Task {
            do {
                _ = try getFunction(descriptor)
                logger.debug("Preloaded function: \(descriptor.name)")
            } catch {
                logger.error("Failed to preload function \(descriptor.name): \(error.localizedDescription)")
            }
        }
    }
    
    public func preloadCommonFunctions() {
        let commonFunctions = [
            "vertex_passthrough",
            "fragment_texture_sample",
            "fragment_color_fill",
            "compute_image_process",
            "vertex_transform",
            "fragment_blend"
        ]
        
        for functionName in commonFunctions {
            let descriptor = ShaderFunctionDescriptor(name: functionName)
            preloadFunction(descriptor)
        }
    }
    
    public func clearCache() {
        accessQueue.async(flags: .barrier) {
            self.functions.removeAll()
        }
        logger.info("Shader function cache cleared")
    }
    
    public func availableFunctions(in libraryName: String? = nil) -> [String] {
        return accessQueue.sync {
            let targetLibrary = libraryName ?? "default"
            guard let library = libraries[targetLibrary] else { return [] }
            return library.functionNames
        }
    }
    
    public func supportsFunction(_ name: String, in libraryName: String? = nil) -> Bool {
        return accessQueue.sync {
            let targetLibrary = libraryName ?? "default"
            guard let library = libraries[targetLibrary] else { return false }
            return library.functionNames.contains(name)
        }
    }
    
    private func createFunction(_ descriptor: ShaderFunctionDescriptor) throws -> MTLFunction {
        let targetLibrary = descriptor.library ?? "default"
        
        guard let library = libraries[targetLibrary] else {
            throw ShaderError.libraryNotFound
        }
        
        let function: MTLFunction
        
        if descriptor.constants.isEmpty {
            guard let basicFunction = library.makeFunction(name: descriptor.name) else {
                throw ShaderError.functionNotFound(descriptor.name)
            }
            function = basicFunction
        } else {
            let constantValues = MTLFunctionConstantValues()
            
            for constant in descriptor.constants {
                switch constant.type {
                case .bool:
                    if let value = constant.value as? Bool {
                        var boolValue = value
                        constantValues.setConstantValue(&boolValue, type: constant.type, index: constant.index)
                    }
                case .int:
                    if let value = constant.value as? Int32 {
                        var intValue = value
                        constantValues.setConstantValue(&intValue, type: constant.type, index: constant.index)
                    }
                case .uint:
                    if let value = constant.value as? UInt32 {
                        var uintValue = value
                        constantValues.setConstantValue(&uintValue, type: constant.type, index: constant.index)
                    }
                case .float:
                    if let value = constant.value as? Float {
                        var floatValue = value
                        constantValues.setConstantValue(&floatValue, type: constant.type, index: constant.index)
                    }
                case .float2:
                    if let value = constant.value as? SIMD2<Float> {
                        var float2Value = value
                        constantValues.setConstantValue(&float2Value, type: constant.type, index: constant.index)
                    }
                case .float3:
                    if let value = constant.value as? SIMD3<Float> {
                        var float3Value = value
                        constantValues.setConstantValue(&float3Value, type: constant.type, index: constant.index)
                    }
                case .float4:
                    if let value = constant.value as? SIMD4<Float> {
                        var float4Value = value
                        constantValues.setConstantValue(&float4Value, type: constant.type, index: constant.index)
                    }
                default:
                    logger.warning("Unsupported constant type: \(constant.type.rawValue)")
                }
            }
            
            do {
                function = try library.makeFunction(name: descriptor.name, constantValues: constantValues)
            } catch {
                throw ShaderError.compilationFailed(descriptor.name, error)
            }
        }
        
        validateFunctionCapabilities(function)
        
        logger.debug("Created function: \(descriptor.name)")
        return function
    }
    
    private func validateFunctionCapabilities(_ function: MTLFunction) {
        // Check if the function requires capabilities not available on the current device
        if function.functionType == .kernel {
            // Check compute shader requirements
            let maxThreads = device.capabilities.maxThreadsPerThreadgroup
            if let computeFunction = function as? MTLComputePipelineState {
                // Note: For actual validation, we'd need the pipeline state, not just the function
                // This is a placeholder for now
                logger.debug("Validated compute function: \(function.name)")
            }
        }
        
        // Additional capability checks can be added here based on device features
    }
    
    private func loadDefaultLibrary() {
        guard let library = device.makeDefaultLibrary() else {
            logger.warning("No default Metal library found")
            return
        }
        
        libraries["default"] = library
        logger.info("Loaded default Metal library with \(library.functionNames.count) functions")
    }
    
    private func loadBuiltinShaders() {
        // Load common shader source if available
        Task {
            do {
                let commonShaderSource = generateCommonShaderSource()
                try await loadLibrary(source: commonShaderSource, name: "common")
            } catch {
                logger.error("Failed to load common shaders: \(error.localizedDescription)")
            }
        }
    }
    
    private func generateCommonShaderSource() -> String {
        return """
        #include <metal_stdlib>
        using namespace metal;
        
        struct Vertex2D {
            float2 position [[attribute(0)]];
            float2 texCoord [[attribute(1)]];
        };
        
        struct Vertex3D {
            float3 position [[attribute(0)]];
            float3 normal [[attribute(1)]];
            float2 texCoord [[attribute(2)]];
        };
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
            float4 color;
        };
        
        struct VertexUniforms {
            float4x4 modelViewProjectionMatrix;
            float4x4 modelMatrix;
            float4x4 normalMatrix;
        };
        
        struct FragmentUniforms {
            float4 color;
            float time;
            float2 resolution;
        };
        
        // Vertex Shaders
        vertex VertexOut vertex_passthrough(Vertex2D in [[stage_in]],
                                           constant VertexUniforms& uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 0.0, 1.0);
            out.texCoord = in.texCoord;
            out.color = float4(1.0);
            return out;
        }
        
        vertex VertexOut vertex_transform(Vertex3D in [[stage_in]],
                                         constant VertexUniforms& uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
            out.texCoord = in.texCoord;
            out.color = float4(1.0);
            return out;
        }
        
        // Fragment Shaders
        fragment float4 fragment_texture_sample(VertexOut in [[stage_in]],
                                               texture2d<float> texture [[texture(0)]],
                                               sampler textureSampler [[sampler(0)]]) {
            return texture.sample(textureSampler, in.texCoord);
        }
        
        fragment float4 fragment_color_fill(VertexOut in [[stage_in]],
                                           constant FragmentUniforms& uniforms [[buffer(0)]]) {
            return uniforms.color;
        }
        
        fragment float4 fragment_blend(VertexOut in [[stage_in]],
                                      texture2d<float> sourceTexture [[texture(0)]],
                                      texture2d<float> overlayTexture [[texture(1)]],
                                      sampler textureSampler [[sampler(0)]],
                                      constant FragmentUniforms& uniforms [[buffer(0)]]) {
            float4 source = sourceTexture.sample(textureSampler, in.texCoord);
            float4 overlay = overlayTexture.sample(textureSampler, in.texCoord);
            
            // Simple alpha blend
            float alpha = overlay.a;
            return source * (1.0 - alpha) + overlay * alpha;
        }
        
        // Compute Shaders
        kernel void compute_image_process(texture2d<float, access::read> inputTexture [[texture(0)]],
                                         texture2d<float, access::write> outputTexture [[texture(1)]],
                                         uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
                return;
            }
            
            float4 color = inputTexture.read(gid);
            outputTexture.write(color, gid);
        }
        """
    }
}

extension ShaderLibrary {
    public func createVertexFunction(_ name: String, constants: [FunctionConstant] = []) throws -> MTLFunction {
        let descriptor = ShaderFunctionDescriptor(name: name, constants: constants)
        let function = try getFunction(descriptor)
        
        guard function.functionType == .vertex else {
            throw ShaderError.unsupportedFunction("Expected vertex function, got \(function.functionType)")
        }
        
        return function
    }
    
    public func createFragmentFunction(_ name: String, constants: [FunctionConstant] = []) throws -> MTLFunction {
        let descriptor = ShaderFunctionDescriptor(name: name, constants: constants)
        let function = try getFunction(descriptor)
        
        guard function.functionType == .fragment else {
            throw ShaderError.unsupportedFunction("Expected fragment function, got \(function.functionType)")
        }
        
        return function
    }
    
    public func createComputeFunction(_ name: String, constants: [FunctionConstant] = []) throws -> MTLFunction {
        let descriptor = ShaderFunctionDescriptor(name: name, constants: constants)
        let function = try getFunction(descriptor)
        
        guard function.functionType == .kernel else {
            throw ShaderError.unsupportedFunction("Expected compute function, got \(function.functionType)")
        }
        
        return function
    }
    
    public func printLibraryInfo() {
        accessQueue.sync {
            logger.info("Shader Library Status:")
            for (name, library) in self.libraries {
                logger.info("  Library '\(name)': \(library.functionNames.count) functions")
            }
            logger.info("  Cached functions: \(self.functions.count)")
        }
    }
}