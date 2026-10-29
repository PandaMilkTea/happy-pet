import AppKit
import Foundation

// MARK: - 用户配置

/// 来自 Assets/config.json 的个性化配置。文件缺失或字段残缺时全部走默认值。
struct PetConfig: Codable {
    var nickname: String
    var birthdayMonth: Int
    var birthdayDay: Int
    /// 纪念日,格式 "2023-05-20"
    var anniversary: String?
    /// 吹灭蜡烛后出现的那句话
    var birthdayWish: String
    /// 调试用:强制进入生日模式,方便提前预览
    var forceBirthdayMode: Bool?

    static let fallback = PetConfig(
        nickname: "宝宝",
        birthdayMonth: 1,
        birthdayDay: 1,
        anniversary: nil,
        birthdayWish: "生日快乐,今年也要一直开开心心的。",
        forceBirthdayMode: false
    )

    // MARK: 派生信息

    /// 今天是否生日(或被强制开启)
    var isBirthdayToday: Bool {
        if forceBirthdayMode == true { return true }
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        return c.month == birthdayMonth && c.day == birthdayDay
    }

    /// 在一起的天数,没配纪念日则为 nil
    var daysTogether: Int? {
        guard let anniversary, let start = PetConfig.dateFormatter.date(from: anniversary) else {
         return nil
        }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: Date())
        ).day
        guard let days, days >= 0 else { return nil }
        return days + 1
    }

    /// 是否是整百天纪念(100 / 200 / 520 / 1000 …)
    var isMilestoneDay: Bool {
        guard let d = daysTogether else { return false }
        return d % 100 == 0 || d == 520 || d == 1314
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - 素材仓库

/// 统一加载 Assets 目录下的素材。任何一项缺失都不影响运行,渲染层会自动退回矢量绘制。
final class PetAssets {

    static let shared = PetAssets()

    let config: PetConfig
    let body: NSImage?
    /// 闭眼整帧立绘。有这张时眨眼直接整图切换,不再叠加眼睛图层。
    let blinkBody: NSImage?
    let eyesOpen: NSImage?
    let eyesClosed: NSImage?
    let armRight: NSImage?
    let photos: [NSImage]
    let birthdaySound: URL?
    let lovePhrases: [String]

    /// 是否有人物立绘。没有就用内置的橘猫。
    var hasCharacter: Bool { body != nil }

    private init() {
        let root = PetAssets.assetsURL()

        config = PetAssets.loadConfig(in: root)
        body = PetAssets.loadImage("girl_body", in: root)
        blinkBody = PetAssets.loadImage("girl_body_blink", in: root)
        eyesOpen = PetAssets.loadImage("girl_eyes_open", in: root)
        eyesClosed = PetAssets.loadImage("girl_eyes_closed", in: root)
        armRight = PetAssets.loadImage("girl_arm_r", in: root)
        photos = PetAssets.loadPhotos(in: root)
        birthdaySound = PetAssets.loadSound(in: root)
        lovePhrases = PetAssets.loadPhrases(in: root)
    }

    // MARK: 路径解析

    /// 优先用环境变量 HAPPYPET_ASSETS(便于改完 love.txt 不重新打包),否则用 bundle 内的 Assets。
    private static func assetsURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["HAPPYPET_ASSETS"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("Assets", isDirectory: true)
    }

    // MARK: 各类加载

    private static func loadConfig(in root: URL?) -> PetConfig {
        guard let url = root?.appendingPathComponent("config.json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(PetConfig.self, from: data)
        else { return .fallback }
        return parsed
    }

    private static func loadImage(_ name: String, in root: URL?) -> NSImage? {
        guard let root else { return nil }
        for ext in ["png", "PNG"] {
            let url = root.appendingPathComponent("\(name).\(ext)")
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    private static func loadPhotos(in root: URL?) -> [NSImage] {
        guard let dir = root?.appendingPathComponent("photos", isDirectory: true),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names
            .filter { ["jpg", "jpeg", "png", "heic"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .compactMap { NSImage(contentsOf: dir.appendingPathComponent($0)) }
    }

    private static func loadSound(in root: URL?) -> URL? {
        guard let root else { return nil }
        for name in ["birthday.m4a", "birthday.mp3", "birthday.wav"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func loadPhrases(in root: URL?) -> [String] {
        guard let url = root?.appendingPathComponent("love.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return PetAssets.defaultPhrases }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.isEmpty ? PetAssets.defaultPhrases : lines
    }

    private static let defaultPhrases = [
        "今天也很喜欢你",
        "记得喝水哦",
        "累了就歇一会儿",
        "我一直都在呢",
        "你笑起来最好看"
    ]
}