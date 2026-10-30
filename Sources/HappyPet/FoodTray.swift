import AppKit
import SwiftUI

// MARK: - 跟着鼠标走的食物虚影

/// 拖拽时跟着光标飞的小窗:不吃鼠标事件,只负责「手上拿着一块食物」的视觉
final class FoodGhostWindow: NSPanel {

    private let side: CGFloat = 56

    /// 虚影在淡出动画期间没人持有会被提前释放,这里自己留个强引用
    private static var alive: [FoodGhostWindow] = []

    init(item: FoodItem) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        let host = NSHostingView(rootView: FoodIconView(item: item, size: 44).padding(6))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        host.autoresizingMask = [.width, .height]
        contentView = host
        orderFrontRegardless()
        FoodGhostWindow.alive.append(self)
    }

    /// 光标在中心
    func move(to screenPoint: NSPoint) {
        setFrameOrigin(NSPoint(x: screenPoint.x - side / 2, y: screenPoint.y - side / 2))
    }

    /// success = 喂中了:缩小吸进去;否则放手弹回原样淡掉
    func vanish(success: Bool) {
        let f = frame
        let scale: CGFloat = success ? 0.25 : 0.8
        let target = NSRect(
            x: f.midX - f.width * scale / 2,
            y: f.midY - f.height * scale / 2 + (success ? 0 : -14),
            width: f.width * scale,
            height: f.height * scale
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = success ? 0.18 : 0.26
            animator().setFrame(target, display: false)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            guard let self else { return }
            FoodGhostWindow.alive.removeAll { $0 === self }
        }
    }
}

// MARK: - 食物盘面板

/// 一盘可以往宠物身上拖的食物
final class FoodTrayPanel: CenteredPanel {

    private static var current: FoodTrayPanel?

    static func show(brain: PetBrain) {
        current?.orderOut(nil)
        let panel = FoodTrayPanel(brain: brain)
        panel.makeKeyAndOrderFront(nil)
        current = panel
    }

    private init(brain: PetBrain) {
        let size = CGSize(width: 330, height: 300)
        super.init(size: size)
        // 宠物窗口也是 .statusBar,同级时后开的窗口会盖住它 —— 降一级,保证人物永远在盘子前面
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        setFrameOrigin(FoodTrayPanel.origin(for: size, avoiding: brain.window?.frame))
        let view = FoodTrayView(
            brain: brain,
            onClose: { [weak self] in self?.dismiss() },
            panel: { [weak self] in self }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    /// 挑一个不压住宠物的位置:底部中央优先,挡住就依次换边,全挡住就选重叠最少的
    private static func origin(for size: CGSize, avoiding petFrame: NSRect?) -> NSPoint {
        // 多屏时跟着宠物所在的那块屏幕走
        let screen = petFrame.flatMap { f in NSScreen.screens.first { $0.frame.intersects(f) } }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        let pad: CGFloat = 24
        let candidates: [NSPoint] = [
            NSPoint(x: visible.midX - size.width / 2, y: visible.minY + pad),          // 底部中央
            NSPoint(x: visible.minX + pad, y: visible.minY + pad),                     // 左下
            NSPoint(x: visible.maxX - size.width - pad, y: visible.minY + pad),        // 右下
            NSPoint(x: visible.minX + pad, y: visible.maxY - size.height - pad),       // 左上
            NSPoint(x: visible.maxX - size.width - pad, y: visible.maxY - size.height - pad), // 右上
            NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)     // 正中
        ]
        guard var pet = petFrame else { return candidates[0] }
        // 留点余量,别贴着人物边缘
        pet = pet.insetBy(dx: -20, dy: -20)

        var best = candidates[0]
        var bestOverlap = CGFloat.greatestFiniteMagnitude
        for p in candidates {
            let rect = NSRect(origin: p, size: size)
            let inter = rect.intersection(pet)
            let overlap = inter.isNull ? 0 : inter.width * inter.height
            if overlap == 0 { return p }
            if overlap < bestOverlap {
                bestOverlap = overlap
                best = p
            }
        }
        return best
    }
}

struct FoodTrayView: View {

    @ObservedObject var brain: PetBrain
    let onClose: () -> Void
    /// 回头拿面板自己(拖动标题栏时要移动窗口)
    let panel: () -> NSWindow?

    @State private var ghost: FoodGhostWindow?
    @State private var draggingID: String?
    @State private var appeared = false
    /// 拖窗口的起点:(窗口原点, 按下时的鼠标位置)
    @State private var moveAnchor: (origin: NSPoint, mouse: NSPoint)?

    private let paper = Color(red: 0.99, green: 0.97, blue: 0.94)
    private let ink = Color(red: 0.22, green: 0.19, blue: 0.18)

    private var items: [FoodItem] { FoodStore.shared.items }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("拖一个给它吃 🍽")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(ink)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ink.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .gesture(windowDragGesture)

            LazyVGrid(columns: Array(repeating: GridItem(spacing: 6), count: 4), spacing: 6) {
                ForEach(items) { item in
                    cell(item)
                }
            }

            Text("松手时对准谁就喂给谁 · 空白处可拖动")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(ink.opacity(0.45))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(paper)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        )
        // 空白处按住就能挪盘子;食物格有自己的手势,子视图优先,不会打架
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .gesture(windowDragGesture)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { appeared = true }
        }
    }

    /// 拖面板本身:用鼠标的屏幕绝对坐标算位移,不受窗口自身移动影响,不会抖
    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                guard let window = panel() else { return }
                let mouse = NSEvent.mouseLocation
                if moveAnchor == nil {
                    moveAnchor = (window.frame.origin, mouse)
                }
                guard let anchor = moveAnchor else { return }
                window.setFrameOrigin(NSPoint(
                    x: anchor.origin.x + mouse.x - anchor.mouse.x,
                    y: anchor.origin.y + mouse.y - anchor.mouse.y
                ))
            }
            .onEnded { _ in moveAnchor = nil }
    }

    private func cell(_ item: FoodItem) -> some View {
        VStack(spacing: 2) {
            FoodIconView(item: item, size: 34)
            Text(item.name)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(ink.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 68, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(draggingID == item.id ? 0.1 : 0.035))
        )
        .opacity(draggingID == item.id ? 0.35 : 1)
        .gesture(dragGesture(item))
    }

    private func dragGesture(_ item: FoodItem) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                if ghost == nil {
                    ghost = FoodGhostWindow(item: item)
                    draggingID = item.id
                }
                ghost?.move(to: NSEvent.mouseLocation)
            }
            .onEnded { _ in
                // 同屏可能站着好几只,松手时对准谁就喂谁
                let target = PetCrew.shared.brain(at: NSEvent.mouseLocation)
                ghost?.vanish(success: target != nil)
                ghost = nil
                draggingID = nil
                target?.feed(item)
            }
    }
}