import SwiftUI

enum Tab: String, CaseIterable {
    case weigh, history, settings

    var title: String {
        switch self {
        case .weigh: return "Вес"
        case .history: return "История"
        case .settings: return "Настройки"
        }
    }
}

/// Панель вкладок — три овальные стеклянные плашки поверх содержимого.
/// На iOS 26 это настоящее «жидкое стекло», на более старых — матовый материал.
struct TabBar: View {
    @Environment(\.palette) private var palette
    @Binding var selection: Tab

    /// Сколько места панель занимает снизу — на столько экраны отступают.
    static let reservedHeight: CGFloat = 92

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    row
                }
            } else {
                row
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var row: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
    }

    @ViewBuilder
    private func item(_ tab: Tab) -> some View {
        let on = tab == selection
        let content = VStack(spacing: 2) {
            icon(for: tab)
                .frame(width: 26, height: 26)
            Text(tab.title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(on ? palette.blue : palette.tabIcon)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Capsule())

        if #available(iOS 26.0, *) {
            content
                // Тонировать сильнее нельзя: стекло и так подбирает цвет того,
                // что проезжает под ним, и вкладка становится ядовито-синей.
                .glassEffect(on ? .regular.tint(palette.blue.opacity(0.10)).interactive()
                                : .regular.interactive(),
                             in: .capsule)
                .onTapGesture { selection = tab }
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(palette.sep, lineWidth: 0.5))
                .onTapGesture { selection = tab }
        }
    }

    @ViewBuilder
    private func icon(for tab: Tab) -> some View {
        switch tab {
        case .weigh:
            ScaleDialIcon(size: 26, lineWidth: 1.7)
        case .history:
            Path { p in
                p.move(to: CGPoint(x: 3.5, y: 18))
                p.addLine(to: CGPoint(x: 9.5, y: 11))
                p.addLine(to: CGPoint(x: 14, y: 14.5))
                p.addLine(to: CGPoint(x: 22.5, y: 5))
                p.move(to: CGPoint(x: 3.5, y: 22))
                p.addLine(to: CGPoint(x: 22.5, y: 22))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 26, height: 26)
        case .settings:
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .regular))
        }
    }
}
