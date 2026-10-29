import AVFoundation
import Foundation

/// 麦克风"吹气"检测器。
///
/// 思路:取麦克风单声道 PCM,算每帧的 RMS 音量 + 低频能量占比。
/// 吹气的特征是「音量突然变大」且「能量集中在低频(风噪)」,
/// 这样可以跟说话、敲键盘区分开(不追求精确,够用就行)。
///
/// 任何一步失败(没权限 / 没输入设备 / 引擎起不来)都会安静地降级,
/// 用户仍然可以直接点蛋糕吹蜡烛。
final class BreathDetector {

    /// 检测到吹气时回调(主线程)
    var onBlow: (() -> Void)?
    /// 是否正在监听
    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    /// 连续超过阈值的累计时长
    private var hotDuration: Double = 0
    /// 触发后的冷却,避免一口气触发好几次
    private var cooldownUntil: Date = .distantPast

    // MARK: - 可调参数

    /// 响度阈值(dBFS),越接近 0 越难触发
    private let loudnessThreshold: Float = -26
    /// 低频能量占比阈值,吹气的风噪集中在低频
    private let lowFreqRatioThreshold: Float = 0.62
    /// 需要连续满足条件多久才算一次"吹"
    private let requiredDuration: Double = 0.18

    // MARK: - 启动 / 停止

    /// 请求权限并开始监听。`completion` 回传是否真的启动成功。
    func start(completion: ((Bool) -> Void)? = nil) {
        guard !isRunning else { completion?(true); return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            let ok = launchEngine()
            completion?(ok)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { completion?(false); return }
                    guard granted else { completion?(false); return }
                    completion?(self.launchEngine())
                }
            }
        default:
            completion?(false)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        hotDuration = 0
    }

    // MARK: - 内部

    private func launchEngine() -> Bool {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        // 没有可用输入设备时 sampleRate 会是 0
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.analyze(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
    }

    private func analyze(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 32 else { return }

        let sampleRate = buffer.format.sampleRate
        let chunkSeconds = Double(count) / max(sampleRate, 1)

        // 一次遍历同时算:整体能量、一阶差分能量(近似高频能量)
        var energy: Float = 0
        var diffEnergy: Float = 0
        var previous = channel[0]
        for i in 0..<count {
            let sample = channel[i]
            energy += sample * sample
            let d = sample - previous
            diffEnergy += d * d
            previous = sample
        }
        guard energy > 0 else { resetHot(); return }

        let rms = (energy / Float(count)).squareRoot()
        let loudness = 20 * log10(max(rms, 1e-7))
        // 差分能量相对总能量越小 => 波形越平滑 => 能量越偏低频
        let highRatio = min(diffEnergy / energy, 4) / 4
        let lowFreqRatio = 1 - highRatio

        let hit = loudness > loudnessThreshold && lowFreqRatio > lowFreqRatioThreshold
        guard hit else { resetHot(); return }

        hotDuration += chunkSeconds
        guard hotDuration >= requiredDuration else { return }
        hotDuration = 0

        let now = Date()
        guard now > cooldownUntil else { return }
        cooldownUntil = now.addingTimeInterval(2.5)

        DispatchQueue.main.async { [weak self] in
            self?.onBlow?()
        }
    }

    private func resetHot() {
        if hotDuration > 0 { hotDuration = max(0, hotDuration - 0.05) }
    }
}