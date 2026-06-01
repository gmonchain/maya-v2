# Báo cáo: Tách file lớn trong Maya

**Ngày:** 2026-06-01  
**Tiêu chí:** File > 300 dòng nên tách theo quy tắc CLAUDE.md

---

## Tổng quan

| File | Dòng | Trạng thái |
|------|------|-----------|
| `Models/Project.swift` | 707 | 🔴 Quá lớn |
| `Views/SettingsSidebar.swift` | 633 | 🔴 Quá lớn |
| `Services/ExportService.swift` | 595 | 🔴 Quá lớn |
| `Views/AnimationEditorSheet.swift` | 449 | 🟡 Nên tách |
| `Views/Timeline/TimelineView.swift` | 438 | 🟡 Nên tách |
| `Views/Timeline/AnimationsTrack.swift` | 374 | 🟡 Nên tách |
| `Services/DeviceFrameCompositor.swift` | 353 | 🟡 Nên tách |
| `Views/BackgroundPicker.swift` | 341 | 🟡 Nên tách |

**Tổng:** 3,890 dòng trong 8 file cần tách

---

## Đề xuất tách cụ thể

### 1. `Models/Project.swift` (707 dòng) → 3 file

Hiện tại Project.swift chứa: undo system, multi-clip logic, trim logic, zoom logic, sandbox adoption, playback. Nên tách:

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Models/Project.swift` | Core state, computed properties, playback, lifecycle | ~250 |
| `Models/Project+Undo.swift` | `ProjectSnapshot`, `undoStack`, `redoStack`, `pushUndo()`, `undo()`, `redo()`, `makeSnapshot()`, `restore()` | ~120 |
| `Models/Project+Clips.swift` | `clips` array, `splitAtPlayhead()`, `deleteActiveClip()`, `snapClipPosition()`, `wouldOverlap()`, clip helpers | ~200 |
| `SandboxHelper.swift` | `adoptIntoSandbox()`, `cacheDirectory()`, `cleanupCachedSource()` — static utility, không thuộc instance | ~80 |

### 2. `Views/SettingsSidebar.swift` (633 dòng) → 3 file

Settings sidebar chứa nhiều section independent. Nên tách theo section:

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Views/Settings/SettingsSidebar.swift` | Container view, NavigationSplitView sidebar | ~80 |
| `Views/Settings/RecordingSection.swift` | Recording/canvas settings | ~150 |
| `Views/Settings/DeviceSection.swift` | Device model/color picker, frame preview | ~200 |
| `Views/Settings/BackgroundSection.swift` | Background picker, shadow settings | ~200 |

### 3. `Services/ExportService.swift` (595 dòng) → 2-3 file

ExportService chứa: Snapshot builder, background pipeline, transparent pipeline, animation shifting, helpers.

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Services/ExportService.swift` | Actor definition, public API, snapshot builder | ~150 |
| `Services/ExportBackgroundPipeline.swift` | `runWithBackground()`, background CIImage builder | ~180 |
| `Services/ExportTransparentPipeline.swift` | `runTransparent()`, pumpVideo/pumpAudio, shiftSamplePTS | ~200 |

### 4. `Views/AnimationEditorSheet.swift` (449 dòng) → 2 file

Panel chứa header + presets + customization panels. Tách phần presets:

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Views/AnimationEditorSheet.swift` | Panel body, header, actions | ~200 |
| `Views/AnimationPresets.swift` | `PresetCard`, `CurveOptionButton`, `FocusOptionButton` — reusable components | ~250 |

### 5. `Views/Timeline/TimelineView.swift` (438 dòng) → 2 file

TimelineView chứa cả TimelineToolbar (private). Tách toolbar:

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Views/Timeline/TimelineView.swift` | Tracks, ruler, playhead | ~200 |
| `Views/Timeline/TimelineToolbar.swift` | Transport bar, split button, overlap toggle, clips badge, shortcuts | ~240 |

### 6. `Views/Timeline/AnimationsTrack.swift` (374 dòng) → 2 file

Chứa SegmentBlock (private) khá lớn. Tách ra:

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Views/Timeline/AnimationsTrack.swift` | Track container, snap guide, hover-to-add | ~120 |
| `Views/Timeline/SegmentBlock.swift` | `SegmentBlock`, resize handles, drag logic, tooltip | ~200 |

### 7. `Services/DeviceFrameCompositor.swift` (353 dòng) → giữ nguyên hoặc tách nhẹ

File này đã khá compact — mỗi method ngắn. **Đề xuất giữ nguyên** vì cấu trúc đã rõ ràng và logic compositor nên ở cùng nhau.

### 8. `Views/BackgroundPicker.swift` (341 dòng) → 2 file

| File mới | Nội dung | Ước tính dòng |
|----------|----------|--------------|
| `Views/BackgroundPicker.swift` | Main picker view | ~180 |
| `Views/BackgroundOptionViews.swift` | `SolidColorOption`, `GradientOption`, `ImageOption`, `VideoBlurOption` cards | ~160 |

---

## Thứ tự ưu tiên thực hiện

1. **Project.swift** — Ưu tiên cao nhất, lớn nhất và phức tạp nhất
2. **SettingsSidebar.swift** — Dễ tách nhất (các section independent)
3. **ExportService.swift** — Tách pipeline rõ ràng
4. **TimelineView.swift** — Tách toolbar đơn giản
5. **AnimationEditorSheet.swift** — Tách preset components
6. **AnimationsTrack.swift** — Tách SegmentBlock
7. **BackgroundPicker.swift** — Tách option views
8. **DeviceFrameCompositor.swift** — Giữ nguyên

---

## Ước tính tổng sau khi tách

- Từ 8 file lớn → ~18 file nhỏ hơn
- Mỗi file đều dưới 300 dòng
- Dễ maintain, dễ find & edit
