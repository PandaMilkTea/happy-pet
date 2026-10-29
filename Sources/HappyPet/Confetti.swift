import AppKit
import SwiftUI

// MARK: - 全屏庆祝面板

/// 铺满屏幕的撒花 + 烟花。完全点击穿透,到时间自动淡出关闭。
final class ConfettiPanel: NSPanel {

    private static var live: [ConfettiPanel] = []

    /// 在所有屏幕上放一场烟花
    static func celebrate(duration: Double = 9) {
        for screen in NSScreen.screens {
            let panel = ConfettiPanel(screen: screen, duration: duration)
            panel.orderFrontRegardless()
            live.append(panel)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.dismiss()
            }
        }
    }

    init(screen: NSScreen, duration: Double) {
        let frame = screen.frame
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true           // 关键:完全不挡住正常操作

        let host = NSHostingView(
            rootView: CelebrationLayer(duration: duration)
                .frame(width: frame.width, height: frame.height)
        )
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            ConfettiPanel.live.removeAll { $0 === self }
        }
    }
}

// MARK: - 粒子绘制

/// 用 Canvas 画撒花与烟花,所有运动都由时间推导,不保存逐帧状态
struct CelebrationLayer: View {

    let duration: Double

    @State private var start = Date()
    private let flakes: [Flake] = CelebrationLayer.makeFlakes()
    private let bursts: [Burst] = CelebrationLayer.makeBursts()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                draw(flakes: gc, size: size, t: t)
                draw(bursts: gc, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }

    // MARK: 撒花

    private func draw(flakes gc: GraphicsContext, size: CGSize, t: Double) {
        for f in flakes {
            let tt = t - f.delay
            if tt <= 0 { continue }
            let y = CGFloat(tt) * f.speed - f.h * 2
            if y > size.height + 20 { continue }
            let x = f.x * size.width
                + CGFloat(sin(tt * f.swayRate + f.phase)) * f.sway
            let fade = max(0, min(1, (duration - t) / 1.6))
            var layer = gc
            layer.opacity = f.alpha * fade
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .degrees(tt * f.spin))
            let rect = CGRect(x: -f.w / 2, y: -f.h / 2, width: f.w, height: f.h)
            let path = f.isCircle
                ? Path(ellipseIn: rect)
                : Path(roundedRect: rect, cornerRadius: 1.2)
            layer.fill(path, with: .color(f.color))
        }
    }

    // MARK: 烟花

    private func draw(bursts gc: GraphicsContext, size: CGSize, t: Double) {
        let life = 1.7
        for b in bursts {
            let p = t - b.time
            if p < 0 || p > life { continue }
            let progress = p / life
            let ease = 1 - pow(1 - progress, 2.4)          // 先快后慢
            let alpha = pow(1 - progress, 1.6)
            let origin = CGPoint(x: b.center.x * size.width,
                                 y: b.center.y * size.height)
            for i in 0..<b.count {
                let angle = Double(i) / Double(b.count) * .pi * 2 + b.rotation
                let reach = b.radius * (0.72 + 0.28 * sin(Double(i) * 2.7))
                let r = CGFloat(ease) * reach
                let gx = origin.x + cos(angle) * r
                let gy = origin.y + sin(angle) * r + CGFloat(pow(p, 2)) * 110
                var layer = gc
                layer.opacity = alpha
                let d: CGFloat = 4.2 - CGFloat(progress) * 2.4
                layer.fill(
                    Path(ellipseIn: CGRect(x: gx - d / 2, y: gy - d / 2, width: d, height: d)),
                    with: .color(Color(hue: b.hue + Double(i % 5) * 0.015,
                                       saturation: 0.72, brightness: 1.0))
                )
            }
            // 爆心一闪
            if progress < 0.14 {
               var flash = gc
                flash.opacity = (0.14 - progress) / 0.14 * 0.8
                let d: CGFloat = 26
                flash.fill(
                    Path(ellipseIn: CGRect(x: origin.x - d / 2, y: origin.y - d / 2,
                                           width: d, height: d)),
                    with: .color(.white)
                )
            }
        }
    }

    // MARK: 粒子生成

    private static let palette: [Color] = [
        Color(red: 1.00, green: 0.45, blue: 0.56),
        Color(red: 1.00, green: 0.75, blue: 0.35),
        Color(red: 0.55, green: 0.85, blue: 0.70),
        Color(red: 0.55, green: 0.70, blue: 1.00),
        Color(red: 0.85, green: 0.62, blue: 1.00),
        Color(red: 1.00, green: 0.95, blue: 0.55)
    ]

    private static func makeFlakes() -> [Flake] {
        (0..<150).map { _ in
            Flake(
                x: CGFloat.random(in: -0.02...1.02),
                delay: Double.random(in: 0...4.5),
                speed: CGFloat.random(in: 110...260),
                sway: CGFloat.random(in: 14...48),
                swayRate: Double.random(in: 1.1...2.6),
                phase: Double.random(in: 0...6.28),
                spin: Double.random(in: -300...300),
                w: CGFloat.random(in: 5...11),
                h: CGFloat.random(in: 7...15),
                alpha: Double.random(in: 0.75...1.0),
                color: palette.randomElement() ?? .pink,
                isCircle: Int.random(in: 0..<4) == 0
            )
        }
    }

    private static func makeBursts() -> [Burst] {
        (0..<7).map { i in
            Burst(
                center: CGPoint(x: CGFloat.random(in: 0.15...0.85),
                                y: CGFloat.random(in: 0.18...0.52)),
                time: 0.25 + Double(i) * Double.random(in: 0.75...1.25),
                hue: Double.random(in: 0...1),
                count: Int.random(in: 26...40),
                radius: Double.random(in: 120...210),
                rotation: Double.random(in: 0...6.28)
            )
        }
    }

    struct Flake {
        let x: CGFloat
        let delay: Double
        let speed: CGFloat
        let sway: CGFloat
        let swayRate: Double
        let phase: Double
        let spin: Double
        let w: CGFloat
        let h: CGFloat
        let alpha: Double
        let color: Color
        let isCircle: Bool
    }

    struct Burst {
        let center: CGPoint
        let time: Double
        let hue: Double
        let count: Int
        let radius: Double
        let rotation: Double
    }
}