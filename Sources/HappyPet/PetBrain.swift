import AppKit
import Combine
import Foundation

/// 宠物的行为状态
enum PetState: Int, Equatable, CaseIterable {
    case idle      // 待机(呼吸 + 小动作)
    case walk      // 散步
    case sleep     // 睡觉
    case drag      // 被拖拽中
    case fall      // 松手后下落
    case happy     // 被戳到后开心跳跃
    case cake      // 生日模式:捧着蛋糕站定
    case eat       // 正在吃投喂的食物
    case purr      // 被摸头后咕噜咕噜

    /// 对应的帧动画动作名
    var spriteAction: String {
        switch self {
        case .idle:  return "idle"
        case .walk:  return "walk"
        case .sleep: return "sleep"
        case .drag:  return "drag"
        case .fall:  return "fall"
        case .happy: return "happy"
        case .cake:  return "cake"
        case .eat:   return "eat"
        case .purr:  return "purr"
        }
    }
}

/// 一帧渲染所需的全部姿态量。
/// 全部在 PetBrain 的主循环里算好,视图层只负责画,
/// 这样所有形变都能共享同一套相位 / 平滑,不会各自跳变。
struct PetPose {
    /// 垂直偏移(负 = 向上)
    var bob: CGFloat = 0
    /// 跳跃高度(负 = 向上)
    var jump: CGFloat = 0
    /// 左右重心偏移
    var sway: CGFloat = 0
    /// 身体挤压 / 拉伸
    var squash = CGSize(width: 1, height: 1)
    /// 整体倾斜(度)
    var tilt: Double = 0
   /// 抬手角度(度)
    var armAngle: Double = 0
    /// 朝向插值:+1 朝右,-1 朝左,过渡期间经过 0(等于一次快速转身)
    var facing: CGFloat = 1
    /// 眼睛张开程度 1~0
    var eyeOpen: Double = 1
    /// 呼吸系数(给矢量橘猫用)
    var breath: CGFloat = 0
    /// 迈腿幅度
    var legSwing: CGFloat = 0
    /// 甩尾相位 -1~1
    var tailSwing: CGFloat = 0
    /// 地面阴影缩放
    var shadowScale: CGFloat = 1
    /// 阴影浓度
    var shadowOpacity: Double = 0.16
}

/// 待机时的随机小动作
private enum IdleGesture {
    case none
    case lookAround   // 左右张望
    case headTilt     // 歪头
    case tiptoe       // 踮脚
    case stretch      // 伸个懒腰
}

/// 宠物大脑:负责状态机、位置更新、姿态解算
final class PetBrain: ObservableObject {

    // MARK: - 对外发布的状态
    @Published private(set) var state: PetState = .idle
    @Published private(set) var facingRight: Bool = true
    /// 统一动画时钟(秒)。每 tick 变化一次,顺带驱动 SwiftUI 重绘。
    @Published private(set) var clock: Double = 0
    @Published var followMouse: Bool = false {
        didSet { if followMouse, state == .sleep { switchTo(.idle) } }
    }

    /// 本帧姿态。不是 @Published —— clock 每帧都变,视图重绘时自然读到最新值。
    private(set) var pose = PetPose()
    /// 帧动画播放器(没有帧素材时内部为空,渲染层回退静态立绘)
    private(set) var sprites: SpriteAnimator
    /// 当前出场角色
    @Published private(set) var role: PetRole
    /// 当前角色的素材
    private(set) var roleAssets: RoleAssets
    /// 嘉宾模式:撒花时临时出场的其他角色。只站着鼓掌,不走动 / 不睡觉 / 不举牌,
    /// 也不会把角色选择写回 UserDefaults(不能污染用户自己挑的主角)。
    let isGuest: Bool

    /// 兼容旧调用:眼睛快闭上时视为眨眼
    var isBlinking: Bool { pose.eyeOpen < 0.45 }

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

    // MARK: - 投喂 / 摸头

    /// 正在吃的食物,nil = 没在吃。渲染层据此在嘴边画出来。
    @Published private(set) var eatingFood: FoodItem?
    /// 这一口吃到哪了 0~1,用来让食物一点点变小
    private(set) var eatProgress: Double = 0
    /// 正在咕噜咕噜(摸头)
    @Published private(set) var isPurring: Bool = false

