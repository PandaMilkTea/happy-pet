import AppKit
import Combine
import SwiftUI

// MARK: - 居中小窗基类

/// 屏幕居中的无边框面板,支持 Esc 关闭 + 淡入淡出
class CenteredPanel: NSPanel {

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
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
        center()
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                   y: f.midY - size.height / 2))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss() } else { super.keyDown(with: event) }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
        }
    }
}

// MARK: - 照片彩蛋

/// 连戳 10 次解锁:拍立得样式的合照轮播
final class PhotoPanel: CenteredPanel {

    private static var current: PhotoPanel?

    static func show(caption: String) {
        current?.orderOut(nil)
        let panel = PhotoPanel(caption: caption)
        panel.makeKeyAndOrderFront(nil)
        current = panel
    }

    private init(caption: String) {
        super.init(size: CGSize(width: 440, height: 440))
        let view = PhotoCardView(
            photos: PetAssets.shared.photos,
            caption: caption,
            onClose: { [weak self] in self?.dismiss() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }
}

/// 相纸卡片:点一下换下一张,也会自己轮播
struct PhotoCardView: View {

    let photos: [NSImage]
    let caption: String
    let onClose: () -> Void

    @State private var index = 0
    @State private var appeared = false
    private let ticker = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    private let paper = Color(red: 0.99, green: 0.98, blue: 0.96)

    var body: some View {
        card
            .scaleEffect(appeared ? 1 : 0.84)
            .opacity(appeared ? 1 : 0)
            .rotationEffect(.degrees(-1.6))
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    appeared = true
                }
            }
            .onReceive(ticker) { _ in advance() }
            .frame(width: 440, height: 440)
    }

    private var card: some View {
        VStack(spacing: 12) {
            photoArea
                .frame(width: 348, height: 268)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

            Text(caption)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.30, green: 0.22, blue: 0.24))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 330)

            if photos.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        Circle()
                            .fill(i == index
                                  ? Color(red: 0.95, green: 0.45, blue: 0.55)
                                  : Color.black.opacity(0.16))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(paper)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        )
        .overlay(closeButton, alignment: .topTrailing)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    @ViewBuilder
    private var photoArea: some View {
        if photos.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.86, blue: 0.88),
                             Color(red: 0.88, green: 0.90, blue: 1.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    HeartShape()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 54, height: 50)
                    Text("把合照放进 Assets/photos 就会出现在这里")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        } else {
            Image(nsImage: photos[min(index, photos.count - 1)])
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .id(index)
                .transition(.opacity.animation(.easeInOut(duration: 0.35)))
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
      .background(Circle().fill(Color.black.opacity(0.32)))
        }
        .buttonStyle(.plain)
        .padding(10)
    }

    private func advance() {
        guard photos.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            index = (index + 1) % photos.count
        }
    }
}

// MARK: - 礼物盒

/// 点三下拆开,然后一张张翻礼物清单
final class GiftPanel: CenteredPanel {

    private static var current: GiftPanel?

    static func show() {
        current?.orderOut(nil)
        let panel = GiftPanel()
        panel.makeKeyAndOrderFront(nil)
        current = panel
    }

    private init() {
        super.init(size: CGSize(width: 400, height: 500))
        let view = GiftFlowView(
            items: GiftStore.shared.items,
            onClose: { [weak self] in self?.dismiss() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }
}

/// 拆盒 → 清单两个阶段
struct GiftFlowView: View {

    let items: [GiftItem]
    let onClose: () -> Void

    @State private var showList = false

    var body: some View {
        ZStack {
            if showList {
                GiftListView(items: items, onClose: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                GiftBoxView(
                    message: items.isEmpty ? "🎉" : "里面有 \(items.count) 件东西",
                    onOpened: {
                        ConfettiPanel.celebrate(duration: 8)
                        guard !items.isEmpty else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                            withAnimation(.easeInOut(duration: 0.42)) { showList = true }
                        }
                    },
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
        .frame(width: 400, height: 500)
    }
}