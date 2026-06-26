@testable import SplatStage
import Testing
import Foundation

// #expect(throws: someCase) requires the error type to be Equatable.
extension SplatPLYError: Equatable {
    public static func == (l: SplatPLYError, r: SplatPLYError) -> Bool {
        switch (l, r) {
        case (.notBinaryLittleEndian, .notBinaryLittleEndian), (.truncated, .truncated): return true
        case let (.missingField(a), .missingField(b)): return a == b
        default: return false
        }
    }
}

@Suite struct SplatPLYTests {
    // Helper to build minimal valid binary_little_endian PLY data
    func makeValidPLYData(count: Int) -> Data {
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex \(count)
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        """
        var data = (header + "\n").data(using: .ascii)!
        
        for _ in 0..<count {
            // Write 14 floats in little-endian format
            let values: [Float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            for value in values {
                data.append(withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) })
            }
        }
        return data
    }
    
    @Test func validPLYParsing() throws {
        let data = makeValidPLYData(count: 5)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).ply")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let cloud = try SplatPLY.parse(url: url, cap: 10)
        #expect(cloud.count == 5)
        #expect(cloud.positions.count == 5 * 3)
        #expect(cloud.logScales.count == 5 * 3)
        #expect(cloud.rotations.count == 5 * 4)
        #expect(cloud.logitOpacities.count == 5)
        #expect(cloud.dc.count == 5 * 3)
    }
    
    @Test func invalidFormatThrowsNotBinaryLittleEndian() throws {
        let header = """
        ply
        format ascii 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        """
        let data = (header + "\n").data(using: .ascii)!
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).ply")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        
        #expect(throws: SplatPLYError.notBinaryLittleEndian) {
            _ = try SplatPLY.parse(url: url, cap: 10)
        }
    }
    
    @Test func missingFieldThrowsMissingField() throws {
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex 1
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        """
        let data = (header + "\n").data(using: .ascii)!
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).ply")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        
        #expect(throws: SplatPLYError.missingField("scale_2")) {
            _ = try SplatPLY.parse(url: url, cap: 10)
        }
    }
    
    @Test func truncatedBodyThrowsTruncated() throws {
        let header = """
        ply
        format binary_little_endian 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        """
        var data = (header + "\n").data(using: .ascii)!
        // Only write one vertex worth of data instead of two
        let values: [Float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        for value in values {
            data.append(withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) })
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).ply")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        
        #expect(throws: SplatPLYError.truncated) {
            _ = try SplatPLY.parse(url: url, cap: 10)
        }
    }
    
    @Test func recenterToMedianCentersPositions() {
        var cloud = SplatCloud.synthetic(count: 100)
        // Set known positions
        for i in 0..<100 {
            cloud.positions[i*3 + 0] = Float(i) * 10.0
            cloud.positions[i*3 + 1] = Float(i) * 10.0
            cloud.positions[i*3 + 2] = Float(i) * 10.0
        }
        cloud.recenterToMedian()
        // Check that median is near zero
        let x = cloud.positions[0..<300].enumerated().filter { $0.offset % 3 == 0 }.map { $0.element }.sorted()
        let y = cloud.positions[0..<300].enumerated().filter { $0.offset % 3 == 1 }.map { $0.element }.sorted()
        let z = cloud.positions[0..<300].enumerated().filter { $0.offset % 3 == 2 }.map { $0.element }.sorted()
        let medianX = x[x.count/2]
        let medianY = y[y.count/2]
        let medianZ = z[z.count/2]
        #expect(abs(medianX) < 1e-5)
        #expect(abs(medianY) < 1e-5)
        #expect(abs(medianZ) < 1e-5)
    }
    
    @Test func importancePrunedReturnsCorrectCountAndKeepsHighestOpacity() {
        var cloud = SplatCloud.synthetic(count: 100)
        // Set opacities so that splats 0..49 are low and 50..99 are high
        for i in 0..<100 {
            cloud.logitOpacities[i] = i < 50 ? -10.0 : 10.0
        }
        let pruned = cloud.importancePruned(to: 10)
        #expect(pruned.count == 10)
        // All kept splats must come from the high-opacity group (logit 10.0).
        #expect(pruned.logitOpacities.allSatisfy { $0 == 10.0 })
    }
    
    @Test func syntheticProducesCorrectSizesAndUnitLengthRotations() {
        let cloud = SplatCloud.synthetic(count: 50)
        #expect(cloud.count == 50)
        #expect(cloud.positions.count == 50 * 3)
        #expect(cloud.logScales.count == 50 * 3)
        #expect(cloud.rotations.count == 50 * 4)
        #expect(cloud.logitOpacities.count == 50)
        #expect(cloud.dc.count == 50 * 3)
        
        // Check rotations are unit quaternions
        for i in 0..<50 {
            let x = cloud.rotations[i*4 + 0]
            let y = cloud.rotations[i*4 + 1]
            let z = cloud.rotations[i*4 + 2]
            let w = cloud.rotations[i*4 + 3]
            let norm = sqrt(x*x + y*y + z*z + w*w)
            #expect(abs(norm - 1.0) < 1e-5)
        }
    }
}
