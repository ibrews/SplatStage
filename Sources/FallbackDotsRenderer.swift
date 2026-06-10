import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

/// Renders a SplatCloud as color-bucketed unlit quads — NO GaussianSplat API.
///
/// Purpose: the native splat renderer is device-only in visionOS 27 beta 1
/// (sim/macOS/iOS SDKs have zero GaussianSplat symbols), so this is the only way
/// to *see* the data pipeline in the Simulator. It is also a device-side A/B probe:
/// if the dots show correct colors/positions but the native path doesn't, the bug
/// is in the GaussianSplatResource configuration, not in our parsing/data.
///
/// Faithfulness: positions are exact; color is the documented DC convention
/// (0.2820948·f_dc + 0.5) quantized to ≤64 buckets; size is the splat's mean
/// linear scale (clamped); orientation is two crossed quads (visibility from all
/// directions beats per-splat orientation for verification).
enum FallbackDotsRenderer {

    static let maxDots = 80_000

    @MainActor
    static func makeEntity(from cloud: SplatCloud) -> Entity {
        let root = Entity()
        let n = cloud.count
        guard n > 0 else { return root }
        let stride = max(1, n / maxDots)

        // color bucket (4 levels/channel = 64 max) -> accumulated quad vertices
        var bucketPositions: [Int: [SIMD3<Float>]] = [:]

        var i = 0
        while i < n {
            let p = SIMD3<Float>(cloud.positions[i * 3], cloud.positions[i * 3 + 1], cloud.positions[i * 3 + 2])
            let c = SIMD3<Float>(
                max(0, min(1, 0.2820948 * cloud.dc[i * 3 + 0] + 0.5)),
                max(0, min(1, 0.2820948 * cloud.dc[i * 3 + 1] + 0.5)),
                max(0, min(1, 0.2820948 * cloud.dc[i * 3 + 2] + 0.5)))
            let qx = Int(min(c.x, 0.999) * 4), qy = Int(min(c.y, 0.999) * 4), qz = Int(min(c.z, 0.999) * 4)
            let bucket = qx * 16 + qy * 4 + qz

            let meanScale = (exp(cloud.logScales[i * 3]) + exp(cloud.logScales[i * 3 + 1])
                             + exp(cloud.logScales[i * 3 + 2])) / 3
            let half = max(0.004, min(0.05, meanScale)) // keep every dot visible

            // two crossed quads (XY plane + YZ plane), 8 verts / 4 tris per splat
            var verts = bucketPositions[bucket] ?? []
            verts.append(contentsOf: [
                p + SIMD3(-half, -half, 0), p + SIMD3(half, -half, 0),
                p + SIMD3(half, half, 0), p + SIMD3(-half, half, 0),
                p + SIMD3(0, -half, -half), p + SIMD3(0, half, -half),
                p + SIMD3(0, half, half), p + SIMD3(0, -half, half),
            ])
            bucketPositions[bucket] = verts
            i += stride
        }

        for (bucket, verts) in bucketPositions {
            var desc = MeshDescriptor(name: "dots-\(bucket)")
            desc.positions = MeshBuffer(verts)
            var indices: [UInt32] = []
            indices.reserveCapacity(verts.count / 8 * 12)
            var v: UInt32 = 0
            while v < UInt32(verts.count) {
                indices.append(contentsOf: [v, v + 1, v + 2, v, v + 2, v + 3,
                                            v + 4, v + 5, v + 6, v + 4, v + 6, v + 7])
                v += 8
            }
            desc.primitives = .triangles(indices)
            guard let mesh = try? MeshResource.generate(from: [desc]) else { continue }

            let r = (Float(bucket / 16) + 0.5) / 4
            let g = (Float((bucket / 4) % 4) + 0.5) / 4
            let b = (Float(bucket % 4) + 0.5) / 4
            var material = UnlitMaterial(color: UIColor(red: CGFloat(r), green: CGFloat(g),
                                                        blue: CGFloat(b), alpha: 1))
            material.faceCulling = .none // crossed quads must be visible from both sides

            let entity = Entity()
            entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
            root.addChild(entity)
        }
        return root
    }
}