    /// 蜡烛被吹灭时回调(交给 AppDelegate 放撒花 + 音乐)
    var onCandleBlownOut: (() -> Void)?
    /// 连戳满 10 次的照片彩蛋回调
    var onPhotoEasterEgg: (() -> Void)?
    /// 纪念日 / 周年庆祝回调(撒花时长由 occasion 决定)
    var onCelebration: ((PetOccasion) -> Void)?
    /// 进入生日模式(启动时 / 跨到生日那天 / 菜单重放)时回调,用来开麦克风听吹气
    var onBirthdayBegan: (() -> Void)?

    // MARK: - 可调参数
    /// 窗口比宠物本体大一圈,上方留给举牌 / 气泡,下方留给蛋糕
    let windowSize = CGSize(width: 200, height: 300)
    private let walkSpeed: Double = 38        // 像素/秒(走路帧按实际位移推进,调慢这里步频也跟着慢,不会滑步)
    private let followSpeed: Double = 150
    private let gravity: Double = 1500
    private let tickInterval: Double = 1.0 / 60.0
    /// 起步 / 停步的加速度(像素/秒²)。匀速突变是「生硬」的主要来源之一。
    private let acceleration: Double = 320
    /// 迈一步的距离,决定颠簸和迈腿的节奏(和 walk 帧动画的步幅对齐:小碎步 ~24px)
    private var strideLength: Double { role.isHuman ? 24 : 18 }
    /// 状态权重过渡时长
    private let blendTime: Double = 0.18
    /// 转身时长
    private let turnTime: Double = 0.16

    // MARK: - 位置(浮点,避免每帧从窗口读回导致的取整丢失)
    weak var window: NSWindow? {
        didSet { syncPositionFromWindow() }
    }
    private var posX: Double = 0
    private var posY: Double = 0
    private var velX: Double = 0
    private var fallVelocity: Double = 0
    /// 本 tick 实际水平位移,喂给帧动画和步态相位
    private var frameDistance: Double = 0
    /// 拖拽时窗口由鼠标直接驱动,用它估算拖拽速度做身体摆动
    private var dragVelX: Double = 0
    private var dragVelY: Double = 0

    // MARK: - 状态机
    private var timer: Timer?
    private var stateElapsed: Double = 0
    private var stateDuration: Double = 3
    /// 各状态的混合权重,下标 = PetState.rawValue
    private var weights = [Double](repeating: 0, count: PetState.allCases.count)

    // MARK: - 相位累加器(绝对时钟会在频率变化时跳相位,必须用累加器)
    private var breathPhase: Double = 0
    private var stridePhase: Double = 0     // 0~1,一步一个循环
    private var hopPhase: Double = 0        // 0~1,一跳一个循环
    private var dragPhase: Double = 0
    private var tailPhase: Double = 0

    // MARK: - 投喂 / 摸头计时
    private var eatElapsed: Double = 0
    private var eatBites: Int = 0
    private let eatDuration: Double = 3.0
    private var purrElapsed: Double = 0
    private let purrDuration: Double = 3.4
    private var chewPhase: Double = 0

    // MARK: - 眨眼
    private var blinkCountdown: Double = 3
    private var blinkElapsed: Double?
    private var blinkPending: Int = 0
    private let blinkClose: Double = 0.055
    private let blinkHold: Double = 0.045
    private let blinkOpenDur: Double = 0.08

    // MARK: - 手臂弹簧
    private var armAngle: Double = 0
    private var armVel: Double = 0

    // MARK: - 落地冲击
    private var impactElapsed: Double?

    // MARK: - 待机小动作
    private var gesture: IdleGesture = .none
    private var gestureElapsed: Double = 0
    private var gestureDuration: Double = 1
    private var gestureCountdown: Double = Double.random(in: 2.5...6)

    // MARK: - 朝向插值
    private var facingBlend:Double = 1

    // MARK: - 举牌 / 气泡
    private var signCountdown: Double = 12
    private var signRemaining: Double = 0
    private var bubbleRemaining: Double = 0
    private var pokeStreakDeadline: Double = 0
    private var lastPhraseIndex: Int = -1

    // MARK: - 节日检测
    /// 上次评估节日时是哪一天(yyyyMMdd)。App 常驻跨过午夜时靠它发现「换天了」。
    private var checkedDayStamp: Int = 0
    /// 距下次查日期还有多久(秒)。不用每帧都问系统时间。
    private var dayCheckCountdown: Double = 20

