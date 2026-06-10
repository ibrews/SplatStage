import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
    enum SceneChoice: String, CaseIterable, Identifiable {
        case synthetic = "Synthetic shell"
        case train = "Train (2.7M)"
        var id: String { rawValue }
    }

    var sceneChoice: SceneChoice = .synthetic
    /// Max splats uploaded (importance-pruned above this). The benchmark lever.
    var splatCap: Int = 400_000
    var worldScale: Float = 1.0
    var heightOffset: Float = 0.0
    /// Up-axis calibration, same convention as SplatDiorama:
    /// 0 = identity, 1 = π about X (typical 3DGS y-down fix), 2 = π about Z, 3 = -π/2 about X
    var upMode: Int = 1

    // Read-only status surfaced to the controls window.
    private(set) var fps: Double = 0
    var loadedCount: Int = 0
    var status: String = "Idle"
    var lastLoadSeconds: Double = 0

    var reloadKey: String { "\(sceneChoice.rawValue)|\(splatCap)" }

    private var emaFPS: Double = 0
    func tickFPS(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        let inst = 1.0 / deltaTime
        emaFPS = emaFPS == 0 ? inst : (emaFPS * 0.95 + inst * 0.05)
        // Avoid hammering SwiftUI: publish at coarse granularity.
        if abs(emaFPS - fps) > 0.5 { fps = emaFPS }
    }

    static func upQuat(_ mode: Int) -> simd_quatf {
        switch mode {
        case 1: return simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        case 2: return simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1))
        case 3: return simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        default: return simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        }
    }
}
