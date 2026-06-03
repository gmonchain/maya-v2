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

### View hierarchy

```
EditorView (NavigationSplitView)
├── sidebar: SettingsSidebar          — recording, canvas, device, transform, background, shadow, export
├── detail: HStack
│   ├── VStack
│   │   ├── CanvasView                — aspect-fitted canvas with FramedDeviceView + BackgroundView
│   │   └── TimelineView              — ruler + animations track + video strip + playhead
│   ├── AnimationEditorPanel (conditional, 340pt) — right panel for selected zoom event
│   └── TransitionPanel (conditional, 340pt)   — right panel for selected transition
```

### State management: the `Project` class (`Maya/Models/Project.swift`)

`@Observable` class that owns ALL mutable state. Created once in `EditorView` via
`@State private var project = Project()` and passed down the view tree. No view models.

Key state groups:
- **Video**: `videoURL`, `player` (AVPlayer), `videoNaturalSize`, `videoDuration`, `currentSeconds`
- **Canvas**: `scale`, `offset`, `canvasAspect` (1:1, 9:16, etc.), `background` (solid/gradient/image/video/videoBlur/none), `shadow`
- **Device**: `deviceModelID`, `deviceColorID` (resolved to `DeviceFrame` via computed `deviceFrame`)
- **Clips** (multi-clip editing): `clips: [VideoClip]`, `activeClipID`, `allowClipOverlap`, `trackCount`
  - Each `VideoClip` has `trimStartTime`, `trimEndTime`, `timelineStart`, `trackIndex`, `speed` (playback rate)
  - Clips on the same track cannot overlap (unless `allowClipOverlap` is true)
  - Split at playhead (`⌘S`), delete clip, ripple-edit on same track
- **Animations**: `animations: [ZoomSegment]`, `selectedAnimationID`
- **Transitions** (between clips): `transitions: [Transition]`, `selectedTransitionID`
- **Audio**: `audioClips: [AudioClip]`, per-clip volume/mute, live sync with main player
- **Export**: `exportQuality` (Standard/High/Ultra), `exportRenderSize` (1080p/1440p/4K), progress/error
- **Timeline viewport**: `timelineZoom` (0.1–20×), `timelineScrollOffset` (px)
- **Undo/Redo**: `undoStack` / `redoStack` of `ProjectSnapshot` (max 40 deep)

### Multi-clip editing

The timeline supports splitting a video into multiple `VideoClip` segments, each with independent
trim points and timeline position. Clips can be placed on separate tracks (rows). Key operations:

- **Split** (`S` or `⌘S` in timeline): `Project.splitAtPlayhead()` — splits active clip at playhead
- **Delete clip** (`⌫` when clip selected): `Project.deleteActiveClip()` — ripple-deletes, closing gap
- **Snap**: `Project.snapClipPosition(_:duration:excludingClipAt:)` — snaps to adjacent clip edges
  within 0.3s threshold, prevents overlap on same track
- **Coordinate mapping**: `VideoClip.timelineToSource(_:)` / `sourceToTimeline(_:)` account for `speed`

### Timeline coordinate system

Three coordinate spaces:
- **Source time**: absolute position in the original video file. Animations are stored in source coords.
- **Timeline time**: position on the project timeline. Clips can be shifted independently of trim.
- **Composition time**: used during export — clips placed at their `timelineStart` in the composition.

`Project.timelineToSource(_:)` and `sourceToTimeline(_:)` convert between source and timeline.
`ExportService.animationsForComposition(_:clips:)` maps animations to composition time for export.

### Export pipeline (two paths)

1. **With background** (`.mp4` H.264): `AVMutableComposition` → `AVAssetExportSession` with custom
   `DeviceFrameCompositor` (per-frame compositing via Core Image + Metal).
   - `ExportBackgroundPipeline.swift` builds the composition (multi-clip, multi-track, background video loop, audio passthrough + extra audio clips with volume)
   - Backgrounds: solid/gradient rendered via CIFilter, image scale-to-fill, video looped behind main content, videoBlur via cached poster
   - Export quality controls: preset (`AVAssetExportPresetMediumQuality` / `HighestQuality`), optional bitrate
