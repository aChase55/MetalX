import Metal
import simd
import Foundation
import os.log

public enum RenderContextError: Error, LocalizedError {
    case invalidEncoder
    case resourceNotBound
    case invalidRenderState
    case commandBufferFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidEncoder:
            return "Invalid render encoder"
        case .resourceNotBound:
            return "Required resource not bound"
        case .invalidRenderState:
            return "Invalid render state"
        case .commandBufferFailed:
            return "Command buffer execution failed"
        }
    }
}

public struct RenderTargetDescriptor {
    public let colorTextures: [MTLTexture?]
    public let depthTexture: MTLTexture?
    public let stencilTexture: MTLTexture?
    public let sampleCount: Int
    public let loadAction: MTLLoadAction
    public let storeAction: MTLStoreAction
    public let clearColor: MTLClearColor
    public let clearDepth: Double
    public let clearStencil: UInt32
    
    public init(
        colorTextures: [MTLTexture?] = [],
        depthTexture: MTLTexture? = nil,
        stencilTexture: MTLTexture? = nil,
        sampleCount: Int = 1,
        loadAction: MTLLoadAction = .clear,
        storeAction: MTLStoreAction = .store,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
        clearDepth: Double = 1.0,
        clearStencil: UInt32 = 0
    ) {
        self.colorTextures = colorTextures
        self.depthTexture = depthTexture
        self.stencilTexture = stencilTexture
        self.sampleCount = sampleCount
        self.loadAction = loadAction
        self.storeAction = storeAction
        self.clearColor = clearColor
        self.clearDepth = clearDepth
        self.clearStencil = clearStencil
    }
}

public struct RenderState {
    public var pipelineState: MTLRenderPipelineState?
    public var depthStencilState: MTLDepthStencilState?
    public var cullMode: MTLCullMode = .none
    public var frontFaceWinding: MTLWinding = .counterClockwise
    public var fillMode: MTLTriangleFillMode = .fill
    public var depthClipMode: MTLDepthClipMode = .clip
    public var viewport: MTLViewport = MTLViewport()
    public var scissorRect: MTLScissorRect?
    
    public init() {}
}

public struct BoundResources {
    public var vertexBuffers: [MTLBuffer?] = Array(repeating: nil, count: 31)
    public var vertexBufferOffsets: [Int] = Array(repeating: 0, count: 31)
    public var fragmentBuffers: [MTLBuffer?] = Array(repeating: nil, count: 31)
    public var fragmentBufferOffsets: [Int] = Array(repeating: 0, count: 31)
    public var fragmentTextures: [MTLTexture?] = Array(repeating: nil, count: 31)
    public var fragmentSamplers: [MTLSamplerState?] = Array(repeating: nil, count: 16)
    
    public init() {}
    
    public mutating func reset() {
        vertexBuffers = Array(repeating: nil, count: 31)
        vertexBufferOffsets = Array(repeating: 0, count: 31)
        fragmentBuffers = Array(repeating: nil, count: 31)
        fragmentBufferOffsets = Array(repeating: 0, count: 31)
        fragmentTextures = Array(repeating: nil, count: 31)
        fragmentSamplers = Array(repeating: nil, count: 16)
    }
}

public class RenderContext {
    public let device: MetalDevice
    private let logger = Logger(subsystem: "com.metalx.engine", category: "RenderContext")
    
    private var currentCommandBuffer: MTLCommandBuffer?
    private var currentRenderEncoder: MTLRenderCommandEncoder?
    private var currentComputeEncoder: MTLComputeCommandEncoder?
    private var currentBlitEncoder: MTLBlitCommandEncoder?
    
    public private(set) var renderState = RenderState()
    public private(set) var boundResources = BoundResources()
    public private(set) var currentRenderTarget: RenderTargetDescriptor?
    
    private var encoderStack: [(String, Any)] = []
    private var debugGroups: [String] = []
    
    public var isEncoding: Bool {
        currentRenderEncoder != nil || currentComputeEncoder != nil || currentBlitEncoder != nil
    }
    
    public var currentEncoder: MTLCommandEncoder? {
        return currentRenderEncoder ?? currentComputeEncoder ?? currentBlitEncoder
    }
    
    public init(device: MetalDevice) {
        self.device = device
    }
    
    public func beginFrame(label: String = "Frame") throws -> MTLCommandBuffer {
        guard currentCommandBuffer == nil else {
            throw RenderContextError.invalidRenderState
        }
        
        guard let commandBuffer = device.makeCommandBuffer(label: label) else {
            throw RenderContextError.commandBufferFailed
        }
        
        currentCommandBuffer = commandBuffer
        return commandBuffer
    }
    
    public func endFrame() throws {
        guard let commandBuffer = currentCommandBuffer else {
            throw RenderContextError.invalidRenderState
        }
        
        endCurrentEncoder()
        
        currentCommandBuffer = nil
        currentRenderTarget = nil
        renderState = RenderState()
        boundResources.reset()
        
        commandBuffer.commit()
    }
    
