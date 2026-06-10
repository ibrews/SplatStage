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

- ✅ App builds for visionOS 27 **simulator** (fallback renderer) and **device** (native path).
- ⚠️ **`GaussianSplatResource`/`GaussianSplatComponent` are DEVICE-ONLY in beta 1** —
  zero GaussianSplat symbols in the simulator, macOS 27, and iOS 27 SDKs (macOS 27's
  runtime carries only an unbindable internal `_proto_SplatComponent`). Verified by
  SDK swiftinterface sweeps + dyld export dumps.
- 🟦 **Fallback dots renderer** (`FallbackDotsRenderer`): the same `SplatCloud` drawn as
  color-bucketed unlit crossed-quads — always used in the simulator, and available on
  device via the "Debug dots" toggle. It's the A/B probe that separates "our data is
  wrong" from "the native resource config is wrong."
- ✅ **Device-verified working** (2026-06-10): synthetic shell + Tanks-and-Temples Train
  render correctly on AVP. The five load-bearing rules (full recipe in the KB technique
  doc § "DEVICE-PROVEN RECIPE"):
  1. Raw 3DGS values + `.exponential`/`.sigmoid` activations; raw `f_dc` SH (degree 0).
  2. `resource.colorSpace = sRGB` — mandatory, else colorless "passthrough ghost."
  3. Rotation buffer is **w-first** (`w,x,y,z` as in the PLY), normalized.
  4. Buffer capacities padded to **256-byte multiples** (16-byte passes validation but
     renders scrambled).
  5. **Spatial-grid chunking** — beta-1 culls a whole entity once the camera is within
     ~3× its bounding radius (3σ kernel support), so walk-inside scenes must be split
     (4³ grid, runt cells folded). Bonus: also bypasses the ~200k per-resource limit.
- Open empirical question: the `f_rest_*` SH layout above degree zero.

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
   **In the simulator** this renders via the fallback dots automatically — you should see
   a direction-keyed color gradient surrounding the camera.
3. **Walk the train:** on a visionOS 27 device, scene "Train (2.7M)", cap 400k → 2.7M,
   and watch the FPS readout — this is the MetalSplatter-vs-native benchmark.
4. **Up-axis calibration:** if the scene is sideways/upside-down, cycle "Up axis"
   (mode 1 = the usual 3DGS y-down fix).
5. **Importance pruning:** drop the cap to 100k and note which splats survive —
   highest opacity×scale first (same pruning insight as SplatDiorama).

## Credits

Built by Alex Coulombe ([ibrews](https://github.com/ibrews)). Native splat API surface
documented in the Agile Lens KB: `intelligence/techniques/realitykit-gaussian-splat-api-visionos27.md`.