2. **Transparent** (`.mov` HEVC + alpha): `AVAssetReader` + `AVAssetWriter` manual pipeline
   because `AVAssetExportSession` can't write alpha.
   - `ExportTransparentPipeline.swift` — identical composition build + manual frame pump via `AVAssetWriterInputPixelBufferAdaptor`
   - HEVC+alpha via `kVTCompressionPropertyKey_AlphaChannelMode`, bitrate scaled by pixel count relative to 1080p

Both paths share `DeviceFrameCompositionInstruction` and `DeviceFrameCompositor`.

### Project persistence (`.mayaproj`)

Projects save as macOS packages (directories) containing:
- `project.json` — all editing state serialized via `MayaProjectFile` (Codable)
- `media/` — copies of video, audio, background image, and background video files

- `ProjectService.swift` — save/load logic, atomic save (write to temp → replace)
- `ProjectStateManager.swift` — `@Observable` class tracking `projectURL`, `hasUnsavedChanges`, dirty tracking via `ProjectChangeTracker` modifiers (split into two to avoid compiler timeout)
- `RecentProjectsStore.swift` — persists recent project URLs
- Auto-save every 5 seconds when a save location exists and project is dirty
- Menu commands: File > New/Open/Save via `NotificationCenter` (`MayaApp.swift`)
- `MayaProjectFile.toProjectFile()` / `loadFromProjectFile(_:videoURL:audioURLs:imageURLs:backgroundVideoURLs:)` on `Project` extension

### Key services (`Maya/Services/`)

| File | Role |
|---|---|
| `DeviceFrameCompositor.swift` | Custom `AVVideoCompositing` — renders every frame: background → shadow → masked video → bezel → frame overlay |
| `ExportService.swift` | Actor that orchestrates exports, builds `Snapshot` from `Project` on `@MainActor`, maps animations to composition time |
| `ExportBackgroundPipeline.swift` | Builds composition for .mp4 export — multi-clip, multi-track, background video loop, audio mix with volume |
| `ExportTransparentPipeline.swift` | Manual AVAssetReader→AVAssetWriter pipeline for HEVC+alpha .mov — frame pump with pixel buffer adaptor |
| `AnimationSampler.swift` | Stateless envelope math — given time + segments → effective scale/offset. Used by both preview and compositor |
| `BlurPosterCache.swift` | Actor that generates/caches a blurred + darkened poster frame for the video-blur background |
| `VideoThumbnailGenerator.swift` | Actor that generates timeline thumbnails via `AVAssetImageGenerator` |
| `ProjectService.swift` | Save/load `.mayaproj` project bundles (atomic temp-dir → replace) |
| `ProjectStateManager.swift` | `@Observable` dirty-state + save/open panel logic, `ProjectChangeTracker` view modifiers |

### Sandbox file adoption

The app is sandboxed (`App Sandbox` capability). Videos from drag-drop or `NSOpenPanel` are
hard-linked (or copied) into `~/Library/Caches/VideoSources/<UUID>-<name>` on load via
`SandboxHelper.adoptIntoSandbox(_:)`. All subsequent AVFoundation reads use the sandbox-local copy.

### Keyboard shortcuts

Hidden `Button` views with `.opacity(0)` in `EditorView` — macOS routes keys to first responder
first, so text fields still work.

