# Graph Report - .  (2026-06-01)

## Corpus Check
- 83 files · ~192,052 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 439 nodes · 645 edges · 37 communities (33 shown, 4 thin omitted)
- Extraction: 92% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 45 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Data Models|Data Models]]
- [[_COMMUNITY_Timeline & Background UI|Timeline & Background UI]]
- [[_COMMUNITY_App Core & Project State|App Core & Project State]]
- [[_COMMUNITY_Animation Sampling & Framing|Animation Sampling & Framing]]
- [[_COMMUNITY_Export Pipeline|Export Pipeline]]
- [[_COMMUNITY_Background Configuration|Background Configuration]]
- [[_COMMUNITY_Video Player Wrappers|Video Player Wrappers]]
- [[_COMMUNITY_Asset Catalog Structure|Asset Catalog Structure]]
- [[_COMMUNITY_Frame Compositor|Frame Compositor]]
- [[_COMMUNITY_Animation Editor UI|Animation Editor UI]]
- [[_COMMUNITY_Build & Documentation|Build & Documentation]]
- [[_COMMUNITY_Editor View Controller|Editor View Controller]]
- [[_COMMUNITY_Video Trimming|Video Trimming]]
- [[_COMMUNITY_Branding & Marketing Assets|Branding & Marketing Assets]]
- [[_COMMUNITY_Blur Poster Cache|Blur Poster Cache]]
- [[_COMMUNITY_iPhone 1617 Pro Frames|iPhone 16/17 Pro Frames]]
- [[_COMMUNITY_iPhone 15 Pro Frames|iPhone 15 Pro Frames]]
- [[_COMMUNITY_AccentColor Metadata|AccentColor Metadata]]
- [[_COMMUNITY_AppIcon Metadata|AppIcon Metadata]]
- [[_COMMUNITY_iPhone 15 Pro Black Metadata|iPhone 15 Pro Black Metadata]]
- [[_COMMUNITY_iPhone 15 Pro Natural Metadata|iPhone 15 Pro Natural Metadata]]
- [[_COMMUNITY_iPhone 15 Pro White Metadata|iPhone 15 Pro White Metadata]]
- [[_COMMUNITY_iPhone 16 Pro Black Metadata|iPhone 16 Pro Black Metadata]]
- [[_COMMUNITY_iPhone 16 Pro Gold Metadata|iPhone 16 Pro Gold Metadata]]
- [[_COMMUNITY_iPhone 16 Pro Frame Assets|iPhone 16 Pro Frame Assets]]
- [[_COMMUNITY_iPhone 16 Pro Natural Metadata|iPhone 16 Pro Natural Metadata]]
- [[_COMMUNITY_iPhone 16 Pro White Metadata|iPhone 16 Pro White Metadata]]
- [[_COMMUNITY_iPhone 17 Pro Deep Blue Metadata|iPhone 17 Pro Deep Blue Metadata]]
- [[_COMMUNITY_iPhone 17 Pro Silver Metadata|iPhone 17 Pro Silver Metadata]]
- [[_COMMUNITY_MacBook Pro 14 Metadata|MacBook Pro 14 Metadata]]
- [[_COMMUNITY_iPhone 15 Pro Standalone Metadata|iPhone 15 Pro Standalone Metadata]]
- [[_COMMUNITY_iPhone 17 Pro Cosmic Orange Metadata|iPhone 17 Pro Cosmic Orange Metadata]]
- [[_COMMUNITY_Video Thumbnail Generator|Video Thumbnail Generator]]
- [[_COMMUNITY_Root Asset Catalog Metadata|Root Asset Catalog Metadata]]
- [[_COMMUNITY_iPhone Frames Folder Metadata|iPhone Frames Folder Metadata]]
- [[_COMMUNITY_MacBook Frames Folder Metadata|MacBook Frames Folder Metadata]]

## God Nodes (most connected - your core abstractions)
1. `Project` - 34 edges
2. `ZoomSegment` - 14 edges
3. `AnimationCurve` - 13 edges
4. `DeviceModel` - 13 edges
5. `CanvasAspectRatio` - 12 edges
6. `EditorView` - 12 edges
7. `AnimationEditorPanel` - 12 edges
8. `iPhone Frames Asset Folder (device bezel overlays)` - 12 edges
9. `BackgroundOption` - 11 edges
10. `ExportService` - 11 edges

## Surprising Connections (you probably didn't know these)
- `ExportService` --semantically_similar_to--> `BackgroundView`  [INFERRED] [semantically similar]
  Maya/Services/ExportService.swift → Maya/Views/BackgroundView.swift
