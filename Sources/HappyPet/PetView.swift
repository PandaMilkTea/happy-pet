import SwiftUI

/// 宠物的全部外观与动画(纯代码绘制,无需图片资源)
struct PetView: View {

    @ObservedObject var brain: PetBrain

    // MARK: - 配色
    private let furTop = Color(red: 1.00, green: 0.82, blue: 0.58)
    private let furBottom = Color(red: 0.98, green: 0.62, blue: 0.29)
    private let ink = Color(red: 0.24, green: 0.16, blue: 0.12)
    private let blush = Color(red: 1.00, green: 0.55, blue: 0.60)

    // MARK: - 动画推导量(全部来自 PetBrain 解算好的姿态)
    private var t: Double { brain.clock }
    private var pose: PetPose { brain.pose }
    private var isWalking: Bool { brain.state == .walk }
    private var isSleeping: Bool { brain.state == .sleep }
    private var isHappy: Bool { brain.state == .happy }
    private var isDragging: Bool { brain.state == .drag }
    private var isFalling: Bool { brain.state == .fall }
    /// 眼睛张开度 < 0.45 就画闭眼(眨眼过程本身在大脑里做了缓动)
    private var eyesClosed: Bool { pose.eyeOpen < 0.45 }

    private var breath: CGFloat { pose.breath }
    /// 帧动画在播时,起伏/挤压已经画在帧里了,程序化形变要收着来,否则双重抖
    private var spriteDriven: Bool { brain.sprites.current != nil }
    private var bob: CGFloat { pose.bob * (spriteDriven ? 0.3 : 1) }
    private var jump: CGFloat { pose.jump }
    private var squash: CGSize { pose.squash }
    /// 立绘帧专用:把挤压往 1.0 收,只留一点落地冲击的味道
    private var spriteSquash: CGSize {
        guard spriteDriven else { return pose.squash }
        let keep: CGFloat = 0.35
        return CGSize(width: 1 + (pose.squash.width - 1) * keep,
                      height: 1 + (pose.squash.height - 1) * keep)
    }
    private var tilt: Double { pose.tilt }
    private var tailSwing: CGFloat { pose.tailSwing }
    private var legSwing: CGFloat { pose.legSwing }

    // MARK: - body

    /// 宠物本体在窗口里的下移量:上方留给举牌和气泡
    private let bodyDrop = PetGeometry.bodyDrop

    var body: some View {
        ZStack {
            ZStack {
                groundShadow
                avatar
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .offset(x: pose.sway, y: PetGeometry.avatarNudge + bob + jump)
                cakeLayer
                foodLayer
                effects
            }
            .frame(width: PetGeometry.bodyBoxSide, height: PetGeometry.bodyBoxSide)
            .offset(y: bodyDrop)

            overlayLayer
        }
        .frame(width: PetGeometry.windowSize.width, height: PetGeometry.windowSize.height)
        .allowsHitTesting(false)
    }

    // MARK: - 地面阴影

    private var groundShadow: some View {
        let baseWidth: CGFloat = hasCharacter ? (brain.role.isHuman ? 54 : 84) : 76
        return Ellipse()
            .fill(Color.black.opacity(pose.shadowOpacity))
            .frame(width: baseWidth * pose.shadowScale, height: (hasCharacter ? 10 : 13) * pose.shadowScale)
            .offset(x: pose.sway * 0.5, y: hasCharacter ? 70 : 62)
            .blur(radius: 2)
    }

    // MARK: - 本体:有立绘就用立绘,否则用内置橘猫

    private var hasCharacter: Bool { brain.roleAssets.hasAnything }
    /// 当前角色的显示高度(pt),猫狗比人矮一截
    private var displayHeight: CGFloat { brain.role.displayHeight }
    /// 脚底在 avatar 容器里的 y 偏移:所有角色共用同一条地面线
    private static let feetLine = PetGeometry.feetInBodyBox

    @ViewBuilder
    private var avatar: some View {
        if hasCharacter { characterBody } else { catBody }
    }

