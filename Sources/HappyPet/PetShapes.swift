import SwiftUI

/// 耳朵(圆润三角)
struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX + 1, y: rect.minY),
            control: CGPoint(x: rect.minX + 1, y: rect.midY - 6)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - 1, y: rect.midY + 4)
        )
        p.closeSubpath()
     return p
    }
}

/// 尾巴(可摆动的曲线)
struct TailShape: Shape {
    /// -1...1 的摆动量
    var swing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.minX + 4 - swing * 6, y: rect.minY + 6 - swing * 10),
            control1: CGPoint(x: rect.midX - swing * 4, y: rect.maxY - 6),
            control2: CGPoint(x: rect.minX - 6 - swing * 12, y: rect.midY + 10)
        )
        return p
    }
}

/// 闭眼的弧线
struct ClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY + 2)
        )
        return p
    }
}

/// 微笑的嘴(ω 形)
struct MouthShape: Shape {
    /// 0 = 闭嘴微笑, 1 = 张嘴大笑
    var open: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midX
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: mid, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY + open * 4)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.maxY + open * 4)
        )
        return p
    }
}

/// 头顶的三条小纹路
struct StripesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let x = rect.minX + rect.width * (0.1 + 0.4 * CGFloat(i))
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: x + rect.width * 0.2, y: rect.maxY),
                control: CGPoint(x: x + rect.width * 0.1, y: rect.minY)
            )
        }
        return p
    }
}

/// 爱心
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w / 2, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.28),
                   control1: CGPoint(x: w * 0.2, y: h * 0.78),
                   control2: CGPoint(x: 0, y: h * 0.55))
        p.addArc(center: CGPoint(x: w * 0.25, y: h * 0.28), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: w * 0.75, y: h * 0.28), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: w / 2, y: h),
                   control1: CGPoint(x: w, y: h * 0.55),
                   control2: CGPoint(x: w * 0.8, y: h * 0.78))
        p.closeSubpath()
        return p
    }
}