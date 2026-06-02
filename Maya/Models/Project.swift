import AVFoundation
import CoreMedia
import Foundation
import Observation
import SwiftUI
import VideoToolbox

// MARK: - Export quality

enum ExportQuality: String, CaseIterable, Identifiable, Sendable {
    case standard
    case high
    case ultra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .high: "High"
        case .ultra: "Ultra"
        }
    }

    var helpText: String {
        switch self {
        case .standard: "Smaller file, faster export"
        case .high: "Best balance of quality and file size"
        case .ultra: "Near-lossless, large file size"
        }
    }

    /// AVAssetExportSession preset for the background pipeline.
    var backgroundPreset: String {
        switch self {
        case .standard: AVAssetExportPresetMediumQuality
        case .high: AVAssetExportPresetHighestQuality
        case .ultra: AVAssetExportPresetHighestQuality
        }
    }

    /// VideoToolbox quality value (0…1) for the transparent pipeline.
    var transparentQuality: Float {
        switch self {
        case .standard: 0.75
        case .high: 0.85
        case .ultra: 1.0
        }
    }

    /// Average video bitrate (bits/sec) for the transparent pipeline.
    /// nil means use the quality value only.
    var transparentBitrate: Int? {
        switch self {
        case .standard: 8_000_000
        case .high: 15_000_000
        case .ultra: nil // let quality=1.0 drive it
        }
    }
}

// MARK: - Export render size

enum ExportRenderSize: String, CaseIterable, Identifiable, Sendable {
    case hd1080
    case qhd1440
    case uhd2160

    var id: String { rawValue }

    var shortSide: CGFloat {
        switch self {
        case .hd1080:  1080
        case .qhd1440: 1440
        case .uhd2160: 2160
        }
    }

    var displayName: String {
        switch self {
        case .hd1080:  "1080p"
        case .qhd1440: "1440p"
        case .uhd2160: "4K"
        }
    }

    var helpText: String {
        switch self {
        case .hd1080:  "HD — standard social media quality"
        case .qhd1440: "QHD — higher detail for large screens"
        case .uhd2160: "4K — maximum detail, large file size"
        }
    }
}

@Observable
final class Project {
    var videoURL: URL?
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

    var deviceModelID: String = DeviceModel.iPhone17Pro.id
    var deviceColorID: String = DeviceModel.iPhone17Pro.defaultColor.id

    var bareCornerRadius: CGFloat = 0.15
    var bareBezelWidth: CGFloat = 0.025
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

    // MARK: - Transitions (between clips)

    var transitions: [Transition] = []
    var selectedTransitionID: Transition.ID?

    // MARK: - Multi-clip state

    var clips: [VideoClip] = []
    var activeClipID: UUID?
    var allowClipOverlap: Bool = false
    var backgroundBlurRadius: Double = 0

    // MARK: - Multi-track state

    var trackCount: Int = 1

    func addTrack() {
        pushUndo()
        trackCount += 1
    }

    func removeTrack(at index: Int) {
        guard trackCount > 1, index > 0, index < trackCount else { return }
        pushUndo()
        // Move clips from removed track to track 0
        for i in clips.indices where clips[i].trackIndex == index {
            clips[i].trackIndex = 0
        }
        // Re-index tracks above the removed one
        for i in clips.indices where clips[i].trackIndex > index {
            clips[i].trackIndex -= 1
        }
        trackCount -= 1
    }

    /// Removes a track and moves all its clips to track 0 (the bottom track).
    func removeTrackAndMoveClips(at index: Int) {
        removeTrack(at: index)
    }

    // MARK: - Audio clips

    var audioClips: [AudioClip] = []
    var activeAudioClipID: UUID?

    /// In-memory AVPlayers for audio preview sync (not observed by SwiftUI).
    private var audioPlayerCache: [UUID: AVPlayer] = [:]
    private var audioLooperCaches: [UUID: NSObjectProtocol] = [:]