    /// 图片素材驱动的角色。
    /// 优先播帧动画(Assets 里的 `<角色>_<动作>_<序号>.png`);
    /// 没有帧素材时退回单张立绘:有「闭眼整帧」就整图切换,否则叠眼睛图层。
    private var characterBody: some View {
        let assets = brain.roleAssets
        let sprites = brain.sprites
        return ZStack(alignment: .bottom) {
            if let frame = sprites.current {
                layer(frame)
                // 当前帧 + 下一帧交叉淡化,相当于给 2~4 张帧补间,硬切就不闪了
                if let upcoming = sprites.next, sprites.mix > 0.001 {
                    layer(upcoming).opacity(sprites.mix)
                }
            } else if let blink = assets.blinkBody {
                layer(eyesClosed ? blink : (assets.body ?? blink))
                armLayer
            } else {
                if let bodyImage = assets.body {
                    layer(bodyImage)
                }
                if let open = assets.eyesOpen, let closed = assets.eyesClosed {
                    layer(eyesClosed ? closed : open)
                }
                armLayer
            }
        }
        .frame(width: brain.role.displayWidth, height: displayHeight, alignment: .bottom)
        .offset(y: Self.feetLine - displayHeight / 2)
        .scaleEffect(x: spriteSquash.width, y: spriteSquash.height, anchor: .bottom)
        .scaleEffect(x: pose.facing, y: 1, anchor: .center)
    }

    @ViewBuilder
    private var armLayer: some View {
        if let arm = brain.roleAssets.armRight {
            layer(arm)
                .rotationEffect(.degrees(armAngle), anchor: .top)
        }
    }

    /// 素材的统一像素尺度:抠图脚本保证同一角色的所有帧和立绘用同一比例,
    /// 只是画布大小会因为甩手/跳起而变宽变高。
    /// 所以这里按「自身像素高 ÷ 角色基准像素高 × 角色显示高度」算显示尺寸,
    /// 用 aspectRatio(.fit) 的话宽画布会被挤小,人物就一帧一个大小了。
    private func pixelSize(_ image: NSImage) -> CGSize {
        if let rep = image.representations.first, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    private func layer(_ image: NSImage) -> some View {
        let unit = brain.roleAssets.pixelUnit > 1
            ? brain.roleAssets.pixelUnit
            : pixelSize(image).height
        let px = pixelSize(image)
        let scale = unit > 1 ? displayHeight / unit : 0
        let h = scale > 0 ? px.height * scale : displayHeight
        let w = px.height > 1 ? h * px.width / px.height : brain.role.displayWidth
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: w, height: h)
    }

    /// 抬手角度:由大脑的弹簧解算,不再瞬间跳到目标值
    private var armAngle: Double { pose.armAngle }

    // MARK: - 蛋糕 / 举牌 / 气泡

    @ViewBuilder
    private var cakeLayer: some View {
        if brain.isHoldingCake {
            // 蛋糕端在身体中段:脚底线往上挪半个身高多一点,矮个子角色才不会把蛋糕举到天上
            let cakeY: CGFloat = hasCharacter ? (Self.feetLine - displayHeight * PetGeometry.cakeHeightRatio) : 26
            CakeView(lit: brain.candleLit, clock: t)
                .scaleEffect(hasCharacter && !brain.role.isHuman ? 0.7 : 0.92)
                .offset(x: brain.facingRight ? PetGeometry.cakeOffsetX : -PetGeometry.cakeOffsetX,
                        y: cakeY + bob + jump * 0.4)
        }
    }

    /// 嘴边的食物:一口一口变小,吃完消失
    @ViewBuilder
    private var foodLayer: some View {
        if let food = brain.eatingFood {
            // 三口吃完,所以尺寸按 1 / 2/3 / 1/3 台阶往下掉,看着像被咬掉
            let step = min(2, Int(brain.eatProgress * 3))
            let shrink = CGFloat(1 - Double(step) * 0.3)
            let mouthY: CGFloat = hasCharacter ? (Self.feetLine - displayHeight * PetGeometry.mouthHeightRatio) : 4
            let chew = CGFloat(sin(t * 11) * 1.6)
            FoodIconView(item: food, size: 34 * shrink)
                .rotationEffect(.degrees(brain.facingRight ? -12 : 12))
                .offset(x: (brain.facingRight ? 18 : -18) + pose.sway,
                        y: mouthY + bob + jump * 0.4 + chew)
                .animation(.easeOut(duration: 0.18), value: step)
        }
    }