    /// - Parameter guestRole: 传 nil 就是主角(读用户上次选的角色);传角色名则是撒花嘉宾。
    init(guestRole: PetRole? = nil) {
        let shared = PetAssets.shared
        let initial = guestRole ?? PetRole.stored(default: shared.defaultRole)
        isGuest = guestRole != nil
        role = initial
        let bundle = shared.assets(for: initial)
        roleAssets = bundle
        sprites = SpriteAnimator(frames: bundle.frames, walkPixelsPerFrame: initial.pixelsPerWalkFrame)
        let opening: PetState = isGuest ? .happy : .idle
        state = opening
        weights[opening.rawValue] = 1
        sprites.play(opening.spriteAction)
    }

    // MARK: - 角色切换

    /// 换一个角色出场。素材整组替换,状态回到待机,位置保持不动。
    func switchRole(to next: PetRole) {
        guard next != role else { return }
        role = next
        PetRole.store(next)
        let bundle = assets.assets(for: next)
        roleAssets = bundle
        sprites = SpriteAnimator(frames: bundle.frames, walkPixelsPerFrame: next.pixelsPerWalkFrame)

        // 人形专属的举牌 / 蛋糕在猫狗身上没有素材,切过去时一并收掉
        if !next.isHuman {
            signText = nil
            isHoldingCake = false
        }
        signRemaining = 0
        bubbleText = nil
        bubbleRemaining = 0
        switchTo(.idle, duration: 2.5)
        sprites.play(PetState.idle.spriteAction, restart: true)
        showBubble("\(config.displayName(for: next))来啦", duration: 3)
    }

    // MARK: - 生命周期

    func start() {
        guard timer == nil else { return }
        syncPositionFromWindow()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // 默认 tolerance 会让系统随意推迟触发,画面就会出现细微的卡顿感
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 嘉宾只负责开心,生日流程 / 纪念日气泡都归主角
        if isGuest {
            switchTo(.happy, duration: .infinity)
            return
        }

        evaluateOccasion()
    }

    // MARK: - 节日检测

    /// 今天是不是什么特别的日子。启动时查一次,之后每 20 秒复查,
    /// 所以 App 挂着不关机也能在午夜自动切到生日 / 纪念日。
    private func evaluateOccasion() {
        guard !isGuest else { return }
        checkedDayStamp = PetBrain.dayStamp()

        guard let occasion = config.occasionToday else {
            return
        }

        if occasion.isBirthday {
            // 生日是当天的主体验,重启也应该重新捧上蛋糕,所以不做跨启动去重
            enterBirthdayMode()
            return
        }

        // 纪念日只自动庆祝一次,当天重复启动不再反复撒花
        guard !PetBrain.hasCelebrated(occasion) else { return }
        PetBrain.markCelebrated(occasion)

        showBubble(occasion.bubble, duration: 8)
        switchTo(.happy, duration: 2.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.onCelebration?(occasion)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self, !self.isHoldingCake else { return }
            self.showSign(occasion.sign, duration: 9)
            // 牌子说心意,气泡顺手补一句「几年几个月几天」
            if let span = self.config.togetherSpanText {
                self.showBubble(span, duration: 7)
            }
        }
    }

    /// 日期指纹,形如 20261031
    private static func dayStamp(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private static let celebratedKey = "HappyPet.lastCelebration"

    private static func celebrationToken(_ occasion: PetOccasion) -> String {
        "\(dayStamp())#\(occasion.key)"
    }

    private static func hasCelebrated(_ occasion: PetOccasion) -> Bool {
        UserDefaults.standard.string(forKey: celebratedKey) == celebrationToken(occasion)
    }

    private static func markCelebrated(_ occasion: PetOccasion) {
        UserDefaults.standard.set(celebrationToken(occasion), forKey: celebratedKey)
    }

    func stop() {
       timer?.invalidate()
        timer = nil
    }

    // MARK: - 位置

    /// 把浮点坐标与窗口当前位置对齐(启动、外部拖拽后调用)
    private func syncPositionFromWindow() {
        guard let window else { return }
        posX = Double(window.frame.origin.x)
        posY = Double(window.frame.origin.y)
    }

    /// 把浮点坐标写回窗口
    private func applyPosition() {
        guard let window else { return }
        window.setFrameOrigin(NSPoint(x: posX, y: posY))
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
        } else if pokeStreak == 1, bubbleText == nil, Int.random(in: 0..<12) == 0,
                  let d = config.daysTogether {
            // 平日里偶尔才提一次天数,比每次启动都报数更像惊喜。
            // 两种说法随机挑一个:要么报总天数,要么报几年几个月几天。
            if let span = config.togetherSpanText, Bool.random() {
                showBubble("我们已经在一起 \(span) 啦", duration: 4)
            } else {
                showBubble("今天是我们一起的第 \(d) 天哦", duration: 4)
            }
        }

        if !isHoldingCake {
            // 被戳的瞬间来一下轻微挤压,反馈更"有肉感"
            impactElapsed = 0
            hopPhase = 0
            switchTo(.happy, duration: 1.1)
        }
    }

