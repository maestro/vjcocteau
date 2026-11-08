#!/usr/bin/env swift
// VJ Cocteau のアプリアイコン(1024x1024 PNG)を CoreGraphics で生成します。
// 使い方: swift scripts/make-icon.swift [出力パス]
//   既定の出力先は Resources/AppIcon.png です。
// 続けて .icns を作るには、次のコマンドを実行します。
//   ICONSET=$(mktemp -d)/AppIcon.iconset && mkdir -p "$ICONSET"
//   for s in 16 32 128 256 512; do
//     sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png"
//     sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png"
//   done
//   iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

// 出力先: 引数があればそれを、なければこのスクリプトの一つ上(リポジトリ直下)の Resources/AppIcon.png を使います。
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // scripts/
    .deletingLastPathComponent()  // リポジトリ直下
let outURL: URL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repoRoot.appendingPathComponent("Resources/AppIcon.png")

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("CGContext の作成に失敗しました。")
}

// 角丸正方形(macOS 風, 半径は一辺の約18%)の外側は透明にします。
let bounds = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius = size * 0.18
ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
ctx.clip()

// 背景: 上が明るい紺、下が暗い紺の縦グラデーション。
let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgba(0.10, 0.13, 0.30, 1), rgba(0.02, 0.03, 0.09, 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bgGradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// 2 つのデッキを表す円(Deck A: マゼンタ, Deck B: ブルー)を加算合成で重ねます。
// 重なった部分は両方の光が足し合わされ、明るく輝きます。
let radius: CGFloat = 230
let deckA = CGPoint(x: 400, y: 512)
let deckB = CGPoint(x: 624, y: 512)
let magenta = (r: CGFloat(1.0), g: CGFloat(0.18), b: CGFloat(0.84))
let blue = (r: CGFloat(0.16), g: CGFloat(0.48), b: CGFloat(1.0))

func drawDeck(center: CGPoint, color: (r: CGFloat, g: CGFloat, b: CGFloat)) {
    let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.setShadow(offset: .zero, blur: 70, color: rgba(color.r, color.g, color.b, 0.9))
    ctx.addEllipse(in: circle)
    ctx.clip()
    // 中心が濃く、縁に向かって薄くなる放射グラデーション。
    let fill = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgba(color.r, color.g, color.b, 0.85), rgba(color.r, color.g, color.b, 0.25)] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(fill,
                           startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // 縁を細い線で描いて輪郭をはっきりさせます。
    ctx.saveGState()
    ctx.setStrokeColor(rgba(color.r, color.g, color.b, 0.95))
    ctx.setLineWidth(10)
    ctx.addEllipse(in: circle.insetBy(dx: 5, dy: 5))
    ctx.strokePath()
    ctx.restoreGState()
}

drawDeck(center: deckA, color: magenta)
drawDeck(center: deckB, color: blue)

// 交差部分の中心に、白く光るコアを置きます。
let mid = CGPoint(x: (deckA.x + deckB.x) / 2, y: 512)
let core = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgba(1, 1, 1, 1), rgba(1, 0.9, 1, 0.0)] as CFArray,
    locations: [0, 1])!
ctx.saveGState()
ctx.setBlendMode(.plusLighter)
ctx.drawRadialGradient(core,
                       startCenter: mid, startRadius: 0,
                       endCenter: mid, endRadius: 120,
                       options: [])
ctx.restoreGState()

// PNG として書き出します。
guard let image = ctx.makeImage() else {
    fatalError("画像の作成に失敗しました。")
}
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("出力先を作成できませんでした: \(outURL.path)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fatalError("PNG の書き出しに失敗しました: \(outURL.path)")
}
print("作成しました: \(outURL.path)")
