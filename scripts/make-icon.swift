// 生成 Resources/AppIcon.icns：swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // 底板：macOS 图标网格 824×824，圆角约 185
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        NSColor(srgbRed: 0.925, green: 0.937, blue: 0.957, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    NSColor.black.withAlphaComponent(0.08).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    rim.lineWidth = 3
    rim.stroke()

    // Markdown 标记：M + 向下箭头
    let glyph = NSBezierPath()
    glyph.lineWidth = 70
    glyph.lineCapStyle = .round
    glyph.lineJoinStyle = .round
    glyph.move(to: NSPoint(x: 272, y: 352))
    glyph.line(to: NSPoint(x: 272, y: 672))
    glyph.line(to: NSPoint(x: 397, y: 527))
    glyph.line(to: NSPoint(x: 522, y: 672))
    glyph.line(to: NSPoint(x: 522, y: 352))
    glyph.move(to: NSPoint(x: 682, y: 672))
    glyph.line(to: NSPoint(x: 682, y: 372))
    glyph.move(to: NSPoint(x: 597, y: 457))
    glyph.line(to: NSPoint(x: 682, y: 362))
    glyph.line(to: NSPoint(x: 767, y: 457))

    ctx.saveGState()
    ctx.addPath(glyph.cgPath.copy(strokingWithWidth: 70, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.27, green: 0.55, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.14, green: 0.38, blue: 0.92, alpha: 1),
    ])!.draw(in: NSRect(x: 200, y: 300, width: 624, height: 420), angle: -90)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = drawIcon(size: px).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "已生成 \(output)" : "iconutil 失败")
