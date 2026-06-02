import AVFoundation
import AppKit
import SwiftUI

extension GradientSpec {
    var startUnitPoint: UnitPoint {
        let r = angleDegrees * .pi / 180
        return UnitPoint(x: 0.5 - cos(r) * 0.5, y: 0.5 - sin(r) * 0.5)
    }
    var endUnitPoint: UnitPoint {
        let r = angleDegrees * .pi / 180
        return UnitPoint(x: 0.5 + cos(r) * 0.5, y: 0.5 + sin(r) * 0.5)
    }
}

struct BackgroundView: View {
    let background: BackgroundOption
    let blurPoster: NSImage?
    var blurRadius: Double = 0

    var body: some View {
        Group {
            switch background {
            case .none:
                TransparencyCheckerboard()
            case .solid(let hex):
                (Color(hex: hex) ?? .black)
                    .ignoresSafeArea()
            case .gradient(let spec):
                LinearGradient(
                    colors: [spec.startColor, spec.endColor],
                    startPoint: spec.startUnitPoint,
                    endPoint: spec.endUnitPoint
                )
            case .image(let url):
                BackgroundImageView(url: url)
            case .video(let url):
                BackgroundVideoPlayerView(url: url)
            case .videoBlur:
                if let poster = blurPoster {
                    Image(nsImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
        }
        .blur(radius: blurRadius)
    }
}

/// Photoshop-style checkered pattern that signals "this area will be transparent in the export".
struct TransparencyCheckerboard: View {
    var cellSize: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for r in 0..<rows {
                for c in 0..<cols {
                    let color: Color = (r + c) % 2 == 0
                        ? Color(white: 0.92)
                        : Color(white: 0.78)
                    let rect = CGRect(
                        x: CGFloat(c) * cellSize,
                        y: CGFloat(r) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

private struct BackgroundImageView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .task(id: url) {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let loaded = NSImage(contentsOf: url)
            await MainActor.run { self.image = loaded }
        }
    }
}

/// Loops a background video silently via AVPlayerLayer, aspect-filling its container.
private struct BackgroundVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingBGPlayerView {
        let view = LoopingBGPlayerView()
        view.load(url: url)
        return view
    }

    func updateNSView(_ nsView: LoopingBGPlayerView, context: Context) {
        if nsView.currentURL != url {
            nsView.load(url: url)
        }
    }

    static func dismantleNSView(_ nsView: LoopingBGPlayerView, coordinator: ()) {
        nsView.stop()
    }
}

private final class LoopingBGPlayerView: NSView {
    private(set) var currentURL: URL?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func load(url: URL) {
        stop()
        guard url.startAccessingSecurityScopedResource() else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        let looper = AVPlayerLooper(player: queue, templateItem: item)

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.layer?.addSublayer(layer)

        self.currentURL = url
        self.player = queue
        self.looper = looper
        self.playerLayer = layer
        queue.play()
    }

    func stop() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper = nil
        player = nil
        if let url = currentURL {
            url.stopAccessingSecurityScopedResource()
        }
        currentURL = nil
    }
}
