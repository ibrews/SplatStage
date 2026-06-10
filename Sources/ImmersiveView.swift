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
        stageLog.error("STAGE_BEGIN scene=\(choice.rawValue, privacy: .public) cap=\(cap)")
        print("[SplatStage] STAGE_BEGIN scene=\(choice.rawValue) cap=\(cap)")
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
            let entity: Entity
            var mode = "dots"
            #if targetEnvironment(simulator)
            // Beta-1: no GaussianSplat API in the sim SDK — fallback is the only renderer.
            entity = FallbackDotsRenderer.makeEntity(from: cloud)
            #else
            if model.debugDots {
                entity = FallbackDotsRenderer.makeEntity(from: cloud)
            } else {
                let resource = try SplatResourceBuilder.makeResource(from: cloud)
                entity = Entity()
                entity.components.set(GaussianSplatComponent(resource))
                mode = "native"
            }
            #endif
            root.children.forEach { $0.removeFromParent() }
            root.addChild(entity)
            model.loadedCount = cloud.count
            model.lastLoadSeconds = Date().timeIntervalSince(t0)
            model.status = "Live (\(mode))"
            stageLog.error("STAGE_RESULT \(mode, privacy: .public) scene=\(choice.rawValue, privacy: .public) splats=\(cloud.count) loadSeconds=\(String(format: "%.2f", Date().timeIntervalSince(t0)), privacy: .public)")
            print("[SplatStage] STAGE_RESULT \(mode) scene=\(choice.rawValue) splats=\(cloud.count) loadSeconds=\(String(format: "%.2f", Date().timeIntervalSince(t0)))")
        } catch {
            model.status = "Error: \(error)"
            stageLog.error("STAGE_RESULT error=\(String(describing: error), privacy: .public)")
            print("[SplatStage] STAGE_RESULT error=\(error)")
        }
    }
}
