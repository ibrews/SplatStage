# SplatStage — needs Alex

## ~~☀️ MORNING TEST~~ ✅ DONE 2026-06-10 — splats working; benchmark is next

## (was) MORNING TEST (2026-06-10, build 4 already installed on AVP)

Two-step A/B, ~3 minutes, synthetic scene @ **100k cap**:

1. **Dots first:** Controls → Placement → turn ON "Debug dots (fallback renderer)" →
   Enter Stage. You should see a colored gradient wall of small squares all around you
   (sim-verified tonight, screenshot in /tmp/splatstage_sim_synthetic.png).
   - If YES → parser/colors/transform are all good; any native problem is resource config.
   - If NO → something device-side is wrong beyond the splat API; tell me what you see.
2. **Native:** toggle dots OFF (stage rebuilds automatically). Build 4 adds the missing
   `colorSpace = sRGB` (renderer binary gates its color stage on it) and returns to raw
   values + real .exponential/.sigmoid activations.
   - Colored shell → FIXED, I'll benchmark and write it up.
   - Still passthrough-ghost → report; next probes are queued (opacity float4 stride,
     premultiplied DC, .perspective projection, sortingMode).


1. **Install visionOS 27 beta 1 on your Vision Pro?** The native splat renderer is
   device-only in beta 1 (sim SDK lacks the API entirely). Everything is staged for the
   moment the device is on 27: `xcodegen generate && build for device && install`.
   Risk: beta 1 on your primary demo headset the week of NY Tech Week — your call.
   (Alternative: wait for beta 2 to hopefully add sim support; HISTORICALLY sim gaps
   like this often close by beta 2-3.)
2. **Quat order + DC color convention** are assumptions (x,y,z,w; 0.282·dc+0.5) —
   10-minute on-device check with the synthetic shell scene, then I'll lock them in.
3. **Repo push to github.com/ibrews/SplatStage?** README/gitignore ready; splats are
   gitignored (144MB). Say go and it ships.