- `iPhone 15 Pro Standalone Imageset (screen recording template)` --semantically_similar_to--> `iPhone Frames Asset Folder (device bezel overlays)`  [INFERRED] [semantically similar]
  Maya/Assets.xcassets/iPhone 15 Pro.imageset/Contents.json → Maya/Assets.xcassets/iphone frames/Contents.json
- `Maya Website Icon` --semantically_similar_to--> `Maya App Icon`  [EXTRACTED] [semantically similar]
  docs/icon.png → Maya/Assets.xcassets/AppIcon.appiconset/icon_256.png
- `DMG Installer Background` --references--> `Maya App Icon`  [INFERRED]
  scripts/dmg-assets/background.png → Maya/Assets.xcassets/AppIcon.appiconset/icon_256.png
- `Dual Export Pipeline (H.264 MP4 + HEVC-alpha MOV)` --conceptually_related_to--> `BackgroundOption`  [INFERRED]
  Maya/Models/Project.swift → Maya/Models/BackgroundOption.swift

## Hyperedges (group relationships)
- **iPhone Pro Device Models (15/16/17 Pro + Generic + None + MacBook Pro)** — models_deviceframe_devicemodel, models_deviceframe_devicecolor, models_deviceframe_deviceframe, models_deviceframe_deviceframekind [EXTRACTED 1.00]
- **Zoom Animation System (Segment + Focus + Curve + Presets)** — models_zoomkeyframe_zoomsegment, models_zoomkeyframe_zoomfocus, models_zoomkeyframe_animationcurve, models_zoomkeyframe_preset [EXTRACTED 1.00]
- **Release Pipeline (Script + CI Workflow + Docs + Website Download)** — scripts_build_release_sh, workflows_release_yml, releasing_releasing_md, docs_index_html, dmg_assets_make_background_swift [EXTRACTED 1.00]
- **Canvas Preview Pipeline** —  [INFERRED]
- **Export Pipeline** —  [INFERRED]
- **Timeline Editing** —  [INFERRED]
- **iPhone 15 Pro device frame color variant set** —  [INFERRED]
- **iPhone 16 Pro Device Frame Color Set** — iphone_16_pro_black_titanium_frame, iphone_16_pro_natural_titanium_frame [INFERRED]
- **Device Frame Compositor Pipeline** — iphone_16_pro_black_titanium_frame, iphone_16_pro_natural_titanium_frame [INFERRED]

## Communities (37 total, 4 thin omitted)

### Community 0 - "Data Models"
Cohesion: 0.07
Nodes (38): CaseIterable, Hashable, Identifiable, CanvasAspectRatio, landscape16x9, landscape4x3, square, vertical4x5 (+30 more)

### Community 1 - "Timeline & Background UI"
Cohesion: 0.07
Nodes (33): VideoThumbnailGenerator, AnimationsTrack, AnimationsTrack, Edge, leading, trailing, formatTimestamp(), HoverAddButton (+25 more)

### Community 2 - "App Core & Project State"
Cohesion: 0.09
Nodes (7): App, ContentView, MayaApp, Project, Sandbox File Adoption via Hard-link/Copy, Single @Observable State (Project as sole state owner), Timeline Two-Coordinate System (Source + Timeline)

### Community 3 - "Animation Sampling & Framing"
Cohesion: 0.12
Nodes (16): Equatable, AnimationSampler, AnimationSample, AnimationSampler, BlurPosterCache, DeviceFrameCompositor, DeviceFrameCompositionInstruction, ExportService (+8 more)

### Community 4 - "Export Pipeline"
Cohesion: 0.13
Nodes (13): ExportError, appendFailed, cannotBuildComposition, cannotInitExportSession, missingFrameOverlay, noSourceVideo, noVideoTrack, readerStartFailed (+5 more)

### Community 5 - "Background Configuration"
Cohesion: 0.11
Nodes (11): BackgroundOption, gradient, image, none, solid, videoBlur, Color, Color.init(hex:) (+3 more)

### Community 6 - "Video Player Wrappers"
Cohesion: 0.14
Nodes (7): NSView, NSViewRepresentable, LoopingPlayerHostView, LoopingVideoView, VideoPlayerNSView, PlayerHostView, VideoPlayerNSView

### Community 7 - "Asset Catalog Structure"
Cohesion: 0.26
Nodes (18): AccentColor (universal accent color), AppIcon (macOS app icon set, 16-512px @1x/@2x), Assets.xcassets Root Asset Catalog, DeviceFrame.swift — DeviceModel and DeviceColor enums, iPhone 15 Pro Device Frame (color: Black Titanium), iPhone 15 Pro Standalone Imageset (screen recording template), iPhone 15 Pro Device Frame (color: Natural Titanium), iPhone 15 Pro Device Frame (color: White Titanium) (+10 more)

