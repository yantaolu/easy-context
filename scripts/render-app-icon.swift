#!/usr/bin/env swift
// 生成 Easy Context 的 App 图标（全部尺寸），输出到 AppIcon.appiconset。
//
// 用法：swift scripts/render-app-icon.swift [输出目录]
// 默认输出目录：EasyContext/Assets.xcassets/AppIcon.appiconset
//
// 设计：靛紫到洋红的渐变底上，一个实心白色文件夹，正面镂空出粗大的「>_」，
// 表达「在这个文件夹里打开终端 / 编辑器 / AI 工具」。只有一个主体、底色饱和、
// 对比强烈，保证在程序坞（32–64pt）里依然清晰可辨。
// 全部用 CoreGraphics 矢量绘制，每个尺寸单独渲染；修改颜色或细节后重新运行即可。
//
// 坐标约定：设计画布 1024×1024，原点左上；图标主体 824×824（x/y 100…924），
// 圆角 185，与 macOS 图标网格一致，四周留白用于投影。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!
/// 阴影的 offset / blur 位于设备空间、不随 CTM 缩放，需按输出尺寸手动缩放。
var shadowScale: CGFloat = 1

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
}
func gradient(_ stops: [(CGFloat, UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { rgb($0.1, $0.2) } as CFArray, locations: stops.map(\.0))!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

extension CGContext {
    /// 设计坐标 y 向下；位图上下翻转后阴影 y 方向随之翻转。
    func glow(dy: CGFloat = 0, blur: CGFloat, _ color: CGColor) {
        setShadow(offset: CGSize(width: 0, height: -dy * shadowScale), blur: blur * shadowScale, color: color)
    }
    func fill(_ path: CGPath, _ g: CGGradient, _ from: CGPoint, _ to: CGPoint) {
        saveGState(); addPath(path); clip()
        drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)

// MARK: - 图形

/// 实心文件夹轮廓：左上带标签。
func folderGlyph() -> CGPath {
    let x: CGFloat = 222, y: CGFloat = 282, w: CGFloat = 580, h: CGFloat = 456, r: CGFloat = 54
    let tabW: CGFloat = 230, tabH: CGFloat = 50
    let p = CGMutablePath()
    p.move(to: pt(x, y + r))
    p.addArc(tangent1End: pt(x, y), tangent2End: pt(x + r, y), radius: r)
    p.addLine(to: pt(x + tabW - tabH, y))
    p.addCurve(to: pt(x + tabW + tabH * 0.4, y + tabH), control1: pt(x + tabW - tabH * 0.2, y),
               control2: pt(x + tabW - tabH * 0.1, y + tabH))
    p.addLine(to: pt(x + w - r, y + tabH))
    p.addArc(tangent1End: pt(x + w, y + tabH), tangent2End: pt(x + w, y + tabH + r), radius: r)
    p.addLine(to: pt(x + w, y + h - r))
    p.addArc(tangent1End: pt(x + w, y + h), tangent2End: pt(x + w - r, y + h), radius: r)
    p.addLine(to: pt(x + r, y + h))
    p.addArc(tangent1End: pt(x, y + h), tangent2End: pt(x, y + h - r), radius: r)
    p.closeSubpath()
    return p
}

/// 要从文件夹上镂空的「>_」轮廓（粗描边转为填充路径后与下划线合并）。
func promptCutout() -> CGPath {
    let chevron = CGMutablePath()
    chevron.move(to: pt(372, 430)); chevron.addLine(to: pt(468, 520)); chevron.addLine(to: pt(372, 610))
    let outline = chevron.copy(strokingWithWidth: 62, lineCap: .round, lineJoin: .round, miterLimit: 10)
    return outline.union(rounded(CGRect(x: 520, y: 580, width: 150, height: 60), 30))
}

// MARK: - 图标

func drawIcon(_ ctx: CGContext) {
    // 外形投影
    ctx.saveGState(); ctx.glow(dy: 18, blur: 40, rgb(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(); ctx.restoreGState()

    // 背景：靛紫 → 紫 → 洋红，左上叠一层柔光增加立体感
    ctx.fill(bodyPath, gradient([(0, 0x818CF8, 1), (0.5, 0x8B5CF6, 1), (1, 0xDB2777, 1)]), pt(160, 120), pt(864, 904))
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
    ctx.drawRadialGradient(gradient([(0, 0xFFFFFF, 0.28), (1, 0xFFFFFF, 0)]),
                           startCenter: pt(400, 120), startRadius: 0, endCenter: pt(400, 120), endRadius: 640, options: [])

    // 文件夹减去提示符（布尔运算镂空，底色从镂空处透出）。
    // 不用奇偶填充：粗描边在尖角处自身重叠，奇偶规则会在那里留下小三角。
    let glyph = folderGlyph().subtracting(promptCutout())
    ctx.saveGState(); ctx.glow(dy: 20, blur: 44, rgb(0x0B1030, 0.30))
    ctx.addPath(glyph); ctx.setFillColor(rgb(0xF1E8FF)); ctx.fillPath(); ctx.restoreGState()
    ctx.fill(glyph, gradient([(0, 0xFFFFFF, 1), (1, 0xF1E8FF, 1)]), pt(512, 282), pt(512, 738))
    // 一条极淡的横线暗示文件夹前板，保持实心剪影的简洁
    ctx.saveGState(); ctx.addPath(glyph); ctx.clip()
    ctx.setFillColor(rgb(0x000000, 0.06)); ctx.fill(CGRect(x: 222, y: 360, width: 580, height: 6))
    ctx.restoreGState()
    ctx.restoreGState()

    // 外形内描边高光：让边缘在浅色、深色桌面上都清晰
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
    ctx.addPath(bodyPath); ctx.setLineWidth(6); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, 0xFFFFFF, 0.35), (1, 0xFFFFFF, 0.03)]),
                           start: pt(512, 100), end: pt(512, 924), options: [])
    ctx.restoreGState()
}

// MARK: - 输出

func render(size: Int, to url: URL) throws {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw NSError(domain: "render-app-icon", code: 1) }
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    shadowScale = CGFloat(size) / 1024
    drawIcon(ctx)
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "render-app-icon", code: 2) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "render-app-icon", code: 3) }
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : scriptDir.appendingPathComponent("../EasyContext/Assets.xcassets/AppIcon.appiconset").standardizedFileURL

// 文件名与 AppIcon.appiconset/Contents.json 一致。
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let url = outDir.appendingPathComponent("icon_\(size).png")
    try render(size: size, to: url)
    print("wrote \(url.path)")
}
