import AppKit
import Foundation

/// 一个动作的帧序列及其播放参数
struct SpriteClip {
    var frames: [NSImage]
    /// 按时间推进时的帧率
    var fps: Double = 6
    /// 非 nil 时改为按「实际走过的像素」推进。
    ///走路必须用它:帧率和移动速度脱钩就会出现「滑步」。
    var pixelsPerFrame: Double?
    var loops: Bool = true
    /// 帧间交叉淡化。AI 生成的帧通常只有 2~4 张,硬切会闪,
    /// 轻度 cross-dissolve 相当于免费的补间。
    var crossfade: Bool = true
    /// 每帧的相对停留时长。眨眼全靠它:睁眼帧停 1.0、闭眼帧只停 0.07,
    /// 平分时长的话就不是眨眼,而是「一半时间闭着眼」。
    var holds: [Double]?
    /// 交叉淡化窗口(秒),只在每帧末尾这段时间内混合。
    /// 停留很久的帧若全程淡化,会一直显示半透明的下一帧 —— 看着像永远半闭眼。
    var fadeSeconds: Double = 0.25

    var count: Int { frames.count }

    func hold(at index: Int) -> Double {
        guard let holds, !holds.isEmpty else { return 1 }
        return max(0.02, holds[index % holds.count])
    }
}

/// 帧序列播放器。
///
/// 设计要点:
/// 1. 只认动作名字符串,不依赖 PetState,方便以后加动作;
/// 2. 素材缺失时按 fallbackChain 自动降级,一路降到 nil 就让渲染层回退静态立绘;
/// 3. 对外暴露 current / next / mix 三件套,渲染层叠两张图做交叉淡化;
/// 4. phase 给代码形变(颠簸、重心摆)当相位,保证形变和脚步对得上。
final class SpriteAnimator {

    /// 每个动作的默认播放参数
    private static let presets: [String: SpriteClip] = [
        // 走路:每走 12px 换一帧,4 帧正好一个完整步态循环(约 48px)
        "walk": SpriteClip(frames: [], fps: 6, pixelsPerFrame: 12, loops: true, crossfade: true),
        // 待机:帧 1 睁眼停 ≈2.4s、帧 2 闭眼只停 ≈0.17s,就是一次自然的眨眼。
        // 淡化窗口压到 0.05s —— 眨眼本来就是快动作,慢慢渐变反而像犯困。
        "idle": SpriteClip(frames: [], fps: 0.42, pixelsPerFrame: nil, loops: true,
                           crossfade: true, holds: [1.0, 0.07], fadeSeconds: 0.05),
        "happy": SpriteClip(frames: [], fps: 7.5, pixelsPerFrame: nil, loops: true, crossfade: false),
        // 睡觉:两帧呼吸起伏,淡化给足,胸口才是「缓慢起落」而不是一跳一跳
        "sleep": SpriteClip(frames: [], fps: 1.1, pixelsPerFrame: nil, loops: true,
                            crossfade: true, fadeSeconds: 0.45),
        "cake": SpriteClip(frames: [], fps: 3, pixelsPerFrame: nil, loops: true, crossfade: true),
        "sign": SpriteClip(frames: [], fps: 3, pixelsPerFrame: nil, loops: true, crossfade: true),
        "drag": SpriteClip(frames: [], fps: 5, pixelsPerFrame: nil, loops: true, crossfade: true),
        "fall": SpriteClip(frames: [], fps: 8, pixelsPerFrame: nil, loops: false, crossfade: false),
        "poke": SpriteClip(frames: [], fps: 8, pixelsPerFrame: nil, loops: false, crossfade: false)
    ]

    /// 素材缺失时的降级顺序(不含自身)
    private static let fallbackChain: [String: [String]] = [
        "walk": ["idle"],
        "happy": ["poke", "idle"],
        "poke": ["happy", "idle"],
        "sign": ["happy", "idle"],
        "cake": ["sign", "happy", "idle"],
        "drag": ["fall", "idle"],
        "fall": ["drag", "idle"],
        "sleep": ["idle"],
        "idle": []
    ]

    private let clips: [String: SpriteClip]

    /// 当前真正在播的动作(可能是降级后的结果);nil = 无可用帧
    private(set) var action: String?
    /// 请求播放的动作,用来判断是否需要重新解析
    private var requested: String?
    /// 浮点帧游标,范围 [0, count)
    private var cursor: Double = 0
    /// 单次播放的动作是否已播完
    private(set) var isFinished: Bool = false

    /// 是否有任何帧素材。没有就让渲染层走老的静态立绘逻辑。
    var isEmpty: Bool { clips.isEmpty }

