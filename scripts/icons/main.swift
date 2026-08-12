import AppKit
import CoreGraphics
import Foundation

// Значки приложения. Рисуются кодом, а не в редакторе: пять вариантов на одной
// палитре и одной геометрии, любой можно поправить на пункт и пересобрать.
// Формат App Store: 1024×1024, БЕЗ прозрачности и БЕЗ скруглений — маску
// накладывает система (на контрольном листе она нарисована для наглядности).

let S: CGFloat = 1024
let out = ("~/projects/libra-scale/icons" as NSString).expandingTildeInPath
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// Палитра приложения.
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let blue = rgb(0x0A84FF)
let blueDeep = rgb(0x0040A8)
let green = rgb(0x30D158)
let white = rgb(0xFFFFFF)
let inkTop = rgb(0x16202F)      // тёмный фон значка: не чёрный квадрат,
let inkBottom = rgb(0x080B12)   // иначе на тёмных обоях значок «исчезает»
let track = rgb(0x2C2C2E)

func ctx() -> CGContext {
    let c = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setAllowsAntialiasing(true)
    c.interpolationQuality = .high
    return c
}

func gradient(_ c: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint,
              locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                       colors: colors as CFArray, locations: locations)!
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation,
                                                            .drawsAfterEndLocation])
}

func fillBackground(_ c: CGContext, _ colors: [CGColor]) {
    c.saveGState()
    c.clip(to: CGRect(x: 0, y: 0, width: S, height: S))
    gradient(c, colors, from: CGPoint(x: 0, y: S), to: CGPoint(x: 0, y: 0))
    c.restoreGState()
}

/// Точки кривой веса — одна и та же ломаная во всех вариантах, чтобы значки
/// смотрелись одной семьёй. Координаты в долях 0…1, начало снизу слева.
let curve: [CGPoint] = [
    CGPoint(x: 0.00, y: 0.82), CGPoint(x: 0.14, y: 0.72), CGPoint(x: 0.26, y: 0.80),
    CGPoint(x: 0.38, y: 0.62), CGPoint(x: 0.52, y: 0.66), CGPoint(x: 0.64, y: 0.46),
    CGPoint(x: 0.78, y: 0.50), CGPoint(x: 1.00, y: 0.30),
]

func curvePath(in r: CGRect) -> CGMutablePath {
    let p = CGMutablePath()
    for (i, pt) in curve.enumerated() {
        let q = CGPoint(x: r.minX + pt.x * r.width, y: r.minY + pt.y * r.height)
        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
    }
    return p
}

func save(_ c: CGContext, _ name: String) {
    let img = c.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    let path = out + "/" + name
    try! data.write(to: URL(fileURLWithPath: path))
    print("→", path)
}

// MARK: 1. Циферблат — тот же значок, что рисует само приложение

