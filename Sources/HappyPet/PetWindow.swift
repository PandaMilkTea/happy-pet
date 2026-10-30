import AppKit
import SwiftUI

/// 承载宠物的无边框透明悬浮窗
final class PetPanel: NSPanel {

    /// - Parameter interactive: false 时完全点击穿透(撒花嘉宾用,不该抢主角的点击)
    init(brain: PetBrain, interactive: Bool = true) {
        let size = brain.windowSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar                     // 浮在普通窗口之上
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        ignoresMouseEvents = !interactive

        let container = PetContainerView(brain: brain)
        container.frame = NSRect(origin: .zero, size: size)

        let host = NSHostingView(rootView: PetView(brain: brain))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) { host.layer?.backgroundColor = .clear }
        container.addSubview(host)

        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 负责鼠标命中区域、拖拽、点击、右键菜单
final class PetContainerView: NSView {

    private let brain: PetBrain
    private var mouseDownLocation: NSPoint = .zero
    private var windowOriginAtMouseDown: NSPoint = .zero
    private var dragged = false

    init(brain: PetBrain) {
        self.brain = brain
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    /// 只有宠物身体范围内才接收鼠标事件,其余区域点击穿透到桌面
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = superview.map { convert(point, from: $0) } ?? point
        let hasCharacter = brain.roleAssets.hasAnything
        let role = brain.role
        // 本体在 300 高的窗口里靠下站立(脚底固定在中线下方 138pt),上方留给举牌 / 气泡
        let feet = bounds.midY - 138.5
        let h = role.displayHeight
        let center = hasCharacter
            ? CGPoint(x: bounds.midX, y: feet + h / 2)
            : CGPoint(x: bounds.midX, y: bounds.midY - 70)
        // 四足角色矮而宽,命中区得按身高横向放大,不然很难点到
        let rx: CGFloat = hasCharacter ? (role.isHuman ? h * 0.23 : h * 0.6) : 58
        let ry: CGFloat = hasCharacter ? h * 0.48 : 54
        let dx = (p.x - center.x) / rx
        let dy = (p.y - center.y) / ry
        if (dx * dx + dy * dy) <= 1 { return self }

        // 捧着蛋糕时,蛋糕也要能点(等于吹蜡烛的兜底)
        if brain.isHoldingCake {
            let cakeCenter = CGPoint(x: bounds.midX + (brain.facingRight ? 6 : -6),
                                     y: hasCharacter ? (feet + h * 0.48) : (bounds.midY - 96))
            let cdx = (p.x - cakeCenter.x) / 34
            let cdy = (p.y - cakeCenter.y) / 32
            if (cdx * cdx + cdy * cdy) <= 1 { return self }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - mouseDownLocation.x
        let dy = now.y - mouseDownLocation.y
        if !dragged && (abs(dx) + abs(dy) < 3) { return }
        dragged = true
        brain.beginDrag()
        window.setFrameOrigin(
            NSPoint(x: windowOriginAtMouseDown.x + dx, y: windowOriginAtMouseDown.y + dy)
        )
    }

    override func mouseUp(with event: NSEvent) {
        if dragged {
            brain.endDrag()
        } else if event.clickCount >= 2 {
            // 双击 = 摸头
            brain.headPat()
        } else {
            brain.poke()
        }
        dragged = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = (NSApp.delegate as? AppDelegate)?.makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}