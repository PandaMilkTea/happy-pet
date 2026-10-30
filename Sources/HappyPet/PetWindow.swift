import AppKit
import SwiftUI

/// 承载宠物的无边框透明悬浮窗
final class PetPanel: NSPanel {

    /// 主角窗(非嘉宾),供其它面板定位到桌宠所在那块屏
    private(set) static weak var host: PetPanel?

    /// 换主角时把宿主窗指过去
    static func setHost(_ panel: PetPanel?) { host = panel }

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
        if interactive && brain.isLeader { PetPanel.host = self }
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
        if PetGeometry.bodyContains(p, in: bounds, role: brain.role, hasCharacter: hasCharacter) {
            return self
        }
        // 捧着蛋糕时,蛋糕也要能点(等于吹蜡烛的兜底)
        if brain.isHoldingCake,
           PetGeometry.cakeContains(p,
                                    in: bounds,
                                    role: brain.role,
                                    hasCharacter: hasCharacter,
                                    facingRight: brain.facingRight) {
            return self
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