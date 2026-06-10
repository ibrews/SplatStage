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
                Section("Benchmark") {
                    Button(model.benchRunning ? "Sweeping… keep looking around" : "Run cap sweep (fps vs splats)") {
                        Task { await runBenchmark() }
                    }
                    .disabled(model.benchRunning || !spaceOpen)
                    if !model.benchLog.isEmpty {
                        Text(model.benchLog)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("SplatStage v0.1")
        }
        .task { await autoEnterIfRequested() }
    }

    /// Steps the splat cap through the benchmark ladder, letting each load settle,
    /// then samples the EMA fps. Results land in the Benchmark section and in the
    /// console as STAGE_BENCH lines (devicectl --console captures them).
    @MainActor
    private func runBenchmark() async {
        let ladder = [100_000, 200_000, 400_000, 800_000, 1_600_000, 2_700_000]
        model.benchRunning = true
        model.benchLog = "scene: \(model.sceneChoice.rawValue)\n"
        defer { model.benchRunning = false }
        for cap in ladder {
            model.splatCap = cap                       // triggers .task(id:) rebuild
            // wait for the load to finish (status leaves "Loading…"), max 90 s
            for _ in 0..<180 {
                try? await Task.sleep(for: .milliseconds(500))
                if model.status.hasPrefix("Live") || model.status.hasPrefix("Error") { break }
            }
            guard model.status.hasPrefix("Live") else {
                model.benchLog += "\(cap / 1000)k: LOAD FAILED — \(model.status)\n"
                continue
            }
            try? await Task.sleep(for: .seconds(10))   // settle: sort, EMA converge
            let line = "\(cap / 1000)k: \(Int(model.fps.rounded())) fps (loaded \(model.loadedCount), \(String(format: "%.1f", model.lastLoadSeconds))s)"
            model.benchLog += line + "\n"
            print("[SplatStage] STAGE_BENCH \(line)")
        }
        model.benchLog += "done."
    }

    /// Headless verification hook (same pattern as SplatDiorama):
    /// SIMCTL_CHILD_AUTO_ENTER=1 opens the stage without a spatial tap.
    @MainActor
    private func autoEnterIfRequested() async {
        guard ProcessInfo.processInfo.environment["AUTO_ENTER"] == "1", !spaceOpen else { return }
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
