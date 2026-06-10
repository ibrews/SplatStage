import SwiftUI

struct ControlsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var spaceOpen = false

    private let caps = [100_000, 200_000, 400_000, 800_000, 1_600_000, 2_700_000]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Stage") {
                    Picker("Scene", selection: $model.sceneChoice) {
                        ForEach(AppModel.SceneChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Splat cap", selection: $model.splatCap) {
                        ForEach(caps, id: \.self) { Text("\($0 / 1000)k").tag($0) }
                    }
                    Button(spaceOpen ? "Leave Stage" : "Enter Stage") {
                        Task {
                            if spaceOpen {
                                await dismissImmersiveSpace()
                                spaceOpen = false
                            } else {
                                let result = await openImmersiveSpace(id: "stage")
                                spaceOpen = (result == .opened)
                            }
                        }
                    }
                }
                Section("Placement") {
                    LabeledContent("Scale: \(model.worldScale, specifier: "%.2f")×") {
                        Slider(value: $model.worldScale, in: 0.1...4)
                    }
                    LabeledContent("Height: \(model.heightOffset, specifier: "%.2f") m") {
                        Slider(value: $model.heightOffset, in: -3...3)
                    }
                    Picker("Up axis", selection: $model.upMode) {
                        Text("0 identity").tag(0)
                        Text("1 π@X (3DGS)").tag(1)
                        Text("2 π@Z").tag(2)
                        Text("3 -π/2@X").tag(3)
                    }
                    #if !targetEnvironment(simulator)
                    Toggle("Debug dots (fallback renderer)", isOn: $model.debugDots)
                    Toggle("Chunked (3σ-cull workaround)", isOn: $model.chunked)
                    Picker("Chunk grid", selection: $model.chunkGrid) {
                        Text("2³").tag(2); Text("4³").tag(4); Text("6³").tag(6); Text("8³").tag(8)
                    }
                    Picker("Sorting", selection: $model.sortMode) {
                        Text("depth").tag(0); Text("distance").tag(1)
                    }
                    Picker("Projection", selection: $model.projMode) {
                        Text("perspective").tag(0); Text("tangential").tag(1)
                    }
                    #endif
                }
                Section("Telemetry") {
                    LabeledContent("Status", value: model.status)
                    LabeledContent("Splats live", value: "\(model.loadedCount)")
                    LabeledContent("Load time", value: String(format: "%.1f s", model.lastLoadSeconds))
                    LabeledContent("FPS (EMA)", value: String(format: "%.0f", model.fps))
                }
            }
            .navigationTitle("SplatStage v0.1")
        }
        .task {
            // Headless verification hook (same pattern as SplatDiorama):
            // SIMCTL_CHILD_AUTO_ENTER=1 opens the stage without a spatial tap.
            if ProcessInfo.processInfo.environment["AUTO_ENTER"] == "1", !spaceOpen {
                if let scene = ProcessInfo.processInfo.environment["AUTO_SCENE"],
                   let choice = AppModel.SceneChoice.allCases.first(where: { $0.rawValue.hasPrefix(scene) }) {
                    model.sceneChoice = choice
                }
                if let capStr = ProcessInfo.processInfo.environment["AUTO_CAP"], let cap = Int(capStr) {
                    model.splatCap = cap
                }
                let result = await openImmersiveSpace(id: "stage")
                spaceOpen = (result == .opened)
            }
        }
    }
}