    public func beginRenderPass(
        to target: RenderTargetDescriptor,
        label: String = "Render Pass"
    ) throws -> MTLRenderCommandEncoder {
        guard let commandBuffer = currentCommandBuffer else {
            throw RenderContextError.invalidRenderState
        }
        
        endCurrentEncoder()
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        for (index, texture) in target.colorTextures.enumerated() {
            guard let texture = texture, index < 8 else { continue }
            
            let attachment = renderPassDescriptor.colorAttachments[index]!
            attachment.texture = texture
            attachment.loadAction = target.loadAction
            attachment.storeAction = target.storeAction
            attachment.clearColor = target.clearColor
        }
        
        if let depthTexture = target.depthTexture {
            renderPassDescriptor.depthAttachment.texture = depthTexture
            renderPassDescriptor.depthAttachment.loadAction = target.loadAction
            renderPassDescriptor.depthAttachment.storeAction = target.storeAction
            renderPassDescriptor.depthAttachment.clearDepth = target.clearDepth
        }
        
        if let stencilTexture = target.stencilTexture {
            renderPassDescriptor.stencilAttachment.texture = stencilTexture
            renderPassDescriptor.stencilAttachment.loadAction = target.loadAction
            renderPassDescriptor.stencilAttachment.storeAction = target.storeAction
            renderPassDescriptor.stencilAttachment.clearStencil = target.clearStencil
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw RenderContextError.invalidEncoder
        }
        
        encoder.label = label
        currentRenderEncoder = encoder
        currentRenderTarget = target
        encoderStack.append((label, encoder))
        
        if !target.colorTextures.isEmpty, let firstTexture = target.colorTextures.first {
            let texture = firstTexture ?? target.depthTexture
            if let tex = texture {
                renderState.viewport = MTLViewport(
                    originX: 0,
                    originY: 0,
                    width: Double(tex.width),
                    height: Double(tex.height),
                    znear: 0.0,
                    zfar: 1.0
                )
                encoder.setViewport(renderState.viewport)
            }
        }
        
        return encoder
    }
    
    public func beginComputePass(label: String = "Compute Pass") throws -> MTLComputeCommandEncoder {
        guard let commandBuffer = currentCommandBuffer else {
            throw RenderContextError.invalidRenderState
        }
        
        endCurrentEncoder()
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderContextError.invalidEncoder
        }
        
        encoder.label = label
        currentComputeEncoder = encoder
        encoderStack.append((label, encoder))
        
