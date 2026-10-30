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
    /// 首次启动时默认出场的角色(girl / boy / cat / dog),缺省 girl
    var defaultRole: String?
    /// 各角色在菜单和气泡里的称呼,key 用角色名(girl / boy / cat / dog)。
    /// 没配或配了空串的角色走内置默认值,girl 默认复用 nickname。
    var roleNames: [String: String]?

    static let fallback = PetConfig(
        nickname: "宝宝",
        birthdayMonth: 1,
        birthdayDay: 1,
        anniversary: nil,
        birthdayWish: "生日快乐,今年也要一直开开心心的。",
        forceBirthdayMode: false,
        defaultRole: nil,
        roleNames: nil
    )

    // MARK: 派生信息

    /// 角色对外显示的名字。优先 config.roleNames,其次 girl 复用 nickname,最后用内置默认。
    func displayName(for role: PetRole) -> String {
        if let custom = roleNames?[role.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return role == .girl ? nickname : role.defaultName
    }

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

    /// 在一起的整年数(今天是纪念日当天时才有意义)
    var yearsTogether: Int? {
        guard let anniversary, let start = PetConfig.dateFormatter.date(from: anniversary) else {
            return nil
        }
        return Calendar.current.dateComponents(
            [.year],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: Date())
        ).year
    }

    /// 今天是否是每年的纪念日(月 / 日都对得上)
    var isAnniversaryToday: Bool {
        guard let anniversary, let start = PetConfig.dateFormatter.date(from: anniversary) else {
            return false
        }
        let cal = Calendar.current
        let a = cal.dateComponents([.month, .day], from: start)
        let b = cal.dateComponents([.month, .day], from: Date())
        return a.month == b.month && a.day == b.day
    }

    /// 在一起多久的「年 / 月 / 天」说法,例如 "5 年 6 个月 25 天"。
    /// 不满一年就省掉年,不满一个月就只剩天数。
    var togetherSpanText: String? {
        guard let anniversary, let start = PetConfig.dateFormatter.date(from: anniversary) else {
            return nil
        }
        let cal = Calendar.current
        let c = cal.dateComponents(
            [.year, .month, .day],
            from: cal.startOfDay(for: start),
            to: cal.startOfDay(for: Date())
        )
        guard let y = c.year, let m = c.month, let d = c.day, y >= 0, m >= 0, d >= 0 else {
            return nil
        }
        var parts: [String] = []
        if y > 0 { parts.append("\(y) 年") }
        if m > 0 { parts.append("\(m) 个月") }
        if d > 0 || parts.isEmpty { parts.append("\(d) 天") }
        return parts.joined(separator: " ")
    }

    /// 一行里把两种说法都摆出来:"在一起 2035 天 · 5 年 6 个月 25 天"
    var togetherSummary: String? {
        guard let days = daysTogether else { return nil }
        guard let span = togetherSpanText else { return "在一起 \(days) 天" }
        return "在一起 \(days) 天 · \(span)"
    }

    /// 举牌用的两行版(牌子窄,横排放不下)
    var togetherSignText: String? {
        guard let days = daysTogether else { return nil }
        guard let span = togetherSpanText else { return "在一起 \(days) 天" }
        return "在一起 \(days) 天\n\(span)"
    }

    /// 今天值得庆祝的事,没有就是 nil。优先级:生日 > 周年 > 1314 > 520 > 整百天。
    var occasionToday: PetOccasion? {
        if isBirthdayToday { return .birthday }
        guard let days = daysTogether else { return nil }
        if isAnniversaryToday, let years = yearsTogether, years >= 1 {
            return .anniversary(years: years, days: days)
        }
        if days == 1314 { return .days1314 }
        if days == 520 { return .days520 }
        if days % 100 == 0 { return .hundredDays(days) }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - 值得庆祝的日子

/// 今天是什么日子。只在当天自动触发一次,靠 key 做去重。
enum PetOccasion: Equatable {
    /// 生日
    case birthday
    /// 每年的纪念日当天
    case anniversary(years: Int, days: Int)
    /// 在一起 520 天
    case days520
    /// 在一起 1314 天
    case days1314
    /// 在一起整百天
    case hundredDays(Int)

    var isBirthday: Bool { self == .birthday }

    /// 去重用的稳定标识
    var key: String {
        switch self {
        case .birthday:                 return "birthday"
        case .anniversary(let y, _):    return "anniversary-\(y)"
        case .days520:                  return "d520"
        case .days1314:                 return "d1314"
        case .hundredDays(let d):       return "d\(d)"
        }
    }

    /// 头顶气泡文案
    var bubble: String {
        switch self {
        case .birthday:                 return "今天是你的生日 🎂"
        case .anniversary(let y, _):    return "我们在一起 \(y) 周年啦"
        case .days520:                  return "520 天,刚好是我想说的话"
        case .days1314:                 return "1314 天,一生一世"
        case .hundredDays(let d):       return "在一起 \(d) 天啦"
        }
    }

    /// 庆祝之后举的那块牌子
    var sign: String {
        switch self {
        case .birthday:                 return "生日快乐"
        case .anniversary(let y, let d): return "第 \(y) 年,第 \(d) 天,还想继续"
        case .days520:                  return "我爱你"
        case .days1314:                 return "一生一世,说到做到"
        case .hundredDays:              return "往后的每一百天也一起过"
        }
    }

    /// 配套撒花的时长(秒)
    var confettiDuration: Double {
        switch self {
        case .birthday:    return 14
        case .anniversary: return 10
        case .days1314:    return 10
        case .days520:     return 9
        case .hundredDays: return 7
        }
    }
}

// MARK: - 角色

/// 可切换的出场角色。文件名前缀就是 rawValue:`cat_walk_1.png` 属于 .cat。
enum PetRole: String, CaseIterable {
    case girl
    case boy
    case cat
    case dog

    /// 人形角色才有「举牌 / 捧蛋糕」这类需要手的动作
    var isHuman: Bool { self == .girl || self == .boy }

    /// 本体在窗口里的显示高度(pt)。猫狗矮一截,不能和人共用一个尺度。
    var displayHeight: CGFloat {
        switch self {
        case .girl: return 185
        case .boy:  return 196
        case .cat:  return 104
        case .dog:  return 120
        }
    }

    /// 身体容器的宽度(pt)。帧画布会因为甩手/摆尾比立绘宽不少,
    /// 容器给窄了帧就会被挤出去,所以按角色留足余量:
    /// 人形最宽的 boy 画布约 0.74 倍身高,四足动物猫约 1.5 倍。
    /// 容器只负责框住内容,实际绘制尺寸在 PetView.layer 里按像素比例算。
    var displayWidth: CGFloat { displayHeight * (isHuman ? 0.9 : 1.7) }

    /// 走路帧的步幅(px/帧)。四足动物碎步更密。
    var pixelsPerWalkFrame: Double {
        switch self {
        case .girl, .boy: return 12
        case .cat, .dog:  return 9
        }
    }

    /// 内置默认称呼。想改名不用动代码,在 Assets/config.json 的 roleNames 里配即可。
    var defaultName: String {
        switch self {
        case .girl: return "宝宝"
        case .boy:  return "我"
        case .cat:  return "猫"
        case .dog:  return "狗"
        }
    }

    // MARK: 选择的持久化

    private static let storageKey = "HappyPet.selectedRole"

    static func stored(default fallback: PetRole) -> PetRole {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let role = PetRole(rawValue: raw)
        else { return fallback }
        return role
    }

    static func store(_ role: PetRole) {
        UserDefaults.standard.set(role.rawValue, forKey: storageKey)
    }
}

/// 单个角色的全部素材。帧动画为主,静态立绘兜底。
final class RoleAssets {

    let role: PetRole
    let body: NSImage?
    /// 闭眼整帧立绘。有这张时眨眼直接整图切换,不再叠加眼睛图层。
    let blinkBody: NSImage?
    let eyesOpen: NSImage?
    let eyesClosed: NSImage?
    let armRight: NSImage?
    /// 动作帧序列,键是动作名(walk / idle / happy …),值按序号排好
    let frames: [String: [NSImage]]

    /// 这个角色的像素尺度基准:所有帧共用同一画布高,所以取立绘或任意一帧的像素高即可。
    /// 渲染层用「自身像素高 ÷ 基准 × displayHeight」算尺寸,才不会一帧一个大小。
    let pixelUnit: CGFloat

    var hasAnything: Bool { body != nil || !frames.isEmpty }

    init(role: PetRole, body: NSImage?, blinkBody: NSImage?, eyesOpen: NSImage?,
         eyesClosed: NSImage?, armRight: NSImage?, frames: [String: [NSImage]]) {
        self.role = role
        self.body = body
        self.blinkBody = blinkBody
        self.eyesOpen = eyesOpen
        self.eyesClosed = eyesClosed
        self.armRight = armRight
        self.frames = frames

        let reference = body
            ?? frames["idle"]?.first
            ?? frames.sorted { $0.key < $1.key }.first?.value.first
        if let rep = reference?.representations.first, rep.pixelsHigh > 0 {
            pixelUnit = CGFloat(rep.pixelsHigh)
        } else {
            pixelUnit = reference?.size.height ?? 0
        }
    }
}

// MARK: - 素材仓库

/// 统一加载 Assets 目录下的素材。任何一项缺失都不影响运行,渲染层会自动退回矢量绘制。
final class PetAssets {

    static let shared = PetAssets()

    let config: PetConfig
    /// 各角色的素材,只收录真的有图的角色
    let roles: [PetRole: RoleAssets]
    let photos: [NSImage]
    let birthdaySound: URL?
    let lovePhrases: [String]
    /// Assets 目录本身,给需要按需扫子目录的模块用(食物图标等)
    let assetsRoot: URL?

    /// 菜单里可选的角色,按 PetRole.allCases 的顺序
    var availableRoles: [PetRole] { PetRole.allCases.filter { roles[$0] != nil } }

    /// 配置里指定的首发角色;没素材时退到第一个有素材的角色
    var defaultRole: PetRole {
        if let raw = config.defaultRole, let role = PetRole(rawValue: raw), roles[role] != nil {
            return role
        }
        return availableRoles.first ?? .girl
    }

    func assets(for role: PetRole) -> RoleAssets {
        roles[role] ?? RoleAssets(role: role, body: nil, blinkBody: nil, eyesOpen: nil,
                                  eyesClosed: nil, armRight: nil, frames: [:])
    }

    private init() {
        let root = PetAssets.assetsURL()
        assetsRoot = root

        config = PetAssets.loadConfig(in: root)
        roles = PetAssets.loadRoles(in: root)
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

    /// 扫描 Assets 目录,把 `<角色>_<动作>_<序号>.png` 按角色分桶、再按动作分组。
    /// 静态立绘(girl_body / cat_body_blink / dog_eyes_open …)没有数字后缀,走单独加载。
    private static func loadRoles(in root: URL?) -> [PetRole: RoleAssets] {
        guard let root else { return [:] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []

        var result: [PetRole: RoleAssets] = [:]
        for role in PetRole.allCases {
            let frames = loadFrames(role: role, names: names, in: root)
            let assets = RoleAssets(
                role: role,
                body: loadImage("\(role.rawValue)_body", in: root),
                blinkBody: loadImage("\(role.rawValue)_body_blink", in: root),
                eyesOpen: loadImage("\(role.rawValue)_eyes_open", in: root),
                eyesClosed: loadImage("\(role.rawValue)_eyes_closed", in: root),
                armRight: loadImage("\(role.rawValue)_arm_r", in: root),
                frames: frames
            )
            guard assets.hasAnything else { continue }
            result[role] = assets

            let summary = frames
                .map { "\($0.key)×\($0.value.count)" }
                .sorted()
                .joined(separator: " ")
            print("🎭 \(role.rawValue) 素材: \(summary.isEmpty ? "仅静态立绘" : summary)")
        }
        if result.isEmpty { print("🎭 没扫到任何角色素材,回退内置橘猫") }
        return result
    }

    /// 取出属于某个角色的帧序列,按动作分组、按序号排序
    private static func loadFrames(role: PetRole, names: [String], in root: URL) -> [String: [NSImage]] {
        let prefix = "\(role.rawValue)_"
        var buckets: [String: [(index: Int, file: String)]] = [:]
        for name in names where ["png", "PNG"].contains((name as NSString).pathExtension) {
            let stem = (name as NSString).deletingPathExtension
            guard stem.hasPrefix(prefix) else { continue }
            let parts = stem.dropFirst(prefix.count).split(separator: "_")
            guard parts.count >= 2, let index = Int(parts[parts.count - 1]) else { continue }
            let action = parts.dropLast().joined(separator: "_")
            guard !action.isEmpty else { continue }
            buckets[action, default: []].append((index, name))
        }

        var result: [String: [NSImage]] = [:]
        for (action, list) in buckets {
            let images = list
                .sorted { $0.index < $1.index }
                .compactMap { NSImage(contentsOf: root.appendingPathComponent($0.file)) }
            if !images.isEmpty { result[action] = images }
        }
        return result
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