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

    var body: some View {
        ZStack {
            groundShadow
            petBody
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: 10 + bob + jump)
            effects
        }
        .frame(width: 160, height: 160)
        .allowsHitTesting(false)
    }

    // MARK: - 地面阴影

    private var groundShadow: some View {
        Ellipse()
            .fill(Color.black.opacity(isDragging || isFalling ? 0.08 : 0.16))
            .frame(width: 76 - (jump + bob) * 0.6, height: 13)
            .offset(y: 62)
            .blur(radius: 2)
    }

    // MARK: - 身体

    private var petBody: some View {
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