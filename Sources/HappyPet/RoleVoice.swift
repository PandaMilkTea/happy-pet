import Foundation

/// 四个角色各自的「嘴」。
///
/// 同一件事由谁说出来口吻完全不同:大明撒娇、凯文嘴硬、锅巴高冷、大和热情。
/// 句库都可以用 Assets 里的 txt 覆盖,改词不用重新编译:
/// - `love_<角色>.txt`  举牌情话(没有就用内置 + 通用 love.txt)
/// - `purr_<角色>.txt`  摸头时的咕噜话
///
/// 这里只放纯逻辑,目录由调用方(PetAssets)传进来,避免和素材仓库互相依赖。
enum RoleVoice {

    /// 食物名占位符:句库里写 `{}`,出口时换成真实食物名
    private static let slot = "{}"

    // MARK: - 举牌情话

    /// 角色专属文件优先;否则「通用 love.txt + 该角色内置台词」合在一起,
    /// 这样用户手写的情话不会因为分角色而失效。
    static func lovePhrases(for role: PetRole, in root: URL?) -> [String] {
        if let own = load("love_\(role.rawValue).txt", in: root) { return own }
        let shared = load("love.txt", in: root) ?? []
        let merged = shared + builtinLove(role)
        return merged.isEmpty ? builtinLove(role) : dedup(merged)
    }

    // MARK: - 摸头

    static func purrLines(for role: PetRole, in root: URL?) -> [String] {
        load("purr_\(role.rawValue).txt", in: root) ?? builtinPurr(role)
    }

    // MARK: - 上场问候

    /// 刚被叫出来时说的第一句。`name` 是它自己的称呼。
    static func arrival(for role: PetRole, name: String) -> String {
        switch role {
        case .girl: return ["\(name)来啦~", "我来陪你啦", "想我没有?"].randomElement()!
        case .boy:  return ["\(name)到了", "我来了,有事说", "我在这儿守着"].randomElement()!
        case .cat:  return ["\(name)踱过来了", "喵。来了", "……来了,别吵"].randomElement()!
        case .dog:  return ["\(name)冲过来啦!", "汪!我来啦!!", "来了来了来了!"].randomElement()!
        }
    }

    /// 被收回去时的告别
    static func farewell(for role: PetRole) -> String {
        switch role {
        case .girl: return ["那我先去忙咯~", "我去睡个午觉", "等你再叫我"].randomElement()!
        case .boy:  return ["行,我先退下", "有事随时喊我", "那我撤了"].randomElement()!
        case .cat:  return ["喵。走了", "哼,不送", "我去晒太阳"].randomElement()!
        case .dog:  return ["那我在旁边等你!", "汪……好嘛", "一会儿再叫我!"].randomElement()!
        }
    }

    // MARK: - 投喂

    static func foodGreeting(role: PetRole, taste: FoodTaste, name: String) -> String {
        fill(foodLines(role, taste).greet.randomElement() ?? "开动啦~", name)
    }

    static func foodAfterword(role: PetRole, taste: FoodTaste, name: String) -> String {
        fill(foodLines(role, taste).after.randomElement() ?? "吃饱啦,谢谢你", name)
    }

    private static func fill(_ line: String, _ name: String) -> String {
        line.replacingOccurrences(of: slot, with: name)
    }

    // MARK: - 文件读取

    /// 一行一句,`#` 开头算注释。空文件视为没写。
    private static func load(_ fileName: String, in root: URL?) -> [String]? {
        guard let url = root?.appendingPathComponent(fileName),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.isEmpty ? nil : lines
    }

