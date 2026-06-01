import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - Undo snapshot

/// Captures all mutable editing state so it can be saved/restored for undo/redo.
/// Does NOT include player, videoURL, videoDuration — those are invariant once loaded.
struct ProjectSnapshot: Equatable, Sendable {
    var clips: [VideoClip]
    var activeClipID: UUID?
    var animations: [ZoomSegment]
    var selectedAnimationID: ZoomSegment.ID?
    var scale: CGFloat
    var offset: CGSize
    var background: BackgroundOption
    var shadow: PhoneShadow
}

@Observable
final class Project {
    /// URL of the working copy inside the app's sandbox. The user's original file is never
    /// referenced after load — we hard-link (same volume) or copy it into our Caches dir so
    /// every subsequent read (preview, thumbnails, export) has unrestricted sandbox access
    /// from any thread. This sidesteps the entire security-scoped-resource dance, which is
    /// unreliable for drag-drop URLs across actor/queue boundaries.
    var videoURL: URL?
    /// Display name (the user's original file name) for UI labels.
    var displayName: String?
    var player: AVPlayer?
    var videoNaturalSize: CGSize = .zero
    var videoDuration: CMTime = .zero
    var currentSeconds: Double = 0

    var scale: CGFloat = 0.85
    var offset: CGSize = .zero
    var background: BackgroundOption = .gradient(GradientSpec.presets[0])
    var canvasAspect: CanvasAspectRatio = .square
    var shadow: PhoneShadow = PhoneShadow()

    /// Device picker state. We track model + color separately so switching models
    /// can gracefully fall back to that model's default color.
    var deviceModelID: String = DeviceModel.iPhone17Pro.id
    var deviceColorID: String = DeviceModel.iPhone17Pro.defaultColor.id

    /// Corner radius for the bare video, used when the active device is
    /// `.none` or `.generic`. Normalized to the screen's short side: 0 = sharp,
    /// 0.5 = fully rounded (stadium / circle).
    var bareCornerRadius: CGFloat = 0.15

    /// Stroke width of the generic device bezel, normalized to phone width
    /// (0 → no bezel, 0.1 → fat bezel).
    var bareBezelWidth: CGFloat = 0.025

    /// Color of the generic device bezel, stored as hex so it survives
    /// snapshot/export without bridging through NSColor on background queues.
    var bareBezelHex: String = "#000000"

    var deviceModel: DeviceModel {
        DeviceModel.model(id: deviceModelID) ?? .iPhone17Pro
    }

    var deviceColor: DeviceColor {
        deviceModel.color(id: deviceColorID) ?? deviceModel.defaultColor
    }

    var deviceFrame: DeviceFrame {
        deviceModel.frame(for: deviceColor)
    }

    func selectDeviceModel(_ model: DeviceModel) {
        deviceModelID = model.id
        if model.color(id: deviceColorID) == nil {
            deviceColorID = model.defaultColor.id
        }
    }

    func selectDeviceColor(_ color: DeviceColor) {
        guard deviceModel.color(id: color.id) != nil else { return }
        deviceColorID = color.id
    }

    var animations: [ZoomSegment] = []
    var selectedAnimationID: ZoomSegment.ID?

    // MARK: - Multi-clip state

    /// All video clips on the timeline. Each clip is an independent segment of the
    /// source video with its own trim range and timeline position.
    var clips: [VideoClip] = []

    /// ID of the clip currently selected for editing (trim, split, etc.).
    var activeClipID: UUID?

    /// The currently active clip, if any.
    var activeClip: VideoClip? {
        guard let id = activeClipID else { return nil }
        return clips.first { $0.id == id }
    }

    /// Index of the active clip in the `clips` array, or nil.
    var activeClipIndex: Int? {
        guard let id = activeClipID else { return nil }
        return clips.firstIndex { $0.id == id }
    }

