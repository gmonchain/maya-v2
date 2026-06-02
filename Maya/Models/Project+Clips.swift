import AVFoundation
import CoreMedia
import Foundation
import Observation
import SwiftUI

// MARK: - Clip operations

extension Project {

    // MARK: - Clip state accessors

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

    /// Returns true when a clip (not just a zoom animation) is the primary selection.
    var isClipSelected: Bool {
        activeClipID != nil && selectedAnimationID == nil
    }

    // MARK: - Trim computed properties

    /// In/out points on the *source* video for the active clip.
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

    /// Where the trimmed clip sits on the project timeline.
    var clipTimelineStart: Double {
        get { activeClip?.timelineStart ?? 0 }
        set {
            guard let idx = activeClipIndex else { return }
            var clip = clips[idx]
            clip.timelineStart = max(0, newValue)
            clips[idx] = clip
        }
    }

    static let minTrimDuration: Double = VideoClip.minDuration

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

    // MARK: - Clip duration / timeline helpers

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

    /// Length of the project timeline shown in the editor.
    /// Accounts for video clips, audio clips, and the raw video duration.
    var timelineDuration: Double {
        let maxClipEnd = clips.map(\.timelineEnd).max() ?? 0
        let maxAudioEnd = audioClips.map(\.timelineEnd).max() ?? 0
        return max(durationSeconds, maxClipEnd, maxAudioEnd)
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

    /// Converts a project-timeline second to its source-video second.
    func timelineToSource(_ t: Double) -> Double {
        activeClip?.timelineToSource(t) ?? t
    }

    /// Inverse of `timelineToSource`.
    func sourceToTimeline(_ s: Double) -> Double {
        activeClip?.sourceToTimeline(s) ?? s
    }

    /// Clamps a timeline second into the active clip's window.
    func clampedToClip(_ t: Double) -> Double {
        guard let clip = activeClip, clip.clipDuration > 0 else { return activeClip?.timelineStart ?? 0 }
        if t < clip.timelineStart { return clip.timelineStart }
        if t > clip.timelineEnd { return clip.timelineEnd }
        return t
    }

    /// Clamps a timeline second to the full span covered by ALL clips.
    func clampedToTimeline(_ t: Double) -> Double {
        guard !clips.isEmpty else { return max(0, t) }
        let maxEnd = clips.map(\.timelineEnd).max() ?? 0
        return max(0, min(t, maxEnd))
    }

    /// Finds the clip at a timeline position, or nil if in a gap.
    func clip(at timelineSeconds: Double) -> VideoClip? {
        clips.first(where: { timelineSeconds >= $0.timelineStart && timelineSeconds <= $0.timelineEnd })
    }

    // MARK: - Split at playhead

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
            timelineStart: clip.timelineStart,
            trackIndex: clip.trackIndex
        )

        let rightClip = VideoClip(
            id: UUID(),
            trimStartTime: sourceSplitTime,
            trimEndTime: clip.trimEndTime,
            timelineStart: timelinePos,
            trackIndex: clip.trackIndex
        )

        clips.remove(at: clipIndex)
        clips.insert(contentsOf: [leftClip, rightClip], at: clipIndex)

