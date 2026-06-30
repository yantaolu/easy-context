import AppKit

// 用法：makebg.swift <iconPath> <outPath>
let iconPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

// 逻辑窗口 660x540，输出 @2x = 1320x1080
let scale: CGFloat = 2
let W: CGFloat = 660, H: CGFloat = 545
let pxW = Int(W*scale), pxH = Int(H*scale)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 坐标：AppKit 原点在左下；以下用「从顶部算」的辅助
func topY(_ y: CGFloat) -> CGFloat { H - y }

// 背景：淡雅渐变
let bg = NSGradient(colors: [
    NSColor(srgbRed: 0.95, green: 0.96, blue: 0.99, alpha: 1),
    NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

_ = iconPath // 不再在背景里画图标（窗口顶部留白）

func drawText(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, alpha: CGFloat = 1) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: style]
    let s = NSAttributedString(string: text, attributes: attrs)
    let h = s.size().height
    s.draw(in: NSRect(x: 0, y: topY(y + h), width: W, height: h))
}

// 标题
drawText("Easy Context", y: 36, size: 28, weight: .bold,
         color: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.18, alpha: 1))
// ① 先看安装说明（橙色引导注意力，指向下方的说明文件）
drawText("① 首次使用，请先阅读下方「安装说明（必读）」", y: 84, size: 13, weight: .medium,
         color: NSColor(srgbRed: 0.85, green: 0.45, blue: 0.10, alpha: 1))
// ② 拖拽提示（在箭头上方）
drawText("② 把 EasyContext 拖到「应用程序」", y: 306, size: 13, weight: .medium,
         color: NSColor(srgbRed: 0.45, green: 0.47, blue: 0.55, alpha: 1))

// 箭头（与 app / Applications 同一行 y≈458）
let arrowY = topY(398)
let arrowColor = NSColor(srgbRed: 0.42, green: 0.40, blue: 0.92, alpha: 1)
arrowColor.setStroke(); arrowColor.setFill()
let p = NSBezierPath()
p.lineWidth = 6
p.lineCapStyle = .round
p.move(to: NSPoint(x: 286, y: arrowY))
p.line(to: NSPoint(x: 374, y: arrowY))
p.stroke()
// 箭头头部
let head = NSBezierPath()
head.move(to: NSPoint(x: 392, y: arrowY))
head.line(to: NSPoint(x: 368, y: arrowY + 13))
head.line(to: NSPoint(x: 368, y: arrowY - 13))
head.close(); head.fill()

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(pxW)x\(pxH))")
