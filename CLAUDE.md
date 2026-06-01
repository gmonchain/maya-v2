# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Maya is a native macOS app that wraps iPhone screen recordings in device frames, adds cinematic zoom
animations, and exports ready-to-share videos. Built with SwiftUI + AppKit + AVFoundation.

## Build & run

### Từ Xcode

```bash
open Maya.xcodeproj   # then ⌘R in Xcode
```

### From terminal (no Xcode GUI needed)

```bash
# Build + run in one command
xcodebuild -project Maya.xcodeproj \
  -scheme Maya -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  MACOSX_DEPLOYMENT_TARGET=26.2 \
  build && open .build/Build/Products/Debug/Maya.app
```

The `CODE_SIGN_*` flags skip code signing (needed if you don't have a Developer certificate).
`MACOSX_DEPLOYMENT_TARGET=26.2` works around the project targeting 26.3 while the SDK caps at 26.2.

### Auto build + run on file save (terminal-style hot reload)

Install `watchexec`:

```bash
brew install watchexec
```

Then run from the project root:

```bash
watchexec -w Maya/ -e swift -- \
  'pkill -f Maya 2>/dev/null; xcodebuild -project Maya.xcodeproj -scheme Maya -configuration Debug -derivedDataPath .build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.2 build 2>&1 | grep -E "error:|warning:|BUILD|Build succeeded" && open .build/Build/Products/Debug/Maya.app'
```

Save any `.swift` file and the app rebuilds + relaunches automatically — see UI changes without touching Xcode.

Requires **macOS 26.3 (Tahoe)** or later and **Xcode 26.5** or later.

## Release

```bash
# Local (one-time: create notary keychain profile + brew install create-dmg)
NOTARY_PROFILE=maya-notary ./scripts/build-release.sh

# CI: push a version tag → .github/workflows/release.yml builds, signs, notarizes, publishes
git tag v1.0.0 && git push origin v1.0.0
```

`MARKETING_VERSION` in the Xcode project must match the git tag. The website in `docs/` is served
via GitHub Pages from `/docs` on `main`.

## Architecture

### State management

`Maya/Models/Project.swift` — central `@Observable` class that owns ALL mutable state:
video, player, scale/offset, device selection, background, shadow, animations array,
trim points, export progress. Views bind directly to it via `@Bindable var project`.

No view models, no separate state stores. The `Project` object is created once in
`EditorView` (`@State private var project = Project()`) and passed down the view tree.

### View hierarchy

```
EditorView (NavigationSplitView)
├── sidebar: SettingsSidebar          — recording, canvas, device, transform, background, shadow, export
├── detail: HStack
│   ├── VStack
│   │   ├── CanvasView                — aspect-fitted canvas with FramedDeviceView + BackgroundView
│   │   └── TimelineView              — ruler + animations track + video strip + playhead
│   └── AnimationEditorPanel (conditional, 340pt) — right panel for selected zoom event
```

### Export pipeline (two paths)

1. **With background** (`.mp4` H.264): `AVMutableComposition` → `AVAssetExportSession` with custom
   `DeviceFrameCompositor` (per-frame compositing via Core Image + Metal).
2. **Transparent** (`.mov` HEVC + alpha): `AVAssetReader` + `AVAssetWriter` manual pipeline
   because `AVAssetExportSession` can't write alpha.

Both paths share `DeviceFrameCompositionInstruction` and `DeviceFrameCompositor`.

### Key services (`Maya/Services/`)

| File | Role |
|---|---|
| `DeviceFrameCompositor.swift` | Custom `AVVideoCompositing` — renders every frame: background → shadow → masked video → bezel → frame overlay |
| `ExportService.swift` | Actor that orchestrates exports, builds `Snapshot` from `Project` on `@MainActor` |
| `AnimationSampler.swift` | Stateless envelope math — given time + segments → effective scale/offset. Used by both preview and compositor |
| `BlurPosterCache.swift` | Actor that generates/caches a blurred + darkened poster frame for the video-blur background |
| `VideoThumbnailGenerator.swift` | Actor that generates timeline thumbnails via `AVAssetImageGenerator` |

### Sandbox file adoption

The app is sandboxed (`App Sandbox` capability). Videos from drag-drop or `NSOpenPanel` are
hard-linked (or copied) into `~/Library/Caches/VideoSources/<UUID>-<name>` on load via
`Project.adoptIntoSandbox(_:)`. All subsequent AVFoundation reads use the sandbox-local copy.

### Timeline coordinate system

The timeline has two coordinate spaces:
- **Source time**: absolute position in the original video file. Animations are stored in source coords.
- **Timeline time**: position on the project timeline (clip can be shifted independently of trim).

`Project.timelineToSource(_:)` and `sourceToTimeline(_:)` convert between them.

### Keyboard shortcuts

Hidden `Button` views with `.opacity(0)` in `EditorView` — macOS routes keys to first responder
first, so text fields still work. Space, M, ←/→, ⇧←/⇧→, ⌫, ⌘D, I/O/⌥⌫ (trim marks).

## Code organization rules

- **Không để một file code quá lớn.** Khi một file bắt đầu dài và khó theo dõi (khoảng trên 300-400 dòng), hãy tách nó thành các file nhỏ hơn và đặt vào folder hợp lý. Ví dụ: tách `TimelineView.swift` ban đầu ra thành folder `Views/Timeline/` chứa `TimelineView.swift`, `TimeRuler`, `AnimationsTrack.swift`, `VideoThumbnailStrip.swift`, `TrimmableVideoClip.swift`.
- Mỗi file/view nên có một trách nhiệm duy nhất (single responsibility).
- Models để trong `Models/`, services trong `Services/`, views trong `Views/`. Nếu một view có nhiều subview phức tạp, tạo subfolder trong `Views/`.

## Adding new device frames

1. Drop transparent-screen PNG(s) into `Maya/Assets.xcassets/iphone frames/` (one imageset per color).
2. Add a `DeviceModel` static in `Maya/Models/DeviceFrame.swift` with frame aspect, normalized screen rect, corner radius, and `DeviceColor` entries.
3. Append to `DeviceModel.all`.

The compositor and preview both read from `DeviceFrame.screenRectNormalized` — coordinates are
top-left origin, normalized to the PNG dimensions.

## Common patterns

- `@Observable` for the `Project` class (not `@ObservableObject`/`@StateObject`).
- Actors (`ExportService`, `BlurPosterCache`, `VideoThumbnailGenerator`) for concurrency safety.
- `nonisolated(unsafe)` on stored properties of `@unchecked Sendable` classes that are guarded by
  queue confinement or locks (e.g., `DeviceFrameCompositionInstruction`, `ContinuationGuard`).
- `Color(hex:)` / `.hexString` / `.ciColor` extensions on `Color` for hex ↔ NSColor/CIcolor bridging.
- `NSViewRepresentable` for wrapping `AVPlayerLayer` (SwiftUI has no native video layer).
- `Bundle.main.url(forResource:)` for bundled preset preview `.mp4` files.
- `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` for user-chosen
  files outside the sandbox; paired with `defer` for cleanup.
