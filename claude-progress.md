# SplatStage — progress

## Current state (2026-06-10 overnight, v0.1 build 4)
- DEVICE: native path renders GEOMETRY but no color — "passthrough material" look
  (shape only visible against a window). Build 4 = the authoritative config: raw 3DGS
  values + .exponential/.sigmoid + raw f_dc + **explicit colorSpace = sRGB** (was never
  set before; renderer binary shows the color stage is gated on it). NOT yet user-verified.
- NEW: **FallbackDotsRenderer** — color-bucketed unlit crossed-quads, no GaussianSplat
  API. Always-on in sim; device toggle "Debug dots" in Controls → Placement.
- SIM VERIFIED (screenshots): synthetic shell = direction-keyed color gradient ✓;
  train PLY = sky blues + warm train speckle, parse/recenter/colors all sane ✓.
- Morning A/B on device: dots ON = colored scene? then data is good and any remaining
  native failure is GaussianSplatResource config. Dots OFF = test build-4 colorSpace fix.

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
- **Build 2 misdiagnosis: "beta-1 ignores activation properties" was WRONG.** Pre-applying
  exp/sigmoid on CPU + .identity (build 2) and pre-converting DC→RGB into the SH buffer
  (build 3) both still rendered as colorless "passthrough." Ground truth came from
  demangling /System/Library/PrivateFrameworks/AppleSplatRendering.framework symbols:
  `apple3dgs::TransformGaussians(…ActivationType…)` and `apple3dgs::ComputeColorFromSH(…)`
  exist — the renderer DOES apply activations and DOES evaluate SH internally (wants raw
  f_dc). The color stage linearizes via `GetColorPropertiesFromCGColorSpace(colorSpace)` →
  `ToLinearColorSpace` — the missing piece was never setting `resource.colorSpace`.
  Key reasoning: zero SH would render mid-gray (0.5), not transparent ⇒ "passthrough" =
  near-zero ALPHA ⇒ opacity/colorSpace stage, not a DC-value convention problem.
- **Native splat render is impossible OFF-device in beta 1, fully verified:** sim SDK 0
  symbols, macOS 27 SDK 0 symbols, iOS 27 SDK 0 symbols; macOS 27.0 runtime (this MBP!)
  exports only an internal `_proto_SplatComponent` (ABI-only, in no swiftinterface — not
  practically bindable). Hence FallbackDotsRenderer for sim verification.
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
