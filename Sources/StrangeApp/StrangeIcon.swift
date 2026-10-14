import AppKit

/// One vector drawing supplies the menu-bar glyph, runtime app icon, and ICNS.
enum StrangeIcon {
    enum Style: Sendable { case menuBar, application }
    enum ExportError: Error { case renderingFailed }

    static func image(style: Style) -> NSImage {
        let size: CGFloat = style == .menuBar ? 18 : 1024
        let image = NSImage(size: CGSize(width: size, height: size), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, bounds: bounds, style: style)
            return true
        }
        image.isTemplate = style == .menuBar
        image.accessibilityDescription = "Strange: nine sections inside a circle"
        return image
    }

    private static func draw(in context: CGContext, bounds: CGRect, style: Style) {
        context.saveGState()
        defer { context.restoreGState() }
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = size * (style == .menuBar ? 0.425 : 0.41)
        let stroke = style == .menuBar ? size * (1.3 / 18) : size * 0.04
        let circle = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineWidth(stroke)
        context.setLineCap(.round)

        if style == .application {
            context.setFillColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
            context.fillEllipse(in: circle)
            context.setStrokeColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        } else {
            context.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
        }

        // Clip the four straight lines to the circle, then draw its outline.
        // The symmetric offsets create three columns and three rows.
        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        for offset in [-radius / 3, radius / 3] {
            context.move(to: CGPoint(x: center.x + offset, y: circle.minY))
            context.addLine(to: CGPoint(x: center.x + offset, y: circle.maxY))
            context.move(to: CGPoint(x: circle.minX, y: center.y + offset))
            context.addLine(to: CGPoint(x: circle.maxX, y: center.y + offset))
        }
        context.strokePath()
        context.restoreGState()
        context.strokeEllipse(in: circle)
    }

    static func export(to directory: URL) throws {
        let fileManager = FileManager.default
        let iconset = directory.appendingPathComponent("Strange.iconset", isDirectory: true)
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let data = try png(pixels: points * scale, style: .application)
                try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
            }
        }
        try png(pixels: 1024, style: .application).write(to: directory.appendingPathComponent("Strange.png"), options: .atomic)
        try png(pixels: 36, style: .menuBar).write(to: directory.appendingPathComponent("Strange-menu.png"), options: .atomic)
    }

    private static func png(pixels: Int, style: Style) throws -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ExportError.renderingFailed
        }
        draw(in: context, bounds: CGRect(x: 0, y: 0, width: pixels, height: pixels), style: style)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ExportError.renderingFailed
        }
        return data
    }
}
