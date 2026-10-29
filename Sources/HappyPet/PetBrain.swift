import AppKit
import Combine
import Foundation

/// 宠物的行为状态
enum PetState: Equatable {
    case idle      // 待机(呼吸 + 甩尾)
    case walk      // 散步
    case sleep     // 睡觉
    case drag      // 被拖拽中
    case fall      // 松手后下落
    case happy     // 被戳到后开心跳跃
    case cake      // 生日模式:捧着蛋糕站定
}

/// 宠物大脑:负责状态机、位置更新、动画时钟
final class PetBrain: ObservableObject {

    // MARK: - 对外发布的状态
    @Published private(set) var state: PetState = .idle
    @Published private(set) var facingRight: Bool = true
    @Published private(set) var isBlinking: Bool = false
    /// 统一动画时钟(秒),所有周期动画都基于它推导
    @Published private(set) var clock: Double = 0
    @Published var followMouse: Bool = false {
        didSet { if followMouse, state == .sleep { switchTo(.idle) } }
    }

    // MARK: - 生日 / 情话相关

    let assets = PetAssets.shared
    var config: PetConfig { assets.config }

    /// 举牌内容,nil 表示没在举牌
    @Published private(set) var signText: String?
    /// 头顶小气泡(恋爱天数、提示语等)
    @Published private(set) var bubbleText: String?
    /// 生日模式:是否捧着蛋糕
    @Published private(set) var isHoldingCake: Bool = false
    /// 蜡烛是否还亮着
    @Published private(set) var candleLit: Bool = true
    /// 连续戳的次数(中间隔太久会清零)
    @Published private(set) var pokeStreak: Int = 0

    /// 蜡烛被吹灭时回调(交给 AppDelegate 放撒花 + 音乐)
    var onCandleBlownOut: (() -> Void)?
    /// 连戳满 10 次的照片彩蛋回调
    var onPhotoEasterEgg: (() -> Void)?
    /// 整百天纪念回调
    var onMilestone: (() -> Void)?

    // MARK: - 可调参数
    /// 窗口比宠物本体大一圈,上方留给举牌 / 气泡,下方留给蛋糕
    let windowSize = CGSize(width: 200, height: 300)
    private let walkSpeed: CGFloat = 55      // 像素/秒
    private let followSpeed: CGFloat = 150
    private let gravity: CGFloat = 1500
    private let tickInterval: Double = 1.0 / 60.0

    // MARK: - 内部状态
    weak var window: NSWindow?
    private var timer: Timer?
    private var stateElapsed: Double = 0
    private var stateDuration: Double = 3
    private var blinkCountdown: Double = 3
    private var fallVelocity: CGFloat = 0
    private var signCountdown: Double = 12
    private var signRemaining: Double = 0
    private var bubbleRemaining: Double = 0
    private var pokeStreakDeadline: Double = 0
    private var lastPhraseIndex: Int = -1

    // MARK: - 生命周期

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        if config.isBirthdayToday {
            enterBirthdayMode()
        } else if config.isMilestoneDay, let d = config.daysTogether {
            showBubble("在一起 \(d) 天啦", duration: 8)
            switchTo(.happy, duration: 2.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.onMilestone?()
            }
        } else if let d = config.daysTogether {
            showBubble("在一起 \(d) 天", duration: 6)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 交互入口

    /// 鼠标点击宠物
    func poke() {
        fallVelocity = 0

        // 生日模式下,点蛋糕就等于吹蜡烛(麦克风不可用时的兜底)
        if isHoldingCake, candleLit {
            blowOutCandle()
            return
        }

        // 连戳累计
        if clock > pokeStreakDeadline { pokeStreak = 0 }
        pokeStreak += 1
        pokeStreakDeadline = clock + 2.0

        if pokeStreak >= 10 {
            pokeStreak = 0
            showBubble("好啦好啦,给你看个东西", duration: 3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onPhotoEasterEgg?()
            }
        } else if pokeStreak == 6 {
            showBubble("再戳就有惊喜了哦", duration: 2.5)
        }

        if !isHoldingCake { switchTo(.happy, duration: 1.1) }
    }

    // MARK: - 生日流程

    func enterBirthdayMode() {
        isHoldingCake = true
        candleLit = true
        signText = nil
        switchTo(.cake, duration: .infinity)
        showBubble("对着麦克风吹一下 🎂", duration: 10)
    }

    func exitBirthdayMode() {
        isHoldingCake = false
        candleLit = true
        switchTo(.idle, duration: 2)
    }

    /// 吹灭蜡烛(麦克风检测到吹气,或直接点击蛋糕)
    func blowOutCandle() {
        guard isHoldingCake, candleLit else { return }
        candleLit = false
        bubbleText = nil
        switchTo(.happy, duration: 3.2)
        onCandleBlownOut?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.isHoldingCake else { return }
            self.isHoldingCake = false
            self.switchTo(.idle, duration: 2)
            self.showSign(self.config.birthdayWish, duration: 9)
        }
    }

    // MARK: - 举牌 / 气泡

