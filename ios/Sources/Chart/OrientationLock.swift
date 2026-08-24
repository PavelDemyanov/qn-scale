import SwiftUI
import UIKit

/// Разрешённые ориентации ВСЕГО окна.
///
/// iOS не умеет «повернуть одну вьюху»: маску он спрашивает один раз у делегата
/// приложения и применяет ко всему `UIWindowScene`. Поэтому по умолчанию здесь
/// портрет — ровно как было записано в `Info.plist`, — а расширяет её и
/// возвращает обратно РОВНО ОДИН экран, «История» с графиком.
///
/// Почему не переопределить `supportedInterfaceOrientations` у контроллера:
/// своего `UIViewController` в SwiftUI-приложении нет, хост создаёт
/// `UIHostingController` сам. Пришлось бы заворачивать всё дерево в свой
/// сабкласс хостинга или свизлить — оба варианта хуже одного статического поля,
/// которое читает делегат. Приём взят из EUC Logger, где он уже отработан.
///
/// Зачем при этом ВСЁ РАВНО нужен `requestGeometryUpdate`: маска — только
/// разрешение, а поворачивает экран человек. При включённом в Пункте управления
/// замке поворота устройство не повернётся никогда, и без явной кнопки «во весь
/// экран» альбомный режим был бы недоступен тем, кто держит замок включённым.
/// Обратная сторона того же: без кнопки «свернуть» из альбома было бы не выйти.
enum OrientationLock {

    /// Читается делегатом приложения. Только с главного потока — и чтение, и
    /// запись: UIKit спрашивает маску на главном.
    static var mask: UIInterfaceOrientationMask = .portrait

    static let landscapeCapable: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]

    /// Сцену НЕ кешируем: после возврата из фона она может быть уже другой.
    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Самый верхний контроллер: вопрос об ориентации UIKit задаёт именно ему,
    /// и `setNeedsUpdate…` звать надо тоже на нём. Обход `presentedViewController`
    /// обязателен — над «Историей» открываются шторки (день, ручной ввод).
    private static var topViewController: UIViewController? {
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    /// Разрешить альбом. Дальше решает человек: повернул телефон — повернулось.
    static func unlock() {
        guard mask != landscapeCapable else { return }
        mask = landscapeCapable
        topViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        // Телефон УЖЕ лежит горизонтально: расширить маску мало — система
        // поворачивает по СОБЫТИЮ от акселерометра, а его не будет, пока
        // телефон не шевельнут. Просим поворот сами, в ту сторону, куда он и
        // повёрнут.
        switch UIDevice.current.orientation {
        case .landscapeLeft: rotate(to: .landscapeRight)
        case .landscapeRight: rotate(to: .landscapeLeft)
        default: break
        }
    }

    /// Повернуть принудительно. Работает и при включённом замке поворота: замок
    /// глушит поворот ОТ УСТРОЙСТВА, а этот запрос идёт от приложения.
    ///
    /// Звать только ПОСЛЕ `unlock()`: ориентацию вне текущей маски UIKit
    /// отклоняет молча — классический симптом «кнопка не работает».
    static func rotate(to orientation: UIInterfaceOrientationMask) {
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }

    /// Вернуть портрет при уходе с экрана графика.
    ///
    /// Одного сужения маски мало: UIKit перечитывает её только по явному
    /// `setNeedsUpdate…`, а при включённом замке поворота устройство из альбома
    /// само не повернётся уже никогда — приложение осталось бы лежать на боку.
    static func relock() {
        guard mask != .portrait else { return }
        mask = .portrait
        rotate(to: .portrait)
        topViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// ЕДИНСТВЕННАЯ обязанность делегата — отдавать маску. Инициализацию сюда не
/// класть: весы, «Здоровье» и напоминания живут в своих объектах, а делегат
/// создаётся SwiftUI в неопределённый относительно них момент.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
