import SwiftUI
import RealityKit
import os

private let stageLog = Logger(subsystem: "com.ibrews.SplatStage", category: "stage")

struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @State private var root = Entity()
    @State private var subscriptions: [EventSubscription] = []

    var body: some View {
        RealityView { content in
            content.add(root)
            let sub = content.subscribe(to: SceneEvents.Update.self) { event in
                Task { @MainActor in
                    model.tickFPS(deltaTime: event.deltaTime)
                }
            }
            subscriptions.append(sub)
        } update: { _ in
            // Runs on observed-state change: live transform without rebuilds.
            root.transform = Transform(
                scale: SIMD3(repeating: model.worldScale),
                rotation: AppModel.upQuat(model.upMode),
                translation: SIMD3(0, model.heightOffset, 0)
            )
        }
        .task(id: model.reloadKey) {
            await rebuild()
        }
    }

    @MainActor
    private func rebuild() async {
        let choice = model.sceneChoice
        let cap = model.splatCap
        model.status = "Loading \(choice.rawValue)…"
        let t0 = Date()
        do {
            let cloud: SplatCloud
            switch choice {
            case .synthetic:
                let n = min(cap, 500_000)
                cloud = await Task.detached(priority: .userInitiated) {
                    SplatCloud.synthetic(count: n)
                }.value
            case .train:
                guard let url = Bundle.main.url(forResource: "entire-train", withExtension: "ply",
                                                subdirectory: "Splats") else {
                    model.status = "Error: entire-train.ply not in bundle"
                    return
                }
                cloud = try await Task.detached(priority: .userInitiated) {
                    try SplatPLY.parse(url: url, cap: cap)
                }.value
            }
            guard choice == model.sceneChoice, cap == model.splatCap else { return } // stale
            #if targetEnvironment(simulator)
            // Beta-1: no GaussianSplat API in the sim SDK. Parse/prune still runs
            // (validates the loader + telemetry); rendering needs the device.
            root.children.forEach { $0.removeFromParent() }
            model.loadedCount = cloud.count
            model.lastLoadSeconds = Date().timeIntervalSince(t0)
            model.status = "Parsed OK — native splat render is DEVICE-ONLY in visionOS 27 beta 1"
            stageLog.info("STAGE_RESULT sim-stub scene=\(choice.rawValue, privacy: .public) splats=\(cloud.count) loadSeconds=\(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)")
            #else
            let resource = try SplatResourceBuilder.makeResource(from: cloud)
            let entity = Entity()
            entity.components.set(GaussianSplatComponent(resource))
            root.children.forEach { $0.removeFromParent() }
            root.addChild(entity)
            model.loadedCount = cloud.count
            model.lastLoadSeconds = Date().timeIntervalSince(t0)
            model.status = "Live"
            stageLog.info("STAGE_RESULT native scene=\(choice.rawValue, privacy: .public) splats=\(cloud.count) loadSeconds=\(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)")
            #endif
        } catch {
            model.status = "Error: \(error)"
            stageLog.error("STAGE_RESULT error=\(String(describing: error), privacy: .public)")
        }
    }
}
