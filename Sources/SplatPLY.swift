import Foundation
import simd

/// Parsed 3DGS splat cloud in RAW .ply encodings:
/// scales are log-space, opacities are logits, DC is SH-DC (no 0.282/+0.5 applied).
/// RealityKit's GaussianSplatResource activations (.exponential / .sigmoid) consume
/// these raw values directly — no CPU preprocessing pass.
struct SplatCloud {
    var count: Int
    var positions: [Float]   // xyz interleaved, 3 per splat
    var logScales: [Float]   // 3 per splat (raw scale_0..2)
    var rotations: [Float]   // 4 per splat, normalized, stored x,y,z,w (PLY is w,x,y,z)
    var logitOpacities: [Float] // 1 per splat
    var dc: [Float]          // 3 per splat (f_dc_0..2)
}

enum SplatPLYError: Error, CustomStringConvertible {
    case notBinaryLittleEndian
    case missingField(String)
    case truncated
    var description: String {
        switch self {
        case .notBinaryLittleEndian: return "PLY is not binary_little_endian"
        case .missingField(let f): return "PLY missing required 3DGS field \(f)"
        case .truncated: return "PLY data shorter than header promises"
        }
    }
}

enum SplatPLY {
    /// Minimal binary-little-endian 3DGS PLY parser. Float properties only for the
    /// fields we need; tolerates and skips others (incl. uchar) via stride math.
    static func parse(url: URL, cap: Int) throws -> SplatCloud {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // ---- Header (ASCII until "end_header\n")
        let probe = data.prefix(64 * 1024)
        guard let headerEnd = probe.range(of: Data("end_header\n".utf8))?.upperBound else {
            throw SplatPLYError.truncated
        }
        let header = String(decoding: probe[..<headerEnd], as: UTF8.self)
        guard header.contains("binary_little_endian") else { throw SplatPLYError.notBinaryLittleEndian }

        var vertexCount = 0
        var offsets: [String: Int] = [:]   // property name -> byte offset in row
        var rowStride = 0
        var inVertexElement = false
        for line in header.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            if parts.first == "element" {
                inVertexElement = (parts.count >= 3 && parts[1] == "vertex")
                if inVertexElement { vertexCount = Int(parts[2]) ?? 0 }
            } else if parts.first == "property", inVertexElement, parts.count >= 3 {
                let size: Int
                switch parts[1] {
                case "float", "float32", "int", "int32", "uint", "uint32": size = 4
                case "double", "float64": size = 8
                case "uchar", "uint8", "char", "int8": size = 1
                case "short", "ushort", "int16", "uint16": size = 2
                default: size = 4
                }
                offsets[parts[2]] = rowStride
                rowStride += size
            }
        }

        let required = ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
                        "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
        for f in required where offsets[f] == nil { throw SplatPLYError.missingField(f) }

        let body = data.dropFirst(headerEnd)
        guard body.count >= vertexCount * rowStride else { throw SplatPLYError.truncated }

        let oX = offsets["x"]!, oY = offsets["y"]!, oZ = offsets["z"]!
        let oD0 = offsets["f_dc_0"]!, oD1 = offsets["f_dc_1"]!, oD2 = offsets["f_dc_2"]!
        let oOp = offsets["opacity"]!
        let oS0 = offsets["scale_0"]!, oS1 = offsets["scale_1"]!, oS2 = offsets["scale_2"]!
        let oR0 = offsets["rot_0"]!, oR1 = offsets["rot_1"]!, oR2 = offsets["rot_2"]!, oR3 = offsets["rot_3"]!

        var positions = [Float](repeating: 0, count: vertexCount * 3)
        var logScales = [Float](repeating: 0, count: vertexCount * 3)
        var rotations = [Float](repeating: 0, count: vertexCount * 4)
        var logitOpacities = [Float](repeating: 0, count: vertexCount)
        var dc = [Float](repeating: 0, count: vertexCount * 3)

        body.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!
            for i in 0..<vertexCount {
                let row = base + i * rowStride
                func f(_ off: Int) -> Float { row.loadUnaligned(fromByteOffset: off, as: Float.self) }
                positions[i * 3 + 0] = f(oX)
                positions[i * 3 + 1] = f(oY)
                positions[i * 3 + 2] = f(oZ)
                dc[i * 3 + 0] = f(oD0)
                dc[i * 3 + 1] = f(oD1)
                dc[i * 3 + 2] = f(oD2)
                logitOpacities[i] = f(oOp)
                logScales[i * 3 + 0] = f(oS0)
                logScales[i * 3 + 1] = f(oS1)
                logScales[i * 3 + 2] = f(oS2)
                // PLY rot_0..3 is (w,x,y,z), unnormalized. Normalize; store x,y,z,w
                // (simd storage order). If splat orientations look wrong on real
                // scenes, the w-position is the first thing to A/B.
                var q = simd_quatf(ix: f(oR1), iy: f(oR2), iz: f(oR3), r: f(oR0))
                let len = simd_length(q.vector)
                if len > 1e-8 { q = simd_quatf(vector: q.vector / len) } else { q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
                rotations[i * 4 + 0] = q.vector.x
                rotations[i * 4 + 1] = q.vector.y
                rotations[i * 4 + 2] = q.vector.z
                rotations[i * 4 + 3] = q.vector.w
            }
        }

