import AppKit
import MetalKit
import SwiftUI

// 使い方: swift run VJCocteau [動画1 動画2 ... 動画8]
// 引数の動画は、Deck A の Bank 01 の Layer 1, 2, ... のスロット1へ割り当て、ON にします。省略できます。
let clipURLs = CommandLine.arguments.dropFirst().prefix(Layer.count).map { URL(fileURLWithPath: $0) }

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Output Window。位置と見た目は、出力先の設定に合わせて AppController が決めます。
let window = OutputWindow(
    contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered, defer: false)

let view = MTKView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
guard let renderer = Renderer(view: view) else {
    FileHandle.standardError.write(Data("Metal の初期化に失敗しました\n".utf8))
    exit(1)
}
let controller = AppController(renderer: renderer)
controller.outputWindow = window
window.delegate = controller
window.contentView = view
for (index, url) in clipURLs.enumerated() {
    guard controller.loadClip(url, bank: renderer.decks[0].bank, layer: index, slot: 0) else {
        FileHandle.standardError.write(Data("動画を開けませんでした: \(url.path)\n".utf8))
        exit(1)
    }
    renderer.decks[0].bank.layers[index].slots[0].setOn(true)
}
controller.applyOutput()

// 操作用ウィンドウ。出力先とは別のディスプレイ(内蔵を優先)の中央に置きます。暗いテーマで、タイトルバーを背景に溶け込ませます。
let controlWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 900),
    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
    backing: .buffered, defer: false)
controlWindow.title = "VJ Cocteau Control"
controlWindow.titlebarAppearsTransparent = true
controlWindow.titleVisibility = .hidden
controlWindow.appearance = NSAppearance(named: .darkAqua)
controlWindow.backgroundColor = NSColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1)
controlWindow.isMovableByWindowBackground = true
let hosting = NSHostingView(rootView: ControlView(controller: controller, settings: renderer.settings, apc: controller.apc))
controlWindow.contentView = hosting
controlWindow.setContentSize(hosting.fittingSize)
if let screen = controller.controlScreen {
    let size = controlWindow.frame.size
    let area = screen.visibleFrame
    controlWindow.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: max(area.minY, area.midY - size.height / 2)))
}
controlWindow.delegate = controller

// メニュー。キー: 1〜3 で Fit Mode、4〜7 で Output Resolution、Cmd+1〜8 で Edit Layer。
let mainMenu = NSMenu()
func addMenu(_ title: String, _ build: (NSMenu) -> Void) {
    let item = NSMenuItem(); mainMenu.addItem(item)
    let menu = NSMenu(title: title); item.submenu = menu
    build(menu)
}
addMenu("VJ Cocteau") { menu in
    menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
}
addMenu("表示") { menu in
    let full = menu.addItem(withTitle: "フルスクリーン切り替え", action: #selector(AppController.toggleFullScreen(_:)), keyEquivalent: "f")
    full.target = controller
    let outputItem = NSMenuItem(title: "出力ディスプレイ", action: nil, keyEquivalent: "")
    let outputMenu = NSMenu(title: "出力ディスプレイ")
    outputMenu.delegate = controller
    outputItem.submenu = outputMenu
    menu.addItem(outputItem)
    menu.addItem(.separator())
    for (i, mode) in FitMode.allCases.enumerated() {
        let item = menu.addItem(withTitle: "Fit Mode: \(mode.title)", action: #selector(AppController.selectFit(_:)), keyEquivalent: "\(i + 1)")
        item.tag = Int(mode.rawValue); item.target = controller
        item.keyEquivalentModifierMask = []
    }
    menu.addItem(.separator())
    for (i, res) in OutputResolution.allCases.enumerated() {
        let item = menu.addItem(withTitle: "Output Resolution: \(res.title)", action: #selector(AppController.selectResolution(_:)), keyEquivalent: "\(i + 4)")
        item.tag = res.rawValue; item.target = controller
        item.keyEquivalentModifierMask = []
    }
}
addMenu("Layer") { menu in
    for index in 0..<Layer.count {
        let item = menu.addItem(withTitle: "Edit Layer を \(index + 1) にする", action: #selector(AppController.selectEditLayer(_:)), keyEquivalent: "\(index + 1)")
        item.tag = index; item.target = controller
        item.keyEquivalentModifierMask = .command
    }
    menu.addItem(.separator())
    let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    let more = menu.addItem(withTitle: "Edit Clip の不透明度を上げる", action: #selector(AppController.changeOpacity(_:)), keyEquivalent: up)
    more.tag = 10; more.target = controller; more.keyEquivalentModifierMask = []
    let less = menu.addItem(withTitle: "Edit Clip の不透明度を下げる", action: #selector(AppController.changeOpacity(_:)), keyEquivalent: down)
    less.tag = -10; less.target = controller; less.keyEquivalentModifierMask = []
    let blend = menu.addItem(withTitle: "Edit Clip の Blend Mode を切り替える", action: #selector(AppController.cycleBlendMode(_:)), keyEquivalent: "b")
    blend.target = controller; blend.keyEquivalentModifierMask = []
    let toggle = menu.addItem(withTitle: "Edit Clip の ON/OFF", action: #selector(AppController.toggleEditClip(_:)), keyEquivalent: "m")
    toggle.target = controller; toggle.keyEquivalentModifierMask = []
}
addMenu("Deck") { menu in
    for (index, deck) in renderer.decks.enumerated() {
        let item = menu.addItem(withTitle: "Edit Deck を \(deck.name) にする", action: #selector(AppController.selectEditDeck(_:)), keyEquivalent: index == 0 ? "a" : "s")
        item.tag = index; item.target = controller; item.keyEquivalentModifierMask = []
    }
    menu.addItem(.separator())
    for (index, deck) in renderer.decks.enumerated() {
        let item = menu.addItem(withTitle: "Deck \(deck.name) へ Cut", action: #selector(AppController.cutTo(_:)), keyEquivalent: index == 0 ? "z" : "x")
        item.tag = index; item.target = controller; item.keyEquivalentModifierMask = []
    }
    menu.addItem(.separator())
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    let toA = menu.addItem(withTitle: "Crossfader を A 側へ", action: #selector(AppController.nudgeCrossfader(_:)), keyEquivalent: left)
    toA.tag = -5; toA.target = controller; toA.keyEquivalentModifierMask = []
    let toB = menu.addItem(withTitle: "Crossfader を B 側へ", action: #selector(AppController.nudgeCrossfader(_:)), keyEquivalent: right)
    toB.tag = 5; toB.target = controller; toB.keyEquivalentModifierMask = []
}
addMenu("Beat") { menu in
    let tap = menu.addItem(withTitle: "Tap Tempo", action: #selector(AppController.tapTempo(_:)), keyEquivalent: "t")
    tap.target = controller; tap.keyEquivalentModifierMask = []
    let down = menu.addItem(withTitle: "Downbeat(いまを小節の頭にする)", action: #selector(AppController.setDownbeat(_:)), keyEquivalent: "d")
    down.target = controller; down.keyEquivalentModifierMask = []
    let quant = menu.addItem(withTitle: "Launch Quantize を切り替える", action: #selector(AppController.cycleQuantize(_:)), keyEquivalent: "q")
    quant.target = controller; quant.keyEquivalentModifierMask = []
}
app.mainMenu = mainMenu
controller.updateTitle()

controlWindow.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
controller.apc.start()
app.run()