    /// 保序去重,免得通用句和内置句撞车
    private static func dedup(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    // MARK: - 内置句库:举牌

    private static func builtinLove(_ role: PetRole) -> [String] {
        switch role {
        case .girl:
            return [
                "今天也要你多哄哄我",
                "想我的时候就点我一下",
                "我今天很乖哦",
                "抱一下嘛~",
                "忙完了记得看我一眼",
                "有我在呢,别皱眉"
            ]
        case .boy:
            return [
                "今天也很喜欢你",
                "记得喝水,别又忘了",
                "累了就歇会儿,别硬撑",
                "我一直都在呢",
                "你笑起来最好看",
                "不许不开心,有事找我"
            ]
        case .cat:
            return [
                "喵。看我一眼也行",
                "我不粘人,只是刚好坐在这儿",
                "今天过得还行吧?",
                "随便摸两下,别太久",
                "我守着你,不许说出去"
            ]
        case .dog:
            return [
                "你终于看我啦!!",
                "汪!今天也超喜欢你!",
                "你去哪我就去哪!",
                "摸摸我摸摸我摸摸我",
                "今天也是最棒的一天!"
            ]
        }
    }

    // MARK: - 内置句库:摸头

    private static func builtinPurr(_ role: PetRole) -> [String] {
        switch role {
        case .girl:
            return ["嘿嘿…再摸一下", "最喜欢你摸我头了", "手不要停嘛", "舒服…要睡着了"]
        case .boy:
            return ["咳…就摸这一次", "好吧…再摸会儿", "你手还挺暖", "这感觉还不错"]
        case .cat:
            return ["咕噜咕噜…手拿开", "哼…就一下", "呼噜噜…别停", "勉为其难让你摸"]
        case .dog:
            return ["汪汪汪!好开心!", "尾巴摇到停不下来", "再摸!再摸!", "最喜欢你啦!!"]
        }
    }

    // MARK: - 内置句库:投喂

    private typealias FoodReaction = (greet: [String], after: [String])

    private static func foodLines(_ role: PetRole, _ taste: FoodTaste) -> FoodReaction {
        switch (role, taste) {
        case (.girl, .loved):
            return (["{}!我最爱这个了", "哇——是{}!", "你怎么知道我想吃{}"],
                    ["太好吃了!还想要", "幸福得冒泡泡~", "你最懂我了"])
        case (.girl, .fine):
            return (["谢谢你的{}~", "{}也不错哦", "开动啦~"],
                    ["吃饱啦,谢谢你", "嗯~满足", "心情变好了"])
        case (.girl, .hated):
            return (["唔…{}我不太行", "{}…看在是你给的", "下次换别的好不好"],
                    ["…其实还行吧", "吃完了,下次换口味", "勉强给你个及格"])

        case (.boy, .loved):
            return (["{}!这个我可以", "正好想吃{}", "懂我,就是{}"],
                    ["够劲,还有没有", "这顿满意", "下次还是这个"])
        case (.boy, .fine):
            return (["行,{}我吃", "{}也挺好", "那我不客气了"],
                    ["吃完了,谢了", "还不错", "嗯,饱了"])
        case (.boy, .hated):
            return (["{}…说实话有点难", "你给的我才吃{}", "就这一次啊"],
                    ["咳…也不算难吃", "下次别点这个了", "吃完了,给你面子"])

        case (.cat, .loved):
            return (["{}!喵喵喵!", "是{}…给我给我", "这个勉强算合格…快给"],
                    ["喵~吃光了", "咕噜咕噜…还要", "你算懂事"])
        case (.cat, .fine):
            return (["{}…放那儿吧", "喵。接受", "我看看…还行"],
                    ["吃完了,别看我", "喵。可以", "舔爪子ing"])
        case (.cat, .hated):
            return (["{}?喵——不吃", "拿走拿走,{}不行", "你认真的吗"],
                    ["哼,算你有心", "下次拿小鱼干来", "……就吃一口"])

        case (.dog, .loved):
            return (["{}!!!汪汪汪!", "是{}!我转圈圈了!", "给我给我给我!"],
                    ["汪!还要还要!", "今天最幸福的一天!", "你是最好的人!"])
        case (.dog, .fine):
            return (["{}也吃!什么都吃!", "谢谢你谢谢你!", "开饭啦!"],
                    ["汪!吃光啦!", "肚子圆啦!", "谢谢你喂我!"])
        case (.dog, .hated):
            return (["{}…闻起来怪怪的", "我…我试试", "下次能换骨头吗"],
                    ["吃完了!我很棒吧", "下次要骨头!", "呜…但还是谢谢你"])
        }
    }
}