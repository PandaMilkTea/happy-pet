import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let crew = PetCrew.shared
    private var statusItem: NSStatusItem?
    private var followItem: NSMenuItem?
    private var roleItems: [NSMenuItem] = []
    private var daysItem: NSMenuItem?

    private let breath = BreathDetector()
    private var player: AVAudioPlayer?
    /// 吹气检测是否已经开着,避免生日流程被触发两次时重复启麦克风
    private var breathActive = false

    /// 菜单动作都作用在主角身上
    private var brain: PetBrain { crew.leader }
    private var config: PetConfig { brain.config }

    /// 右键点中的那只。状态栏菜单打开时清空,落回主角。
    private weak var menuTarget: PetBrain?
    /// 「戳一戳 / 摸摸头」这类动作的作用对象
    private var actor: PetBrain { menuTarget ?? crew.leader }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 不在 Dock 里显示

        crew.onLeaderChanged = { [weak self] _ in self?.wireUpCallbacks() }
        crew.onMemberJoined = { [weak self] member in self?.wireShared(to: member) }
        wireUpCallbacks()
        crew.start()
        setupStatusItem()
        observeScreenChanges()
    }

    /// 外接屏拔掉、分辨率切换、Dock 换位置都会发这个通知。
    /// 不处理的话宠物会停在一块已经不存在的区域里,看着就是"桌宠不见了"。
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.crew.clampAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        breath.stop()
        crew.stopAll()
    }

    // MARK: - 大脑回调

    /// 每只角色都该有的回调:谁被连戳十下,谁就掏出照片
    private func wireShared(to member: PetBrain) {
        member.onPhotoEasterEgg = { [weak self] in
            guard let self else { return }
            PhotoPanel.show(caption: "和\(self.config.nickname)的那些日子")
        }
    }

    /// 只有主角负责的回调:生日、节日撒花
    private func wireUpCallbacks() {
        wireShared(to: brain)

        brain.onCandleBlownOut = { [weak self] in
            guard let self else { return }
            self.breath.stop()
            self.breathActive = false
            self.throwConfetti(duration: 14)
            self.playBirthdaySong()
        }

        brain.onCelebration = { [weak self] occasion in
            self?.throwConfetti(duration: occasion.confettiDuration)
        }

        // 生日模式可能在启动时进入,也可能是 App 挂到午夜自动进入,麦克风跟着它开
        brain.onBirthdayBegan = { [weak self] in
            self?.startBreathDetection()
        }
    }

    /// 撒花 = 彩带 + 还没上桌的角色集体登场庆祝
    private func throwConfetti(duration: Double) {
        ConfettiPanel.celebrate(duration: duration)
        GuestParade.show(host: brain, duration: duration, residents: Set(crew.activeRoles))
    }

    /// 吹气检测:拿不到麦克风权限时安静降级,点蛋糕也能吹灭
    private func startBreathDetection() {
        guard !breathActive else { return }
        breathActive = true
        breath.onBlow = { [weak self] in
            self?.brain.blowOutCandle()
        }
        breath.start { [weak self] ok in
            guard let self, !ok else { return }
            self.breathActive = false
            self.brain.showBubble("点一下蛋糕就能吹蜡烛啦", duration: 8)
        }
    }

    private func playBirthdaySong() {
        guard let url = brain.assets.birthdaySound else {
            NSSound(named: "Glass")?.play()
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0
        player?.prepareToPlay()
        player?.play()
        // 淡入,别一下子炸出来
        player?.setVolume(0.8, fadeDuration: 1.5)
    }

    /// 重新开始生日流程时,先把上一轮的歌温柔收掉
    private func stopBirthdaySong() {
        guard let current = player, current.isPlaying else { return }
        current.setVolume(0, fadeDuration: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak current] in
            current?.stop()
        }
        player = nil
    }

    // MARK: - 菜单栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "heart.fill",
                accessibilityDescription: "桌面宠物"
            )
            button.image?.isTemplate = true
        }
        let menu = makeContextMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: - 右键 / 状态栏菜单

    /// - Parameter target: 右键点中的角色;nil 表示状态栏菜单,动作落在主角身上
    func makeContextMenu(for target: PetBrain? = nil) -> NSMenu {
        menuTarget = target
        let isStatusMenu = target == nil
        let who = target ?? crew.leader
        let menu = NSMenu()

        if !isStatusMenu {
            let head = NSMenuItem(title: config.displayName(for: who.role), action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
        }

        addItem(to: menu, title: "戳一戳", action: #selector(pokePet))
        addItem(to: menu, title: "喂点东西吃 🍗", action: #selector(openFoodTray))
        addItem(to: menu, title: "摸摸头", action: #selector(patHead))

        let follow = NSMenuItem(title: "跟随鼠标", action: #selector(toggleFollow), keyEquivalent: "")
        follow.target = self
        follow.state = who.followMouse ? .on : .off
        menu.addItem(follow)
        if isStatusMenu { followItem = follow }

        addItem(to: menu, title: "睡一会儿 / 醒来", action: #selector(toggleSleep))

        if brain.assets.availableRoles.count > 1 {
            menu.addItem(.separator())
            menu.addItem(roleMenuItem(remember: isStatusMenu))
        }

        menu.addItem(.separator())

        addItem(to: menu, title: "说句情话", action: #selector(showLovePhrase))
        addItem(to: menu, title: "看看我们的照片", action: #selector(showPhotos))
        addItem(to: menu, title: "拆礼物", action: #selector(openGift))
        addItem(to: menu, title: "再过一次生日 🎂", action: #selector(replayBirthday))
        addItem(to: menu, title: "撒个花", action: #selector(celebrate))

        menu.addItem(.separator())

        addItem(to: menu, title: "回到屏幕右下角", action: #selector(resetPosition))

        if config.daysTogether != nil {
            let item = NSMenuItem(title: daysTogetherTitle(),
                                  action: #selector(showDaysTogether),
                                  keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            if isStatusMenu { daysItem = item }
        }

        menu.addItem(.separator())

        addItem(to: menu, title: "退出", action: #selector(quit), key: "q")

        return menu
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    /// 「谁来陪你」子菜单。勾上就上桌,取消就送走,场上至少留一只。
    private func roleMenuItem(remember: Bool) -> NSMenuItem {
        let parent = NSMenuItem(title: "谁来陪你 🐾", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        var items: [NSMenuItem] = []
        for role in brain.assets.availableRoles {
            let item = NSMenuItem(title: config.displayName(for: role),
                                  action: #selector(pickRole(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = role.rawValue
            item.state = crew.contains(role) ? .on : .off
            sub.addItem(item)
            items.append(item)
        }
        parent.submenu = sub
        if remember { roleItems = items }
        return parent
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // 只有状态栏菜单挂了 delegate,走到这里说明用的是状态栏入口 → 动作回到主角
        menuTarget = nil
        followItem?.state = brain.followMouse ? .on : .off
        // 菜单只建一次,天数会跨天变,打开时现算
        daysItem?.title = daysTogetherTitle()
        for item in roleItems {
            guard let raw = item.representedObject as? String,
                  let role = PetRole(rawValue: raw) else { continue }
            item.state = crew.contains(role) ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func pokePet() {
        actor.poke()
    }

    @objc private func openFoodTray() {
        FoodTrayPanel.show(brain: actor)
    }

    @objc private func patHead() {
        actor.headPat()
    }

    @objc private func toggleFollow() {
        let who = actor
        who.followMouse.toggle()
        followItem?.state = brain.followMouse ? .on : .off
    }

    @objc private func toggleSleep() {
        actor.toggleSleep()
    }

    @objc private func pickRole(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let role = PetRole(rawValue: raw)
        else { return }
        crew.toggle(role)
        sender.state = crew.contains(role) ? .on : .off
    }

    @objc private func showLovePhrase() {
        actor.showSign(duration: 8)
    }

    @objc private func showPhotos() {
        PhotoPanel.show(caption: "和\(config.nickname)的那些日子")
    }

    @objc private func openGift() {
        GiftPanel.show()
    }

    /// 「在一起 N 天 · X 年 X 个月 X 天」菜单标题。周年当天额外标一下。
    private func daysTogetherTitle() -> String {
        guard let summary = config.togetherSummary else { return "在一起" }
        if config.isAnniversaryToday, let years = config.yearsTogether, years >= 1 {
            return "\(summary) · \(years) 周年 🎉"
        }
        return summary
    }

    @objc private func showDaysTogether() {
        let who = actor
        if let occasion = config.occasionToday, !occasion.isBirthday {
            who.showSign(occasion.sign, duration: 9)
            if let span = config.togetherSpanText {
                who.showBubble(span, duration: 6)
            }
        } else if let sign = config.togetherSignText {
            who.showSign(sign, duration: 9)
        }
    }

    /// 生日流程(麦克风、歌、撒花)只认主角,别让嘉宾捧个点不着的蛋糕
    @objc private func replayBirthday() {
        stopBirthdaySong()
        crew.leader.enterBirthdayMode()
    }

    @objc private func celebrate() {
        throwConfetti(duration: 7)
    }

    @objc private func resetPosition() {
        crew.resetPositions()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 启动

let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()