    /// 立刻举一次牌。不传文案就从 love.txt 随机抽一句(避免连续重复)。
    func showSign(_ text: String? = nil, duration: Double = 6) {
        let phrases = assets.lovePhrases
        var content = text
        if content == nil, !phrases.isEmpty {
            var idx = Int.random(in: 0..<phrases.count)
            if phrases.count > 1, idx == lastPhraseIndex {
                idx = (idx + 1) % phrases.count
            }
            lastPhraseIndex = idx
            content = phrases[idx]
        }
        guard let content else { return }
        signText = content
        signRemaining = duration
        signCountdown = Double.random(in: 40...90)
        if state == .sleep { switchTo(.idle, duration: 3) }
    }

    func showBubble(_ text: String, duration: Double = 5) {
        bubbleText = text
        bubbleRemaining = duration
    }

    func beginDrag() {
        if state != .drag { switchTo(.drag, duration: .infinity) }
    }

    func endDrag() {
        fallVelocity = 0
        switchTo(.fall, duration: .infinity)
    }

    func toggleSleep() {
        switchTo(state == .sleep ? .idle : .sleep, duration: state == .sleep ? 2 : 20)
    }

    /// 回到屏幕右下角
    func resetPosition() {
        guard let window, let screen = currentScreen() else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.maxX - windowSize.width - 20, y: frame.minY)
        window.setFrameOrigin(origin)
        switchTo(.idle)
    }

    // MARK: - 主循环

    private func tick() {
        clock += tickInterval
        stateElapsed += tickInterval
        updateBlink()
        updateSignAndBubble()

        switch state {
        case .walk:  stepWalk()
        case .fall:  stepFall()
        case .idle, .sleep, .happy:
            if followMouse, state != .happy { chaseMouse() }
        case .drag, .cake:
            break
        }

        if stateElapsed >= stateDuration { decideNextState() }
    }

    /// 举牌与气泡的倒计时;平时每隔一段时间自动举一次牌
    private func updateSignAndBubble() {
        if signRemaining > 0 {
            signRemaining -= tickInterval
            if signRemaining <= 0 { signText = nil }
        }
        if bubbleRemaining > 0 {
            bubbleRemaining -= tickInterval
            if bubbleRemaining <= 0 { bubbleText = nil }
        }
        guard !isHoldingCake, signText == nil else { return }
        signCountdown -= tickInterval
        if signCountdown <= 0, state != .drag, state != .fall {
            showSign()
        }
    }

    private func updateBlink() {
        blinkCountdown -= tickInterval
        if blinkCountdown <= 0 {
            isBlinking = true
            blinkCountdown = Double.random(in: 2.2...5.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
                self?.isBlinking = false
            }
        }
    }

    // MARK: - 行为实现

    private func stepWalk() {
        if followMouse { chaseMouse(); return }
        move(dx: (facingRight ? 1 : -1) * walkSpeed * CGFloat(tickInterval))
    }

    private func chaseMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let centerX = window.frame.midX
        let delta = mouse.x - centerX
        guard abs(delta) > 45 else {
            if state == .walk { switchTo(.idle, duration: 1.2) }
            return
        }
        if state != .walk { switchTo(.walk, duration: .infinity) }
        facingRight = delta > 0
        let step = min(abs(delta), followSpeed * CGFloat(tickInterval))
        move(dx: delta > 0 ? step : -step)
    }

    private func stepFall() {
        guard let window, let screen = currentScreen() else { return }
        let baseline = screen.visibleFrame.minY
        fallVelocity += gravity * CGFloat(tickInterval)
        var origin = window.frame.origin
        origin.y -= fallVelocity * CGFloat(tickInterval)
        if origin.y <= baseline {
            origin.y = baseline
            window.setFrameOrigin(origin)
            switchTo(.happy, duration: 0.7)
        } else {
            window.setFrameOrigin(origin)
        }
    }

    /// 水平移动并在屏幕边缘转身
    private func move(dx: CGFloat) {
        guard let window, let screen = currentScreen() else { return }
        let frame = screen.visibleFrame
        var origin = window.frame.origin
        origin.x += dx
        if origin.x <= frame.minX {
            origin.x = frame.minX
            facingRight = true
        } else if origin.x + windowSize.width >= frame.maxX {
            origin.x = frame.maxX - windowSize.width
            facingRight = false
        }
        window.setFrameOrigin(origin)
    }

    // MARK: - 状态切换

    private func decideNextState() {
        // 捧着蛋糕时站定不动,等着被吹
        if isHoldingCake {
            if state != .happy { switchTo(.cake, duration: .infinity) }
            else { stateElapsed = 0; stateDuration = 3 }
            return
        }
        // 举牌期间不走动,安静站着让人看清
        if signText != nil {
            switchTo(.idle, duration: 1.5)
            return
        }
        if followMouse { chaseMouse(); stateElapsed = 0; stateDuration = 1; return }
        switch Int.random(in: 0..<10) {
        case 0...4:
            facingRight = Bool.random()
            switchTo(.walk, duration: Double.random(in: 2.5...6))
        case 5...8:
            switchTo(.idle, duration: Double.random(in: 2...5))
        default:
            switchTo(.sleep, duration: Double.random(in: 6...14))
        }
    }

    private func switchTo(_ next: PetState, duration: Double = 2.5) {
        state = next
        stateElapsed = 0
        stateDuration = duration
    }

    private func currentScreen() -> NSScreen? {
        guard let window else { return NSScreen.main }
        return NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main
    }
}