func icon1() -> CGContext {
    let c = ctx()
    fillBackground(c, [inkTop, inkBottom])
    let center = CGPoint(x: S / 2, y: S / 2)

    c.setLineWidth(62)
    c.setStrokeColor(blue)
    c.addArc(center: center, radius: 300, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.strokePath()

    // Стрелка из центра вправо-вверх — как на циферблате весов.
    c.setLineCap(.round)
    c.setLineWidth(72)
    c.setStrokeColor(white)
    c.move(to: center)
    c.addLine(to: CGPoint(x: center.x + 168, y: center.y + 158))
    c.strokePath()

    c.setFillColor(white)
    c.addArc(center: center, radius: 52, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.fillPath()
    return c
}

// MARK: 2. Кривая веса

func icon2() -> CGContext {
    let c = ctx()
    fillBackground(c, [inkTop, inkBottom])
    let r = CGRect(x: 150, y: 250, width: S - 300, height: 500)

    // Заливка под кривой — как на графике в приложении.
    let area = curvePath(in: r).mutableCopy()!
    area.addLine(to: CGPoint(x: r.maxX, y: 120))
    area.addLine(to: CGPoint(x: r.minX, y: 120))
    area.closeSubpath()
    c.saveGState()
    c.addPath(area)
    c.clip()
    gradient(c, [rgb(0x0A84FF, 0.55), rgb(0x0A84FF, 0)],
             from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: 120))
    c.restoreGState()

    // Пунктир цели.
    c.saveGState()
    c.setLineWidth(18)
    c.setLineCap(.round)
    c.setStrokeColor(green)
    c.setLineDash(phase: 0, lengths: [40, 46])
    c.move(to: CGPoint(x: r.minX, y: 190))
    c.addLine(to: CGPoint(x: r.maxX, y: 190))
    c.strokePath()
    c.restoreGState()

    c.setLineWidth(70)
    c.setLineJoin(.round)
    c.setLineCap(.round)
    c.setStrokeColor(blue)
    c.addPath(curvePath(in: r))
    c.strokePath()

    // Точка «вы здесь» на конце.
    let end = CGPoint(x: r.maxX, y: r.minY + curve[curve.count - 1].y * r.height)
    c.setFillColor(white)
    c.addArc(center: end, radius: 62, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.fillPath()
    c.setFillColor(blue)
    c.addArc(center: end, radius: 34, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.fillPath()
    return c
}

// MARK: 3. Монограмма QN — по названию протокола ищут в App Store

func icon3() -> CGContext {
    let c = ctx()
    fillBackground(c, [rgb(0x2A9BFF), blueDeep])

    let nsCtx = NSGraphicsContext(cgContext: c, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    var font = NSFont.systemFont(ofSize: 400, weight: .bold)
    if let rounded = NSFont.systemFont(ofSize: 400, weight: .bold).fontDescriptor
        .withDesign(.rounded) {
        font = NSFont(descriptor: rounded, size: 400) ?? font
    }
    let text = NSAttributedString(string: "QN", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -14,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (S - size.width) / 2, y: (S - size.height) / 2 + 12))
    NSGraphicsContext.restoreGraphicsState()

    // Подчёркивание-кривая: значок остаётся про вес, а не про две буквы.
    // Точек мало и линия толстая — на 60 пунктах мелкая ломаная сливалась
    // в кляксу.
    c.setLineWidth(38)
    c.setLineJoin(.round)
    c.setLineCap(.round)
    c.setStrokeColor(rgb(0xFFFFFF, 0.92))
    c.move(to: CGPoint(x: 322, y: 268))
    c.addLine(to: CGPoint(x: 460, y: 232))
    c.addLine(to: CGPoint(x: 580, y: 252))
    c.addLine(to: CGPoint(x: 702, y: 206))
    c.strokePath()
    return c
}

// MARK: 4. Кольцо цели

func icon4() -> CGContext {
    let c = ctx()
    fillBackground(c, [inkTop, inkBottom])
    let center = CGPoint(x: S / 2, y: S / 2)
    let radius: CGFloat = 300

    c.setLineWidth(84)
    c.setStrokeColor(track)
    c.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.strokePath()

    // Пройденный путь — от верха по часовой стрелке.
    c.setLineCap(.round)
    c.setStrokeColor(blue)
    c.addArc(center: center, radius: radius, startAngle: .pi / 2,
             endAngle: .pi / 2 - .pi * 1.55, clockwise: true)
    c.strokePath()

    // Хвост кольца зелёный — цель, к которой идут.
    c.setStrokeColor(green)
    c.addArc(center: center, radius: radius, startAngle: .pi / 2 - .pi * 1.36,
             endAngle: .pi / 2 - .pi * 1.55, clockwise: true)
    c.strokePath()

    // Внутри — стрелка вниз: вес снижается.
    c.setLineWidth(64)
    c.setLineJoin(.round)
    c.setStrokeColor(white)
    c.move(to: CGPoint(x: center.x, y: center.y + 130))
    c.addLine(to: CGPoint(x: center.x, y: center.y - 120))
    c.strokePath()
    c.move(to: CGPoint(x: center.x - 92, y: center.y - 30))
    c.addLine(to: CGPoint(x: center.x, y: center.y - 126))
    c.addLine(to: CGPoint(x: center.x + 92, y: center.y - 30))
    c.strokePath()
    return c
}

// MARK: 5. Кривая в кольце

func icon5() -> CGContext {
    let c = ctx()
    fillBackground(c, [blue, blueDeep])

    let center = CGPoint(x: S / 2, y: S / 2)
    c.setLineWidth(54)
    c.setStrokeColor(rgb(0xFFFFFF, 0.9))
    c.addArc(center: center, radius: 316, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.strokePath()

    c.saveGState()
    c.addArc(center: center, radius: 316 - 27, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    c.clip()
    c.setLineWidth(66)
    c.setLineJoin(.round)
    c.setLineCap(.round)
    c.setStrokeColor(white)
    c.addPath(curvePath(in: CGRect(x: 296, y: 402, width: 432, height: 240)))
    c.strokePath()
    c.restoreGState()
    return c
}

// MARK: Контрольный лист

let icons: [(String, CGContext)] = [
    ("1 — циферблат", icon1()),
    ("2 — кривая веса", icon2()),
    ("3 — монограмма QN", icon3()),
    ("4 — кольцо цели", icon4()),
    ("5 — кривая в кольце", icon5()),
]

for (i, item) in icons.enumerated() {
    save(item.1, "icon-\(i + 1).png")
}

// Лист со всеми пятью — со скруглением, как на домашнем экране, и с крупным
// и мелким размером рядом: значок обязан читаться на 60 пунктах.
do {
    let cell: CGFloat = 300
    let small: CGFloat = 120
    let pad: CGFloat = 46
    let rowH = cell + 110
    let labelWidth = icons.map {
        NSAttributedString(string: $0.0, attributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .semibold)
        ]).size().width
    }.max() ?? 600
    let W = pad + cell + 40 + small + 60 + labelWidth + pad
    let H = pad + rowH * CGFloat(icons.count)
    let c = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8,
                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(rgb(0x111114))
    c.fill(CGRect(x: 0, y: 0, width: W, height: H))

    let nsCtx = NSGraphicsContext(cgContext: c, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    for (i, item) in icons.enumerated() {
        let y = H - pad - rowH * CGFloat(i + 1) + 96
        let img = item.1.makeImage()!

        func draw(_ rect: CGRect) {
            c.saveGState()
            // Скругление iOS — примерно 22,4 % стороны.
            c.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width * 0.224,
                             cornerHeight: rect.width * 0.224, transform: nil))
            c.clip()
            c.draw(img, in: rect)
            c.restoreGState()
        }
        draw(CGRect(x: pad, y: y, width: cell, height: cell))
        draw(CGRect(x: pad + cell + 40, y: y + (cell - small) / 2, width: small, height: small))

        let label = NSAttributedString(string: item.0, attributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        label.draw(at: NSPoint(x: pad + cell + 40 + small + 60, y: y + cell / 2 - 26))
    }
    NSGraphicsContext.restoreGraphicsState()
    save(c, "icons-preview.png")
}
