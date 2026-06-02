import Foundation

/// File format for saving/loading Maya projects as `.mayaproj` JSON files.
/// Contains all editing state except the video URL (which is tracked separately
/// via sandbox adoption) and the AVPlayer instances.
struct MayaProjectFile: Codable, Sendable {
    var version: Int = 1
    var videoFileName: String?
    var displayName: String?

    // Canvas
    var canvasAspect: String
    var backgroundBlurRadius: Double

    // Device
    var deviceModelID: String
    var deviceColorID: String
    var bareCornerRadius: Double
    var bareBezelWidth: Double
    var bareBezelHex: String

    // Transform
    var scale: Double
    var offsetX: Double
    var offsetY: Double

    // Background
    var background: BackgroundData

    // Shadow
    var shadow: ShadowData

    // Clips
    var clips: [ClipData]
    var activeClipID: String?
    var allowClipOverlap: Bool
    var trackCount: Int

    // Animations
    var animations: [AnimationData]
    var selectedAnimationID: String?

    // Transitions
    var transitions: [Transition]
    var selectedTransitionID: String?

    // Audio
    var audioClips: [AudioClipData]
    var activeAudioClipID: String?

    // Export
    var exportQuality: String
    var exportRenderSize: String

    // Playback position
    var currentSeconds: Double
    
    // Playback speed
    var playbackSpeed: Double
    
    // MARK: - Memberwise initializer
    
    init(
        version: Int = 1,
        videoFileName: String? = nil,
        displayName: String? = nil,
        canvasAspect: String,
        backgroundBlurRadius: Double,
        deviceModelID: String,
        deviceColorID: String,
        bareCornerRadius: Double,
        bareBezelWidth: Double,
        bareBezelHex: String,
        scale: Double,
        offsetX: Double,
        offsetY: Double,
        background: BackgroundData,
        shadow: ShadowData,
        clips: [ClipData],
        activeClipID: String? = nil,
        allowClipOverlap: Bool,
        trackCount: Int,
        animations: [AnimationData],
        selectedAnimationID: String? = nil,
        transitions: [Transition] = [],
        selectedTransitionID: String? = nil,
        audioClips: [AudioClipData],
        activeAudioClipID: String? = nil,
        exportQuality: String,
        exportRenderSize: String,
        currentSeconds: Double,
        playbackSpeed: Double = 1.0
    ) {
        self.version = version
        self.videoFileName = videoFileName
        self.displayName = displayName
        self.canvasAspect = canvasAspect
        self.backgroundBlurRadius = backgroundBlurRadius
        self.deviceModelID = deviceModelID
        self.deviceColorID = deviceColorID
        self.bareCornerRadius = bareCornerRadius
        self.bareBezelWidth = bareBezelWidth
        self.bareBezelHex = bareBezelHex
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.background = background
        self.shadow = shadow
        self.clips = clips
        self.activeClipID = activeClipID
        self.allowClipOverlap = allowClipOverlap
        self.trackCount = trackCount
        self.animations = animations
        self.selectedAnimationID = selectedAnimationID
        self.transitions = transitions
        self.selectedTransitionID = selectedTransitionID
        self.audioClips = audioClips
        self.activeAudioClipID = activeAudioClipID
        self.exportQuality = exportQuality
        self.exportRenderSize = exportRenderSize
        self.currentSeconds = currentSeconds
        self.playbackSpeed = playbackSpeed
    }
    