    /// Selects the clip that contains the given *timeline* second.
    @discardableResult
    func selectClip(at timelineSecond: Double) -> VideoClip? {
        guard let idx = clips.firstIndex(where: {
            timelineSecond >= $0.timelineStart && timelineSecond <= $0.timelineEnd
        }) else { return nil }
        activeClipID = clips[idx].id
        return clips[idx]
    }

    // MARK: - Computed properties delegating to the active clip

    /// In/out points on the *source* video. Non-destructive: the underlying file is untouched.
    /// Together with `clipTimelineStart` they define an "edit": which portion of the source
    /// to play and where to place it on the project timeline.
    var trimStartTime: Double {
        get { activeClip?.trimStartTime ?? 0 }
        set {
            guard let idx = activeClipIndex else { return }
            var clip = clips[idx]
            let maxStart = max(0, clip.trimEndTime - Self.minTrimDuration)
            clip.trimStartTime = max(0, min(newValue, maxStart))
            clips[idx] = clip
        }
    }

    var trimEndTime: Double {
        get { activeClip?.trimEndTime ?? durationSeconds }
        set {
            guard let idx = activeClipIndex else { return }
            var clip = clips[idx]
            let minEnd = min(durationSeconds, clip.trimStartTime + Self.minTrimDuration)
            clip.trimEndTime = max(minEnd, min(newValue, durationSeconds))
            clips[idx] = clip
        }
    }

    /// Where the trimmed clip sits on the project timeline. This is independent from
    /// `trimStartTime` — the user can grab the clip and slide it anywhere on the
    /// timeline without changing which source frames play. NLE-style.
    var clipTimelineStart: Double {
        get { activeClip?.timelineStart ?? 0 }
        set {
            guard let idx = activeClipIndex else { return }
            var clip = clips[idx]
            clip.timelineStart = max(0, newValue)
            clips[idx] = clip
        }
    }

    /// Minimum length you can trim a clip down to. Mirrors Apple Photos' behavior.
    static let minTrimDuration: Double = VideoClip.minDuration

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var lastExportError: String?

    var isMuted: Bool = true {
        didSet { player?.isMuted = isMuted }
    }

    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?

    // MARK: - Undo/Redo stacks

    private var undoStack: [ProjectSnapshot] = []
    private var redoStack: [ProjectSnapshot] = []
    /// Maximum number of undo steps to keep in memory.
    private static let maxUndoDepth = 40

