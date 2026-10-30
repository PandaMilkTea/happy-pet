import SwiftUI

/// 拆开之后的礼物清单:一张张翻,兑换券可以当场用掉。
struct GiftListView: View {

    let items: [GiftItem]
    let onClose: () -> Void

    @State private var index = 0
    @State private var used: Set<String> = []
    @State private var appeared = false
    @State private var stamping = false

    private let ink = Color(red: 0.32, green: 0.20, blue: 0.24)
    private let paper = Color(red: 1.0, green: 0.98, blue: 0.96)
    private let accent = Color(red: 0.95, green: 0.42, blue: 0.52)

    private var current: GiftItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            cardArea
            pager
        }
        .padding(.vertical, 20)
        .frame(width: 380, height: 470)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(paper.opacity(0.98))
                .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        )
        .overlay(closeButton, alignment: .topTrailing)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            used = Set(items.filter { GiftStore.shared.isUsed($0) }.map { $0.id })
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76)) { appeared = true }
        }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(spacing: 4) {
            Text("礼物清单")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(ink)
            Text("一共 \(items.count) 件,慢慢看")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(ink.opacity(0.5))
        }
    }

    // MARK: 卡片

    private var cardArea: some View {
        ZStack {
            // 背后压着的两张,做出"还有一叠"的厚度
            ForEach(1...2, id: \.self) { depth in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ink.opacity(0.08), lineWidth: 1)
                    )
                    .frame(width: 300 - CGFloat(depth) * 14, height: 300)
                    .offset(y: CGFloat(depth) * 7)
                    .opacity(index + depth < items.count ? 1 : 0)
            }

            if let item = current {
                card(for: item)
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94)),
                        removal: .opacity
                    ))
            }
        }
        .frame(width: 320, height: 314)
    }

    @ViewBuilder
    private func card(for item: GiftItem) -> some View {
        if item.isCoupon {
            couponCard(item)
        } else if item.kind == .photo, let image = item.image {
            photoCard(image)
        } else {
            plainCard(item)
        }
    }

    /// 普通卡片:一句话、里程碑、情话
    private func plainCard(_ item: GiftItem) -> some View {
        VStack(spacing: 14) {
            Text(item.emoji).font(.system(size: 38))
            Text(item.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(accent)
            Text(item.body)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(ink)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 24)
        }
        .frame(width: 300, height: 300)
        .background(cardBackground)
    }

    /// 合照卡片:整张照片完整放进来,横图竖图都不裁
    private func photoCard(_ image: NSImage) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ink.opacity(0.05))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            .frame(width: 262, height: 224)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("那天的我们")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(ink.opacity(0.65))
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: 300, height: 300)
        .background(cardBackground)
    }

    /// 兑换券:虚线票根 + 盖章
    private func couponCard(_ item: GiftItem) -> some View {
        let isUsed = used.contains(item.id)
        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("🎟️").font(.system(size: 30))
                Text(item.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(ink)
                Text(item.body)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(ink.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
            }
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundColor(ink.opacity(0.22))
                )
                .padding(.horizontal, 18)

            useButton(item, isUsed: isUsed)
                .frame(height: 72)
        }
        .frame(width: 300, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.96, blue: 0.93),
                             Color(red: 1.0, green: 0.90, blue: 0.90)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .overlay(isUsed ? stamp : nil)
        .opacity(isUsed ? 0.82 : 1)
    }

    private func useButton(_ item: GiftItem, isUsed: Bool) -> some View {
        Button {
            guard !isUsed else { return }
            GiftStore.shared.markUsed(item)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                _ = used.insert(item.id)
                stamping = true
            }
        } label: {
            Text(isUsed ? "已经用掉啦" : "用掉这一张")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isUsed ? ink.opacity(0.4) : .white)
                .frame(width: 180, height: 36)
                .background(
                    Capsule().fill(isUsed ? ink.opacity(0.1) : accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(isUsed)
    }

    private var stamp: some View {
        Text("已兑换")
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(Color(red: 0.84, green: 0.22, blue: 0.26).opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(red: 0.84, green: 0.22, blue: 0.26).opacity(0.7), lineWidth: 2.5)
            )
            .rotationEffect(.degrees(-14))
            .offset(y: -34)
            .scaleEffect(stamping ? 1 : 1.6)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: stamping)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ink.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    // MARK: 翻页

    private var pager: some View {
        HStack(spacing: 18) {
            arrow("chevron.left", enabled: index > 0) { step(-1) }

            if items.count <= 14 {
                HStack(spacing: 5) {
                    ForEach(items.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index ? accent : ink.opacity(0.16))
                            .frame(width: 6, height: 6)
                    }
                }
            } else {
                Text("\(index + 1) / \(items.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(ink.opacity(0.45))
                    .frame(minWidth: 70)
            }

            arrow("chevron.right", enabled: index < items.count - 1) { step(1) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(enabled ? .white : ink.opacity(0.25))
                .frame(width: 30, height: 30)
                .background(Circle().fill(enabled ? accent : ink.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        stamping = false
        withAnimation(.easeInOut(duration: 0.28)) { index = next }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black.opacity(0.28)))
        }
        .buttonStyle(.plain)
        .padding(12)
    }
}