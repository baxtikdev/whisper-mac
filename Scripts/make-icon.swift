import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let side = 1024
let canvas = CGFloat(side)

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: rep)
else { fatalError("bitmap") }

NSGraphicsContext.current = context
let cg = context.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: space,
        colors: stops.map { color($0.0, $0.1) } as CFArray,
        locations: stops.map(\.2)
    )!
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.5))
cg.addPath(tilePath)
cg.setFillColor(color(0x0A0A0A))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(tilePath)
cg.clip()
cg.drawLinearGradient(
    gradient([(0x2A2A2C, 1, 0), (0x121213, 1, 0.45), (0x050505, 1, 1)]),
    start: CGPoint(x: canvas / 2, y: tile.maxY),
    end: CGPoint(x: canvas / 2, y: tile.minY),
    options: []
)
cg.drawRadialGradient(
    gradient([(0xFFFFFF, 0.07, 0), (0xFFFFFF, 0, 1)]),
    startCenter: CGPoint(x: canvas / 2, y: canvas / 2 + 60), startRadius: 0,
    endCenter: CGPoint(x: canvas / 2, y: canvas / 2 + 60), endRadius: 420,
    options: []
)
cg.restoreGState()

cg.saveGState()
cg.addPath(tilePath)
cg.setStrokeColor(color(0xFFFFFF, 0.1))
cg.setLineWidth(3)
cg.strokePath()
cg.restoreGState()

let heights: [CGFloat] = [170, 330, 480, 600, 450, 300, 160]
let barWidth: CGFloat = 62
let gap: CGFloat = 26
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (canvas - total) / 2
let bars = CGMutablePath()
for height in heights {
    let rect = CGRect(x: x, y: canvas / 2 - height / 2, width: barWidth, height: height)
    bars.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    x += barWidth + gap
}

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x000000, 0.8))
cg.addPath(bars)
cg.setFillColor(color(0x8A8A8E))
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(bars)
cg.clip()
cg.drawLinearGradient(
    gradient([(0xF4F4F6, 1, 0), (0xB9B9BE, 1, 0.38), (0x6E6E74, 1, 0.62), (0xD8D8DC, 1, 0.82), (0x9A9A9F, 1, 1)]),
    start: CGPoint(x: canvas / 2 - 160, y: canvas / 2 + 320),
    end: CGPoint(x: canvas / 2 + 160, y: canvas / 2 - 320),
    options: []
)
cg.restoreGState()

cg.saveGState()
cg.addPath(bars)
cg.clip()
cg.translateBy(x: 0, y: -10)
cg.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
cg.addPath(bars)
cg.setFillColor(color(0xFFFFFF, 0.55))
cg.fillPath(using: .evenOdd)
cg.restoreGState()

cg.saveGState()
cg.addPath(bars)
cg.setStrokeColor(color(0x000000, 0.35))
cg.setLineWidth(2)
cg.strokePath()
cg.restoreGState()

NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: output))
