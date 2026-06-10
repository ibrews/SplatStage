# SplatStage — needs Alex

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
