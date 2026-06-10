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

    /// ⚠️ Beta-1 culling bug (measured on device 2026-06-10): the renderer culls the
    /// ENTIRE entity whenever the camera is within ~3× the cloud's bounding radius of
    /// its center (the 3σ kernel support applied to the whole field). A walk-inside
    /// scene is therefore invisible as one entity. Fix: split into a spatial grid of
    /// sub-entities — only the chunk the camera is inside ever culls.
    @MainActor
    static func makeChunkedEntity(from cloud: SplatCloud, grid: Int,
                                  sorting: GaussianSplatResource.SortingMode,
                                  projection: GaussianSplatResource.ProjectionMode) throws -> Entity {
        let root = Entity()
        guard cloud.count > 0 else { return root }

        // bounds of positions
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for i in 0..<cloud.count {
            let p = SIMD3<Float>(cloud.positions[i*3], cloud.positions[i*3+1], cloud.positions[i*3+2])
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        let span = simd_max(hi - lo, SIMD3<Float>(repeating: 1e-5))
        let g = Float(grid)

        var cells: [Int: [Int]] = [:]
        for i in 0..<cloud.count {
            let p = SIMD3<Float>(cloud.positions[i*3], cloud.positions[i*3+1], cloud.positions[i*3+2])
            let n = simd_clamp((p - lo) / span * g, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: g - 1))
            let key = (Int(n.x) * grid + Int(n.y)) * grid + Int(n.z)
            cells[key, default: []].append(i)
        }

        // Runt cells (<256 splats) produce buffers the renderer mishandles —
        // fold them into the largest cell (Vitrine device-proven).
        let minimumChunk = 256
        let runts = cells.filter { $0.value.count < minimumChunk }.map(\.key)
        if !runts.isEmpty, let biggest = cells.max(by: { $0.value.count < $1.value.count })?.key {
            for key in runts where key != biggest {
                cells[biggest, default: []].append(contentsOf: cells.removeValue(forKey: key) ?? [])
            }
        }

        for (_, idx) in cells {
            // Positions stay in cloud space; chunk entities at identity (Vitrine-proven).
            let sub = cloud.gathered(idx)
            let resource = try makeResource(from: sub)
            resource.sortingMode = sorting
            resource.projectionMode = projection
            let e = Entity()
            e.components.set(GaussianSplatComponent(resource))
            root.addChild(e)
        }
        return root
    }

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
        // ⚠️ Beta-1: capacity must be padded to a 256-BYTE multiple. Unpadded throws
        // ResourceError.invalid(bufferCapacity:); 16-byte padding passes the validator
        // but renders scattered garbage ("exploded" chunks). 256 is device-proven
        // (Vitrine). bytesUsed stays exact.
        let buffer = try LowLevelBuffer(descriptor: .init(capacity: (byteCount + 255) & ~255))
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