    // MARK: - Custom decoding for backwards compatibility
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        videoFileName = try container.decodeIfPresent(String.self, forKey: .videoFileName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        canvasAspect = try container.decode(String.self, forKey: .canvasAspect)
        backgroundBlurRadius = try container.decode(Double.self, forKey: .backgroundBlurRadius)
        deviceModelID = try container.decode(String.self, forKey: .deviceModelID)
        deviceColorID = try container.decode(String.self, forKey: .deviceColorID)
        bareCornerRadius = try container.decode(Double.self, forKey: .bareCornerRadius)
        bareBezelWidth = try container.decode(Double.self, forKey: .bareBezelWidth)
        bareBezelHex = try container.decode(String.self, forKey: .bareBezelHex)
        scale = try container.decode(Double.self, forKey: .scale)
        offsetX = try container.decode(Double.self, forKey: .offsetX)
        offsetY = try container.decode(Double.self, forKey: .offsetY)
        background = try container.decode(BackgroundData.self, forKey: .background)
        shadow = try container.decode(ShadowData.self, forKey: .shadow)
        clips = try container.decode([ClipData].self, forKey: .clips)
        activeClipID = try container.decodeIfPresent(String.self, forKey: .activeClipID)
        allowClipOverlap = try container.decode(Bool.self, forKey: .allowClipOverlap)
        trackCount = try container.decode(Int.self, forKey: .trackCount)
        animations = try container.decode([AnimationData].self, forKey: .animations)
        selectedAnimationID = try container.decodeIfPresent(String.self, forKey: .selectedAnimationID)
        transitions = try container.decodeIfPresent([Transition].self, forKey: .transitions) ?? []
        selectedTransitionID = try container.decodeIfPresent(String.self, forKey: .selectedTransitionID)
        audioClips = try container.decodeIfPresent([AudioClipData].self, forKey: .audioClips) ?? []
        activeAudioClipID = try container.decodeIfPresent(String.self, forKey: .activeAudioClipID)
        exportQuality = try container.decode(String.self, forKey: .exportQuality)
        exportRenderSize = try container.decode(String.self, forKey: .exportRenderSize)
        currentSeconds = try container.decode(Double.self, forKey: .currentSeconds)
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1.0
    }
}

// MARK: - Background serialization

enum BackgroundData: Codable, Sendable {
    case none
    case solid(hex: String)
    case gradient(startHex: String, endHex: String, angleDegrees: Double)
    case image(fileName: String)
    case video(fileName: String)
    case videoBlur

    init(from background: BackgroundOption) {
        switch background {
        case .none:
            self = .none
        case .solid(let hex):
            self = .solid(hex: hex)
        case .gradient(let spec):
            self = .gradient(startHex: spec.startHex, endHex: spec.endHex, angleDegrees: spec.angleDegrees)
        case .image(let url):
            self = .image(fileName: url.lastPathComponent)
        case .video(let url):
            self = .video(fileName: url.lastPathComponent)
        case .videoBlur:
            self = .videoBlur
        }
    }

    func toBackgroundOption() -> BackgroundOption {
        switch self {
        case .none:
            return .none
        case .solid(let hex):
            return .solid(hex: hex)
        case .gradient(let startHex, let endHex, let angle):
            return .gradient(GradientSpec(startHex: startHex, endHex: endHex, angleDegrees: angle))
        case .image:
            // Image background requires the file to be copied into sandbox during load.
            // This is handled by ProjectService.
            return .solid(hex: "#000000") // Fallback, will be overridden
        case .video:
            // Video background requires the file to be copied into sandbox during load.
            // This is handled by ProjectService.
            return .solid(hex: "#000000") // Fallback, will be overridden
        case .videoBlur:
            return .videoBlur
        }
    }
}

// MARK: - Shadow serialization

struct ShadowData: Codable, Sendable {
    var enabled: Bool
    var colorHex: String
    var radius: Double
    var offsetY: Double
    var offsetX: Double
    var opacity: Double

    init(from shadow: PhoneShadow) {
        self.enabled = shadow.enabled
        self.colorHex = shadow.colorHex
        self.radius = Double(shadow.radius)
        self.offsetY = Double(shadow.offsetY)
        self.offsetX = Double(shadow.offsetX)
        self.opacity = shadow.opacity
    }

    func toPhoneShadow() -> PhoneShadow {
        var shadow = PhoneShadow()
        shadow.enabled = enabled
        shadow.colorHex = colorHex
        shadow.radius = CGFloat(radius)
        shadow.offsetY = CGFloat(offsetY)
        shadow.offsetX = CGFloat(offsetX)
        shadow.opacity = opacity
        return shadow
    }
}

// MARK: - Clip serialization

struct ClipData: Codable, Sendable {
    var id: String
    var trimStartTime: Double
    var trimEndTime: Double
    var timelineStart: Double
    var trackIndex: Int
    var speed: Double