        var cloud = SplatCloud(count: vertexCount, positions: positions, logScales: logScales,
                               rotations: rotations, logitOpacities: logitOpacities, dc: dc)
        cloud.recenterToMedian()
        if cap < vertexCount { cloud = cloud.importancePruned(to: cap) }
        return cloud
    }
}

extension SplatCloud {
    /// Robust recenter: median center (sampled), so distant outliers don't drag
    /// the scene away from the viewer. Same lesson as SplatDiorama's auto-fit.
    mutating func recenterToMedian() {
        let n = count
        guard n > 0 else { return }
        let sampleN = min(n, 100_000)
        let step = max(1, n / sampleN)
        var xs: [Float] = [], ys: [Float] = [], zs: [Float] = []
        xs.reserveCapacity(sampleN); ys.reserveCapacity(sampleN); zs.reserveCapacity(sampleN)
        var i = 0
        while i < n {
            xs.append(positions[i * 3]); ys.append(positions[i * 3 + 1]); zs.append(positions[i * 3 + 2])
            i += step
        }
        xs.sort(); ys.sort(); zs.sort()
        let cx = xs[xs.count / 2], cy = ys[ys.count / 2], cz = zs[zs.count / 2]
        for j in 0..<n {
            positions[j * 3] -= cx
            positions[j * 3 + 1] -= cy
            positions[j * 3 + 2] -= cz
        }
    }

    /// Keep the `target` highest-contribution splats (sigmoid(opacity) × mean linear
    /// scale) — drops tiny near-transparent splats first. Ported idea from
    /// SplatDiorama (where it both cleaned AND sped up scenes).
    func importancePruned(to target: Int) -> SplatCloud {
        guard target < count else { return self }
        var scores = [(Float, Int)](); scores.reserveCapacity(count)
        for i in 0..<count {
            let op = 1.0 / (1.0 + exp(-logitOpacities[i]))
            let s = (exp(logScales[i * 3]) + exp(logScales[i * 3 + 1]) + exp(logScales[i * 3 + 2])) / 3
            scores.append((op * s, i))
        }
        scores.sort { $0.0 > $1.0 }
        var out = SplatCloud(count: target,
                             positions: .init(repeating: 0, count: target * 3),
                             logScales: .init(repeating: 0, count: target * 3),
                             rotations: .init(repeating: 0, count: target * 4),
                             logitOpacities: .init(repeating: 0, count: target),
                             dc: .init(repeating: 0, count: target * 3))
        for (j, pair) in scores.prefix(target).enumerated() {
            let i = pair.1
            for k in 0..<3 {
                out.positions[j * 3 + k] = positions[i * 3 + k]
                out.logScales[j * 3 + k] = logScales[i * 3 + k]
                out.dc[j * 3 + k] = dc[i * 3 + k]
            }
            for k in 0..<4 { out.rotations[j * 4 + k] = rotations[i * 4 + k] }
            out.logitOpacities[j] = logitOpacities[i]
        }
        return out
    }

    /// Synthetic test cloud: a colorful spherical shell around the viewer.
    /// Decouples "does GaussianSplatComponent render in this sim" from "is the
    /// PLY parser right".
    static func synthetic(count: Int) -> SplatCloud {
        var cloud = SplatCloud(count: count,
                               positions: .init(repeating: 0, count: count * 3),
                               logScales: .init(repeating: 0, count: count * 3),
                               rotations: .init(repeating: 0, count: count * 4),
                               logitOpacities: .init(repeating: 0, count: count),
                               dc: .init(repeating: 0, count: count * 3))
        var rng = SystemRandomNumberGenerator()
        let logScale = log(Float(0.015))           // exp() → 1.5 cm splats
        let logitOpaque: Float = 2.2               // sigmoid() → ~0.9
        for i in 0..<count {
            // Shell between 1.5 m and 3.5 m, full sphere.
            let u = Float.random(in: -1...1, using: &rng)
            let phi = Float.random(in: 0..<(2 * .pi), using: &rng)
            let r = Float.random(in: 1.5...3.5, using: &rng)
            let s = sqrt(max(0, 1 - u * u))
            let p = SIMD3<Float>(s * cos(phi), u, s * sin(phi)) * r
            cloud.positions[i * 3] = p.x
            cloud.positions[i * 3 + 1] = p.y
            cloud.positions[i * 3 + 2] = p.z
            for k in 0..<3 { cloud.logScales[i * 3 + k] = logScale }
            cloud.rotations[i * 4 + 3] = 1 // identity (x,y,z,w)
            cloud.logitOpacities[i] = logitOpaque
            // Direction-keyed rainbow, encoded as SH DC: color = 0.2820948*dc + 0.5
            let c = SIMD3<Float>(0.5 + 0.5 * p.x / r, 0.5 + 0.5 * p.y / r, 0.5 + 0.5 * p.z / r)
            let dcv = (c - SIMD3<Float>(repeating: 0.5)) / 0.2820948
            cloud.dc[i * 3] = dcv.x; cloud.dc[i * 3 + 1] = dcv.y; cloud.dc[i * 3 + 2] = dcv.z
        }
        return cloud
    }
}
