import AppKit
import AVFoundation
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.gmonchain.maya", category: "ExportUI")

struct EditorView: View {
    @State private var project = Project()
    @State private var stateManager = ProjectStateManager()
    @State private var blurPoster: NSImage?
    @State private var exporter = ExportService()
    @State private var recentProjects = RecentProjectsStore()
    
    private let newProjectPublisher = NotificationCenter.default.publisher(for: .newProject)
    private let openProjectPublisher = NotificationCenter.default.publisher(for: .openProject)
    private let saveProjectPublisher = NotificationCenter.default.publisher(for: .saveProject)
    private let importVideoPublisher = NotificationCenter.default.publisher(for: .importVideo)
    private let autoSaveTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(project: project, onExport: runExport)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    CanvasView(
                        project: project,
                        blurPoster: blurPoster,
                        recentProjects: recentProjects,
                        onOpenVideo: openVideoPicker,
                        onOpenProject: openProject,
                        onOpenRecentProject: openRecentProject
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard let url = urls.first else { return false }
                            importVideo(from: url)
                            return true
                        }

                    if project.videoURL != nil {
                        TimelineView(project: project) { segment in
                            project.selectedAnimationID = segment.id
                        }
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .background(keyboardShortcuts)

                if let selectedID = project.selectedAnimationID,
                   project.animations.contains(where: { $0.id == selectedID }) {
                    Divider()
                    AnimationEditorPanel(project: project, segmentID: selectedID) {
                        project.selectedAnimationID = nil
                    }
                    .frame(width: 340)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if let transitionID = project.selectedTransitionID,
                   project.transitions.contains(where: { $0.id == transitionID }) {
                    Divider()
                    TransitionPanel(project: project, transitionID: transitionID) {
                        project.selectedTransitionID = nil
                    }
                    .frame(width: 340)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if let audioClipID = project.activeAudioClipID,
                   project.audioClips.contains(where: { $0.id == audioClipID }),
                   project.selectedAnimationID == nil,
                   project.selectedTransitionID == nil {
                    Divider()
                    AudioEditorPanel(project: project, clipID: audioClipID) {
                        project.activeAudioClipID = nil
                    }
                    .frame(width: 340)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: project.selectedAnimationID)
            .animation(.easeInOut(duration: 0.2), value: project.selectedTransitionID)
            .animation(.easeInOut(duration: 0.2), value: project.activeAudioClipID)
        }
        .navigationTitle(stateManager.projectURL != nil ? stateManager.projectURL!.deletingPathExtension().lastPathComponent : "Maya")
        .onChange(of: project.videoURL) { _, _ in
            updateBlurPoster()
            project.validateForAppStore()
        }
        .onChange(of: project.canvasAspect) { _, _ in
            project.validateForAppStore()
        }
        .onChange(of: project.clips) { _, _ in
            project.validateForAppStore()
        }
        .onChange(of: project.exportFPS) { _, _ in
            project.validateForAppStore()
        }
        .onChange(of: project.exportVideoCodec) { _, _ in
            project.validateForAppStore()
        }
        .trackProjectChanges(project: project, stateManager: stateManager)
        .onReceive(newProjectPublisher) { _ in
            newProject()
        }
        .onReceive(openProjectPublisher) { _ in
            openProject()
        }
        .onReceive(saveProjectPublisher) { _ in
            saveProject()
        }
        .onReceive(importVideoPublisher) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                importVideo(from: url)
            }
        }
        .onReceive(autoSaveTimer) { _ in
            autoSave()
        }
    }

    /// Hidden buttons attach app-wide shortcuts without needing focus management.
    /// macOS automatically routes the key to the first responder first — so text
    /// fields keep typing spaces, deletes, etc., and these only fire when nothing
    /// else claims the event.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { project.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { deleteSelectedSegment() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { duplicateSelectedSegment() }
                .keyboardShortcut("d", modifiers: .command)
            Button("") { scrub(-0.25) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { scrub(+0.25) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { scrub(-1.0) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("") { scrub(+1.0) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("") { project.toggleMute() }
                .keyboardShortcut("m", modifiers: [])

            // Trim shortcuts (Final Cut / iMovie convention).
            Button("") { markTrimIn() }
                .keyboardShortcut("i", modifiers: [])
            Button("") { markTrimOut() }
                .keyboardShortcut("o", modifiers: [])
            Button("") { resetTrim() }
                .keyboardShortcut(.delete, modifiers: .option)

            // Split shortcut
            Button("") { project.splitAtPlayhead() }
                .keyboardShortcut("s", modifiers: [])

            // Undo / Redo
            Button("") { project.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("") { project.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func markTrimIn() {
        guard project.videoURL != nil else { return }
        project.pushUndo()
        let newSource = project.timelineToSource(project.currentSeconds)
        let delta = newSource - project.trimStartTime
        project.setTrimStart(newSource)
        project.clipTimelineStart += delta
    }

    private func markTrimOut() {
        guard project.videoURL != nil else { return }
        project.pushUndo()
        let newSource = project.timelineToSource(project.currentSeconds)
        project.setTrimEnd(newSource)
    }

    private func resetTrim() {
        guard project.videoURL != nil else { return }
        project.pushUndo()
        project.trimStartTime = 0
        project.trimEndTime = project.durationSeconds
        project.clipTimelineStart = 0
    }

    private func deleteSelectedSegment() {
        // Priority: if a zoom animation is selected, delete it.
        if let id = project.selectedAnimationID {
            project.removeZoomSegment(id: id)
            return
        }
        // Otherwise delete the active clip (ripple: remaining clips close the gap).
        project.deleteActiveClip()
    }

    private func duplicateSelectedSegment() {
        guard let id = project.selectedAnimationID else { return }
        _ = project.duplicateZoomSegment(id: id)
    }

    private func scrub(_ delta: Double) {
        guard project.videoURL != nil else { return }
        project.seek(to: project.currentSeconds + delta)
    }

    private func updateBlurPoster() {
        guard case .videoBlur = project.background,
              let url = project.videoURL else {
            blurPoster = nil
            return
        }
        Task {
            let image = await BlurPosterCache.shared.poster(for: url)
            await MainActor.run { self.blurPoster = image }
        }
    }

    private func importVideo(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        do {
            let adopted = try Project.adoptIntoSandbox(url)
            if didStart { url.stopAccessingSecurityScopedResource() }
            Task {
                project.displayName = adopted.displayName
                await project.loadVideo(url: adopted.sandboxURL)
            }
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            project.lastExportError = "Could not import video: \(error.localizedDescription)"
        }
    }

    private func openVideoPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importVideo(from: url)
        }
    }

    private func openRecentProject(_ url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try ProjectService.load(from: url)
            stateManager.projectURL = url
            stateManager.markClean()
            recentProjects.didOpen(url: url)
            project = Project()
            Task { @MainActor in
                await project.loadFromProjectFile(
                    loaded.projectFile,
                    videoURL: loaded.videoURL,
                    audioURLs: loaded.audioURLs,
                    imageURLs: loaded.imageURLs,
                    backgroundVideoURLs: loaded.backgroundVideoURLs
                )
                blurPoster = nil
                updateBlurPoster()
                project.validateForAppStore()
            }
        } catch {
            project.lastExportError = "Failed to open project: \(error.localizedDescription)"
        }
    }

    private func runExport() {
        let isTransparent = project.background.isTransparent
        let ext = isTransparent ? "mov" : project.exportVideoCodec.fileExtension
        let suggestedName = "Maya-export.\(ext)"
        let types: [UTType] = isTransparent ? [.quickTimeMovie] : [project.exportVideoCodec.utType]

        runSavePanel(suggestedName: suggestedName, allowedTypes: types) { url in
            Task {
                project.isExporting = true
                project.lastExportError = nil
                project.exportProgress = 0
                project.exportedFileURL = nil
                log.info("▶ Export started — mode: \(isTransparent ? "transparent" : "background", privacy: .public), quality: \(String(describing: project.exportQuality), privacy: .public), size: \(project.exportRenderSize.shortSide, privacy: .public)px")
                do {
                    if isTransparent {
                        try await exporter.exportTransparent(
                            project: project,
                            to: url,
                            progress: { p in Task { @MainActor in project.exportProgress = p } }
                        )
                    } else {
                        try await exporter.exportWithBackground(
                            project: project,
                            to: url,
                            progress: { p in Task { @MainActor in project.exportProgress = p } }
                        )
                    }
                    await MainActor.run { project.exportedFileURL = url }
                    // Inspect exported video for detailed metadata.
                    let info = await ExportedVideoInspector.inspect(file: url)
                    await MainActor.run { project.exportedVideoInfo = info }
                    log.info("✓ Export completed successfully: \(url.lastPathComponent, privacy: .public)")
                } catch {
                    let nsError = error as NSError
                    log.error("✗ Export FAILED — description: \(error.localizedDescription, privacy: .public), domain: \(nsError.domain, privacy: .public), code: \(nsError.code, privacy: .public)")
                    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                        log.error("  underlying error: \(underlying.localizedDescription, privacy: .public)")
                    }
                    // Capture the full NSError for debugging
                    let fullError = "\(error.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))"
                    await MainActor.run { project.lastExportError = fullError }
                }
                project.isExporting = false
            }
        }
    }

    private func runSavePanel(suggestedName: String, allowedTypes: [UTType], onPick: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
    
    // MARK: - Project Save/Open

    /// Auto-save: fires every 5s but only writes if the project has a save location and unsaved changes.
    private func autoSave() {
        guard stateManager.projectURL != nil else { return }
        guard stateManager.hasUnsavedChanges else { return }
        do {
            try ProjectService.save(project: project, to: stateManager.projectURL!)
            stateManager.markClean()
        } catch {
            // Silently ignore auto-save errors to avoid nagging the user.
            // Errors on manual save are surfaced via saveProject().
        }
    }

    private func saveProject() {
        stateManager.saveProject(project: project) { error in
            project.lastExportError = error
        }
        if let url = stateManager.projectURL {
            recentProjects.didOpen(url: url)
        }
    }
    
    private func newProject() {
        project = Project()
        stateManager.newProject()
        blurPoster = nil
    }
    
    private func openProject() {
        stateManager.openProject(
            onSuccess: { [self] url, projectFile, videoURL, audioURLs, imageURLs, backgroundVideoURLs in
                recentProjects.didOpen(url: url)
                project = Project()
                Task { @MainActor in
                    await project.loadFromProjectFile(
                        projectFile,
                        videoURL: videoURL,
                        audioURLs: audioURLs,
                        imageURLs: imageURLs,
                        backgroundVideoURLs: backgroundVideoURLs
                    )
                    blurPoster = nil
                    updateBlurPoster()
                    project.validateForAppStore()
                }
            },
            onError: { error in
                project.lastExportError = error
            }
        )
    }
}