    init(from clip: VideoClip) {
        self.id = clip.id.uuidString
        self.trimStartTime = clip.trimStartTime
        self.trimEndTime = clip.trimEndTime
        self.timelineStart = clip.timelineStart
        self.trackIndex = clip.trackIndex
        self.speed = clip.speed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        trimStartTime = try container.decode(Double.self, forKey: .trimStartTime)
        trimEndTime = try container.decode(Double.self, forKey: .trimEndTime)
        timelineStart = try container.decode(Double.self, forKey: .timelineStart)
        trackIndex = try container.decode(Int.self, forKey: .trackIndex)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
    }

    func toVideoClip() -> VideoClip? {
        guard let id = UUID(uuidString: id) else { return nil }
        return VideoClip(
            id: id,
            trimStartTime: trimStartTime,
            trimEndTime: trimEndTime,
            timelineStart: timelineStart,
            trackIndex: trackIndex,
            speed: speed
        )
    }
}

// MARK: - Animation serialization

struct AnimationData: Codable, Sendable {
    var id: String
    var startTime: Double
    var duration: Double
    var scale: Double
    var focus: String
    var transitionIn: Double
    var transitionOut: Double
    var curve: String

    init(from segment: ZoomSegment) {
        self.id = segment.id.uuidString
        self.startTime = segment.startTime
        self.duration = segment.duration
        self.scale = Double(segment.scale)
        self.focus = segment.focus.rawValue
        self.transitionIn = segment.transitionIn
        self.transitionOut = segment.transitionOut
        self.curve = segment.curve.rawValue
    }

    func toZoomSegment() -> ZoomSegment? {
        guard let id = UUID(uuidString: id),
              let focus = ZoomFocus(rawValue: focus),
              let curve = AnimationCurve(rawValue: curve) else { return nil }
        return ZoomSegment(
            id: id,
            startTime: startTime,
            duration: duration,
            scale: CGFloat(scale),
            focus: focus,
            transitionIn: transitionIn,
            transitionOut: transitionOut,
            curve: curve
        )
    }
}

// MARK: - Audio clip serialization

struct AudioClipData: Codable, Sendable {
    var id: String
    var fileName: String
    var displayName: String
    var trimStartTime: Double
    var trimEndTime: Double
    var timelineStart: Double
    var volume: Double
    var isMuted: Bool
    var sourceDuration: Double

    init(from clip: AudioClip) {
        self.id = clip.id.uuidString
        self.fileName = clip.sourceURL.lastPathComponent
        self.displayName = clip.displayName
        self.trimStartTime = clip.trimStartTime
        self.trimEndTime = clip.trimEndTime
        self.timelineStart = clip.timelineStart
        self.volume = clip.volume
        self.isMuted = clip.isMuted
        self.sourceDuration = clip.sourceDuration
    }

    func toAudioClip(sandboxURL: URL) -> AudioClip? {
        guard let id = UUID(uuidString: id) else { return nil }
        return AudioClip(
            id: id,
            sourceURL: sandboxURL,
            displayName: displayName,
            trimStartTime: trimStartTime,
            trimEndTime: trimEndTime,
            timelineStart: timelineStart,
            volume: volume,
            isMuted: isMuted,
            sourceDuration: sourceDuration
        )
    }
}

// MARK: - Project extension for save/load

extension Project {

