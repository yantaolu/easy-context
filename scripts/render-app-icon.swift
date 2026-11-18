#!/usr/bin/env swift
// 生成 Easy Context 的 App 图标（全部尺寸），输出到 AppIcon.appiconset。
//
// 用法：swift scripts/render-app-icon.swift [输出目录]
// 默认输出目录：EasyContext/Assets.xcassets/AppIcon.appiconset
//
// 设计：浅天蓝到浅紫的底色上，一个 macOS 风格的蓝色文件夹（代表访达），右下角弹出
// 一张白色右键菜单，三行分别是终端（>_）、编辑器（</>，品牌色高亮）、AI（四角星）。
// 表达「访达右键菜单扩展：把文件夹连到编辑器、终端与 AI 工具」，而不是终端本身。
// 文件夹与菜单两个大块在程序坞（32–64pt）尺寸下依然可辨。
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
    func fill(_ path: CGPath, _ color: CGColor) { addPath(path); setFillColor(color); fillPath() }
    func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
        addPath(path); setStrokeColor(color); setLineWidth(width); setLineCap(.round); setLineJoin(.round); strokePath()
    }
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)

// MARK: - 文件夹（macOS 风格：带标签的后板 + 前板）

func folderBack(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, tabW: CGFloat, tabH: CGFloat, r: CGFloat) -> CGPath {
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

func drawFolder(_ ctx: CGContext) {
    let x: CGFloat = 168, y: CGFloat = 236, w: CGFloat = 560, h: CGFloat = 440
    let back = folderBack(x, y, w, h, tabW: 220, tabH: 48, r: 50)
    ctx.saveGState(); ctx.glow(dy: 18, blur: 40, rgb(0x0B1030, 0.30)); ctx.fill(back, rgb(0x1E7FE0)); ctx.restoreGState()
    ctx.fill(back, gradient([(0, 0x3FA9F5, 1), (1, 0x1D74D8, 1)]), pt(x, y), pt(x, y + h))
    // 前板比后板矮一截，形成文件夹开口
    let front = rounded(CGRect(x: x, y: y + 96, width: w, height: h - 96), 50)
    ctx.saveGState(); ctx.glow(dy: -6, blur: 24, rgb(0x0B3A80, 0.30)); ctx.fill(front, rgb(0x2F8FEA)); ctx.restoreGState()
    ctx.fill(front, gradient([(0, 0x74C6FF, 1), (1, 0x2B86E6, 1)]), pt(x, y + 96), pt(x, y + h))
    ctx.saveGState(); ctx.addPath(front); ctx.clip()
    ctx.fill(CGPath(rect: CGRect(x: x, y: y + 96, width: w, height: 5), transform: nil), rgb(0xFFFFFF, 0.55))
    ctx.restoreGState()
}

// MARK: - 右键菜单

func chevron(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, left: Bool = false) -> CGPath {
    let p = CGMutablePath(), w = h * 0.5
    if left { p.move(to: pt(x + w, y)); p.addLine(to: pt(x, y + h / 2)); p.addLine(to: pt(x + w, y + h)) }
    else { p.move(to: pt(x, y)); p.addLine(to: pt(x + w, y + h / 2)); p.addLine(to: pt(x, y + h)) }
    return p
}

/// 四角星：c 为中心，r 为外半径。
func sparkle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath(), k = r * 0.16
    p.move(to: pt(c.x, c.y - r))
    p.addQuadCurve(to: pt(c.x + r, c.y), control: pt(c.x + k, c.y - k))
    p.addQuadCurve(to: pt(c.x, c.y + r), control: pt(c.x + k, c.y + k))
    p.addQuadCurve(to: pt(c.x - r, c.y), control: pt(c.x - k, c.y + k))
    p.addQuadCurve(to: pt(c.x, c.y - r), control: pt(c.x - k, c.y - k))
    p.closeSubpath()
    return p
}

enum Tool { case terminal, editor, ai }