    @ViewBuilder
    private var overlayLayer: some View {
        // 牌子和气泡都钉在头顶上方:头顶 = 地面线 - 角色显示高度
        let hasSign = brain.signText != nil
        let headTop = PetGeometry.headTopBelowCenter(height: displayHeight)
        let signY: CGFloat = hasCharacter ? headTop - 15 : -6
        let bubbleY: CGFloat = hasCharacter
            ? (hasSign ? headTop - 53 : headTop - 2)
            : (hasSign ? -52 : -18)

        if let sign = brain.signText {
            SignView(text: sign, clock: t)
               .offset(x: 12, y: signY)
        }
        if let bubble = brain.bubbleText {
            BubbleView(text: bubble)
                .offset(y: bubbleY)
        }
    }

    // MARK: - 内置橘猫

    private var catBody: some View {
        ZStack {
            tail
            legs
            torso
            face
        }
        .scaleEffect(x: squash.width, y: squash.height, anchor: .bottom)
        .scaleEffect(x: pose.facing, y: 1, anchor: .center)
    }

    private var torso: some View {
        ZStack {
            ears
            // 身体主体
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(
                    LinearGradient(colors: [furTop, furBottom],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 96, height: 86)
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(ink.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 96, height: 86)
                )
            // 肚皮
            Ellipse()
                .fill(Color.white.opacity(0.78))
                .frame(width: 46, height: 36)
                .offset(y: 22)
            // 头顶纹路
            StripesShape()
                .stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 34, height: 9)
                .offset(y: -30)
        }
    }

    private var ears: some View {
        ZStack {
            earPair(color: furTop, size: CGSize(width: 26, height: 24), dx: 28, dy: -46)
            earPair(color: blush.opacity(0.85), size: CGSize(width: 13, height: 12), dx: 28, dy: -42)
        }
    }

    private func earPair(color: Color, size: CGSize, dx: CGFloat, dy: CGFloat) -> some View {
        let droop: Double = isSleeping ? 16 : 0
        return ZStack {
            EarShape()
                .fill(color)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(-12 - droop), anchor: .bottom)
                .offset(x: -dx, y: dy)
            EarShape()
                .fill(color)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(12 + droop), anchor: .bottom)
                .offset(x: dx, y: dy)
        }
    }

    private var legs: some View {
        ZStack {
            Capsule()
                .fill(furBottom)
                .frame(width: 22, height: 16)
                .offset(x: -21, y: 40 + legSwing)
            Capsule()
                .fill(furBottom)
                .frame(width: 22, height: 16)
                .offset(x: 21, y: 40 - legSwing)
        }
    }

    private var tail: some View {
        TailShape(swing: tailSwing)
            .stroke(
                LinearGradient(colors: [furBottom, furTop], startPoint: .bottom, endPoint: .top),
                style: StrokeStyle(lineWidth: 9, lineCap: .round)
            )
            .frame(width: 38, height: 52)
            .offset(x: -54, y: 2)
    }

    // MARK: - 脸

    private var face: some View {
        ZStack {
            eyes
            blushes
            nose
            mouth
            whiskers
        }
        .offset(y: -6)
    }

    private var eyes: some View {
        ZStack {
            eye(dx: -19)
            eye(dx: 19)
        }
    }

    private func eye(dx: CGFloat) -> some View {
        ZStack {
            if eyesClosed {
                ClosedEyeShape()
                    .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 15, height: 7)
            } else {
                Ellipse()
                    .fill(ink)
                    .frame(width: 13, height: isFalling ? 17 : 15)
                Circle()
                    .fill(Color.white)
                    .frame(width: 4.5, height: 4.5)
                    .offset(x: 2.5, y: -3.5)
            }
        }
        .offset(x: dx)
    }

    private var blushes: some View {
        ZStack {
            Ellipse()
                .fill(blush.opacity(isHappy ? 0.55 : 0.32))
                .frame(width: 15, height: 8)
                .offset(x: -34, y: 10)
            Ellipse()
                .fill(blush.opacity(isHappy ? 0.55 : 0.32))
                .frame(width: 15, height: 8)
                .offset(x: 34, y: 10)
        }
    }

    private var nose: some View {
        Triangle()
            .fill(blush)
            .frame(width: 7, height: 5)
            .offset(y: 11)
    }

    private var mouth: some View {
        MouthShape(open: isHappy ? 1 : 0)
            .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .frame(width: 20, height: 6)
            .offset(y: 17)
    }

    private var whiskers: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let dy = CGFloat(i) * 5 - 5
                Group {
                    Capsule()
                        .fill(ink.opacity(0.35))
                        .frame(width: 16, height: 1.4)
                        .rotationEffect(.degrees(Double(i - 1) * 12))
                        .offset(x: -40, y: 12 + dy)
                    Capsule()
                        .fill(ink.opacity(0.35))
                        .frame(width: 16, height: 1.4)
                        .rotationEffect(.degrees(Double(1 - i) * 12))
                        .offset(x: 40, y: 12 + dy)
                }
            }
        }
    }

    // MARK: - 特效(Zzz / 爱心)

    @ViewBuilder
    private var effects: some View {
        if brain.isPurring {
            // 摸头:心心更密更多,再配两个音符当「咕噜」声
            ForEach(0..<5, id: \.self) { i in
                let p = CGFloat((t * 1.1 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1))
                HeartShape()
                    .fill(blush.opacity(Double(1 - p)))
                    .frame(width: 15 - p * 5, height: 14 - p * 5)
                    .offset(x: CGFloat(i - 2) * 17 + CGFloat(sin(Double(p) * 6 + Double(i)) * 5),
                            y: -36 - p * 40)
            }
            ForEach(0..<2, id: \.self) { i in
                let p = CGFloat((t * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1))
                Text("♪")
                    .font(.system(size: 13 + p * 6, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.68).opacity(Double(1 - p) * 0.9))
                    .offset(x: (i == 0 ? 42 : -42) - p * 8, y: -30 - p * 32)
            }
        } else if isSleeping {
            ForEach(0..<3, id: \.self) { i in
                let p = CGFloat((t * 0.45 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1))
                Text("z")
                    .font(.system(size: 12 + p * 10, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.45, blue: 0.75).opacity(Double(1 - p) * 0.9))
                    .offset(x: 38 + p * 14, y: -40 - p * 26)
            }
        } else if isHappy, brain.heartLevel > 0 {
            happyHearts
        }
    }

    /// 开心时冒的心心。喂对了最爱会翻倍爆发(heartLevel == 2)。
    @ViewBuilder
    private var happyHearts: some View {
        let burst: Bool = brain.heartLevel >= 2
        let count: Int = burst ? 7 : 3
        ForEach(0..<count, id: \.self) { i in
            happyHeart(i, count: count, burst: burst)
        }
    }

    private func happyHeart(_ i: Int, count: Int, burst: Bool) -> some View {
        let speed: Double = burst ? 1.25 : 0.9
        let step: Double = 1.0 / Double(count)
        let raw: Double = (t * speed + Double(i) * step).truncatingRemainder(dividingBy: 1)
        let p: CGFloat = CGFloat(raw)
        let size: CGFloat = burst ? 19 : 13
        // 爆发时左右交错铺开,普通时固定从两侧冒
        let wobble: CGFloat = CGFloat(sin(raw * 5 + Double(i)) * 7)
        let x: CGFloat = burst
            ? CGFloat(i - count / 2) * 15 + wobble
            : (i % 2 == 0 ? CGFloat(34) : CGFloat(-34)) + p * 6
        let rise: CGFloat = burst ? 46 : 30
        return HeartShape()
            .fill(blush.opacity(Double(1 - p) * 0.95))
            .frame(width: size - p * 4, height: size - 1 - p * 4)
            .offset(x: x, y: -44 - p * rise)
    }
}

/// 小三角(鼻子)
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}