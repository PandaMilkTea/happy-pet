import CoreGraphics

/// 宠物窗口内所有几何关系的单一来源。
///
/// 以前「脚底线 / 命中椭圆」这组数字在三处各写了一份(绘制、点击命中、投喂命中),
/// 只要改某个角色的 `displayHeight`,三处就会错位 —— 点不到、喂不进、牌子飞天。
/// 现在全部从这里推导,改一次就同步。
///
/// 坐标约定:
/// - `*BelowCenter` / `*InBodyBox` 一律是 SwiftUI 的「向下为正」,相对各自容器的中心;
/// - 命中判定接口收的是 AppKit 的「向上为正」坐标(视图 bounds 或窗口 frame),内部自行换算。
enum PetGeometry {

    // MARK: - 绘制基准

    /// 窗口尺寸。比本体大一圈:上方留给举牌 / 气泡,下方留给蛋糕。
    static let windowSize = CGSize(width: 200, height: 300)

    /// 身体层容器的边长(阴影 / 本体 / 蛋糕 / 食物 / 特效都在这个方盒里)
    static let bodyBoxSide: CGFloat = 160

    /// 身体层相对窗口中心的下移量
    static let bodyDrop: CGFloat = 70

    /// 布局地面线在身体层方盒里的下移量
    static let feetInBodyBox: CGFloat = 68.5

    /// 本体相对布局地面线的额外下移。历史微调值,蛋糕 / 牌子 / 阴影都不跟随它。
    static let avatarNudge: CGFloat = 10

    /// 布局地面线相对窗口中心的距离:蛋糕、牌子、气泡、阴影都钉在这条线上
    static let feetBelowCenter: CGFloat = bodyDrop + feetInBodyBox

    /// 本体真正的落脚线。命中判定按这条走,才和画面上看到的人对得上。
    static let avatarFeetBelowCenter: CGFloat = feetBelowCenter + avatarNudge

    /// 蛋糕端在身体中段:从脚底线往上挪半个身高多一点,矮个子角色才不会把蛋糕举到天上
    static let cakeHeightRatio: CGFloat = 0.48
    /// 蛋糕相对身体中轴的横向偏移(朝着面朝的方向)
    static let cakeOffsetX: CGFloat = 6
    /// 嘴巴高度占身高的比例,用来把食物画在嘴边
    static let mouthHeightRatio: CGFloat = 0.78

    /// 头顶线(相对窗口中心,向下为正)。牌子和气泡据此往上排。
    static func headTopBelowCenter(height: CGFloat) -> CGFloat {
        feetBelowCenter - height
    }

    // MARK: - 命中椭圆的尺寸

    /// 身体命中椭圆的半径。四足角色矮而宽,横向得按身高放大,不然很难点到。
    static func bodyRadii(role: PetRole) -> (rx: CGFloat, ry: CGFloat) {
        let h = role.displayHeight
        return (role.isHuman ? h * 0.23 : h * 0.6, h * 0.48)
    }

    /// 内置橘猫(没有任何立绘素材时)的兜底几何
    private static let fallbackCenterBelowCenter: CGFloat = 70
    private static let fallbackRadii: (rx: CGFloat, ry: CGFloat) = (58, 54)
    private static let fallbackCakeBelowCenter: CGFloat = 96
    private static let cakeRadii: (rx: CGFloat, ry: CGFloat) = (34, 32)

    // MARK: - 命中判定

    /// 某个点是否落在宠物身上。
    /// - Parameters:
    ///   - point: 待判定的点,AppKit 坐标,和 `rect` 同一个坐标空间
    ///   - rect: 宿主矩形。点击命中传视图 bounds,投喂命中传窗口 frame
    ///   - hasCharacter: 有立绘素材就按角色身高算,否则用内置橘猫的固定尺寸
    ///   - padding: 额外放宽的半径。投喂拖拽会放宽一圈,更好对准
    static func bodyContains(_ point: CGPoint,
                             in rect: CGRect,
                             role: PetRole,
                             hasCharacter: Bool,
                             padding: CGFloat = 0) -> Bool {
        let center: CGPoint
        let radii: (rx: CGFloat, ry: CGFloat)
        if hasCharacter {
            let feet = rect.midY - avatarFeetBelowCenter
            center = CGPoint(x: rect.midX, y: feet + role.displayHeight / 2)
            radii = bodyRadii(role: role)
        } else {
            center = CGPoint(x: rect.midX, y: rect.midY - fallbackCenterBelowCenter)
            radii = fallbackRadii
        }
        return inEllipse(point, center: center, rx: radii.rx + padding, ry: radii.ry + padding)
    }

    /// 捧着蛋糕时,蛋糕本身也要能点(等于吹蜡烛的兜底)
    static func cakeContains(_ point: CGPoint,
                             in rect: CGRect,
                             role: PetRole,
                             hasCharacter: Bool,
                             facingRight: Bool) -> Bool {
        let y = hasCharacter
            ? rect.midY - feetBelowCenter + role.displayHeight * cakeHeightRatio
            : rect.midY - fallbackCakeBelowCenter
        let center = CGPoint(x: rect.midX + (facingRight ? cakeOffsetX : -cakeOffsetX), y: y)
        return inEllipse(point, center: center, rx: cakeRadii.rx, ry: cakeRadii.ry)
    }

    private static func inEllipse(_ p: CGPoint, center: CGPoint, rx: CGFloat, ry: CGFloat) -> Bool {
        guard rx > 0, ry > 0 else { return false }
        let dx = (p.x - center.x) / rx
        let dy = (p.y - center.y) / ry
        return dx * dx + dy * dy <= 1
    }
}