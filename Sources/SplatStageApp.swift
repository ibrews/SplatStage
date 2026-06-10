import SwiftUI

@main
struct SplatStageApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ControlsView()
                .environment(model)
        }
        .defaultSize(width: 480, height: 640)

        ImmersiveSpace(id: "stage") {
            ImmersiveView()
                .environment(model)
        }
        // .mixed is the proven path on device (see KB:
        // visionos-colored-immersive-background-mixed-not-full). The splat
        // environment surrounds the viewer and occludes passthrough on its own.
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
