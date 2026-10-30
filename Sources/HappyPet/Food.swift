import AppKit
import Foundation
import SwiftUI

// MARK: - 食物模型

/// 某个角色对一样食物的态度
enum FoodTaste {
    case loved   // 最爱
    case fine    // 一般都吃
    case hated   // 不太行
}

/// 一样可以喂的食物。
/// 图标优先用 `Assets/food/<名称>.png`,没有就直接画 emoji —— 零素材也能玩。
struct FoodItem: Identifiable {

    let id: String
    let emoji: String
    let name: String
    /// 爱吃这个的角色(PetRole.rawValue)
    let lovedBy: Set<String>
    /// 不爱吃这个的角色
    let hatedBy: Set<String>
    let image: NSImage?

    func taste(for role: PetRole) -> FoodTaste {
        if hatedBy.contains(role.rawValue) { return .hated }
        if lovedBy.contains(role.rawValue) { return .loved }
        return .fine
    }

    /// 刚接到食物时的反应
    func greeting(for role: PetRole) -> String {
        switch taste(for: role) {
        case .loved:
            return ["\(name)!我最爱这个了", "哇——是\(name)!", "这个这个!超喜欢\(name)"].randomElement()!
        case .fine:
            return ["谢谢你的\(name)~", "\(name)也不错哦", "开动啦~"].randomElement()!
        case .hated:
            return ["唔…\(name)我不太行", "\(name)…看在是你给的", "勉为其难吃一口"].randomElement()!
        }
    }

    /// 吃完的满足感
    func afterword(for role: PetRole) -> String {
        switch taste(for: role) {
        case .loved:
            return ["太好吃了!还想要", "幸福得冒泡泡~", "你最懂我了"].randomElement()!
        case .fine:
            return ["吃饱啦,谢谢你", "嗯~满足", "心情变好了"].randomElement()!
        case .hated:
            return ["…其实还行吧", "吃完了!下次换个口味", "勉强及格啦"].randomElement()!
        }
    }
}

// MARK: - 食物清单

/// 食物清单。优先读 `Assets/food.txt`,缺失就用内置清单。
/// 文件格式(每行一条,`#` 开头是注释):
/// `emoji|名称|爱吃的角色,逗号分隔|不爱吃的角色,逗号分隔`
final class FoodStore {

    static let shared = FoodStore()

    let items: [FoodItem]

    private init() {
        let root = PetAssets.shared.assetsRoot
        let lines = FoodStore.readLines(in: root) ?? FoodStore.builtin
        let iconDir = root?.appendingPathComponent("food", isDirectory: true)
        items = lines.enumerated().compactMap { FoodStore.parse($0.element, index: $0.offset, iconDir: iconDir) }
    }

    private static func readLines(in root: URL?) -> [String]? {
        guard let url = root?.appendingPathComponent("food.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.isEmpty ? nil : lines
    }

    private static func parse(_ line: String, index: Int, iconDir: URL?) -> FoodItem? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        let name = parts[1]
        return FoodItem(
            id: "\(index)-\(name)",
            emoji: parts[0].isEmpty ? "🍚" : parts[0],
            name: name,
            lovedBy: roles(parts.count > 2 ? parts[2] : ""),
            hatedBy: roles(parts.count > 3 ? parts[3] : ""),
            image: icon(named: name, in: iconDir)
        )
    }

    private static func roles(_ raw: String) -> Set<String> {
        let valid = Set(PetRole.allCases.map { $0.rawValue })
        let list = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { valid.contains($0) }
        return Set(list)
    }

    private static func icon(named name: String, in dir: URL?) -> NSImage? {
        guard let dir else { return nil }
        for ext in ["png", "PNG"] {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    /// 没有 food.txt 时的内置清单
    private static let builtin = [
        "🍗|鸡腿|boy,dog|",
        "🐟|小鱼干|cat|",
        "🍔|汉堡|boy|cat",
        "🍟|薯条|boy,girl|dog",
        "🍕|披萨|boy,girl|",
        "🍰|小蛋糕|girl|dog",
        "🧋|奶茶|girl|cat,dog",
        "🍓|草莓|girl,cat|",
        "🍦|冰淇淋|girl|boy",
        "🦴|大骨头|dog|girl",
        "🍜|拉面|boy|cat",
        "🍣|寿司|cat,girl|"
    ]
}

// MARK: - 图标视图

/// 食物图标:有 png 用 png,否则画 emoji
struct FoodIconView: View {

    let item: FoodItem
    let size: CGFloat

    var body: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Text(item.emoji)
                .font(.system(size: size * 0.84))
                .frame(width: size, height: size)
        }
    }
}