    /// Captures the current editable state as a snapshot.
    private func makeSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            clips: clips,
            activeClipID: activeClipID,
            animations: animations,
            selectedAnimationID: selectedAnimationID,
            scale: scale,
            offset: offset,
            background: background,
            shadow: shadow
        )
    }

    /// Restores project state from a snapshot (does NOT touch player/videoURL/etc.).
    private func restore(from snapshot: ProjectSnapshot) {
        clips = snapshot.clips
        activeClipID = snapshot.activeClipID
        animations = snapshot.animations
        selectedAnimationID = snapshot.selectedAnimationID
        scale = snapshot.scale
        offset = snapshot.offset
        background = snapshot.background
        shadow = snapshot.shadow
    }

    /// Call before any destructive edit to push the current state onto the undo stack.
    func pushUndo() {
        undoStack.append(makeSnapshot())
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst()
        }
        // Any new action invalidates the redo history.
        redoStack.removeAll()
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(makeSnapshot())
        restore(from: undoStack.removeLast())
    }

    func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(makeSnapshot())
        restore(from: redoStack.removeLast())
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Lifecycle

    deinit {
        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        Self.cleanupCachedSource(at: videoURL)
    }

    var durationSeconds: Double {
        let s = videoDuration.seconds
        return (s.isFinite && s > 0) ? s : 0
    }

    /// Length of the active clip (after trim) in seconds.
    var clipDuration: Double {
        activeClip?.clipDuration ?? 0
    }

    /// Backwards-compat alias used by the toolbar and export.
    var trimmedDuration: Double { clipDuration }

    /// Right edge of the active clip on the project timeline.
    var clipTimelineEnd: Double {
        activeClip?.timelineEnd ?? 0
    }

    /// Length of the project timeline shown in the editor. Grows beyond the source duration
    /// only if the user has dragged a clip past the natural end.
    var timelineDuration: Double {
        let maxClipEnd = clips.map(\.timelineEnd).max() ?? 0
        return max(durationSeconds, maxClipEnd)
    }

    /// True when the user has trimmed, shifted, or split the video.
    var isTrimmed: Bool {
        guard durationSeconds > 0 else { return false }
        return clips.count > 1 || clips.contains(where: { clip in
            clip.trimStartTime > 0.001
                || clip.trimEndTime < durationSeconds - 0.001
                || clip.timelineStart > 0.001
        })
    }

    /// Converts a project-timeline second to its source-video second. Outside any clip's
    /// timeline window the closest source edge is returned so seeks land on a renderable frame.
    func timelineToSource(_ t: Double) -> Double {
        activeClip?.timelineToSource(t) ?? t
    }

    /// Inverse of `timelineToSource`.
    func sourceToTimeline(_ s: Double) -> Double {
        activeClip?.sourceToTimeline(s) ?? s
    }

    func setTrimStart(_ t: Double) {
        guard let idx = activeClipIndex else { return }
        var clip = clips[idx]
        let maxStart = max(0, clip.trimEndTime - Self.minTrimDuration)
        clip.trimStartTime = max(0, min(t, maxStart))
        clips[idx] = clip
    }

    func setTrimEnd(_ t: Double) {
        guard let idx = activeClipIndex else { return }
        var clip = clips[idx]
        let minEnd = min(durationSeconds, clip.trimStartTime + Self.minTrimDuration)
        clip.trimEndTime = max(minEnd, min(t, durationSeconds))
        clips[idx] = clip
    }

    /// Clamps a timeline second into the active clip's window.
    func clampedToClip(_ t: Double) -> Double {
        guard let clip = activeClip, clip.clipDuration > 0 else { return activeClip?.timelineStart ?? 0 }
        if t < clip.timelineStart { return clip.timelineStart }
        if t > clip.timelineEnd { return clip.timelineEnd }
        return t
    }

    /// Looks up the segment under a *timeline* second. Returns nil if the timeline time
    /// lies outside any clip window.
    func segment(containing timelineTime: Double) -> ZoomSegment? {
        guard let clip = clips.first(where: {
            timelineTime >= $0.timelineStart && timelineTime <= $0.timelineEnd
        }) else { return nil }
        let s = clip.timelineToSource(timelineTime)
        return animations.first { s >= $0.startTime && s <= $0.endTime }
    }

    /// Adds a zoom anchored at the given *timeline* second. Stored internally in source
    /// coords so the animation stays attached to the same source frame even if the clip
    /// is later moved or re-trimmed.
    func addZoomSegment(at timelineTime: Double) -> ZoomSegment {
        let dur = ZoomSegment.defaultDuration
        guard let clipIndex = clips.firstIndex(where: {
            timelineTime >= $0.timelineStart && timelineTime <= $0.timelineEnd
        }) else {
            // Fallback: add to active clip
            guard let idx = activeClipIndex else { return ZoomSegment(startTime: 0, duration: dur, scale: ZoomSegment.defaultScale, focus: .center) }
            return addZoomSegment(at: timelineTime, clipIndex: idx)
        }
        return addZoomSegment(at: timelineTime, clipIndex: clipIndex)
    }

    private func addZoomSegment(at timelineTime: Double, clipIndex: Int) -> ZoomSegment {
        pushUndo()
        let dur = ZoomSegment.defaultDuration
        var clip = clips[clipIndex]
        let clipStart = clip.timelineStart
        let clipEnd = clip.timelineEnd
        let clampedTimeline = max(clipStart, min(timelineTime, max(clipEnd - dur, clipStart)))
        let sourceStart = clip.timelineToSource(clampedTimeline)
        var segment = ZoomSegment(
            startTime: sourceStart,
            duration: min(dur, max(clip.trimEndTime - sourceStart, 0.4)),
            scale: ZoomSegment.defaultScale,
            focus: .center
        )
        segment.normalize()
        animations.append(segment)
        selectedAnimationID = segment.id
        activeClipID = clip.id
        return segment
    }

    func updateZoomSegment(_ segment: ZoomSegment) {
        guard let idx = animations.firstIndex(where: { $0.id == segment.id }) else { return }
        var s = segment
        s.normalize()
        animations[idx] = s
    }

    func removeZoomSegment(id: ZoomSegment.ID) {
        pushUndo()
        animations.removeAll { $0.id == id }
        if selectedAnimationID == id { selectedAnimationID = nil }
    }

    @discardableResult
    func duplicateZoomSegment(id: ZoomSegment.ID) -> ZoomSegment? {
        guard let original = animations.first(where: { $0.id == id }) else { return nil }
        pushUndo()
        var copy = original
        copy.id = UUID()
        copy.startTime = min(original.endTime + 0.1, max(durationSeconds - copy.duration, 0))
        copy.normalize()
        animations.append(copy)
        selectedAnimationID = copy.id
        return copy
    }

    func toggleMute() {
        isMuted.toggle()
    }

    /// Returns true when a clip (not just a zoom animation) is the primary selection.
    var isClipSelected: Bool {
        activeClipID != nil && selectedAnimationID == nil
    }

    // MARK: - Delete clip

    /// Removes the active clip and closes the gap by sliding all subsequent clips left.
    /// If only one clip remains after deletion, it resets to cover the full video duration.
    func deleteActiveClip() {
        guard let idx = activeClipIndex, clips.count > 1 else { return }
        pushUndo()
        let deletedClip = clips[idx]
        let gap = deletedClip.clipDuration

        clips.remove(at: idx)

        // Ripple: slide every clip that was to the right of the deleted one leftward.
        for i in idx..<clips.count {
            var clip = clips[i]
            clip.timelineStart = max(0, clip.timelineStart - gap)
            clips[i] = clip
        }

        // Select the nearest surviving clip.
        if idx < clips.count {
            activeClipID = clips[idx].id
        } else {
            activeClipID = clips.last?.id
        }

        // Remove any zoom animations that no longer fall inside any clip's source range.
        animations.removeAll { seg in
            !clips.contains(where: { clip in
                seg.startTime >= clip.trimStartTime && seg.startTime < clip.trimEndTime
            })
        }
    }

    // MARK: - Split at playhead

    /// Splits the clip that contains the playhead into two independent clips.
    /// The left half keeps the original timeline position; the right half starts
    /// at the playhead. Both share the same source file.
    func splitAtPlayhead() {
        let timelinePos = currentSeconds
        guard let clipIndex = clips.firstIndex(where: {
            timelinePos > $0.timelineStart + 0.05 && timelinePos < $0.timelineEnd - 0.05
        }) else { return }

        pushUndo()

        let clip = clips[clipIndex]
        let sourceSplitTime = clip.timelineToSource(timelinePos)

        let leftClip = VideoClip(
            id: UUID(),
            trimStartTime: clip.trimStartTime,
            trimEndTime: sourceSplitTime,
            timelineStart: clip.timelineStart
        )

        let rightClip = VideoClip(
            id: UUID(),
            trimStartTime: sourceSplitTime,
            trimEndTime: clip.trimEndTime,
            timelineStart: timelinePos
        )

        clips.remove(at: clipIndex)
        clips.insert(contentsOf: [leftClip, rightClip], at: clipIndex)

        // Select the right clip (after the split point).
        activeClipID = rightClip.id
    }

    /// Seek to a project-timeline second. The player itself runs in source coords so we
    /// translate before issuing the seek.
    func seek(to timelineSeconds: Double) {
        guard let player else { return }
        let clamped = clampedToClip(timelineSeconds)
        if let clip = clips.first(where: { clamped >= $0.timelineStart && clamped <= $0.timelineEnd }) {
            let source = clip.timelineToSource(clamped)
            let time = CMTime(seconds: source, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        currentSeconds = clamped
    }

    /// Loads a video. `url` must already be inside the app sandbox (use
    /// `Project.adoptIntoSandbox(_:)` first). Cleans up the previous working copy.
    func loadVideo(url: URL) async {
        let previousURL = videoURL
        let asset = AVURLAsset(url: url)
        var naturalSize = CGSize.zero
        var duration = CMTime.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                naturalSize = size
            }
        }
        if let d = try? await asset.load(.duration) {
            duration = d
        }

        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted

        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak newPlayer] _ in
            guard let self, let clip = self.activeClip else { return }
            let target = CMTime(seconds: clip.trimStartTime, preferredTimescale: 600)
            newPlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            newPlayer?.play()
        }

        if let observer = timeObserver, let oldPlayer = self.player {
            oldPlayer.removeTimeObserver(observer)
        }

        self.videoURL = url
        self.videoNaturalSize = naturalSize
        self.videoDuration = duration
        self.player = newPlayer

        // Initialize a single untrimmed clip covering the full video.
        let durSeconds = duration.seconds.isFinite ? duration.seconds : 0
        let initialClip = VideoClip(
            id: UUID(),
            trimStartTime: 0,
            trimEndTime: max(durSeconds, 0),
            timelineStart: 0
        )
        self.clips = [initialClip]
        self.activeClipID = initialClip.id
        self.currentSeconds = 0
        // Clear undo history when loading a new video.
        self.undoStack.removeAll()
        self.redoStack.removeAll()

        // Now safe to remove the previous working copy.
        Self.cleanupCachedSource(at: previousURL)

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let sourceTime = time.seconds
            // If the player crosses the active clip's trim-out while playing, snap back.
            if let clip = self.activeClip, clip.clipDuration > 0, sourceTime >= clip.trimEndTime - 0.01 {
                let target = CMTime(seconds: clip.trimStartTime, preferredTimescale: 600)
                self.player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                self.currentSeconds = clip.timelineStart
            } else if let clip = self.clips.first(where: {
                sourceTime >= $0.trimStartTime && sourceTime <= $0.trimEndTime
            }) {
                self.currentSeconds = clip.sourceToTimeline(sourceTime)
            } else {
                self.currentSeconds = sourceTime
            }
        }

        newPlayer.play()
    }

    func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            guard let clip = activeClip else { return }
            // If the playhead drifted outside the clip, snap to clip-in (timeline coords).
            if currentSeconds < clip.timelineStart || currentSeconds >= clip.timelineEnd - 0.01 {
                seek(to: clip.timelineStart)
            }
            player.play()
        }
    }

    // MARK: - Sandbox file adoption
    //
    // macOS App Sandbox restricts file access by path. URLs obtained via drag-drop or
    // NSOpenPanel only carry usable scope on the thread / queue that received them, and
    // bookmark-with-security-scope creation is unreliable for drop URLs. The robust way
    // to handle this for any subsequent processing (preview, AVAssetReader on a background
    // thread, AVAssetExportSession, AVAssetImageGenerator…) is to bring the file *into*
    // the sandbox once, then operate on the local copy.
    //
    // We try a hard link first (instant, no extra disk usage, works on the same volume),
    // then fall back to a regular copy. The caller is responsible for opening the
    // security scope of the source URL before invoking this and stopping it afterward —
    // we don't bother capturing a bookmark because we no longer need post-callback access.

    static func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("VideoSources", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func adoptIntoSandbox(_ source: URL) throws -> (sandboxURL: URL, displayName: String) {
        let originalName = source.lastPathComponent
        let cleanedName = originalName.replacingOccurrences(of: "/", with: "-")
        let dest = try cacheDirectory()
            .appendingPathComponent("\(UUID().uuidString)-\(cleanedName)")

        do {
            try FileManager.default.linkItem(at: source, to: dest)
        } catch {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return (dest, originalName)
    }

    static func cleanupCachedSource(at url: URL?) {
        guard let url else { return }
        let dir = (try? cacheDirectory().path) ?? ""
        guard !dir.isEmpty, url.path.hasPrefix(dir) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
