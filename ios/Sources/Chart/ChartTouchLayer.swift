import SwiftUI
import UIKit

enum ChartGestureEvent {
    case markerBegan(x: CGFloat)
    case markerMoved(x: CGFloat)
    case markerEnded
    case tapped
    case panBegan
    case panChanged(byFraction: Double)
    case panEnded
    case zoomBegan(anchor: Double)
    case zoomChanged(scale: Double)
    case zoomEnded
    case glide(byFraction: Double)
}

/// Жестовый слой графика.
///
/// SwiftUI-жестами это не делается в принципе. Прежний вариант — `DragGesture`
/// с нулевым порогом внутри строки списка плюс рукописный таймер на 550 мс,
/// запускаемый и отменяемый только из `onChanged`/`onEnded`. При перехвате
/// жеста прокруткой `onEnded` не вызывается ВОВСЕ: задача доживала до конца и
/// ставила метку с вибрацией прямо во время скролла, а флаг удержания оставался
/// поднятым. Здесь развилку «скраб или протяжка» держит UIKit.
struct ChartTouchLayer: UIViewRepresentable {
    var plot: CGRect             // ПОЛОСА ЛИНИИ, не весь кадр
    var resetToken: Int
    var onEvent: (ChartGestureEvent) -> Void

    func makeUIView(context: Context) -> UIView {
        let c = context.coordinator
        let view = UIView()
        view.backgroundColor = .clear

        let press = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.22    // «слегка задержать палец»
        press.allowableMovement = 10         // ушёл раньше — это протяжка окна
        press.numberOfTouchesRequired = 1

        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1       // второй палец ЗАКАНЧИВАЕТ панораму

        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let watch = TouchWatch()
        watch.onSequenceEnded = { [weak c] in c?.sequenceEnded() }
        // Палец на катящемся графике останавливает его — как в любом списке iOS.
        // Ловить это распознавателями нельзя: пока человек просто держит палец,
        // ни один из них не срабатывает.
        //
        // Остановка инерции — это КОНЕЦ ЖЕСТА, и терминальное событие тут
        // обязательно: без него у модели навсегда остаётся поднятый признак
        // «жест идёт», а с ним замирают сводка, список и вся прокрутка экрана.
        // Инерция начинается без отрыва пальца от жизни модели, и другого
        // источника `.panEnded` у неё нет. На касании без инерции `stopGlide`
        // выходит по своему guard и не шлёт ничего.
        watch.onTouchBegan = { [weak c] in c?.stopGlide(emitEnd: true) }

        for g in [press, pan, pinch, tap, watch] as [UIGestureRecognizer] {
            g.cancelsTouchesInView = false   // список обязан продолжать видеть касание
            g.delegate = c
            view.addGestureRecognizer(g)
        }
        pan.require(toFail: press)
        tap.require(toFail: press)
        c.press = press
        c.pan = pan
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.plot = plot
        context.coordinator.onEvent = onEvent    // замыкание обновляем ПЕРВЫМ
        if context.coordinator.token != resetToken {
            context.coordinator.token = resetToken
            context.coordinator.forceEnd()
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.stopGlide(emitEnd: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(plot: plot, onEvent: onEvent) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var plot: CGRect
        var onEvent: (ChartGestureEvent) -> Void
        var token = 0
        weak var press: UILongPressGestureRecognizer?
        weak var pan: UIPanGestureRecognizer?
        private var markerActive = false
        private var markerLocked = false
        private var panActive = false
        private var zoomActive = false
        private let click = UISelectionFeedbackGenerator()

        init(plot: CGRect, onEvent: @escaping (ChartGestureEvent) -> Void) {
            self.plot = plot
            self.onEvent = onEvent
        }

        private func fraction(_ p: CGPoint) -> Double {
            guard plot.width > 0 else { return 0 }
            let f = Double((p.x - plot.minX) / plot.width)
            return Swift.min(Swift.max(f.isFinite ? f : 0, 0), 1)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, !markerLocked else { return }
            onEvent(.tapped)                      // короткий тап снимает метку
        }

        @objc func press(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                guard !markerLocked else { return }
                markerActive = true
                // Щёлкаем ТОЛЬКО здесь, никогда в `.changed`: непрерывная
                // отдача на каждом кадре — десятки щелчков в секунду.
                click.selectionChanged()
                onEvent(.markerBegan(x: g.location(in: g.view).x))
            case .changed:
                guard markerActive else { return }
                onEvent(.markerMoved(x: g.location(in: g.view).x))
            default:                              // .ended/.cancelled/.failed — ОДНА ветка
                guard markerActive else { return }
                markerActive = false
                onEvent(.markerEnded)
            }
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                panActive = true
                // Отсчёт с нуля от точки РАСПОЗНАВАНИЯ: к `.began` палец уже
                // ушёл на порог, и накопленная протяжка дёрнула бы окно.
                g.setTranslation(.zero, in: g.view)
                onEvent(.panBegan)
            case .changed:
                guard panActive, plot.width > 0 else { return }
                onEvent(.panChanged(byFraction: Double(g.translation(in: g.view).x) / plot.width))
            default:
                guard panActive else { return }
                panActive = false
                // Инерция — только у НОРМАЛЬНОГО конца: у отмены скорости нет
                // по смыслу, жест отобрали. Приход ВТОРОГО пальца тоже даёт
                // `.ended` (у панорамы максимум один палец), но это не бросок:
                // пальцы ещё на экране, и запущенная тут инерция уезжала бы
                // из-под начинающегося щипка. Отличаем по числу касаний: при
                // настоящем отрыве их к этому моменту не остаётся.
                if g.state == .ended, g.numberOfTouches == 0, plot.width > 0 {
                    startGlide(Double(g.velocity(in: g.view).x) / plot.width)
                } else {
                    onEvent(.panEnded)
                }
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                // Инерцию гасим МОЛЧА: `.panEnded` сбил бы базу щипка, который
                // как раз начинается.
                stopGlide(emitEnd: false)
                // Щипок сильнее метки: два пальца, задержанные на графике,
                // успевают взвести удержание. Запираем метку до конца КАСАНИЯ,
                // а распознаватель гасим принудительно — переключение
                // `isEnabled` переводит его в `.cancelled` немедленно. Гасить
                // вслепую нельзя: после `.began` он ЖИВ, и следующий `.changed`
                // взвёл бы метку обратно вместе со щелчком.
                markerLocked = true
                if markerActive { markerActive = false; onEvent(.markerEnded) }
                press?.isEnabled = false
                press?.isEnabled = true
                zoomActive = true
                onEvent(.zoomBegan(anchor: anchor(of: g)))
            case .changed:
                guard zoomActive else { return }
                onEvent(.zoomChanged(scale: Double(g.scale)))
            default:
                guard zoomActive else { return }
                zoomActive = false
                onEvent(.zoomEnded)
            }
        }

        /// Середина между пальцами и есть якорь: точка под пальцами обязана
        /// остаться на месте.
        private func anchor(of g: UIPinchGestureRecognizer) -> Double {
            guard g.numberOfTouches >= 2, let v = g.view else {
                return fraction(g.location(in: g.view))
            }
            let a = g.location(ofTouch: 0, in: v)
            let b = g.location(ofTouch: 1, in: v)
            return fraction(CGPoint(x: (a.x + b.x) / 2, y: 0))
        }

        /// Запрет снимается по концу ВСЕГО касания: быстрый щипок удержание
        /// вовсе не запускает, и `.ended` от него не придёт никогда.
        func sequenceEnded() { markerLocked = false }

        func forceEnd() {
            if markerActive { markerActive = false; onEvent(.markerEnded) }
            if panActive { panActive = false; onEvent(.panEnded) }
            if zoomActive { zoomActive = false; onEvent(.zoomEnded) }
            // Терминальное событие не теряется и на аварийном сбросе.
            stopGlide(emitEnd: true)
            markerLocked = false
        }

        // MARK: Инерция

        /// Затухание за миллисекунду — `UIScrollView.DecelerationRate.normal`.
        private static let decelerationPerMs = 0.998
        private static let glideStop = 0.05
        /// Потолок разгона: бросок через весь экран иначе унёс бы окно к концу
        /// истории, и человек потерял бы место, куда смотрел.
        private static let glideMax = 6.0
        private var link: CADisplayLink?
        private var velocity = 0.0
        private var time: CFTimeInterval = 0

        func startGlide(_ v0: Double) {
            stopGlide(emitEnd: false)
            let v = Swift.min(Swift.max(v0, -Self.glideMax), Self.glideMax)
            guard abs(v) > Self.glideStop else { onEvent(.panEnded); return }
            velocity = v
            time = CACurrentMediaTime()
            let l = CADisplayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func stopGlide(emitEnd: Bool) {
            guard link != nil else { return }
            link?.invalidate()
            link = nil
            velocity = 0
            if emitEnd { onEvent(.panEnded) }
        }

        @objc private func step(_ l: CADisplayLink) {
            let now = CACurrentMediaTime()
            // Зажим шага: после подвисания или ухода в фон разница бывает в
            // секунды, и окно улетело бы одним кадром.
            let dt = Swift.min(Swift.max(now - time, 0), 1.0 / 20)
            time = now
            onEvent(.glide(byFraction: velocity * dt))
            velocity *= pow(Self.decelerationPerMs, dt * 1000)
            if abs(velocity) < Self.glideStop { stopGlide(emitEnd: true) }
        }

        // MARK: Разводка конкурентов

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other is UIScreenEdgePanGestureRecognizer)
        }

