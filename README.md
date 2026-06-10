# SplatStage

Stand **inside** a photoreal Gaussian-splat environment on Apple Vision Pro, rendered by
**visionOS 27's native RealityKit splat API** (`GaussianSplatComponent`) — then light it
like a film set with the new cinematic RealityKit stack (projective-texture spotlights,
soft shadows, ray-traced reverb meshes).

Built the day after WWDC 2026 against Xcode 27 beta 1. Sibling of
[SplatDiorama](../SplatDiorama) (MetalSplatter-based walk-around dioramas); SplatStage is
the walk-*inside*, native-API counterpart and the A/B benchmark vehicle:

| Renderer | 90 fps budget (AVP M2, measured in SplatDiorama) |
|---|---|
| MetalSplatter (custom CompositorServices Metal) | ~400–450k splats |
| RealityKit `GaussianSplatComponent` (native) | **TBD — the experiment** |

## Status / known beta-1 gaps

- ✅ App builds for visionOS 27 **simulator** (stub) and **device** (full native path).
- ⚠️ **`GaussianSplatResource`/`GaussianSplatComponent` are DEVICE-ONLY in beta 1** —
  the simulator SDK contains zero GaussianSplat symbols in any framework. The sim build
  parses/prunes and reports telemetry but cannot render splats natively.
- Raw 3DGS `.ply` values are uploaded unmodified; the renderer applies
  `scaleActivation=.exponential` and `opacityActivation=.sigmoid`.
- Open empirical questions (need device): quaternion component order (we upload
  normalized x,y,z,w), SH DC color convention (0.2820948·dc+0.5 assumed), and whether
  `bytesUsed`/`withUnsafeMutableBytes` is the correct LowLevelBuffer fill for static data.

## Quickstart

```bash
brew install xcodegen   # if needed
cd SplatStage
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild -project SplatStage.xcodeproj \
  -scheme SplatStage -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=27.0' build
```

Splat data: drop a standard 3DGS `.ply` (fields `x,y,z,f_dc_0..2,opacity,scale_0..2,rot_0..3`)
into `Resources/Splats/` (gitignored; `entire-train.ply` — 2.7M splats — is the dev scene).

## Things to Try

1. **Headless sim verification:** build, install, then
   `SIMCTL_CHILD_AUTO_ENTER=1 SIMCTL_CHILD_AUTO_SCENE="Train" SIMCTL_CHILD_AUTO_CAP=400000 xcrun simctl launch <udid> com.ibrews.SplatStage`
   — watch `log show --predicate 'subsystem == "com.ibrews.SplatStage"'` for `STAGE_RESULT`.
2. **Synthetic shell:** pick "Synthetic shell" in the controls — a rainbow splat sphere
   around the viewer; first thing to look at on device (validates API + color convention
   with zero parser risk).
3. **Walk the train:** on a visionOS 27 device, scene "Train (2.7M)", cap 400k → 2.7M,
   and watch the FPS readout — this is the MetalSplatter-vs-native benchmark.
4. **Up-axis calibration:** if the scene is sideways/upside-down, cycle "Up axis"
   (mode 1 = the usual 3DGS y-down fix).
5. **Importance pruning:** drop the cap to 100k and note which splats survive —
   highest opacity×scale first (same pruning insight as SplatDiorama).

## Credits

Built by Alex Coulombe ([ibrews](https://github.com/ibrews)). Native splat API surface
documented in the Agile Lens KB: `intelligence/techniques/realitykit-gaussian-splat-api-visionos27.md`.