### Community 8 - "Frame Compositor"
Cohesion: 0.14
Nodes (9): AVVideoCompositing, LocalizedError, NSObject, CompositorError, cannotAllocateBuffer, invalidSource, missingContext, missingSource (+1 more)

### Community 9 - "Animation Editor UI"
Cohesion: 0.21
Nodes (6): AnimationEditorPanel, AnimationEditorPanel, CurveOptionButton, FocusOptionButton, PresetCard, LoopingVideoView

### Community 10 - "Build & Documentation"
Cohesion: 0.24
Nodes (7): Landing Page (docs/index.html), DMG Signing + Notarization + Stapling Chain, fail(), notarize(), step(), build-release.sh script, Release Workflow (.github/workflows/release.yml)

### Community 12 - "Video Trimming"
Cohesion: 0.24
Nodes (6): HandleSnapshot, TrimEdge, end, start, TrimmableVideoClip, VideoThumbnailStrip

### Community 13 - "Branding & Marketing Assets"
Cohesion: 0.29
Nodes (10): Maya App Branding, Maya App Icon, Device Frame Wrapping Feature, DMG Installer Drag-to-Applications UX, DMG Installer Background, DMG Installer Background Retina, Maya Website Icon, Maya App Screenshot (+2 more)

### Community 15 - "iPhone 16/17 Pro Frames"
Cohesion: 0.50
Nodes (8): iPhone 16 Pro - Gold Titanium Frame PNG, iPhone 16 Pro DeviceModel, iPhone 16 Pro vs 17 Pro Camera Design, iPhone 17 Pro - Cosmic Orange Frame PNG, iPhone 17 Pro - Silver Frame PNG, iPhone 17 Pro DeviceModel, Device Frame Compositing Pipeline, iPhone 16 Pro / 17 Pro Shared Frame Geometry

### Community 16 - "iPhone 15 Pro Frames"
Cohesion: 0.36
Nodes (8): iPhone 15 Pro Black Titanium device frame, iPhone 15 Pro Natural Titanium Device Frame, iPhone 15 Pro device model, iPhone 15 Pro Natural Titanium device frame, iPhone 15 Pro White Titanium device frame, iPhone 15 Pro Black Titanium Device Frame, iPhone 16 Pro White Titanium Device Frame, MacBook Pro 14-inch Device Frame

### Community 17 - "AccentColor Metadata"
Cohesion: 0.40
Nodes (4): colors, info, author, version

### Community 18 - "AppIcon Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 19 - "iPhone 15 Pro Black Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 20 - "iPhone 15 Pro Natural Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 21 - "iPhone 15 Pro White Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 22 - "iPhone 16 Pro Black Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 23 - "iPhone 16 Pro Gold Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 25 - "iPhone 16 Pro Natural Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 26 - "iPhone 16 Pro White Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 27 - "iPhone 17 Pro Deep Blue Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 28 - "iPhone 17 Pro Silver Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 29 - "MacBook Pro 14 Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 30 - "iPhone 15 Pro Standalone Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 31 - "iPhone 17 Pro Cosmic Orange Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 33 - "Root Asset Catalog Metadata"
Cohesion: 0.50
Nodes (3): info, author, version

### Community 34 - "iPhone Frames Folder Metadata"
Cohesion: 0.50
Nodes (3): info, author, version

### Community 35 - "MacBook Frames Folder Metadata"
Cohesion: 0.50
Nodes (3): info, author, version

## Knowledge Gaps
- **101 isolated node(s):** `author`, `version`, `images`, `author`, `version` (+96 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Project` connect `App Core & Project State` to `Data Models`, `Build & Documentation`, `Background Configuration`?**
  _High betweenness centrality (0.130) - this node is a cross-community bridge._
- **Why does `ContentView` connect `App Core & Project State` to `Timeline & Background UI`?**
  _High betweenness centrality (0.088) - this node is a cross-community bridge._
- **Why does `AnimationSample` connect `Animation Sampling & Framing` to `Data Models`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `Project` (e.g. with `Dual Export Pipeline (H.264 MP4 + HEVC-alpha MOV)` and `Sandbox File Adoption via Hard-link/Copy`) actually correct?**
  _`Project` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `ZoomSegment` (e.g. with `.addZoomSegment()` and `.segmentBinding()`) actually correct?**
  _`ZoomSegment` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `author`, `version`, `images` to the rest of the system?**
  _103 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Data Models` be split into smaller, more focused modules?**
  _Cohesion score 0.06980392156862746 - nodes in this community are weakly interconnected._