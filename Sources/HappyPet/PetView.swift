import SwiftUI

/// 宠物的全部外观与动画(纯代码绘制,无需图片资源)
struct PetView: View {

    @ObservedObject var brain: PetBrain

    // MARK: - 配色
    private let furTop = Color(red: 1.00, green: 0.82, blue: 0.58)
    private let furBottom = Color(red: 0.98, green: 0.62, blue: 0.29)
    private let ink = Color(red: 0.24, green: 0.16, blue: 0.12)
    private let blush = Color(red: 1.00, green: 0.55, blue: 0.60)

    // MARK: - 动画推导量
    private var t: Double { brain.clock }
    private var isWalking: Bool { brain.state == .walk }
    private var isSleeping: Bool { brain.state == .sleep }
    private var isHappy: Bool { brain.state == .happy }
    private var isDragging: Bool { brain.state == .drag }
    private var isFalling: Bool { brain.state == .fall }
    private var eyesClosed: Bool { isSleeping || brain.isBlinking }

    /// 呼吸(睡觉时更慢更深)
    private var breath: CGFloat {
        let speed = isSleeping ? 1.1 : 2.4
        let amount: CGFloat = isSleeping ? 0.045 : 0.022
        return CGFloat(sin(t * speed)) * amount
    }

    /// 走路上下颠簸
    private var bob: CGFloat {
        isWalking ? CGFloat(abs(sin(t * 7))) * -4 : 0
    }

    /// 开心跳跃
    private var jump: CGFloat {
        isHappy ? CGFloat(abs(sin(t * 7))) * -26 : 0
    }

    /// 身体挤压/拉伸
    private var squash: CGSize {
        if isFalling { return CGSize(width: 0.92, height: 1.10) }
        if isHappy { return CGSize(width: 1.0 - breath, height: 1.04 + breath) }
        return CGSize(width: 1 - breath, height: 1 + breath)
    }

    /// 被拖拽时左右晃动
    private var tilt: Double {
        isDragging ? sin(t * 5) * 7 : 0
    }

    private var tailSwing: CGFloat {
        let speed = isSleeping ? 0.9 : (isWalking || isHappy ? 5.0 : 1.8)
        return CGFloat(sin(t * speed))
    }

    private var legSwing: CGFloat {
        isWalking ? CGFloat(sin(t * 7)) * 5 : (isDragging ? CGFloat(sin(t * 5)) * 3 : 0)
    }

    // MARK: - body

    /// 宠物本体在窗口里的下移量:上方留给举牌和气泡
    private let bodyDrop: CGFloat = 70

    var body: some View {
        ZStack {
            ZStack {
                groundShadow
                avatar
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .offset(y: 10 + bob + jump)
                cakeLayer
                effects
            }
            .frame(width: 160, height: 160)
            .offset(y: bodyDrop)

            overlayLayer
        }
        .frame(width: 200, height: 300)
        .allowsHitTesting(false)
    }

    // MARK: - 地面阴影

    private var groundShadow: some View {
        let baseWidth: CGFloat = hasCharacter ? 54 : 76
        return Ellipse()
            .fill(Color.black.opacity(isDragging || isFalling ? 0.08 : 0.16))
            .frame(width: baseWidth - (jump + bob) * 0.6, height: hasCharacter ? 10 : 13)
            .offset(y: hasCharacter ? 70 : 62)
            .blur(radius: 2)
    }

    // MARK: - 本体:有立绘就用立绘,否则用内置橘猫

    private var hasCharacter: Bool { brain.assets.hasCharacter }

    @ViewBuilder
    private var avatar: some View {
        if hasCharacter { characterBody } else { catBody }
    }

    /// 图片素材驱动的人物。
    /// 有「闭眼整帧」时眨眼走整图切换;只有眼睛小图层时才走叠加。
    private var characterBody: some View {
        let assets = brain.assets
        return ZStack(alignment: .bottom) {
            if let blink = assets.blinkBody {
                layer(eyesClosed ? blink : (assets.body ?? blink))
            } else {
                if let bodyImage = assets.body {
                    layer(bodyImage)
                }
                if let open = assets.eyesOpen, let closed = assets.eyesClosed {
                    layer(eyesClosed ? closed : open)
                }
            }
            if let arm = assets.armRight {
                layer(arm)
                    .rotationEffect(.degrees(armAngle), anchor: .top)
            }
        }
        .frame(width: 74, height: 185, alignment: .bottom)
        .offset(y: -24)
        .scaleEffect(x: squash.width, y: squash.height, anchor: .bottom)
        .scaleEffect(x: brain.facingRight ? 1 : -1, y: 1)
    }

    private func layer(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    /// 抬手角度:举牌或捧蛋糕时抬起来,睡着时垂下
    private var armAngle: Double {
        if brain.signText != nil || brain.isHoldingCake { return -58 }
        if isSleeping { return 5 }
        return sin(t * 1.6) * 3
    }

    // MARK: - 蛋糕 / 举牌 / 气泡

    @ViewBuilder
    private var cakeLayer: some View {
        if brain.isHoldingCake {
            CakeView(lit: brain.candleLit, clock: t)
                .scaleEffect(0.92)
                .offset(x: brain.facingRight ? 6 : -6,
                        y: (hasCharacter ? -20 : 26) + bob + jump * 0.4)
        }
    }

    @ViewBuilder
    private var overlayLayer: some View {
        // 立绘是全身比例,头顶比橘猫高不少,牌子和气泡要相应抬高
        let hasSign = brain.signText != nil
        let signY: CGFloat = hasCharacter ? -62 : -6
        let bubbleY: CGFloat = hasCharacter
            ? (hasSign ? -100 : -48)
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
        .scaleEffect(x: brain.facingRight ? 1 : -1, y: 1)
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
        if isSleeping {
            ForEach(0..<3, id: \.self) { i in
                let p = CGFloat((t * 0.45 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1))
                Text("z")
                    .font(.system(size: 12 + p * 10, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.45, blue: 0.75).opacity(Double(1 - p) * 0.9))
                    .offset(x: 38 + p * 14, y: -40 - p * 26)
            }
        } else if isHappy {
            ForEach(0..<3, id: \.self) { i in
                let p = CGFloat((t * 0.9 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1))
                HeartShape()
                    .fill(blush.opacity(Double(1 - p) * 0.95))
                    .frame(width: 13 - p * 4, height: 12 - p * 4)
                    .offset(x: (i % 2 == 0 ? 34 : -34) + p * 6, y: -44 - p * 30)
            }
        }
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