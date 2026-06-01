import AVFoundation
import Foundation
import Observation
import SwiftUI

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

    // MARK: - Multi-clip state

    var clips: [VideoClip] = []
    var activeClipID: UUID?
    var allowClipOverlap: Bool = false

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var lastExportError: String?

    var isMuted: Bool = true {
        didSet { player?.isMuted = isMuted }
    }

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
        self.currentSeconds = 0
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
            if clip(at: currentSeconds) == nil {
                if let nearest = clips.min(by: { abs($0.timelineStart - currentSeconds) < abs($1.timelineStart - currentSeconds) }) {
                    seek(to: nearest.timelineStart)
                }
            }
            player.play()
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