        return encoder
    }
    
    public func beginBlitPass(label: String = "Blit Pass") throws -> MTLBlitCommandEncoder {
        guard let commandBuffer = currentCommandBuffer else {
            throw RenderContextError.invalidRenderState
        }
        
        endCurrentEncoder()
        
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw RenderContextError.invalidEncoder
        }
        
        encoder.label = label
        currentBlitEncoder = encoder
        encoderStack.append((label, encoder))
        
        return encoder
    }
    
    public func endCurrentEncoder() {
        if let encoder = currentRenderEncoder {
            encoder.endEncoding()
            currentRenderEncoder = nil
        }
        
        if let encoder = currentComputeEncoder {
            encoder.endEncoding()
            currentComputeEncoder = nil
        }
        
        if let encoder = currentBlitEncoder {
            encoder.endEncoding()
            currentBlitEncoder = nil
        }
        
        if !encoderStack.isEmpty {
            encoderStack.removeLast()
        }
    }
    
    public func setRenderPipelineState(_ pipelineState: MTLRenderPipelineState) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if renderState.pipelineState !== pipelineState {
            encoder.setRenderPipelineState(pipelineState)
            renderState.pipelineState = pipelineState
        }
    }
    
    public func setDepthStencilState(_ depthStencilState: MTLDepthStencilState?) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if renderState.depthStencilState !== depthStencilState {
            encoder.setDepthStencilState(depthStencilState)
            renderState.depthStencilState = depthStencilState
        }
    }
    
    public func setCullMode(_ cullMode: MTLCullMode) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if renderState.cullMode != cullMode {
            encoder.setCullMode(cullMode)
            renderState.cullMode = cullMode
        }
    }
    
    public func setFrontFaceWinding(_ winding: MTLWinding) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if renderState.frontFaceWinding != winding {
            encoder.setFrontFacing(winding)
            renderState.frontFaceWinding = winding
        }
    }
    
    public func setTriangleFillMode(_ fillMode: MTLTriangleFillMode) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if renderState.fillMode != fillMode {
            encoder.setTriangleFillMode(fillMode)
            renderState.fillMode = fillMode
        }
    }
    
    public func setViewport(_ viewport: MTLViewport) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if !areEqual(renderState.viewport, viewport) {
            encoder.setViewport(viewport)
            renderState.viewport = viewport
        }
    }
    
    public func setScissorRect(_ rect: MTLScissorRect?) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        if let rect = rect {
            if renderState.scissorRect == nil || !areEqual(renderState.scissorRect!, rect) {
                encoder.setScissorRect(rect)
                renderState.scissorRect = rect
            }
        } else if renderState.scissorRect != nil {
            renderState.scissorRect = nil
        }
    }
    
    public func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int = 0, index: Int) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        guard index < boundResources.vertexBuffers.count else {
            throw RenderContextError.invalidRenderState
        }
        
        if boundResources.vertexBuffers[index] !== buffer || boundResources.vertexBufferOffsets[index] != offset {
            encoder.setVertexBuffer(buffer, offset: offset, index: index)
            boundResources.vertexBuffers[index] = buffer
            boundResources.vertexBufferOffsets[index] = offset
        }
    }
    
    public func setFragmentBuffer(_ buffer: MTLBuffer?, offset: Int = 0, index: Int) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        guard index < boundResources.fragmentBuffers.count else {
            throw RenderContextError.invalidRenderState
        }
        
        if boundResources.fragmentBuffers[index] !== buffer || boundResources.fragmentBufferOffsets[index] != offset {
            encoder.setFragmentBuffer(buffer, offset: offset, index: index)
            boundResources.fragmentBuffers[index] = buffer
            boundResources.fragmentBufferOffsets[index] = offset
        }
    }
    
    public func setFragmentTexture(_ texture: MTLTexture?, index: Int) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        guard index < boundResources.fragmentTextures.count else {
            throw RenderContextError.invalidRenderState
        }
        
        if boundResources.fragmentTextures[index] !== texture {
            encoder.setFragmentTexture(texture, index: index)
            boundResources.fragmentTextures[index] = texture
        }
    }
    
    public func setFragmentSamplerState(_ sampler: MTLSamplerState?, index: Int) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        guard index < boundResources.fragmentSamplers.count else {
            throw RenderContextError.invalidRenderState
        }
        
        if boundResources.fragmentSamplers[index] !== sampler {
            encoder.setFragmentSamplerState(sampler, index: index)
            boundResources.fragmentSamplers[index] = sampler
        }
    }
    
    public func drawPrimitives(
        type: MTLPrimitiveType,
        vertexStart: Int = 0,
        vertexCount: Int,
        instanceCount: Int = 1
    ) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        encoder.drawPrimitives(
            type: type,
            vertexStart: vertexStart,
            vertexCount: vertexCount,
            instanceCount: instanceCount
        )
    }
    
    public func drawIndexedPrimitives(
        type: MTLPrimitiveType,
        indexCount: Int,
        indexType: MTLIndexType,
        indexBuffer: MTLBuffer,
        indexBufferOffset: Int = 0,
        instanceCount: Int = 1
    ) throws {
        guard let encoder = currentRenderEncoder else {
            throw RenderContextError.invalidEncoder
        }
        
        encoder.drawIndexedPrimitives(
            type: type,
            indexCount: indexCount,
            indexType: indexType,
            indexBuffer: indexBuffer,
            indexBufferOffset: indexBufferOffset,
            instanceCount: instanceCount
        )
    }
    
    public func pushDebugGroup(_ name: String) {
        debugGroups.append(name)
        currentEncoder?.pushDebugGroup(name)
    }
    
    public func popDebugGroup() {
        if !debugGroups.isEmpty {
            debugGroups.removeLast()
        }
        currentEncoder?.popDebugGroup()
    }
    
    public func insertDebugSignpost(_ label: String) {
        currentEncoder?.insertDebugSignpost(label)
    }
    
    private func areEqual(_ viewport1: MTLViewport, _ viewport2: MTLViewport) -> Bool {
        return viewport1.originX == viewport2.originX &&
               viewport1.originY == viewport2.originY &&
               viewport1.width == viewport2.width &&
               viewport1.height == viewport2.height &&
               viewport1.znear == viewport2.znear &&
               viewport1.zfar == viewport2.zfar
    }
    
    private func areEqual(_ rect1: MTLScissorRect, _ rect2: MTLScissorRect) -> Bool {
        return rect1.x == rect2.x &&
               rect1.y == rect2.y &&
               rect1.width == rect2.width &&
               rect1.height == rect2.height
    }
}

extension RenderContext {
    public func withDebugGroup<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        pushDebugGroup(name)
        defer { popDebugGroup() }
        return try block()
    }
    
    public func withRenderPass<T>(
        to target: RenderTargetDescriptor,
        label: String = "Render Pass",
        _ block: (MTLRenderCommandEncoder) throws -> T
    ) throws -> T {
        let encoder = try beginRenderPass(to: target, label: label)
        defer { endCurrentEncoder() }
        return try block(encoder)
    }
    
    public func withComputePass<T>(
        label: String = "Compute Pass",
        _ block: (MTLComputeCommandEncoder) throws -> T
    ) throws -> T {
        let encoder = try beginComputePass(label: label)
        defer { endCurrentEncoder() }
        return try block(encoder)
    }
    
    public func withBlitPass<T>(
        label: String = "Blit Pass",
        _ block: (MTLBlitCommandEncoder) throws -> T
    ) throws -> T {
        let encoder = try beginBlitPass(label: label)
        defer { endCurrentEncoder() }
        return try block(encoder)
    }
}