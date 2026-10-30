import AppKit

/// 撒花时的「全员登场」。
///
/// 除当前主角外,把 Assets 里有素材的其他角色各开一个点击穿透的小窗,
/// 沿屏幕底部一字排开,全程播开心帧,到时间淡出收工。
/// 每个嘉宾是一个独立的 PetBrain(guest 模式),所以呼吸 / 跳跃 / 阴影全都在线,
/// 但不会走动、不会睡觉、也不会把角色选择写回 UserDefaults。
enum GuestParade {

    private static var brains: [PetBrain] = []
    private static var panels: [PetPanel] = []
    private static var dismissWork: DispatchWorkItem?

    /// 嘉宾出场时随机挑一句头顶气泡
    private static let cheers = ["一起庆祝", "今天是你的日子", "耶!", "撒花撒花", "happy~"]

    /// - Parameters:
    ///   - host: 主角的大脑,用来排除自己、确定在哪块屏幕上登场
    ///   - duration: 停留时长,和撒花时长对齐
    static func show(host: PetBrain, duration: Double) {
        dismissAll()

        let guests = host.assets.availableRoles.filter { $0 != host.role }
        guard !guests.isEmpty else { return }

        let screen = host.window?.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let size = host.windowSize
        // 底部均分站位。主角待在原地不动,嘉宾只占它之外的空当。
        let span = frame.width - size.width
        for (i, role) in guests.enumerated() {
            let ratio = Double(i + 1) / Double(guests.count + 1)
            var x = frame.minX + span * CGFloat(ratio)
            // 和主角窗口离太近就往旁边让一让,避免叠在一起
            if let hostFrame = host.window?.frame, abs(x - hostFrame.minX) < size.width * 0.7 {
                let pushLeft = hostFrame.minX - size.width * 0.75
                let pushRight = hostFrame.minX + size.width * 0.75
                x = pushLeft >= frame.minX ? pushLeft : pushRight
            }
            x = min(max(x, frame.minX), frame.maxX - size.width)
            spawn(role: role, at: NSPoint(x: x, y: frame.minY), delay: Double(i) * 0.22)
        }

        let work = DispatchWorkItem { dismissAll() }
        dismissWork = work
        // 比撒花早收一点,花还在飘的时候退场更自然
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2, duration - 1.2), execute: work)
    }

    private static func spawn(role: PetRole, at origin: NSPoint, delay: Double) {
        let brain = PetBrain(guestRole: role)
        let panel = PetPanel(brain: brain, interactive: false)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        brain.window = panel
        brains.append(brain)
        panels.append(panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // 期间可能已经被 dismissAll 收掉了
            guard panels.contains(where: { $0 === panel }) else { return }
            panel.orderFrontRegardless()
            brain.start()
            if let line = cheers.randomElement() { brain.showBubble(line, duration: 4) }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                panel.animator().alphaValue = 1
            }
        }
    }

    /// 立刻收场(淡出 + 停表)。重复撒花时也靠它清掉上一轮。
    static func dismissAll() {
        dismissWork?.cancel()
        dismissWork = nil
        for brain in brains { brain.stop() }
        brains.removeAll()

        let leaving = panels
        panels.removeAll()
        for panel in leaving {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.6
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }
}