    init(frames: [String: [NSImage]], walkPixelsPerFrame: Double? = nil) {
        var built: [String: SpriteClip] = [:]
        for (name, images) in frames where !images.isEmpty {
            var clip = SpriteAnimator.presets[name]
                ?? SpriteClip(frames: [], fps: 6, pixelsPerFrame: nil, loops: true, crossfade: true)
            clip.frames = images
            clip.crossfade = clip.crossfade && images.count > 1
            // 不同角色腿长不同,走路帧的步幅要跟着换,否则四足动物会滑步
            if name == "walk", let ppf = walkPixelsPerFrame, ppf > 0 {
                clip.pixelsPerFrame = ppf
            }
            built[name] = clip
        }
        clips = built
    }

    // MARK: - 查询

    func has(_ action: String) -> Bool { clips[action] != nil }

    /// 沿降级链找出第一个有素材的动作
    private func resolve(_ name: String) -> String? {
        if clips[name] != nil { return name }
        for candidate in SpriteAnimator.fallbackChain[name] ?? [] {
            if clips[candidate] != nil { return candidate }
        }
        return clips["idle"] != nil ? "idle" : nil
    }

    // MARK: - 播放控制

    /// 切换动作。同一动作重复调用不会打断播放进度。
    func play(_ name: String, restart: Bool = false) {
        if requested == name, !restart { return }
        requested = name
        let resolved = resolve(name)
        // 降级后落到同一个 clip(例如 walk/idle 都降到 idle)就别重置游标,
        // 否则状态来回切时帧会一直跳回第一张。
        if resolved != action || restart {
            action = resolved
            cursor = 0
            isFinished = false
        }
    }

    /// 推进一帧。
    /// - Parameters:
    ///   - dt: 本次 tick 的时长
    ///   - distance: 本次 tick 实际移动的水平距离(像素),给按距离推进的动作用
    func advance(dt: Double, distance: Double = 0) {
        guard let action, let clip = clips[action] else { return }
        guard clip.count > 1 else {
            isFinished = true
            cursor = 0
            return
        }
        let count = Double(clip.count)

        if let ppf = clip.pixelsPerFrame, ppf > 0 {
            cursor += abs(distance) / ppf
        } else {
            // 除以当前帧的停留权重:权重大的帧推进慢、停得久
            cursor += dt * clip.fps / clip.hold(at: frameIndex)
        }

        if clip.loops {
            cursor = cursor.truncatingRemainder(dividingBy: count)
            if cursor < 0 { cursor += count }
        } else if cursor >= count - 1 {
            cursor = count - 1
            isFinished = true
        }
    }

    // MARK: - 渲染取值

    private var currentClip: SpriteClip? {
        guard let action else { return nil }
        return clips[action]
    }

    private var frameIndex: Int {
        guard let clip = currentClip, clip.count > 0 else { return 0 }
        return min(max(Int(cursor.rounded(.down)), 0), clip.count - 1)
    }

    /// 当前帧
    var current: NSImage? {
        guard let clip = currentClip, clip.count > 0 else { return nil }
        return clip.frames[frameIndex]
    }

    /// 下一帧(用于交叉淡化)
    var next: NSImage? {
        guard let clip = currentClip, clip.count > 1 else { return nil }
        let i = frameIndex
        let j = clip.loops ? (i + 1) % clip.count : min(i + 1, clip.count - 1)
        return clip.frames[j]
    }

    /// 下一帧的混合权重 0~1
    var mix: Double {
        guard let clip = currentClip, clip.count > 1, clip.crossfade else { return 0 }
        let frac = cursor - cursor.rounded(.down)
        // 按距离推进(走路):全程补间,4 张帧当成连续步态用
        if clip.pixelsPerFrame != nil {
            return frac * frac * (3 - 2 * frac)
        }
        // 按时间推进:只在帧末尾 fadeSeconds 内淡化。
        // 不限窗口的话,待机那种停 2.4s 的帧会全程叠着闭眼图,就成了半睁眼。
        let frameSeconds = clip.hold(at: frameIndex) / max(clip.fps, 0.01)
        let window = min(clip.fadeSeconds, frameSeconds * 0.5) / frameSeconds
        guard window > 0.0001, frac > 1 - window else { return 0 }
        let t = (frac - (1 - window)) / window
        return t * t * (3 - 2 * t)
    }

    /// 当前动作的整体播放进度 0~1,给代码形变当相位用
    var phase: Double {
        guard let clip = currentClip, clip.count > 0 else { return 0 }
        return cursor / Double(clip.count)
    }

    /// 步态相位 0~1:一个完整的「左脚→右脚」循环。
    /// 走路帧通常是 4 帧两步,所以半个序列就是一步。
    var stridePhase: Double {
        guard let clip = currentClip, clip.count > 1 else { return 0 }
        let stepsPerLoop = max(1.0, Double(clip.count) / 2.0)
        let p = cursor / Double(clip.count) * stepsPerLoop
        return p - p.rounded(.down)
    }
}