    func addAudioClip(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let adopted = try Project.adoptIntoSandbox(url)
            if didStart { url.stopAccessingSecurityScopedResource() }
            let asset = AVURLAsset(url: adopted.sandboxURL)
            Task { @MainActor in
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                let name = url.deletingPathExtension().lastPathComponent
                pushUndo()
                let clip = AudioClip(
                    id: UUID(),
                    sourceURL: adopted.sandboxURL,
                    displayName: name,
                    trimStartTime: 0,
                    trimEndTime: max(duration, 0),
                    timelineStart: currentSeconds,
                    sourceDuration: max(duration, 0)
                )
                audioClips.append(clip)
                activeAudioClipID = clip.id
                setupAudioPlayer(for: clip)
                syncAudioPlayers()
            }
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            lastExportError = "Could not import audio: \(error.localizedDescription)"
        }
    }

    func deleteAudioClip(id: UUID) {
        guard audioClips.count > 0 else { return }
        pushUndo()
        teardownAudioPlayer(id: id)
        audioClips.removeAll { $0.id == id }
        if activeAudioClipID == id {
            activeAudioClipID = audioClips.first?.id
        }
    }

    func setAudioClipVolume(id: UUID, volume: Double) {
        guard let ci = audioClips.firstIndex(where: { $0.id == id }) else { return }
        audioClips[ci].volume = volume
        audioPlayerCache[id]?.volume = Float(volume)
    }

    func toggleAudioClipMute(id: UUID) {
        guard let ci = audioClips.firstIndex(where: { $0.id == id }) else { return }
        audioClips[ci].isMuted.toggle()
        audioPlayerCache[id]?.isMuted = audioClips[ci].isMuted
    }

    /// Returns the total source duration of an audio clip (before trim).
    func audioClipTotalDuration(clipID: UUID) -> Double {
        guard let clip = audioClips.first(where: { $0.id == clipID }) else { return 0 }
        return clip.sourceDuration
    }

    func setupAudioPlayer(for clip: AudioClip) {
        let item = AVPlayerItem(asset: AVURLAsset(url: clip.sourceURL))
        let player = AVPlayer(playerItem: item)
        player.volume = Float(clip.volume)
        player.isMuted = clip.isMuted
        audioPlayerCache[clip.id] = player
    }

    func teardownAudioPlayer(id: UUID) {
        if let o = audioLooperCaches[id] {
            NotificationCenter.default.removeObserver(o)
            audioLooperCaches.removeValue(forKey: id)
        }
        audioPlayerCache[id]?.pause()
        audioPlayerCache.removeValue(forKey: id)
    }

    /// Sync audio players to match the main player's current state.
    func syncAudioPlayers() {
        guard let player else { return }
        let isPlaying = player.timeControlStatus == .playing
        for clip in audioClips {
            guard let audioPlayer = audioPlayerCache[clip.id] else { continue }
            let sourcePos = clip.timelineToSource(currentSeconds)
            let inRange = currentSeconds >= clip.timelineStart && currentSeconds <= clip.timelineEnd
            if isPlaying && inRange && !clip.isMuted {
                let target = CMTime(seconds: sourcePos, preferredTimescale: 600)
                audioPlayer.seek(to: target, toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600))
                audioPlayer.play()
            } else {
                audioPlayer.pause()
            }
        }
    }

    var exportQuality: ExportQuality = .high
    var exportRenderSize: ExportRenderSize = .hd1080
    var isExporting: Bool = false
    var exportProgress: Double = 0
    var lastExportError: String?
    /// URL of the most recently exported file. Shown as a "Reveal in Finder" button after export.
    var exportedFileURL: URL?

    var isMuted: Bool = true {
        didSet { player?.isMuted = isMuted }
    }

    /// Playback speed of the currently active clip.
    /// Setting this updates both the clip's stored speed and the AVPlayer rate.
    /// Also ripple-edits subsequent clips on the same track so they snap to the new clip end.
    var playbackSpeed: Double {
        get { activeClip?.speed ?? 1.0 }
        set {
            guard let id = activeClipID,
                  let idx = clips.firstIndex(where: { $0.id == id }) else { return }
            pushUndo()

            let oldSpeed = clips[idx].speed
            let newSpeed = max(0.25, min(newValue, 4.0))
            guard newSpeed != oldSpeed else { return }

            let oldTimelineDuration = clips[idx].timelineDuration
            let track = clips[idx].trackIndex
            let oldTimelineEnd = clips[idx].timelineEnd

            clips[idx].speed = newSpeed

            let newTimelineDuration = clips[idx].timelineDuration
            let delta = newTimelineDuration - oldTimelineDuration

            // Ripple: shift subsequent clips on the same track to close/open the gap
            if abs(delta) > 0.001 {
                for i in clips.indices where i != idx && clips[i].trackIndex == track {
                    if clips[i].timelineStart >= oldTimelineEnd - 0.001 {
                        clips[i].timelineStart = max(0, clips[i].timelineStart + delta)
                    }
                }
            }

            // Recalculate playhead position in new timeline coordinates
            if currentSeconds >= clips[idx].timelineStart && currentSeconds <= oldTimelineEnd {
                // Playhead was inside the speed-changed clip — remap to new coordinates
                let sourceTime = clips[idx].trimStartTime + (currentSeconds - clips[idx].timelineStart) * oldSpeed
                currentSeconds = clips[idx].sourceToTimeline(sourceTime)
            } else if abs(delta) > 0.001 && currentSeconds >= oldTimelineEnd {
                // Playhead is after the clip on the same track — shift with ripple
                let playheadClip = clip(at: currentSeconds)
                if let pc = playheadClip, pc.trackIndex == track {
                    currentSeconds = max(0, currentSeconds + delta)
                }
            }
            // Clamp to timeline if playhead ended up outside
            currentSeconds = clampedToTimeline(currentSeconds)

            if player?.timeControlStatus == .playing {
                player?.rate = Float(newSpeed)
            }
        }
    }

    /// Tracks which clip's speed was last applied to the player,
    /// so we only change rate on clip transitions.
    private var lastAppliedSpeedClipID: UUID?

    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?

    // MARK: - Undo/Redo stacks

    var undoStack: [ProjectSnapshot] = []
    var redoStack: [ProjectSnapshot] = []
    static let maxUndoDepth = 40

    // MARK: - Lifecycle

    deinit {
        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        SandboxHelper.cleanupCachedSource(at: videoURL)
    }

    var durationSeconds: Double {
        let s = videoDuration.seconds
        return (s.isFinite && s > 0) ? s : 0
    }

    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Zoom segment operations

    func segment(containing timelineTime: Double) -> ZoomSegment? {
        guard let clip = clips.first(where: {
            timelineTime >= $0.timelineStart && timelineTime <= $0.timelineEnd
        }) else { return nil }
        let s = clip.timelineToSource(timelineTime)
        return animations.first { s >= $0.startTime && s <= $0.endTime }
    }

    func addZoomSegment(at timelineTime: Double) -> ZoomSegment {
        let dur = ZoomSegment.defaultDuration
        guard let clipIndex = clips.firstIndex(where: {
            timelineTime >= $0.timelineStart && timelineTime <= $0.timelineEnd
        }) else {
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

    // MARK: - Playback

    func seek(to timelineSeconds: Double) {
        guard let player else { return }
        let clamped = clampedToTimeline(timelineSeconds)
        if let found = clip(at: clamped) {
            activeClipID = found.id
            let source = found.timelineToSource(clamped)
            let time = CMTime(seconds: source, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        currentSeconds = clamped
        syncAudioPlayers()
    }

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

        let durSeconds = duration.seconds.isFinite ? duration.seconds : 0
        let initialClip = VideoClip(
            id: UUID(),
            trimStartTime: 0,
            trimEndTime: max(durSeconds, 0),
            timelineStart: 0
        )
        self.clips = [initialClip]
        self.activeClipID = initialClip.id
        self.trackCount = 1
        self.currentSeconds = 0
        self.exportedFileURL = nil
        self.undoStack.removeAll()
        self.redoStack.removeAll()

        SandboxHelper.cleanupCachedSource(at: previousURL)

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let sourceTime = time.seconds
            if let playingClip = self.clips.first(where: {
                sourceTime >= $0.trimStartTime && sourceTime <= $0.trimEndTime
            }) {
                if playingClip.clipDuration > 0, sourceTime >= playingClip.trimEndTime - 0.01 {
                    let target = CMTime(seconds: playingClip.trimStartTime, preferredTimescale: 600)
                    self.player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                    self.currentSeconds = playingClip.timelineStart
                } else {
                    self.currentSeconds = playingClip.sourceToTimeline(sourceTime)
                }
                // Apply clip speed when transitioning between clips
                if self.lastAppliedSpeedClipID != playingClip.id {
                    self.lastAppliedSpeedClipID = playingClip.id
                    if self.player?.timeControlStatus == .playing {
                        self.player?.rate = Float(playingClip.speed)
                    }
                }
            } else {
                self.currentSeconds = sourceTime
            }
            // Sync audio players to the current playhead
            for clip in self.audioClips {
                guard let audioPlayer = self.audioPlayerCache[clip.id] else { continue }
                let inRange = self.currentSeconds >= clip.timelineStart && self.currentSeconds <= clip.timelineEnd
                if inRange && self.player?.timeControlStatus == .playing && !clip.isMuted {
                    let sourcePos = clip.timelineToSource(self.currentSeconds)
                    let currentAudioPos = audioPlayer.currentTime().seconds
                    if audioPlayer.timeControlStatus != .playing {
                        audioPlayer.seek(to: CMTime(seconds: sourcePos, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        audioPlayer.play()
                    } else if abs(currentAudioPos - sourcePos) > 0.3 {
                        audioPlayer.seek(to: CMTime(seconds: sourcePos, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                } else if audioPlayer.timeControlStatus == .playing {
                    audioPlayer.pause()
                }
            }
        }

        newPlayer.play()
        syncAudioPlayers()
    }

    func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            syncAudioPlayers()
        } else {
            if clip(at: currentSeconds) == nil {
                if let nearest = clips.min(by: { abs($0.timelineStart - currentSeconds) < abs($1.timelineStart - currentSeconds) }) {
                    seek(to: nearest.timelineStart)
                }
            }
            // Apply active clip's speed before playing
            if let activeClip {
                lastAppliedSpeedClipID = activeClip.id
                player.rate = Float(activeClip.speed)
            }
            syncAudioPlayers()
        }
    }

    // MARK: - Sandbox (delegates to SandboxHelper)

    static func cacheDirectory() throws -> URL {
        try SandboxHelper.cacheDirectory()
    }

    static func adoptIntoSandbox(_ source: URL) throws -> (sandboxURL: URL, displayName: String) {
        try SandboxHelper.adoptIntoSandbox(source)
    }

    static func cleanupCachedSource(at url: URL?) {
        SandboxHelper.cleanupCachedSource(at: url)
    }
}
