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
    /// Render via FallbackDotsRenderer (unlit quads) instead of GaussianSplatComponent.
    /// Forced on in the Simulator (native splat API is device-only in beta 1); on device
    /// it's the A/B probe — dots OK + native invisible ⇒ resource config bug, not data.
    #if targetEnvironment(simulator)
    var debugDots: Bool = true
    #else
    var debugDots: Bool = false
    #endif
    /// Spatial-grid chunking — beta-1 workaround for whole-entity 3σ-bounds culling
    /// (entity vanishes when the camera is within ~3× cloud radius of its center).
    var chunked: Bool = true
    /// Grid resolution per axis when chunked (g³ max cells).
    var chunkGrid: Int = 4
    /// 0 = .depth (zDepth), 1 = .distance (cameraDistance)
    var sortMode: Int = 0
    /// 0 = .perspective, 1 = .tangential
    var projMode: Int = 0

    // Read-only status surfaced to the controls window.
    private(set) var fps: Double = 0
    var loadedCount: Int = 0
    var status: String = "Idle"
    var lastLoadSeconds: Double = 0

    // Benchmark sweep (fps vs cap — the SplatDiorama/MetalSplatter A/B).
    var benchRunning = false
    var benchLog = ""

    var reloadKey: String {
        "\(sceneChoice.rawValue)|\(splatCap)|\(debugDots)|\(chunked)|\(chunkGrid)|\(sortMode)|\(projMode)"
    }

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
