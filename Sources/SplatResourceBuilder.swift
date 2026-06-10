import Foundation
import RealityKit
import Metal
import CoreGraphics

// ⚠️ Beta-1 reality (2026-06-09): GaussianSplatResource/Component exist ONLY in the
// device SDK (XROS27.0.sdk). The simulator SDK (XRSimulator27.0.sdk) has zero
// GaussianSplat symbols in ANY framework — so the native path is device-only until
// a later beta. Sim builds get a stub that reports the gap.
#if !targetEnvironment(simulator)

/// Builds a visionOS 27 `GaussianSplatResource` from a SplatCloud's raw 3DGS values.
/// Exact API surface documented in KB:
/// intelligence/techniques/realitykit-gaussian-splat-api-visionos27.md
enum SplatResourceBuilder {

    @MainActor
    static func makeResource(from cloud: SplatCloud) throws -> GaussianSplatResource {
        // Documented path (WWDC26 §279 + the XROS27 swiftinterface), CONFIRMED by the
        // AppleSplatRendering renderer binary's internal stages:
        //   apple3dgs::TransformGaussians(…, ActivationType, …)  → applies exp()/sigmoid()
        //   apple3dgs::ComputeColorFromSH(…)                     → evaluates SH → RGB
        //   apple3dgs::ToLinearColorSpace(float3, TransferFunction) gated by
        //   GetColorPropertiesFromCGColorSpace(colorSpace)       → linearizes for compositing
        // So: upload RAW 3DGS values (no CPU pre-activation, no SH→RGB), set the activation
        // enums, and MUST set a supported colorSpace or the color→linear stage degenerates
        // (splats composite as ~zero-alpha "passthrough"). The earlier "pre-apply + .identity"
        // workaround was a misdiagnosis — the binary shows that machinery is live.
        let position = try descriptor(cloud.positions,      components: 3, format: .float3)
        let scale    = try descriptor(cloud.logScales,      components: 3, format: .float3)
        let rotation = try descriptor(cloud.rotations,      components: 4, format: .float4)
        let opacity  = try descriptor(cloud.logitOpacities, components: 1, format: .float)
        let sh       = try descriptor(cloud.dc,             components: 3, format: .float3)

        let bufferResource = try GaussianSplatResource.BufferResource(
            count: cloud.count,
            position: position,
            scale: scale,
            rotation: rotation,
            opacity: opacity,
            sphericalHarmonics: (sh, .zero)
        )
        let resource = GaussianSplatResource(bufferResource)
        resource.scaleActivation   = .exponential   // raw 3DGS log-scales
        resource.opacityActivation = .sigmoid       // raw 3DGS logit-opacities
        resource.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        return resource
    }

    @MainActor
    private static func descriptor(_ values: [Float], components: Int,
                                   format: MTLAttributeFormat) throws -> GaussianSplatResource.BufferDescriptor {
        let byteCount = values.count * MemoryLayout<Float>.stride
        let buffer = try LowLevelBuffer(descriptor: .init(capacity: byteCount))
        buffer.withUnsafeMutableBytes { raw in
            values.withUnsafeBytes { src in
                raw.copyMemory(from: src)
            }
        }
        buffer.bytesUsed = byteCount
        return .init(buffer: buffer, format: format,
                     stride: components * MemoryLayout<Float>.stride, offset: 0)
    }
}

#endif
