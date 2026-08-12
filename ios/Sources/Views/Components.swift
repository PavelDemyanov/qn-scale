import SwiftUI

/// Общие кирпичики из макета: карточки, строки списков, сегменты, кнопки.

struct CardBackground: ViewModifier {
    @Environment(\.palette) private var palette
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content.background(palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = 22) -> some View { modifier(CardBackground(radius: radius)) }

    /// Горизонтальные отступы карточек — 16 пунктов от края экрана.
    func cardInset() -> some View { padding(.horizontal, 16) }
}

/// Заголовок группы: «ИТОГ ЗА ПЕРИОД», «ВЕСЫ» и прочие.
struct SectionHeader: View {
    @Environment(\.palette) private var palette
    let text: String
    var top: CGFloat = 20
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(palette.fg2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, top)
            .padding(.bottom, 6)
    }
}

/// Пояснение под группой.
struct SectionFooter: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(1)
            .foregroundStyle(palette.fg3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 7)
    }
}

struct RowSeparator: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Rectangle().fill(palette.sep).frame(height: 0.5)
    }
}

/// Строка сгруппированного списка.
struct Row<Trailing: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var subtitle: String? = nil
    var minHeight: CGFloat = 52
    var titleColor: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(titleColor ?? palette.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.fg3)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 18)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }
}

extension Row where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, minHeight: CGFloat = 52, titleColor: Color? = nil) {
        self.init(title: title, subtitle: subtitle, minHeight: minHeight,
                  titleColor: titleColor, trailing: { EmptyView() })
    }
}

struct Chevron: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.fg3)
    }
}

/// Сегментированный переключатель из макета (свой, а не системный: у системного
/// другой радиус и другая типографика).
struct Segmented<T: Hashable>: View {
    @Environment(\.palette) private var palette
    let items: [(value: T, label: String)]
    @Binding var selection: T
    var fontSize: CGFloat = 13
    var selectedBackground: Color? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.value) { item in
                let on = item.value == selection
                Text(item.label)
                    .font(.system(size: fontSize, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? palette.fg : palette.fg2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(on ? (selectedBackground ?? palette.card) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22)) { selection = item.value }
                    }
            }
        }
        .padding(2)
        .background(palette.seg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Большая синяя кнопка внизу экрана.
struct PrimaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var background: Color? = nil
    var foreground: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground ?? .white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(background ?? palette.blue,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Маленькая плитка со значением: «взвешиваний», «дней подряд» и т. п.
struct StatTile: View {
    @Environment(\.palette) private var palette
    let value: String
    let caption: String
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? palette.fg)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .card(radius: 18)
    }
}

/// Плитка с дельтой за период.
struct DeltaTile: View {
    @Environment(\.palette) private var palette
    let caption: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(palette.fg2)
            Text(value.map { Fmt.signed($0) } ?? "—")
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(value.map { palette.delta($0) } ?? palette.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(radius: 18)
    }
}

/// Заголовок экрана в стиле крупного iOS-заголовка.
struct LargeTitle: View {
    @Environment(\.palette) private var palette
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(palette.fg)
    }
}
