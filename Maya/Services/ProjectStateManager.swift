import SwiftUI
import UniformTypeIdentifiers

/// Manages project save/open state and tracks unsaved changes.
/// Separated from EditorView to avoid compiler timeout and make it easier
/// to maintain when adding new features.
@Observable
final class ProjectStateManager {
    var projectURL: URL?
    var hasUnsavedChanges = false
    
    func markDirty() {
        hasUnsavedChanges = true
    }
    
    func markClean() {
        hasUnsavedChanges = false
    }
    
    func saveProject(project: Project, onError: @escaping (String) -> Void) {
        if let existingURL = projectURL {
            // Save to existing location
            do {
                try ProjectService.save(project: project, to: existingURL)
                markClean()
            } catch {
                onError("Failed to save project: \(error.localizedDescription)")
            }
        } else {
            // Save As
            let panel = NSSavePanel()
            panel.nameFieldStringValue = project.displayName ?? "Untitled"
            panel.allowedContentTypes = [.init(filenameExtension: ProjectService.fileExtension) ?? .data]
            panel.canCreateDirectories = true
            panel.title = "Save Project"
            
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try ProjectService.save(project: project, to: url)
                    projectURL = url
                    markClean()
                } catch {
                    onError("Failed to save project: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func newProject() {
        projectURL = nil
        markClean()
    }
    
    func openProject(onSuccess: @escaping (URL, MayaProjectFile, URL, [String: URL], [String: URL], [String: URL]) -> Void, onError: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: ProjectService.fileExtension) ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Open Project"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let loaded = try ProjectService.load(from: url)
                projectURL = url
                markClean()
                onSuccess(url, loaded.projectFile, loaded.videoURL, loaded.audioURLs, loaded.imageURLs, loaded.backgroundVideoURLs)
            } catch {
                onError("Failed to open project: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Project Change Tracking Modifier

/// Tracks changes to project properties and marks the state as dirty.
/// Split into multiple modifiers to avoid compiler type-check timeout.
private struct ProjectChangeTracker1: ViewModifier {
    let project: Project
    let stateManager: ProjectStateManager
    
    func body(content: Content) -> some View {
        content
            .onChange(of: project.background) { _, _ in stateManager.markDirty() }
            .onChange(of: project.scale) { _, _ in stateManager.markDirty() }
            .onChange(of: project.offset) { _, _ in stateManager.markDirty() }
            .onChange(of: project.animations) { _, _ in stateManager.markDirty() }
            .onChange(of: project.transitions) { _, _ in stateManager.markDirty() }
            .onChange(of: project.clips) { _, _ in stateManager.markDirty() }
            .onChange(of: project.shadow) { _, _ in stateManager.markDirty() }
            .onChange(of: project.audioClips) { _, _ in stateManager.markDirty() }
            .onChange(of: project.trackCount) { _, _ in stateManager.markDirty() }
            .onChange(of: project.canvasAspect) { _, _ in stateManager.markDirty() }
    }
}

private struct ProjectChangeTracker2: ViewModifier {
    let project: Project
    let stateManager: ProjectStateManager
    
    func body(content: Content) -> some View {
        content
            .onChange(of: project.backgroundBlurRadius) { _, _ in stateManager.markDirty() }
            .onChange(of: project.deviceModelID) { _, _ in stateManager.markDirty() }
            .onChange(of: project.deviceColorID) { _, _ in stateManager.markDirty() }
            .onChange(of: project.bareCornerRadius) { _, _ in stateManager.markDirty() }
            .onChange(of: project.bareBezelWidth) { _, _ in stateManager.markDirty() }
            .onChange(of: project.bareBezelHex) { _, _ in stateManager.markDirty() }
            .onChange(of: project.allowClipOverlap) { _, _ in stateManager.markDirty() }
            .onChange(of: project.exportQuality) { _, _ in stateManager.markDirty() }
            .onChange(of: project.exportRenderSize) { _, _ in stateManager.markDirty() }
            .onChange(of: project.playbackSpeed) { _, _ in stateManager.markDirty() }
    }
}

extension View {
    func trackProjectChanges(project: Project, stateManager: ProjectStateManager) -> some View {
        self
            .modifier(ProjectChangeTracker1(project: project, stateManager: stateManager))
            .modifier(ProjectChangeTracker2(project: project, stateManager: stateManager))
    }
}