    // MARK: - 投喂 / 摸头

    /// 屏幕坐标是否落在宠物身上。给投喂做命中判定,比点击命中区放宽一圈,拖过去更好对准。
    func bodyContains(_ screenPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let f = window.frame
        let hasCharacter = roleAssets.hasAnything
        let h = role.displayHeight
        // 和 PetContainerView.hitTest 用同一套几何:脚底固定在窗口中线下方 138.5pt
        let feet = f.midY - 138.5
        let center = hasCharacter
            ? CGPoint(x: f.midX, y: feet + h / 2)
            : CGPoint(x: f.midX, y: f.midY - 70)
        let rx = (hasCharacter ? (role.isHuman ? h * 0.23 : h * 0.6) : 58) + 30
        let ry = (hasCharacter ? h * 0.48 : 54) + 30
        let dx = (screenPoint.x - center.x) / rx
        let dy = (screenPoint.y - center.y) / ry
        return (dx * dx + dy * dy) <= 1
    }

    /// 投喂:拖一样食物到身上
    func feed(_ item: FoodItem) {
        guard !isGuest else { return }
        if isHoldingCake {
            showBubble("先把蜡烛吹了嘛 🎂", duration: 2.5)
            return
        }
        pokeStreak = 0
        isPurring = false
        eatingFood = item
        eatElapsed = 0
        eatBites = 0
        eatProgress = 0
        fallVelocity = 0
        velX = 0
        impactElapsed = 0
        switchTo(.eat, duration: eatDuration)
        showBubble(item.greeting(for: role), duration: 2.4)
    }

    /// 双击摸头:咕噜咕噜 + 冒心心
    func headPat() {
        guard !isGuest else { return }
        if isHoldingCake, candleLit {
            blowOutCandle()
            return
        }
        // 摸头不算戳,顺手清掉连戳计数,免得误触照片彩蛋
        pokeStreak = 0
        if state == .eat { return }   // 嘴里有东西就先让它吃完
        isPurring = true
        purrElapsed = 0
        velX = 0
        switchTo(.purr, duration: purrDuration)
        showBubble(PetBrain.purrLines.randomElement() ?? "咕噜咕噜~", duration: 2.8)
    }

    private static let purrLines = [
        "咕噜咕噜~",
        "舒服…再摸摸",
        "最喜欢被你摸头了",
        "呼噜噜…要化了",
        "摸头!开心!"
    ]

    private func updateEat(_ dt: Double) {
        eatElapsed += dt
        eatProgress = min(1, eatElapsed / eatDuration)
        // 分三口吃完,每咬一口挤一下身体,看着才像真在咀嚼
        let bite = min(3, Int(eatProgress * 3.0 + 0.0001))
        if bite > eatBites {
            eatBites = bite
            impactElapsed = 0
        }
        guard eatElapsed >= eatDuration else { return }
        let finished = eatingFood
        eatingFood = nil
        eatProgress = 0
        hopPhase = 0
        switchTo(.happy, duration: 2.2)
        if let finished { showBubble(finished.afterword(for: role), duration: 3.2) }
    }

    private func updatePurr(_ dt: Double) {
        purrElapsed += dt
        guard purrElapsed >= purrDuration else { return }
        isPurring = false
        switchTo(.idle, duration: 2)
    }

    // MARK: - 生日流程
    func enterBirthdayMode() {
        isHoldingCake = true
        candleLit = true
        signText = nil
        switchTo(.cake, duration: .infinity)
        showBubble("对着麦克风吹一下 🎂", duration: 10)
        onBirthdayBegan?()
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
        hopPhase = 0
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
        if state != .drag {
            velX = 0
            switchTo(.drag, duration: .infinity)
        }
    }

    func endDrag() {
        fallVelocity = 0
        syncPositionFromWindow()
        switchTo(.fall, duration: .infinity)
    }

    func toggleSleep() {
        switchTo(state == .sleep ? .idle : .sleep, duration: state == .sleep ? 2 : 20)
    }

    /// 回到屏幕右下角
    func resetPosition() {
        guard let screen = currentScreen() else { return }
        let frame = screen.visibleFrame
        posX = Double(frame.maxX - windowSize.width - 20)
        posY = Double(frame.minY)
        velX = 0
        fallVelocity = 0
        applyPosition()
        switchTo(.idle)
    }

