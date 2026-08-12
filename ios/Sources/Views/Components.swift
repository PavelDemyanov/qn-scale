import SwiftUI

/// Общие кирпичики из макета: карточки, строки, кнопки и плитки. Всё, чему
/// нашлась системная замена (сегменты, шевроны, заголовки экранов), убрано.

struct CardBackground: ViewModifier {
    @Environment(\.palette) private var palette
    var radius: CGFloat = 22
    var onSheet = false
    func body(content: Content) -> some View {
        content.background(onSheet ? palette.cardOnSheet : palette.card,
                           in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = 22) -> some View { modifier(CardBackground(radius: radius)) }

    /// То же, но для карточек внутри шторки — там нужен другой тон.
    func sheetCard(radius: CGFloat = 22) -> some View {
        modifier(CardBackground(radius: radius, onSheet: true))
    }

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

struct RowSeparator: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Rectangle().fill(palette.sep).frame(height: 0.5)
    }
}

/// Строка внутри карточки. Внутри — системный `LabeledContent`: он сам даёт
/// правильные шрифты, поддержку крупного текста и связку «подпись — значение»
/// для VoiceOver; своё здесь только выравнивание по карточке.
struct Row<Trailing: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    var subtitle: String? = nil
    var minHeight: CGFloat = 52
    var titleColor: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Text(title).foregroundStyle(titleColor ?? palette.fg)
            // Подпись может занять две строки: длинную «−0,50 кг в неделю»
            // системный `LabeledContent` иначе выдавливает вбок и режет
            // значение справа.
            if let subtitle { Text(subtitle).lineLimit(2) }
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

/// Кнопка действия — системные стили, а не своя заливка со скруглением.
/// На iOS 26 они сами получают нужную форму и «стекло».
struct ActionButton: View {
    enum Kind { case primary, secondary, destructive }

    let title: String
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        switch kind {
        case .primary:
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        case .secondary:
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        case .destructive:
            Button(title, role: .destructive, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
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

/// Циферблат весов из макета: окружность, стрелка из центра и точка оси.
/// Рисуем сами — у системного «scalemass» другой силуэт.
struct ScaleDialIcon: View {
    var size: CGFloat = 40
    var lineWidth: CGFloat = 2

    var body: some View {
        let k = size / 40
        ZStack {
            Circle()
                .stroke(lineWidth: lineWidth)
                .frame(width: 32 * k, height: 32 * k)
            Path { p in
                p.move(to: CGPoint(x: 20 * k, y: 20 * k))
                p.addLine(to: CGPoint(x: 28 * k, y: 12.5 * k))
            }
            .stroke(style: StrokeStyle(lineWidth: lineWidth * 1.2, lineCap: .round))
            .frame(width: size, height: size)
            Circle().frame(width: 5.6 * k, height: 5.6 * k)
        }
        .frame(width: size, height: size)
    }
}
