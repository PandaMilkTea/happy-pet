import AppKit
import Foundation

// MARK: - 一件礼物

/// 礼物盒里的一张卡片
enum GiftKind {
    /// 写给你的那句话
    case wish
    /// 情话
    case words
    /// 合照
    case photo
    /// 在一起多久
    case milestone
    /// 可以用掉的兑换券
    case coupon
}

struct GiftItem: Identifiable {
    let id: String
    let kind: GiftKind
    let emoji: String
    let title: String
    let body: String
    /// 只有 .photo 用得上
    let image: NSImage?

    init(id: String, kind: GiftKind, emoji: String, title: String,
         body: String, image: NSImage? = nil) {
        self.id = id
        self.kind = kind
        self.emoji = emoji
        self.title = title
        self.body = body
        self.image = image
    }

    var isCoupon: Bool { kind == .coupon }
}

// MARK: - 礼物清单

/// 组装礼物清单,并记住哪些兑换券已经用掉了。
/// 券面可以在 Assets/coupons.txt 里自定义,一行一张:`名称|说明`。
final class GiftStore {

    static let shared = GiftStore()

    /// 每次拆开都重新抽一次:照片和情话会换,兑换券保持原样
    func makeItems() -> [GiftItem] {
        GiftStore.build(assets: PetAssets.shared)
    }

    private static let usedKey = "HappyPet.usedCoupons"
    private var used: Set<String>

    private init() {
        used = Set(UserDefaults.standard.stringArray(forKey: GiftStore.usedKey) ?? [])
    }

    // MARK: 兑换券状态

    func isUsed(_ item: GiftItem) -> Bool { used.contains(item.id) }

    func markUsed(_ item: GiftItem) {
        guard item.isCoupon, !used.contains(item.id) else { return }
        used.insert(item.id)
        UserDefaults.standard.set(Array(used), forKey: GiftStore.usedKey)
    }

    // MARK: 组装

    private static func build(assets: PetAssets) -> [GiftItem] {
        let config = assets.config
        var result: [GiftItem] = []

        // 1. 写给你的那句话
        let wish = config.birthdayWish.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wish.isEmpty {
            result.append(GiftItem(
                id: "wish",
                kind: .wish,
                emoji: "💌",
                title: "想对你说的话",
                body: wish
            ))
        }

        // 2. 在一起多久
        if let days = config.daysTogether {
            let span = config.togetherSpanText
            let body = span.map { "在一起 \(days) 天了\n也就是 \($0)" } ?? "在一起 \(days) 天了"
            result.append(GiftItem(
                id: "milestone",
                kind: .milestone,
                emoji: "📅",
                title: "我们的日子",
                body: body
            ))
        }

        // 3. 合照:随机挑三张混进清单,想看全部走菜单的「看看我们的照片」
        for (i, photo) in assets.photos.shuffled().prefix(3).enumerated() {
            result.append(GiftItem(
                id: "photo-\(i)",
                kind: .photo,
                emoji: "📷",
                title: "那天的我们",
                body: "",
                image: photo
            ))
        }

        // 4. 情话:随机抽三句
        for (i, phrase) in assets.lovePhrases.shuffled().prefix(3).enumerated() {
            result.append(GiftItem(
                id: "words-\(i)",
                kind: .words,
                emoji: "🍬",
                title: "随手掏出来的一句",
                body: phrase
            ))
        }

        // 5. 兑换券
        result.append(contentsOf: loadCoupons())

        return result
    }

    private static func loadCoupons() -> [GiftItem] {
        let lines = readCouponFile() ?? defaultCoupons
        return lines.compactMap { line -> GiftItem? in
            let parts = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let name = parts.first, !name.isEmpty else { return nil }
            let note = parts.count > 1 ? parts[1] : "随时找我用掉它"
            return GiftItem(
                id: "coupon-\(name)",
                kind: .coupon,
                emoji: "🎟️",
                title: name,
                body: note
            )
        }
    }

    /// 读 Assets/coupons.txt,`#` 开头算注释
    private static func readCouponFile() -> [String]? {
        guard let root = PetAssets.shared.assetsRoot else { return nil }
        let url = root.appendingPathComponent("coupons.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.isEmpty ? nil : lines
    }

    private static let defaultCoupons = [
        "撒娇券|随时随地撒娇一次,不许说我烦",
        "点菜券|今天吃什么你定,我负责买单",
        "陪聊券|不管几点,打给我就得接",
        "免吵架券|这次我先认错,不问谁对谁错",
        "许愿券|一个不太离谱的愿望,我来想办法",
        "赖床券|周末多睡一小时,不叫你起床"
    ]
}