    // MARK: - 主循环

    private func tick() {
        let dt = tickInterval
        clock += dt
        stateElapsed += dt
        frameDistance = 0

        updateBlink(dt)
        updateSignAndBubble(dt)
        updateDayWatch(dt)

        switch state {
        case .walk:
            stepWalk(dt)
        case .fall:
            stepFall(dt)
        case .drag:
            trackDrag(dt)
        case .idle, .sleep, .happy:
            if followMouse, state != .happy {
                chaseMouse(dt)
            } else {
                coast(dt)
            }
        case .cake:
            coast(dt)
        case .eat:
            coast(dt)
            updateEat(dt)
        case .purr:
            coast(dt)
            updatePurr(dt)
        }

        if stateElapsed >= stateDuration { decideNextState() }

        updateWeights(dt)
        updatePhases(dt)
        updateIdleGesture(dt)
        updateArm(dt)
        updateFacing(dt)
        updatePose(dt)

        // 帧动画:走路按实际位移推进,其余按时间推进
        sprites.play(spriteAction)
        sprites.advance(dt: dt, distance: frameDistance)
    }

    /// 当前该播哪个动作的帧序列
    private var spriteAction: String {
        if isHoldingCake { return candleLit ? "cake" : "happy" }
        if state == .idle, signText != nil { return "sign" }
        if state == .happy, pokeStreak > 0, sprites.has("poke") { return "poke" }
        return state.spriteAction
    }

    /// 盯着日期变化。跨过午夜(或睡眠唤醒后发现换天了)就重新评估一次节日,
    /// 这样生日 / 纪念日当天不用重启 App 也会自己冒出来。
    private func updateDayWatch(_ dt: Double) {
        guard !isGuest else { return }
        dayCheckCountdown -= dt
        guard dayCheckCountdown <= 0 else { return }
        dayCheckCountdown = 20
        guard PetBrain.dayStamp() != checkedDayStamp else { return }
        // 正捧着蛋糕就先不打扰,等这轮生日流程走完
        guard !isHoldingCake else { return }
        evaluateOccasion()
    }

    /// 举牌与气泡的倒计时;平时每隔一段时间自动举一次牌
    private func updateSignAndBubble(_ dt: Double) {
        if signRemaining > 0 {
            signRemaining -= dt
            if signRemaining <= 0 { signText = nil }
        }
        if bubbleRemaining > 0 {
            bubbleRemaining -= dt
            if bubbleRemaining <= 0 { bubbleText = nil }
        }
        guard !isGuest, !isHoldingCake, signText == nil else { return }
        signCountdown -= dt
        if signCountdown <= 0, state != .drag, state != .fall {
            showSign()
        }
    }

    /// 眨眼:闭 → 停 → 开 三段式,全部由主循环驱动(原来用 asyncAfter,
    /// 固定 0.13 秒的硬切和主循环不同步,看起来就是"抽一下")
    private func updateBlink(_ dt: Double) {
        if var e = blinkElapsed {
            e += dt
            if e >= blinkClose + blinkHold + blinkOpenDur {
                blinkElapsed = nil
                if blinkPending > 0 {
                    blinkPending -= 1
                    // 双眨之间留一点间隔
                    blinkCountdown = 0.09
                }
            } else {
                blinkElapsed = e
            }
            return
        }

        blinkCountdown -= dt
        if blinkCountdown <= 0 {
            blinkElapsed = 0
            blinkCountdown = Double.random(in: 2.2...5.5)
            // 偶尔连眨两下,更像活物
            if blinkPending == 0, Double.random(in: 0...1) < 0.22 { blinkPending = 1 }
        }
    }

    /// 由眨眼进度解算出眼睛张开度(带缓动,不是方波)
    private var blinkEyeOpen: Double {
        guard let e = blinkElapsed else { return 1 }
        if e < blinkClose {
            return 1 - smoothstep(e / blinkClose)
        }
        if e < blinkClose + blinkHold {
            return 0
        }
        let p = (e - blinkClose - blinkHold) / blinkOpenDur
        return smoothstep(min(1, p))
    }

    // MARK: - 行为实现

    private func stepWalk(_ dt: Double) {
        if followMouse { chaseMouse(dt); return }
        accelerate(toward: (facingRight ? 1 : -1) * walkSpeed, dt: dt)
        move(dx: velX * dt)
    }