        /// Решаем ОДИН раз за касание, по направлению скорости: пересмотреть
        /// посреди жеста нельзя — диагональ дёргала бы попеременно окно и
        /// список. Всем остальным распознавателям метод обязан вернуть `true`.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan, g === pan else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) >= abs(v.y)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            // Системный свайп «назад» ЖДЁТ и панораму, и удержание: пока палец
            // на графике, возврат не начинается вовсе.
            if other is UIScreenEdgePanGestureRecognizer { return g === pan || g === press }
            guard let pan, g === pan else { return false }
            // Прокрутка ждёт провала ТОЛЬКО нашей панорамы. Безусловное «да»
            // заставило бы список ждать провала УДЕРЖАНИЯ, которое при
            // неподвижном пальце не провалится никогда, и экран перестал бы
            // листаться. `List` под капотом — коллекция, то есть скролл-вью,
            // так что проверка ловит именно его.
            return other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }

    /// Распознаватель-невидимка: ничего не распознаёт, только считает пальцы.
    /// Нужен потому, что скролл-вью откладывает доставку касаний во вьюху, а
    /// при перехвате не доставляет вовсе.
    final class TouchWatch: UIGestureRecognizer {
        var onSequenceEnded: (() -> Void)?
        var onTouchBegan: (() -> Void)?
        private var active = 0

        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) {
            if active == 0 { onTouchBegan?() }
            active += t.count
            state = .failed
        }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent) { drop(t.count) }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent) { drop(t.count) }

        private func drop(_ n: Int) {
            active = Swift.max(0, active - n)
            if active == 0 { onSequenceEnded?() }
        }

        override func reset() {
            super.reset()
            // Касание может кончиться и БЕЗ touchesEnded/Cancelled — например,
            // при уходе в фон посреди жеста. Молчать здесь значит оставить метку
            // запертой до конца жизни экрана.
            if active > 0 { active = 0; onSequenceEnded?() }
        }
    }
}
