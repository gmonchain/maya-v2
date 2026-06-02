import Foundation
import SwiftUI

// MARK: - Undo snapshot

/// Captures all mutable editing state so it can be saved/restored for undo/redo.
/// Does NOT include player, videoURL, videoDuration, etc. — those are invariant
/// across editing actions.
struct ProjectSnapshot: Equatable, Sendable {
    var clips: [VideoClip]
    var activeClipID: UUID?
    var trackCount: Int
    var animations: [ZoomSegment]
    var selectedAnimationID: ZoomSegment.ID?
    var transitions: [Transition]
    var selectedTransitionID: Transition.ID?
    var scale: CGFloat
    var offset: CGSize
    var background: BackgroundOption
    var shadow: PhoneShadow
    var audioClips: [AudioClip]
    var activeAudioClipID: UUID?
    var backgroundBlurRadius: Double
    var exportQuality: ExportQuality
    var exportRenderSize: ExportRenderSize
}

// MARK: - Undo / Redo

extension Project {

    /// Pushes the current editing state onto the undo stack, clearing redo.
    func pushUndo() {
        undoStack.append(makeSnapshot())
        if undoStack.count > Self.maxUndoDepth {
            undoStack.removeFirst()
        }
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

    // MARK: - Internal helpers

    func makeSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            clips: clips,
            activeClipID: activeClipID,
            trackCount: trackCount,
            animations: animations,
            selectedAnimationID: selectedAnimationID,
            transitions: transitions,
            selectedTransitionID: selectedTransitionID,
            scale: scale,
            offset: offset,
            background: background,
            shadow: shadow,
            audioClips: audioClips,
            activeAudioClipID: activeAudioClipID,
            backgroundBlurRadius: backgroundBlurRadius,
            exportQuality: exportQuality,
            exportRenderSize: exportRenderSize
        )
    }

    func restore(from snapshot: ProjectSnapshot) {
        clips = snapshot.clips
        activeClipID = snapshot.activeClipID
        trackCount = snapshot.trackCount
        animations = snapshot.animations
        selectedAnimationID = snapshot.selectedAnimationID
        transitions = snapshot.transitions
        selectedTransitionID = snapshot.selectedTransitionID
        scale = snapshot.scale
        offset = snapshot.offset
        background = snapshot.background
        shadow = snapshot.shadow
        audioClips = snapshot.audioClips
        activeAudioClipID = snapshot.activeAudioClipID
        backgroundBlurRadius = snapshot.backgroundBlurRadius
        exportQuality = snapshot.exportQuality
        exportRenderSize = snapshot.exportRenderSize
    }
}
