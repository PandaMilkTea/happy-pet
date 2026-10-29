import SwiftUI

// MARK: - 蛋糕 + 蜡烛

/// 生日蛋糕(纯矢量)。lit = 蜡烛是否还亮着。
struct CakeView: View {

    let lit: Bool
    let clock: Double

    private let cream = Color(red: 1.00, green: 0.96, blue: 0.93)
    private let body1 = Color(red: 0.98, green: 0.72, blue: 0.78)
    private let body2 = Color(red: 0.92, green: 0.54, blue: 0.63)
    private let plate = Color(red: 0.96, green: 0.96, blue: 0.98)

    var body: some View {
        ZStack {
            // 盘子
            Ellipse()
                .fill(plate)
                .frame(width: 56, height: 11)
            .overlay(
                    Ellipse().stroke(Color.black.opacity(0.10), lineWidth: 1)
                        .frame(width: 56, height: 11)
                )
                .offset(y: 20)

            // 蛋糕主体
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [body1, body2],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 26)
                .offset(y: 7)

            // 奶油滴边
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle().fill(cream).frame(width: 10, height: 10)
                }
            }
            .frame(width: 46)
            .offset(y: -4)

            // 顶面
            Ellipse()
                .fill(cream)
                .frame(width: 44, height: 11)
                .offset(y: -6)

            // 彩针
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill([Color.orange, .mint, .purple, .pink][i].opacity(0.85))
                    .frame(width: 5, height: 1.8)
                    .rotationEffect(.degrees(Double(i) * 47 - 20))
                    .offset(x: CGFloat(i) * 9 - 14, y: -6)
            }

            candle
        }
        .frame(width: 60, height: 54)
    }

    private var candle: some View {
        ZStack {
            // 蜡烛身
            Capsule()
                .fill(LinearGradient(colors: [Color.white, Color(red: 0.96, green: 0.85, blue: 0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 5, height: 20)
                .offset(y: -17)
            // 烛芯
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: 1.4, height: 4)
                .offset(y: -28)

            if lit {
                flame
            } else {
                smoke
            }
        }
    }

    private var flame: some View {
        let wobble = sin(clock * 9) * 2.2
        let flicker = 1 + sin(clock * 13) * 0.10
        return ZStack {
            // 外焰光晕
            Circle()
                .fill(Color.orange.opacity(0.28))
                .frame(width: 24, height: 24)
                .blur(radius: 6)
            FlameShape()
                .fill(LinearGradient(colors: [Color.yellow, Color.orange],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 9, height: 15)
            FlameShape()
                .fill(Color.white.opacity(0.75))
                .frame(width: 4, height: 7)
                .offset(y: 3)
        }
        .scaleEffect(y: flicker, anchor: .bottom)
        .rotationEffect(.degrees(wobble), anchor: .bottom)
        .offset(x: CGFloat(wobble) * 0.4, y: -37)
    }

    private var smoke: some View {
        ForEach(0..<3, id: \.self) { i in
            let p = (clock * 0.5 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            Circle()
                .fill(Color.gray.opacity((1 - p) * 0.35))
                .frame(width: 4 + CGFloat(p) * 7, height: 4 + CGFloat(p) * 7)
                .offset(x: CGFloat(sin(p * 6 + Double(i))) * 5, y: -32 - CGFloat(p) * 26)
                .blur(radius: 1.5)
        }
    }
}

/// 烛焰形状:底部圆钝,顶部收尖
struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.15),
                   control1: CGPoint(x: rect.midX + rect.width * 0.35, y: rect.height * 0.25),
                   control2: CGPoint(x: rect.maxX, y: rect.height * 0.40))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.15),
                   control1: CGPoint(x: rect.maxX, y: rect.maxY),
                   control2: CGPoint(x: rect.minX, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.height * 0.40),
                   control2: CGPoint(x: rect.midX - rect.width * 0.35, y: rect.height * 0.25))
        p.closeSubpath()
        return p
    }
}

// MARK: - 举牌

/// 举在手里的纸牌,文案来自 love.txt
struct SignView: View {

    let text: String
    let clock: Double

    private var sway: Double { sin(clock * 2.1) * 2.2 }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.28, green: 0.20, blue: 0.22))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(minWidth: 54, maxWidth: 108)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.99, blue: 0.96))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(red: 0.86, green: 0.74, blue: 0.70), lineWidth: 1.2)
                )
            // 木棍
            Capsule()
                .fill(Color(red: 0.72, green: 0.55, blue: 0.38))
                .frame(width: 4, height: 20)
        }
        .rotationEffect(.degrees(sway), anchor: .bottom)
    }
}

// MARK: - 气泡

/// 头顶的小气泡提示
struct BubbleView: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Color(red: 0.26, green: 0.22, blue: 0.26))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
            )
            .fixedSize()
    }
}