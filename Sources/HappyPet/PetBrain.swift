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

    // MARK: - 可调参数
    let windowSize = CGSize(width: 160, height: 160)
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

    // MARK: - 生命周期

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 交互入口

    /// 鼠标点击宠物
    func poke() {
        fallVelocity = 0
        switchTo(.happy, duration: 1.1)
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

        switch state {
        case .walk:  stepWalk()
        case .fall:  stepFall()
        case .idle, .sleep, .happy:
            if followMouse, state != .happy { chaseMouse() }
        case .drag:
            break
        }

        if stateElapsed >= stateDuration { decideNextState() }
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