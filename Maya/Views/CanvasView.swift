import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CanvasView: View {
    @Bindable var project: Project
    let blurPoster: NSImage?
    let recentProjects: RecentProjectsStore
    let onOpenVideo: () -> Void
    let onOpenProject: () -> Void
    let onOpenRecentProject: (URL) -> Void

    var body: some View {
        GeometryReader { proxy in
            let aspect = project.canvasAspect.ratio
            let availW = proxy.size.width
            let availH = proxy.size.height
            let canvasSize: CGSize = {
                if availW / max(availH, 1) > aspect {
                    let h = availH
                    return CGSize(width: h * aspect, height: h)
                } else {
                    let w = availW
                    return CGSize(width: w, height: w / aspect)
                }
            }()

            ZStack {
                BackgroundView(background: project.background, blurPoster: blurPoster, blurRadius: project.backgroundBlurRadius)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()

                if project.videoURL != nil {
                    FramedDeviceView(project: project, canvasSize: canvasSize)
                } else {
                    DropPromptView(
                        recentProjects: recentProjects,
                        onOpenVideo: onOpenVideo,
                        onOpenProject: onOpenProject,
                        onOpenRecentProject: onOpenRecentProject
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }
}

// MARK: - Drop prompt

private struct DropPromptView: View {
    let recentProjects: RecentProjectsStore
    let onOpenVideo: () -> Void
    let onOpenProject: () -> Void
    let onOpenRecentProject: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero section
            VStack(spacing: 20) {
                iPhoneIcon
                titleSection
                actionButtons
            }

            Spacer()

            // Recent projects at bottom
            if !recentProjects.projects.isEmpty {
                recentProjectsSection
                    .padding(.bottom, 8)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.32),
                                Color.black.opacity(0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Inner border glow
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Icon

    private var iPhoneIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 72, height: 72)

            Image(systemName: "iphone.gen3")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text("Drop an iPhone screen recording here")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Text("or drag a .mayaproj folder to reopen")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            WelcomeButton(
                icon: "square.and.arrow.up",
                label: "Open Recording",
                isPrimary: true,
                action: onOpenVideo
            )

            WelcomeButton(
                icon: "folder.badge.plus",
                label: "Open Project",
                isPrimary: false,
                action: onOpenProject
            )
        }
    }

    // MARK: - Recent projects

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Recent projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 1) {
                ForEach(Array(recentProjects.projects.enumerated()), id: \.element.id) { idx, project in
                    RecentProjectRow(project: project, onOpen: onOpenRecentProject)
                    if idx < recentProjects.projects.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 1)
                            .padding(.leading, 34)
                    }
                }
            }
            .recentCardBackground()
        }
    }
}

// MARK: - Welcome button

private struct WelcomeButton: View {
    let icon: String
    let label: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var accent: Color { Color(hex: "#6466FA") ?? .accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isPrimary ? .white : .white.opacity(0.85))
            .frame(width: 160, height: 38)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(buttonBorder)
            .shadow(
                color: isPrimary ? accent.opacity(isHovering ? 0.3 : 0.15) : .clear,
                radius: isHovering ? 8 : 4, x: 0, y: isHovering ? 3 : 1
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isPrimary {
            LinearGradient(
                colors: [accent, accent.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isHovering ? 0.10 : 0.06))
        }
    }

    @ViewBuilder
    private var buttonBorder: some View {
        if isPrimary {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(isHovering ? 0.15 : 0.08), lineWidth: 1)
        }
    }
}

// MARK: - Recent project row

private struct RecentProjectRow: View {
    let project: RecentProject
    let onOpen: (URL) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onOpen(project.url)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#6466FA") ?? .accentColor, (Color(hex: "#6466FA") ?? .accentColor).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(project.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.75))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.4 : 0.0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(isHovering ? 0.06 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Recent card background

private extension View {
    func recentCardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
}
