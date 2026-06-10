# SplatStage — progress

## Current state (2026-06-09, v0.1 build 1)
- Scaffolded day-after-WWDC26. visionOS 27 only.
- Sim build ✅ (stubbed render), device-SDK compile ✅ (full native GaussianSplat path).
- visionOS 27 sim launch ✅ — controls window live, AUTO_ENTER/AUTO_SCENE/AUTO_CAP env
  hooks work, 2.7M-splat PLY parse running in sim (STAGE_RESULT os_log line is the proof).

## Architecture
- xcodegen `project.yml`; Sources/: App, AppModel (@Observable), ControlsView,
  ImmersiveView (RealityView + .task(id:) rebuild), SplatPLY (minimal 3DGS binary-LE
  parser + median recenter + importance prune), SplatResourceBuilder (LowLevelBuffer →
  GaussianSplatResource, device-only #if).
- Raw .ply encodings uploaded; .exponential/.sigmoid activations do the decode in-renderer.
- Immersion: .mixed (proven path; splat surround occludes passthrough on its own).

## Failed approaches / gotchas
- **Simulator SDK has NO GaussianSplat symbols (beta 1)** — first build failed
  "cannot find type"; the API is device-SDK only. Confirmed by sweeping every
  framework swiftinterface in XRSimulator27.0.sdk. → #if targetEnvironment(simulator)
  stub. Do NOT burn time hunting imports/modules — it's genuinely absent.
- venue_full.ply is a trimesh POINT CLOUD (x,y,z,rgba uchar), not 3DGS — unusable here.
- Post Oak Suite .compressed.ply is PlayCanvas splat-transform packed format (chunk +
  packed uints) — needs decompression (splat-transform CLI) before our parser can read it.

## Next steps
1. Device run (needs visionOS 27 beta on Alex's AVP — see REVIEW_NEEDED.md).
2. On device: synthetic shell first (color/quat conventions), then train benchmark
   (fps vs cap: 100k/400k/800k/1.6M/2.7M) vs SplatDiorama MetalSplatter baseline.
3. Cinematic pass: SpotLightComponent.ProjectiveTexture + Shadow.lightSize +
   ReverbMeshResource (+ SurroundingsLight demo moment in mixed mode).
4. SH degree >0: extend parser for f_rest_* once a degree-3 scene matters.
5. Decide repo push (ibrews) — README is ready.