        activeClipID = rightClip.id
        cleanupTransitions()
    }

    // MARK: - Delete clip

    func deleteActiveClip() {
        guard let idx = activeClipIndex, clips.count > 1 else { return }
        pushUndo()
        let deletedClip = clips[idx]
        let gap = deletedClip.timelineDuration
        let deletedTrack = deletedClip.trackIndex

        clips.remove(at: idx)

        // Ripple only clips on the same track
        for i in idx..<clips.count where clips[i].trackIndex == deletedTrack {
            var clip = clips[i]
            clip.timelineStart = max(0, clip.timelineStart - gap)
            clips[i] = clip
        }

        if idx < clips.count {
            activeClipID = clips[idx].id
        } else {
            activeClipID = clips.last?.id
        }

        animations.removeAll { seg in
            !clips.contains(where: { clip in
                seg.startTime >= clip.trimStartTime && seg.startTime < clip.trimEndTime
            })
        }
        cleanupTransitions()
    }

    // MARK: - Snap / Overlap

    /// Given a proposed timeline start for a clip at `clipIndex`, snaps it to the
    /// nearest edge of another clip on the SAME TRACK if within `threshold` seconds,
    /// then ensures the final position does not overlap any other clip on the same track.
    func snapClipPosition(_ proposedStart: Double, duration clipDur: Double, excludingClipAt clipIndex: Int) -> Double {
        guard !allowClipOverlap, clips.count > 1 else { return proposedStart }
        let threshold: Double = 0.3
        let proposedEnd = proposedStart + clipDur
        let track = clips[clipIndex].trackIndex

        var bestSnap = proposedStart
        var bestDistance = Double.infinity

        for (i, other) in clips.enumerated() {
            guard i != clipIndex, other.trackIndex == track else { continue }
            let otherStart = other.timelineStart
            let otherEnd = other.timelineEnd

            let distToAfter = abs(proposedStart - otherEnd)
            if distToAfter < threshold && distToAfter < bestDistance {
                bestDistance = distToAfter
                bestSnap = otherEnd
            }
            let distToBefore = abs(proposedStart - otherStart)
            if distToBefore < threshold && distToBefore < bestDistance {
                bestDistance = distToBefore
                bestSnap = otherStart
            }
            let distEndToStart = abs(proposedEnd - otherStart)
            if distEndToStart < threshold && distEndToStart < bestDistance {
                bestDistance = distEndToStart
                bestSnap = otherStart - clipDur
            }
        }

        if wouldOverlap(start: bestSnap, duration: clipDur, excludingClipAt: clipIndex) {
            var pushTo: Double = 0
            for (i, other) in clips.enumerated() {
                guard i != clipIndex, other.trackIndex == track else { continue }
                if other.timelineEnd <= bestSnap + clipDur && other.timelineEnd > pushTo {
                    pushTo = other.timelineEnd
                }
            }
            bestSnap = pushTo
        }

        return bestSnap
    }

    /// Returns true if placing a clip at `start` with `duration` would overlap
    /// any other clip on the same track (excluding the clip at `excludeIndex`).
    func wouldOverlap(start: Double, duration clipDur: Double, excludingClipAt excludeIndex: Int) -> Bool {
        guard !allowClipOverlap else { return false }
        let end = start + clipDur
        let track = clips[excludeIndex].trackIndex
        for (i, other) in clips.enumerated() {
            guard i != excludeIndex, other.trackIndex == track else { continue }
            if start < other.timelineEnd && end > other.timelineStart {
                return true
            }
        }
        return false
    }

    // MARK: - Transitions

    /// Returns the transition between two clips, if any exists.
    func transition(between beforeID: UUID, and afterID: UUID) -> Transition? {
        transitions.first { $0.clipBeforeID == beforeID && $0.clipAfterID == afterID }
    }

    /// Returns the transition at the boundary of two adjacent clips on the same track.
    /// Finds clips on the same track where one ends near where the other begins.
    func transition(betweenClipsAt timelinePosition: Double, onTrack track: Int) -> Transition? {
        // Find clips on this track adjacent to the position
        let trackClips = clips
            .filter { $0.trackIndex == track }
            .sorted { $0.timelineStart < $1.timelineStart }

        for i in 0..<(trackClips.count - 1) {
            let clip = trackClips[i]
            let nextClip = trackClips[i + 1]
            // Check if position is near the boundary between these two clips
            if abs(timelinePosition - clip.timelineEnd) < 0.5 ||
               abs(timelinePosition - nextClip.timelineStart) < 0.5 {
                return transition(between: clip.id, and: nextClip.id)
            }
        }
        return nil
    }

    /// Adds or updates a transition between two clips.
    @discardableResult
    func addTransition(beforeID: UUID, afterID: UUID, type: TransitionType = .fade) -> Transition {
        pushUndo()
        // Check if transition already exists
        if let existing = transition(between: beforeID, and: afterID) {
            if let idx = transitions.firstIndex(where: { $0.id == existing.id }) {
                transitions[idx].type = type
                selectedTransitionID = existing.id
                return transitions[idx]
            }
        }
        let t = Transition(clipBeforeID: beforeID, clipAfterID: afterID, type: type)
        transitions.append(t)
        selectedTransitionID = t.id
        return t
    }

    /// Removes a transition by ID.
    func removeTransition(id: UUID) {
        pushUndo()
        transitions.removeAll { $0.id == id }
        if selectedTransitionID == id {
            selectedTransitionID = nil
        }
    }

    /// Updates a transition's properties.
    func updateTransition(_ transition: Transition) {
        guard let idx = transitions.firstIndex(where: { $0.id == transition.id }) else { return }
        transitions[idx] = transition
    }

    /// Removes transitions that reference deleted clips.
    func cleanupTransitions() {
        let clipIDs = Set(clips.map(\.id))
        transitions.removeAll { !clipIDs.contains($0.clipBeforeID) || !clipIDs.contains($0.clipAfterID) }
        if let selID = selectedTransitionID, !transitions.contains(where: { $0.id == selID }) {
            selectedTransitionID = nil
        }
    }

    /// Returns the active transition at the current playhead position, if any.
    /// Also returns the progress through the transition (0.0 to 1.0).
    func activeTransition(at time: Double) -> (transition: Transition, progress: Double)? {
        for transition in transitions {
            guard let beforeClip = clips.first(where: { $0.id == transition.clipBeforeID }),
                  let afterClip = clips.first(where: { $0.id == transition.clipAfterID }) else {
                continue
            }

            let transitionStart = beforeClip.timelineEnd - transition.duration
            let transitionEnd = beforeClip.timelineEnd

            if time >= transitionStart && time <= transitionEnd {
                let progress = (time - transitionStart) / transition.duration
                return (transition, progress)
            }
        }
        return nil
    }
}