/// 菜单行左侧的工具符号，c 为中心。
func toolGlyph(_ ctx: CGContext, _ tool: Tool, _ c: CGPoint, _ color: CGColor) {
    switch tool {
    case .terminal: // >_
        ctx.stroke(chevron(c.x - 24, c.y - 20, 40), color, 11)
        ctx.fill(rounded(CGRect(x: c.x + 2, y: c.y + 12, width: 26, height: 10), 5), color)
    case .editor: // </>
        ctx.stroke(chevron(c.x - 34, c.y - 18, 36, left: true), color, 10)
        ctx.stroke(chevron(c.x + 16, c.y - 18, 36), color, 10)
        let slash = CGMutablePath(); slash.move(to: pt(c.x + 7, c.y - 20)); slash.addLine(to: pt(c.x - 7, c.y + 20))
        ctx.stroke(slash, color, 9)
    case .ai:
        ctx.fill(sparkle(c, 26), color)
    }
}

func drawMenu(_ ctx: CGContext) {
    let card = CGRect(x: 448, y: 470, width: 436, height: 382)
    let cardPath = rounded(card, 56)
    ctx.saveGState(); ctx.glow(dy: 24, blur: 54, rgb(0x0B1030, 0.30)); ctx.fill(cardPath, rgb(0xFFFFFF)); ctx.restoreGState()
    ctx.fill(cardPath, gradient([(0, 0xFFFFFF, 1), (1, 0xF3F4FA, 1)]), pt(card.midX, card.minY), pt(card.midX, card.maxY))

    let pad: CGFloat = 30, rowH: CGFloat = 96, gap: CGFloat = (card.height - 2 * pad - 3 * rowH) / 2
    let rows: [(tool: Tool, highlighted: Bool, color: UInt32, barLength: CGFloat)] = [
        (.terminal, false, 0x334155, 0.72),
        (.editor, true, 0xFFFFFF, 0.9),
        (.ai, false, 0x8B5CF6, 0.72),
    ]
    for (i, item) in rows.enumerated() {
        let row = CGRect(x: card.minX + pad, y: card.minY + pad + CGFloat(i) * (rowH + gap),
                         width: card.width - 2 * pad, height: rowH)
        let bar = rounded(CGRect(x: row.minX + 116, y: row.midY - 12,
                                 width: (row.width - 150) * item.barLength, height: 24), 12)
        if item.highlighted {
            // 高亮行：品牌色（紫 → 洋红），整个图标唯一的鲜艳色块
            let pill = rounded(row, 34)
            ctx.saveGState(); ctx.glow(dy: 8, blur: 22, rgb(0x8B5CF6, 0.45)); ctx.fill(pill, rgb(0x8B5CF6)); ctx.restoreGState()
            ctx.fill(pill, gradient([(0, 0x8B5CF6, 1), (1, 0xDB2777, 1)]), pt(row.minX, row.midY), pt(row.maxX, row.midY))
            ctx.fill(bar, rgb(0xFFFFFF, 0.9))
        } else {
            ctx.fill(bar, rgb(0xCBD5E1))
        }
        toolGlyph(ctx, item.tool, pt(row.minX + 58, row.midY), rgb(item.color))
    }
}

// MARK: - 图标

func drawIcon(_ ctx: CGContext) {
    // 外形投影
    ctx.saveGState(); ctx.glow(dy: 18, blur: 40, rgb(0x000000, 0.35)); ctx.fill(bodyPath, rgb(0x000000)); ctx.restoreGState()

    // 背景：浅天蓝 → 浅靛 → 浅紫，左上叠一层柔光
    ctx.fill(bodyPath, gradient([(0, 0xC6E2FB, 1), (0.5, 0xCCD2FB, 1), (1, 0xDCC8F7, 1)]), pt(160, 120), pt(864, 904))
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
    ctx.drawRadialGradient(gradient([(0, 0xFFFFFF, 0.45), (1, 0xFFFFFF, 0)]),
                           startCenter: pt(400, 120), startRadius: 0, endCenter: pt(400, 120), endRadius: 640, options: [])
    drawFolder(ctx)
    drawMenu(ctx)
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
