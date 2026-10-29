import SwiftUI

/// 点三下才拆开的礼物盒。拆开后盖子飞出、爱心升起、显示那句话。
struct GiftBoxView: View {

    let message: String
    let onOpened: () -> Void
    let onClose: () -> Void

    @State private var taps = 0
    @State private var opened = false
    @State private var punch: CGFloat = 1       // 点击时的挤压反馈
    @State private var start = Date()

    private let ribbon = Color(red: 1.00, green: 0.93, blue: 0.70)
    private let boxTop = Color(red: 0.96, green: 0.42, blue: 0.50)
    private let boxBottom = Color(red: 0.84, green: 0.24, blue: 0.36)

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            content(t: t)
        }
        .frame(width: 320, height: 340)
    }

    private func content(t: Double) -> some View {
        VStack(spacing: 18) {
            Text(opened ? "🎉" : (taps == 0 ? "点我三下" : "再点 \(3 - taps) 下"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.28)))

            ZStack {
                if opened { hearts(t: t) }
                box(t: t)
            }
            .frame(width: 180, height: 150)

            Text(opened ? message : " ")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.32, green: 0.20, blue: 0.24))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(width: 250, height: 62, alignment: .top)
                .opacity(opened ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.35), value: opened)
        }
        .padding(.vertical, 22)
        .frame(width: 320, height: 340)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 1.0, green: 0.97, blue: 0.95).opacity(0.97))
                .shadow(color: .black.opacity(0.26), radius: 18, y: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { handleTap() }
    }

    // MARK: 盒子

    private func box(t: Double) -> some View {
        let shake = opened ? 0 : sin(t * 11) * 2.6 * (taps > 0 ? 1.6 : 1)
        return ZStack {
            // 盒身
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [boxTop, boxBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 124, height: 88)
                // 竖丝带
                Rectangle()
                    .fill(ribbon)
                    .frame(width: 20, height: 88)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: 124, height: 88)
            .offset(y: 26)

            // 盒盖
            lid
                .offset(y: opened ? -118 : -22)
                .rotationEffect(.degrees(opened ? -26 : 0))
                .opacity(opened ? 0.0 : 1)
                .animation(.interpolatingSpring(stiffness: 120, damping: 11), value: opened)
        }
        .scaleEffect(x: punch, y: 2 - punch, anchor: .bottom)
        .rotationEffect(.degrees(shake), anchor: .bottom)
    }

    private var lid: some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [boxTop.opacity(0.95), boxBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 140, height: 34)
                Rectangle()
                    .fill(ribbon)
                    .frame(width: 20, height: 34)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(width: 140, height: 34)

            bow.offset(y: -24)
        }
    }

    private var bow: some View {
        ZStack {
            BowLoop()
                .fill(ribbon)
                .frame(width: 26, height: 22)
                .rotationEffect(.degrees(-22))
                .offset(x: -13)
            BowLoop()
                .fill(ribbon)
                .frame(width: 26, height: 22)
                .rotationEffect(.degrees(22))
                .scaleEffect(x: -1, y: 1)
                .offset(x: 13)
            Circle()
                .fill(ribbon)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(boxBottom.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: 拆开后的爱心

    private func hearts(t: Double) -> some View {
        ForEach(0..<9, id: \.self) { i in
            let seed = Double(i)
            let p = ((t * 0.42 + seed * 0.14).truncatingRemainder(dividingBy: 1))
            let drift = sin(seed * 2.3 + p * 4) * 46
            HeartShape()
                .fill(
                    [Color(red: 1.0, green: 0.45, blue: 0.56),
                     Color(red: 1.0, green: 0.72, blue: 0.40),
                     Color(red: 0.78, green: 0.62, blue: 1.0)][i % 3]
                        .opacity((1 - p) * 0.95)
                )
                .frame(width: 20 - CGFloat(p) * 9, height: 19 - CGFloat(p) * 9)
                .offset(x: CGFloat(drift), y: 20 - CGFloat(p) * 150)
        }
    }

    // MARK: 交互

    private func handleTap() {
        if opened {
            onClose()
            return
        }
        taps += 1
        withAnimation(.easeOut(duration: 0.09)) { punch = 1.12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { punch = 1 }
        }
        guard taps >= 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation { opened = true }
            onOpened()
        }
    }
}

// MARK: - 蝴蝶结的一个耳朵

struct BowLoop: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY)
        )
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY),
            control2: CGPoint(x: rect.midX, y: rect.maxY)
        )
        p.closeSubpath()
        return p
    }
}