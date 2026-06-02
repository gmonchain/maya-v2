# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/

# Communication
- Respond in Vietnamese when the user communicates in Vietnamese. Confidence: 0.80

# SwiftUI
- For icon-only buttons, use a custom `.hoverLabel()` modifier (overlay tooltip on hover) instead of `.help()` for immediate, styled hover labels. Confidence: 0.80
- Apply transition animation effects to both the video playback AND the device mockup preview — both elements should animate together. Confidence: 0.80
- For editor panels (e.g. TransitionPanel), follow the AnimationEditorPanel design pattern: presets grid, customize toggle button, collapsible parameter sections (timing, intensity, curve, direction), and actions section. Confidence: 0.65
- When creating ViewModifiers with many chained `.onChange()` calls (20+), split them into multiple smaller ViewModifiers to avoid compiler type-check timeout errors. Confidence: 0.75

# Architecture
- Separate save/load serialization logic into its own dedicated file, so when adding new features the serialization can be easily audited and updated. Confidence: 0.85

# Workflow
- When user asks to "mở app" (open app), build the app with xcodebuild (CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO) and run the built .app — don't just open the Xcode project. Confidence: 0.75