| Key | Action |
|---|---|
| <kbd>Space</kbd> | Play / pause |
| <kbd>M</kbd> | Mute / unmute |
| <kbd>←</kbd> / <kbd>→</kbd> | Scrub ±0.25 s |
| <kbd>⇧</kbd>+<kbd>←</kbd> / <kbd>⇧</kbd>+<kbd>→</kbd> | Scrub ±1 s |
| <kbd>⌫</kbd> | Delete selected zoom event (or active clip if no animation selected) |
| <kbd>⌘</kbd>+<kbd>D</kbd> | Duplicate selected zoom event |
| <kbd>⌘</kbd>+<kbd>Z</kbd> | Undo |
| <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>Z</kbd> | Redo |
| <kbd>I</kbd> / <kbd>O</kbd> | Mark trim in/out at playhead |
| <kbd>⌥</kbd>+<kbd>⌫</kbd> | Reset trim |
| <kbd>S</kbd> | Split clip at playhead |
| <kbd>⌘</kbd>+<kbd>N</kbd> / <kbd>⌘</kbd>+<kbd>O</kbd> / <kbd>⌘</kbd>+<kbd>S</kbd> | File menu: New / Open / Save project |

## Code organization rules

- **Không để một file code quá lớn.** Khi một file bắt đầu dài và khó theo dõi (khoảng trên 300-400 dòng), hãy tách nó thành các file nhỏ hơn và đặt vào folder hợp lý.
- Mỗi file/view nên có một trách nhiệm duy nhất (single responsibility).
- Models để trong `Models/`, services trong `Services/`, views trong `Views/`. Nếu một view có nhiều subview phức tạp, tạo subfolder trong `Views/`.
- `Project` extensions for related functionality go in `Project+*.swift` files (e.g., `Project+Clips.swift`, `Project+Undo.swift`).

## Adding new device frames

1. Drop transparent-screen PNG(s) into `Maya/Assets.xcassets/iphone frames/` (one imageset per color).
2. Add a `DeviceModel` static in `Maya/Models/DeviceFrame.swift` with frame aspect, normalized screen rect, corner radius, and `DeviceColor` entries.
3. Append to `DeviceModel.all`.

The compositor and preview both read from `DeviceFrame.screenRectNormalized` — coordinates are
top-left origin, normalized to the PNG dimensions.

The `DeviceFrameKind` enum distinguishes three modes:
- `.physical` — real device PNG with transparent screen cutout
- `.generic` — drawn placeholder with user-controlled bezel width/color
- `.none` — bare video with rounded corners only

### Undo/Redo system

`ProjectSnapshot` (`Project+Undo.swift`) captures all mutable editing state. `Project.pushUndo()`
is called before every mutating operation, pushes onto `undoStack` (max 40), and clears `redoStack`.
`Project.undo()` / `.redo()` swap snapshots between stacks.

`ProjectSnapshot` captures: clips, activeClipID, trackCount, animations, selectedAnimationID,
transitions, selectedTransitionID, scale, offset, background, shadow, audioClips, backgroundBlurRadius,
exportQuality, exportRenderSize.

## Common patterns

- `@Observable` for the `Project` and `ProjectStateManager` classes (not `@ObservableObject`/`@StateObject`).
- Actors (`ExportService`, `BlurPosterCache`, `VideoThumbnailGenerator`) for concurrency safety.
- `nonisolated(unsafe)` on stored properties of `@unchecked Sendable` classes that are guarded by
  queue confinement or locks (e.g., `DeviceFrameCompositionInstruction`, `ContinuationGuard`).
- `Color(hex:)` / `.hexString` / `.ciColor` extensions on `Color` for hex ↔ NSColor/CIcolor bridging.
- `NSViewRepresentable` for wrapping `AVPlayerLayer` (SwiftUI has no native video layer).
- `Bundle.main.url(forResource:)` for bundled preset preview `.mp4` files.
- `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` for user-chosen
  files outside the sandbox; paired with `defer` for cleanup.
- `NotificationCenter` for menu command dispatch (`MayaApp.swift` posts to `.newProject`, `.openProject`, `.saveProject`; `EditorView` observes).
- `ContinuationGuard<T>` — a thread-safe wrapper around `CheckedContinuation` used in async-to-callback bridging during export (protects against double-resume).
- `ViewModifier` split across multiple structs (`ProjectChangeTracker1`, `ProjectChangeTracker2`) to avoid Swift compiler type-check timeout when observing many `@Observable` properties.
