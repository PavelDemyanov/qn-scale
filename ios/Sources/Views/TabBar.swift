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

/// Своя панель вкладок: у системной другой размер иконок и нет такой заливки.
struct TabBar: View {
    @Environment(\.palette) private var palette
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let on = tab == selection
                VStack(spacing: 2) {
                    icon(for: tab)
                        .frame(width: 27, height: 27)
                    Text(tab.title)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(on ? palette.blue : palette.tabIcon)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .contentShape(Rectangle())
                .onTapGesture { selection = tab }
            }
        }
        .frame(height: 82, alignment: .top)
        .background {
            // Матовое стекло плюс тон из макета (--tabbg): у голого материала
            // другая плотность, и панель выходит светлее.
            Rectangle().fill(.ultraThinMaterial)
                .overlay(palette.tabBar)
        }
        .overlay(alignment: .top) { RowSeparator() }
        // В макете панель ровно 82 пункта и стоит вплотную к низу экрана —
        // зона домашнего индикатора входит в эти 82, а не добавляется к ним.
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func icon(for tab: Tab) -> some View {
        switch tab {
        case .weigh:
            // Тот же циферблат, что на диске взвешивания.
            ScaleDialIcon(size: 27, lineWidth: 1.7)
        case .history:
            Path { p in
                p.move(to: CGPoint(x: 3.5, y: 18.5))
                p.addLine(to: CGPoint(x: 10, y: 11.5))
                p.addLine(to: CGPoint(x: 14.5, y: 15))
                p.addLine(to: CGPoint(x: 23, y: 5.5))
                p.move(to: CGPoint(x: 3.5, y: 22.5))
                p.addLine(to: CGPoint(x: 23, y: 22.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 27, height: 27)
        case .settings:
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .regular))
        }
    }
}
