import AppKit

/// 同屏的一群宠物。
///
/// 每只角色一个独立的 PetBrain + PetPanel,行为完整(会走、会睡、会举牌、能单独投喂),
/// 其中一只是「主角」(leader):只有它负责节日 / 生日流程,也只有它的角色会写回配置。
/// 勾选名单存在 UserDefaults,下次启动原班人马一起上场。
final class PetCrew {

    static let shared = PetCrew()

    private struct Member {
        let brain: PetBrain
        let panel: PetPanel
    }

    private static let activeKey = "HappyPet.activeRoles"

    private var members: [PetRole: Member] = [:]
    /// 上场顺序,队尾最新。主角离场时按这个顺序往下传。
    private var order: [PetRole] = []

    /// 主角。菜单里的动作、生日流程都作用在它身上。
    private(set) var leader: PetBrain
    /// 主角换人时通知外面重新接线(生日回调挂在 AppDelegate 上)
    var onLeaderChanged: ((PetBrain) -> Void)?
    /// 任何一只上场时通知外面接线(每只都要能戳出照片彩蛋,不只是主角)
    var onMemberJoined: ((PetBrain) -> Void)?

    private var assets: PetAssets { PetAssets.shared }

    /// 场上所有角色,按上场顺序
    var activeRoles: [PetRole] { order }

    private init() {
        let brain = PetBrain()
        brain.promoteToLeader()
        leader = brain
    }

    // MARK: - 上场 / 下场

    /// 主角先站好,上次勾选过的伙伴错开一点时间依次登场
    func start() {
        let saved = PetCrew.savedRoles(available: assets.availableRoles)
        // 名单里没有主角,说明配置被外部改过;以名单为准,免得冒出一只没勾选的
        if !saved.isEmpty, !saved.contains(leader.role), let first = saved.first {
            leader.switchRole(to: first)
        }
        let companions = saved.filter { $0 != leader.role }
        assets.reserveCacheSlots(for: 1 + companions.count)

        let panel = PetPanel(brain: leader)
        leader.window = panel
        leader.resetPosition()
        panel.orderFrontRegardless()
        members[leader.role] = Member(brain: leader, panel: panel)
        order = [leader.role]
        onMemberJoined?(leader)
        leader.start()

        guard !companions.isEmpty else { return }
        assets.prewarm(companions)
        for (i, role) in companions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(i + 1)) { [weak self] in
                self?.spawn(role, greet: false)
            }
        }
    }

    /// 勾选 / 取消勾选一个角色。至少得留一只在场上。
    func toggle(_ role: PetRole) {
        if members[role] == nil {
            spawn(role, greet: true)
        } else {
            remove(role)
        }
    }

    func contains(_ role: PetRole) -> Bool { members[role] != nil }

    private func spawn(_ role: PetRole, greet: Bool) {
        guard members[role] == nil, assets.availableRoles.contains(role) else { return }
        assets.reserveCacheSlots(for: members.count + 1)

        let brain = PetBrain(role: role)
        let panel = PetPanel(brain: brain)
        brain.window = panel
        panel.setFrameOrigin(freeOrigin(size: brain.windowSize))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        members[role] = Member(brain: brain, panel: panel)
        order.append(role)
        onMemberJoined?(brain)
        brain.start()
        persist()
        print("🐾 \(role.rawValue) 上场,现在场上: \(order.map { $0.rawValue }.joined(separator: " "))")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            panel.animator().alphaValue = 1
        }
        if greet {
            let name = brain.config.displayName(for: role)
            brain.showBubble(RoleVoice.arrival(for: role, name: name), duration: 4)
        }
    }

    private func remove(_ role: PetRole) {
        guard members.count > 1, let member = members[role] else { return }
        members[role] = nil
        order.removeAll { $0 == role }
        persist()
        print("👋 \(role.rawValue) 下场,现在场上: \(order.map { $0.rawValue }.joined(separator: " "))")

        // 主角走了就把担子交给下一只(位置、回调、宿主窗一起跟过去)
        if member.brain === leader, let next = order.first, let heir = members[next] {
            let wasHoldingCake = member.brain.isHoldingCake
            leader = heir.brain
            PetPanel.setHost(heir.panel)
            // 先接线再升职:promoteToLeader 里可能当场进入生日模式,回调得已经挂好
            onLeaderChanged?(heir.brain)
            heir.brain.promoteToLeader()
            // 上一只正捧着蛋糕(比如「再过一次生日」),别让蛋糕跟着它一起走掉
            if wasHoldingCake, !heir.brain.isHoldingCake {
                heir.brain.enterBirthdayMode()
            }
            print("👑 主角交接: \(role.rawValue) → \(next.rawValue)")
        }

        member.brain.showBubble(RoleVoice.farewell(for: role), duration: 1.4)
        let panel = member.panel
        let brain = member.brain
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.9
            panel.animator().alphaValue = 0
        } completionHandler: {
            brain.stop()
            brain.window = nil
            panel.orderOut(nil)
            // 它的帧图不用再占内存了
            PetAssets.shared.releaseRoles(keeping: Set(PetCrew.shared.order))
            PetAssets.shared.reserveCacheSlots(for: PetCrew.shared.members.count)
        }
    }

    func stopAll() {
        for member in members.values { member.brain.stop() }
    }

    // MARK: - 位置

    /// 全员回到屏幕右下角,一只挨一只排开
    func resetPositions() {
        leader.resetPosition()
        guard let frame = (leader.window?.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = leader.windowSize
        var index = 1
        for role in order where role != leader.role {
            guard let brain = members[role]?.brain else { continue }
            let x = frame.maxX - size.width - 20 - CGFloat(index) * size.width * 0.78
            brain.place(at: NSPoint(x: max(x, frame.minX), y: frame.minY))
            index += 1
        }
    }

    func clampAll() {
        for member in members.values { member.brain.clampToVisibleScreen() }
    }

    /// 屏幕底部找一个没人站的位置,实在挤不开就稍微错开一点叠着
    private func freeOrigin(size: CGSize) -> NSPoint {
        let screen = leader.window?.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        let taken = members.values.map { $0.panel.frame }
        var x = frame.maxX - size.width - 20
        for step in 0..<10 {
            let rect = NSRect(x: x, y: frame.minY, width: size.width, height: size.height)
            let busy = taken.contains { $0.intersects(rect.insetBy(dx: size.width * 0.3, dy: 0)) }
            if !busy { break }
            x -= size.width * 0.78
            if x < frame.minX { x = frame.minX + CGFloat(step) * 16 }
        }
        x = min(max(x, frame.minX), frame.maxX - size.width)
        return NSPoint(x: x, y: frame.minY)
    }

    // MARK: - 命中测试

    /// 这个屏幕坐标点在谁身上(后上场的在上层,优先命中)。投喂松手时用。
    func brain(at screenPoint: NSPoint) -> PetBrain? {
        for role in order.reversed() {
            if let brain = members[role]?.brain, brain.bodyContains(screenPoint) {
                return brain
            }
        }
        return nil
    }

    // MARK: - 持久化

    private func persist() {
        UserDefaults.standard.set(order.map { $0.rawValue }, forKey: PetCrew.activeKey)
    }

    /// 上次的名单,过滤掉没素材的角色;空的话就只有主角
    private static func savedRoles(available: [PetRole]) -> [PetRole] {
        let raw = UserDefaults.standard.stringArray(forKey: activeKey) ?? []
        return raw.compactMap(PetRole.init(rawValue:)).filter { available.contains($0) }
    }
}