    private func chaseMouse(_ dt: Double) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let centerX = Double(window.frame.midX)
        let delta = Double(mouse.x) - centerX
        guard abs(delta) > 45 else {
            decelerate(dt)
            if abs(velX) > 2 { move(dx: velX * dt) }
            if state == .walk, abs(velX) < 4 { switchTo(.idle, duration: 1.2) }
            return
        }
        if state != .walk { switchTo(.walk, duration: .infinity) }
        facingRight = delta > 0
        // 离得越远走越快,临近时自然减速,不再是"贴到脸上才急停"
        let ratio = min(1, abs(delta) / 220)
        let target = (delta > 0 ? 1 : -1) * followSpeed * (0.35 + 0.65 * ratio)
        accelerate(toward: target, dt: dt)
        move(dx: velX * dt)
    }

    private func accelerate(toward target: Double, dt: Double) {
        let diff = target - velX
        let step = acceleration * dt
        velX += max(-step, min(step, diff))
    }

    private func decelerate(_ dt: Double) {
        let step = acceleration * dt
        if abs(velX) <= step { velX = 0 } else { velX -= step * (velX > 0 ? 1 : -1) }
    }

    /// 停步时继续滑一小段再停住,避免"说停就停"的生硬感
    private func coast(_ dt: Double) {
        guard abs(velX) > 0.5 else { velX = 0; return }
        move(dx: velX * dt)
        decelerate(dt)
    }

    private func stepFall(_ dt: Double) {
        guard let screen = currentScreen() else { return }
        let baseline = Double(screen.visibleFrame.minY)
        fallVelocity += gravity * dt
        posY -= fallVelocity * dt
        // 下落时保留一点水平惯性,看着像真的被甩出去
        if abs(velX) > 1 {
            move(dx: velX * dt)
            velX *= 0.96
        }
        if posY <= baseline {
            posY = baseline
            applyPosition()
            // 落地冲击:先压扁再回弹,由 impactElapsed 驱动
            impactElapsed = 0
            fallVelocity = 0
            hopPhase = 0
            switchTo(.happy, duration: 0.9)
        } else {
            applyPosition()
        }
    }

    /// 拖拽中窗口由鼠标直接驱动,这里只负责同步坐标并估算速度
    private func trackDrag(_ dt: Double) {
        guard let window else { return }
        let nx = Double(window.frame.origin.x)
        let ny = Double(window.frame.origin.y)
        let vx = (nx - posX) / dt
        let vy = (ny - posY) / dt
        // 一阶低通,去掉鼠标抖动带来的高频噪声
        dragVelX += (vx - dragVelX) * 0.18
        dragVelY += (vy - dragVelY) * 0.18
        posX = nx
        posY = ny
        velX = dragVelX * 0.35
    }

    /// 水平移动并在屏幕边缘转身
    private func move(dx: Double) {
        guard let screen = currentScreen() else { return }
        let frame = screen.visibleFrame
        let before = posX
        posX += dx
        if posX <= Double(frame.minX) {
            posX = Double(frame.minX)
            facingRight = true
            velX = 0
        } else if posX + Double(windowSize.width) >= Double(frame.maxX) {
            posX = Double(frame.maxX) - Double(windowSize.width)
            facingRight = false
            velX = 0
        }
        frameDistance += posX - before
        applyPosition()
    }

    // MARK: - 状态切换

    private func decideNextState() {
        // 嘉宾一直开心到退场,不走神
        if isGuest {
            if state != .happy { switchTo(.happy, duration: .infinity) }
            stateElapsed = 0
            stateDuration = .infinity
            return
        }
        // 正在吃东西 / 被摸头时不打断,交给各自的计时器收尾
        if state == .eat || state == .purr {
            stateElapsed = 0
            stateDuration = 1
            return
        }
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
        if followMouse { stateElapsed = 0; stateDuration = 1; return }
        switch Int.random(in: 0..<10) {
        case 0...4:
            // 转身在 switchTo 之前定,这样转身动画和起步加速同时发生
            facingRight = Bool.random()
            switchTo(.walk, duration: Double.random(in: 2.5...6))
        case 5...8:
            switchTo(.idle, duration: Double.random(in: 2...5))
        default:
            switchTo(.sleep, duration: Double.random(in: 6...14))
        }
    }

    private func switchTo(_ next: PetState, duration: Double = 2.5) {
        if next != state {
            if next == .happy { hopPhase = 0 }
            if next == .drag { dragVelX = 0; dragVelY = 0; dragPhase = 0 }
            if next != .idle { gesture = .none }
        }
        state = next
        stateElapsed = 0
        stateDuration = duration
    }

    // MARK: - 姿态解算

    private func w(_ s: PetState) -> Double { weights[s.rawValue] }

    /// 状态权重一阶平滑:原来切状态时振幅直接跳变,这里改成 0.18 秒过渡
    private func updateWeights(_ dt: Double) {
        let k = min(1, dt / blendTime)
        for s in PetState.allCases {
            let i = s.rawValue
            let target = (s == state) ? 1.0 : 0.0
            weights[i] += (target - weights[i]) * k
        }
    }

    /// 全部用相位累加器。直接拿 sin(clock * 频率) 的话,
    /// 频率一变相位就会跳,表现出来就是动作"咯噜"一下。
    private func updatePhases(_ dt: Double) {
        let speedRatio = min(1, abs(velX) / walkSpeed)

        breathPhase += dt * (2.4 - 1.3 * w(.sleep))
        if breathPhase > .pi * 2 { breathPhase -= .pi * 2 }

        stridePhase += abs(frameDistance) / strideLength
        stridePhase -= stridePhase.rounded(.down)

        hopPhase += dt * 2.1
        if w(.happy) < 0.02 { hopPhase = 0 }

        dragPhase += dt * 5
        if dragPhase > .pi * 2 { dragPhase -= .pi * 2 }

        let tailSpeed = 1.8 + 3.2 * max(speedRatio, w(.happy)) - 0.9 * w(.sleep)
        tailPhase += dt * tailSpeed
        if tailPhase > .pi * 2 { tailPhase -= .pi * 2 }

        // 咀嚼:只在吃东西时推进,吃完归零,免得下次开口对不上节奏
        if w(.eat) > 0.02 {
            chewPhase += dt * 11
            if chewPhase > .pi * 2 { chewPhase -= .pi * 2 }
        } else {
            chewPhase = 0
        }
    }

    /// 待机不再只有呼吸:隔一会儿来个张望 / 歪头 / 踮脚 / 伸懒腰
    private func updateIdleGesture(_ dt: Double) {
        if gesture != .none {
            gestureElapsed += dt
            if gestureElapsed >= gestureDuration {
                gesture = .none
                gestureCountdown = Double.random(in: 3...7)
            }
            return
        }
        guard state == .idle, signText == nil, !isHoldingCake else { return }
        gestureCountdown -= dt
        guard gestureCountdown <= 0 else { return }
        gestureElapsed = 0
        switch Int.random(in: 0..<4) {
        case 0: gesture = .lookAround; gestureDuration = 2.2
        case 1: gesture = .headTilt;   gestureDuration = 1.6
        case 2: gesture = .tiptoe;     gestureDuration = 1.0
        default: gesture = .stretch;   gestureDuration = 1.8
        }
    }

    /// 小动作的进出包络:两头为 0,中间为 1,保证不会突然开始 / 结束
    private var gestureEnvelope: Double {
        guard gesture != .none, gestureDuration > 0 else { return 0 }
        let p = min(1, max(0, gestureElapsed / gestureDuration))
        let s = sin(.pi * p)
        return s * s
    }

    /// 抬手用弹簧跟随目标角度,而不是直接赋值(原来是 ±3 直接跳到 -58)
    private func updateArm(_ dt: Double) {
        var target: Double
        if signText != nil || isHoldingCake {
            target = -58
        } else {
            target = sin(breathPhase * 0.7) * 3 + 5 * w(.sleep)
        }
        if gesture == .stretch { target -= 34 * gestureEnvelope }
        target += -10 * w(.happy) + 14 * w(.drag)

        let omega = 12.0
        let zeta = 0.85
        let accel = -omega * omega * (armAngle - target) - 2 * zeta * omega * armVel
        armVel += accel * dt
        armAngle += armVel * dt
    }

    /// 转身插值:瞬时镜像会"闪"一下,这里用 0.16 秒压扁翻转
    private func updateFacing(_ dt: Double) {
        let target: Double = facingRight ? 1 : -1
        facingBlend += (target - facingBlend) * min(1, dt / turnTime)
    }

    /// 把所有权重、相位汇总成这一帧的姿态
    private func updatePose(_ dt: Double) {
        // 落地 / 被戳的冲击:先压扁,再两次递减回弹
        var impactSX = 1.0
        var impactSY = 1.0
        if var e = impactElapsed {
            e += dt
            if e >= 0.7 {
                impactElapsed = nil
            } else {
                impactElapsed = e
                let decay = exp(-9 * e)
                let osc = cos(26 * e)
                impactSX = 1 + 0.12 * decay * osc
                impactSY = 1 - 0.14 * decay * osc
            }
        }

        let walkW = w(.walk) * min(1, abs(velX) / walkSpeed)
        let sleepW = w(.sleep)
        let happyW = w(.happy)
        let dragW = w(.drag)
        let fallW = w(.fall)
        let eatW = w(.eat)
        let purrW = w(.purr)
        let env = gestureEnvelope

        var p = PetPose()

        // 呼吸
        let breath = sin(breathPhase) * (0.022 + 0.023 * sleepW)
        p.breath = CGFloat(breath)

        // 走路:sin² 在零点是平的,abs(sin) 会折出一个尖角
        let stepUp = pow(sin(.pi * stridePhase), 2)
        // 落脚瞬间(相位 0 / 1)的触地挤压
        let footContact = pow(abs(cos(.pi * stridePhase)), 10)
        p.bob = CGFloat(-4 * stepUp * walkW)
        p.sway = CGFloat(sin(2 * .pi * stridePhase) * 1.8 * walkW)
        p.legSwing = CGFloat(sin(2 * .pi * stridePhase) * 5 * walkW + sin(dragPhase) * 3 * dragW)
        p.tailSwing = CGFloat(sin(tailPhase))

        // 开心:一跳一个 sin² 弧线,落地那一下再压一次
        let hopF = hopPhase - hopPhase.rounded(.down)
        let hopUp = pow(sin(.pi * hopF), 2)
        let hopLand = pow(abs(cos(.pi * hopF)), 12)
        p.jump = CGFloat(-26 * hopUp * happyW)

        // 待机小动作
        var tilt = 0.0
        var extraBob = 0.0
        switch gesture {
        case .lookAround: tilt += sin(gestureElapsed * 3.1) * 5 * env
        case .headTilt:   tilt += 7 * env
        case .tiptoe:     extraBob -= 5 * env
        case .stretch:    extraBob -= 2 * env
        case .none:       break
        }
        p.bob += CGFloat(extraBob * (1 - walkW))

        // 拖拽:身体随拖拽方向后倾 + 小幅摆动
        let dragLean = max(-16, min(16, -dragVelX * 0.035))
        tilt += (sin(dragPhase) * 7 + dragLean) * dragW

        // 吃东西:小幅点头 + 身体跟着咀嚼节奏一上一下
        let chew = sin(chewPhase)
        p.bob += CGFloat(chew * 1.6 * eatW)
        tilt += chew * 2.6 * eatW

        // 被摸头:整只慢慢左右蹭,像在蹭手
        let purrWave = sin(clock * 2.6)
        p.sway += CGFloat(purrWave * 2.4 * purrW)
        tilt += purrWave * 4 * purrW

        p.tilt = tilt

        // 形变合成
        var sx = 1 - breath
        var sy = 1 + breath
        sx += 0.03 * footContact * walkW + 0.05 * hopLand * happyW
        sy -= 0.03 * footContact * walkW + 0.06 * hopLand * happyW
        // 咀嚼时嘴部挤压,被摸头时整只微微缩成一团
        sx += 0.035 * chew * eatW + 0.03 * purrW
        sy -= 0.035 * chew * eatW + 0.02 * purrW
        // 下落拉长
        sx += (0.92 - 1) * fallW
        sy += (1.10 - 1) * fallW
        // 被拎着时身体稍微拉长
        sy += 0.04 * dragW
        // 转身中途轻微压扁,让镜像翻转有体积感
        let turnSqueeze = 1 - abs(facingBlend)
        sy += 0.06 * turnSqueeze
        p.squash = CGSize(width: CGFloat(sx * impactSX), height: CGFloat(sy * impactSY))

        p.armAngle = armAngle
        let mag = max(0.1, abs(facingBlend))
        p.facing = CGFloat(facingBlend >= 0 ? mag : -mag)
        p.eyeOpen = min(blinkEyeOpen, 1 - sleepW)
        // 享受摸头的时候眯着眼
        p.eyeOpen = min(p.eyeOpen, 1 - 0.7 * purrW)

        let lift = Double(-(p.bob + p.jump))
        p.shadowScale = CGFloat(max(0.45, 1 - lift * 0.013))
        p.shadowOpacity = max(0.05, 0.16 - 0.09 * (dragW + fallW) - lift * 0.0008)

        pose = p
    }

    private func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    private func currentScreen() -> NSScreen? {
        guard let window else { return NSScreen.main }
        return NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main
    }
}