    /// Loads project state from a deserialized project file bundle.
    /// This loads the video, audio clips, background image, and restores all editing state.
    func loadFromProjectFile(
        _ file: MayaProjectFile,
        videoURL: URL,
        audioURLs: [String: URL],
        imageURLs: [String: URL],
        backgroundVideoURLs: [String: URL] = [:]
    ) async {
        // Load the video first
        await loadVideo(url: videoURL)

        // Restore canvas
        if let aspect = CanvasAspectRatio(rawValue: file.canvasAspect) {
            canvasAspect = aspect
        }
        backgroundBlurRadius = file.backgroundBlurRadius

        // Restore device
        if DeviceModel.model(id: file.deviceModelID) != nil {
            deviceModelID = file.deviceModelID
            deviceColorID = file.deviceColorID
        }
        bareCornerRadius = CGFloat(file.bareCornerRadius)
        bareBezelWidth = CGFloat(file.bareBezelWidth)
        bareBezelHex = file.bareBezelHex

        // Restore transform
        scale = CGFloat(file.scale)
        offset = CGSize(width: file.offsetX, height: file.offsetY)

        // Restore background
        switch file.background {
        case .none:
            background = .none
        case .solid(let hex):
            background = .solid(hex: hex)
        case .gradient(let startHex, let endHex, let angle):
            background = .gradient(GradientSpec(startHex: startHex, endHex: endHex, angleDegrees: angle))
        case .image(let fileName):
            if let url = imageURLs[fileName] {
                background = .image(url)
            }
        case .video(let fileName):
            if let url = backgroundVideoURLs[fileName] {
                background = .video(url)
            }
        case .videoBlur:
            background = .videoBlur
        }

        // Restore shadow
        shadow = file.shadow.toPhoneShadow()

        // Restore clips
        clips = file.clips.compactMap { $0.toVideoClip() }
        if let activeID = file.activeClipID,
           let uuid = UUID(uuidString: activeID),
           clips.contains(where: { $0.id == uuid }) {
            activeClipID = uuid
        } else {
            activeClipID = clips.first?.id
        }
        allowClipOverlap = file.allowClipOverlap
        trackCount = file.trackCount

        // Restore animations
        animations = file.animations.compactMap { $0.toZoomSegment() }
        if let selID = file.selectedAnimationID,
           let uuid = UUID(uuidString: selID),
           animations.contains(where: { $0.id == uuid }) {
            selectedAnimationID = uuid
        } else {
            selectedAnimationID = nil
        }

        // Restore transitions
        transitions = file.transitions
        if let selID = file.selectedTransitionID,
           let uuid = UUID(uuidString: selID),
           transitions.contains(where: { $0.id == uuid }) {
            selectedTransitionID = uuid
        } else {
            selectedTransitionID = nil
        }

        // Restore audio clips
        audioClips = []
        audioClips.removeAll()
        for clipData in file.audioClips {
            guard let sandboxURL = audioURLs[clipData.fileName],
                  let clip = clipData.toAudioClip(sandboxURL: sandboxURL) else { continue }
            audioClips.append(clip)
            setupAudioPlayer(for: clip)
        }
        if let activeID = file.activeAudioClipID,
           let uuid = UUID(uuidString: activeID),
           audioClips.contains(where: { $0.id == uuid }) {
            activeAudioClipID = uuid
        } else {
            activeAudioClipID = audioClips.first?.id
        }
        syncAudioPlayers()

        // Restore export settings
        if let quality = ExportQuality(rawValue: file.exportQuality) {
            exportQuality = quality
        }
        if let renderSize = ExportRenderSize(rawValue: file.exportRenderSize) {
            exportRenderSize = renderSize
        }

        // Restore display name
        displayName = file.displayName

        // Restore playback position
        seek(to: file.currentSeconds)
        
        // Restore playback speed
        playbackSpeed = file.playbackSpeed

        // Clear undo/redo for fresh project
        undoStack.removeAll()
        redoStack.removeAll()
    }

    func toProjectFile() -> MayaProjectFile {
        MayaProjectFile(
            videoFileName: videoURL?.lastPathComponent,
            displayName: displayName,
            canvasAspect: canvasAspect.rawValue,
            backgroundBlurRadius: backgroundBlurRadius,
            deviceModelID: deviceModelID,
            deviceColorID: deviceColorID,
            bareCornerRadius: Double(bareCornerRadius),
            bareBezelWidth: Double(bareBezelWidth),
            bareBezelHex: bareBezelHex,
            scale: Double(scale),
            offsetX: Double(offset.width),
            offsetY: Double(offset.height),
            background: BackgroundData(from: background),
            shadow: ShadowData(from: shadow),
            clips: clips.map { ClipData(from: $0) },
            activeClipID: activeClipID?.uuidString,
            allowClipOverlap: allowClipOverlap,
            trackCount: trackCount,
            animations: animations.map { AnimationData(from: $0) },
            selectedAnimationID: selectedAnimationID?.uuidString,
            transitions: transitions,
            selectedTransitionID: selectedTransitionID?.uuidString,
            audioClips: audioClips.map { AudioClipData(from: $0) },
            activeAudioClipID: activeAudioClipID?.uuidString,
            exportQuality: exportQuality.rawValue,
            exportRenderSize: exportRenderSize.rawValue,
            currentSeconds: currentSeconds,
            playbackSpeed: playbackSpeed
        )
    }
}
