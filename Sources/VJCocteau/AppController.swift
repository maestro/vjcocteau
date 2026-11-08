import AppKit
import Combine
import MetalKit
import UniformTypeIdentifiers

/// 枠なしウィンドウでもキー入力とメニュー操作を受け取れる Output Window です。
final class OutputWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } // Esc で終了
        else { super.keyDown(with: event) }
    }
}

/// メニュー、操作用 UI、APC mini MK2 からの操作を受けて、Renderer と Bank の設定を切り替えます。
final class AppController: NSObject, NSMenuItemValidation, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    private static let outputDisplayKey = "outputDisplayID"

    let renderer: Renderer
    weak var outputWindow: NSWindow?
    private(set) lazy var apc = APCMini(controller: self)

    /// コントローラーと画面の操作が向いている Deck の番号です(0 = A, 1 = B)。
    @Published private(set) var editDeck = 0
    @Published private(set) var editLayer = 0
    @Published private(set) var editSlot = 0
    /// APC のシーンボタンで選ぶ Bank のページです(0〜3)。
    @Published private(set) var page = 0
    /// Output Window を出すディスプレイの ID です。0 は、ディスプレイに出さずウィンドウで表示します。
    @Published private(set) var outputDisplayID: Int

    var currentDeck: Deck { renderer.decks[editDeck] }
    var currentBank: Bank { currentDeck.bank }
    var currentLayer: Layer { currentBank.layers[editLayer] }
    var currentSlot: ClipSlot { currentLayer.slots[editSlot] }
    private var cancellables: [AnyCancellable] = []
    /// Cut の指示を受けて、次の拍を待っている先の Deck です。
    @Published private(set) var pendingCut: Int?
    var clock: BeatClock { renderer.clock }

    /// Launch Quantize で待たせている操作です。
    private struct Pending { let key: AnyHashable; let time: Double; let action: () -> Void; let cleanup: () -> Void }
    private var pending: [Pending] = []

    init(renderer: Renderer) {
        self.renderer = renderer
        outputDisplayID = Self.initialOutputDisplayID()
        super.init()
        // 選択や Clip の変更をタイトル表示へ反映します。
        let refreshTitle: () -> Void = { [weak self] in DispatchQueue.main.async { self?.updateTitle() } }
        $editDeck.sink { _ in refreshTitle() }.store(in: &cancellables)
        $editLayer.sink { _ in refreshTitle() }.store(in: &cancellables)
        $editSlot.sink { _ in refreshTitle() }.store(in: &cancellables)
        $outputDisplayID.sink { _ in refreshTitle() }.store(in: &cancellables)
        renderer.settings.objectWillChange.sink { refreshTitle() }.store(in: &cancellables)
        // Deck のロード状況の変化を、画面の UI へ伝えます。
        for deck in renderer.decks {
            deck.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async { self?.objectWillChange.send(); self?.updateTitle() }
            }.store(in: &cancellables)
        }
        for slot in renderer.bankLibrary.flatMap({ $0.slots }) {
            slot.objectWillChange.sink { refreshTitle() }.store(in: &cancellables)
        }
        renderer.onFrame = { [weak self] in self?.runDue() }
        clock.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.objectWillChange.send() } }.store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reapplyOutputFrame() }
    }

    /// Edit Clip の状態と Crossfader を Output Window のタイトルに表示します。
    func updateTitle() {
        let slot = currentSlot
        let state = slot.clipName == nil ? "空" : (slot.isOn ? "ON" : "OFF")
        outputWindow?.title = String(
            format: "VJ Cocteau Output — Crossfader %d%%(A→B) / Edit Deck %@ (Bank %@) / Edit Layer %d / Slot %d [%@] %d%% %@",
            Int((renderer.settings.crossfader * 100).rounded()), currentDeck.name, currentBank.name,
            editLayer + 1, editSlot + 1, state, Int((slot.opacity * 100).rounded()), slot.blendMode.title)
    }

    // MARK: - 選択

    func setEditDeck(_ index: Int) { editDeck = min(max(index, 0), renderer.decks.count - 1) }
    func setPage(_ index: Int) { page = min(max(index, 0), Bank.count / 8 - 1) }
    func setEditLayer(_ index: Int) { editLayer = min(max(index, 0), Layer.count - 1) }
    func setEditClip(layer: Int, slot: Int) {
        editLayer = min(max(layer, 0), Layer.count - 1)
        editSlot = min(max(slot, 0), Layer.slotCount - 1)
    }

    // MARK: - 再生と切り替え

    /// 操作を次の Launch Quantize の境目まで待たせます。待たせたら true を返します(なしなら、すぐ実行して false)。
    /// 同じ key の待ちがあれば、取り消して置き換えます。
    @discardableResult
    private func schedule(key: AnyHashable, action: @escaping () -> Void, cleanup: @escaping () -> Void) -> Bool {
        cancel(key)
        let time = clock.launchTime()
        if time <= CACurrentMediaTime() + 0.0005 { action(); return false }
        pending.append(Pending(key: key, time: time, action: action, cleanup: cleanup))
        return true
    }

    private func cancel(_ key: AnyHashable) {
        let removed = pending.filter { $0.key == key }
        pending.removeAll { $0.key == key }
        removed.forEach { $0.cleanup() }
    }

    /// 時刻が来た操作を実行します。
    private func runDue() {
        let now = CACurrentMediaTime()
        let due = pending.filter { $0.time <= now }
        guard !due.isEmpty else { return }
        pending.removeAll { $0.time <= now }
        for item in due { item.action(); item.cleanup() }
    }

    /// Crossfader を Deck A(0)または Deck B(1)の端へ一気に動かします。次の拍(Launch Quantize)まで待ちます。
    func cut(to deck: Int) {
        let value: Float = deck == 0 ? 0 : 1
        if schedule(key: "cut", action: { [weak self] in self?.renderer.settings.crossfader = value },
                    cleanup: { [weak self] in self?.pendingCut = nil }) {
            pendingCut = deck
        }
    }

    /// Edit Deck の Bank にある Clip の ON/OFF を切り替えます。ON は次の拍まで待ち、OFF はすぐ反映します。
    /// 待っている間にもう一度押すと、取り消します。
    func toggleSlot(layer: Int, slot: Int) {
        let target = currentBank.layers[layer].slots[slot]
        let key = ObjectIdentifier(target)
        if target.isOn {
            cancel(key)
            target.setOn(false)
        } else if target.isPending {
            cancel(key)
        } else if target.clipURL != nil {
            if schedule(key: key, action: { target.setOn(true) }, cleanup: { target.isPending = false }) {
                target.isPending = true
            }
        }
    }

    func toggleLayer(_ index: Int) { currentBank.layers[index].isEnabled.toggle() }

    /// Edit Deck に、Bank Library の Bank をロードします。
    func loadBank(_ index: Int) {
        guard renderer.bankLibrary.indices.contains(index) else { return }
        renderer.loadBank(renderer.bankLibrary[index], into: editDeck)
    }

    // MARK: - Clip の読み込み

    /// 動画をスロットに割り当てます。Deck にロード済みの Bank なら、すぐ開きます(再生はしません)。
    @discardableResult
    func loadClip(_ url: URL, bank: Bank, layer: Int, slot: Int) -> Bool {
        bank.layers[layer].slots[slot].assign(url, device: renderer.metalDevice, open: bank.isActive)
    }

    func clearClip(layer: Int, slot: Int) {
        let target = currentBank.layers[layer].slots[slot]
        cancel(ObjectIdentifier(target))
        target.clear()
    }

    /// Edit Deck の Bank の指定スロットに読み込む動画を選びます。
    func chooseClip(layer: Int, slot: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.message = "Deck \(currentDeck.name)(Bank \(currentBank.name))の Layer \(layer + 1)・スロット \(slot + 1) に読み込む動画を選んでください"
        if panel.runModal() == .OK, let url = panel.url, !loadClip(url, bank: currentBank, layer: layer, slot: slot) {
            let alert = NSAlert()
            alert.messageText = "動画を開けませんでした"
            alert.informativeText = url.path
            alert.runModal()
        }
    }

    // MARK: - 出力先のディスプレイ

    static func screenID(_ screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        CGDisplayIsBuiltin(CGDirectDisplayID(screenID(screen))) != 0
    }

    private static func screen(withID id: Int) -> NSScreen? {
        NSScreen.screens.first { screenID($0) == id }
    }

    /// 前回選んだ出力先があればそれを、なければ内蔵以外で最初のディスプレイを選びます。
    private static func initialOutputDisplayID() -> Int {
        if let saved = UserDefaults.standard.object(forKey: outputDisplayKey) as? Int,
           saved == 0 || screen(withID: saved) != nil {
            return saved
        }
        return NSScreen.screens.first { !isBuiltIn($0) }.map(screenID) ?? 0
    }

    /// ウィンドウ表示のときの、Output Window の位置と大きさです。
    private var windowedFrame: NSRect {
        let base = (NSScreen.screens.first(where: Self.isBuiltIn) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: base.minX + 20, y: base.maxY - 540 - 40, width: 960, height: 540)
    }

    /// 出力先を決めて、ウィンドウの見た目と位置を合わせます。
    func setOutput(displayID: Int) {
        outputDisplayID = displayID
        UserDefaults.standard.set(displayID, forKey: Self.outputDisplayKey)
        applyOutput()
    }

    func applyOutput() {
        guard let window = outputWindow else { return }
        if outputDisplayID != 0, let screen = Self.screen(withID: outputDisplayID) {
            window.styleMask = [.borderless]
            window.level = .mainMenu + 1
            window.setFrame(screen.frame, display: true)
        } else {
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.level = .normal
            window.setFrame(windowedFrame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        updateTitle()
    }

    /// ディスプレイの構成が変わったとき、出力先が残っていれば全画面に戻します。
    /// 出力先が抜けている間は、ウィンドウを動かしません。
    private func reapplyOutputFrame() {
        guard outputDisplayID != 0, let screen = Self.screen(withID: outputDisplayID),
              let window = outputWindow else { return }
        window.setFrame(screen.frame, display: true)
    }

    /// 操作用ウィンドウを置くディスプレイです。出力先以外で、内蔵を優先します。
    var controlScreen: NSScreen? {
        let others = NSScreen.screens.filter { Self.screenID($0) != outputDisplayID }
        return others.first(where: Self.isBuiltIn) ?? others.first ?? NSScreen.main
    }

    /// メニューや UI に出す、選べる出力先の一覧です(ID と名前)。
    var outputChoices: [(id: Int, name: String)] {
        [(0, "ウィンドウで表示")] + NSScreen.screens.map {
            (Self.screenID($0), "\($0.localizedName)(\(Int($0.frame.width))×\(Int($0.frame.height)))")
        }
    }

    // MARK: - メニュー操作

    @objc func selectFit(_ sender: NSMenuItem) {
        if let mode = FitMode(rawValue: Int32(sender.tag)) { renderer.fitMode = mode }
    }
    @objc func selectResolution(_ sender: NSMenuItem) {
        if let res = OutputResolution(rawValue: sender.tag) { renderer.resolution = res }
    }
    @objc func selectOutput(_ sender: NSMenuItem) { setOutput(displayID: sender.tag) }
    @objc func toggleFullScreen(_ sender: Any?) { outputWindow?.toggleFullScreen(nil) }
    @objc func selectEditLayer(_ sender: NSMenuItem) { setEditLayer(sender.tag) }
    @objc func selectEditDeck(_ sender: NSMenuItem) { setEditDeck(sender.tag) }
    @objc func cutTo(_ sender: NSMenuItem) { cut(to: sender.tag) }
    @objc func nudgeCrossfader(_ sender: NSMenuItem) {
        let settings = renderer.settings
        settings.crossfader = min(max(settings.crossfader + Float(sender.tag) / 100, 0), 1)
    }
    @objc func changeOpacity(_ sender: NSMenuItem) {
        currentSlot.opacity = min(max(currentSlot.opacity + Float(sender.tag) / 100, 0), 1)
    }
    @objc func cycleBlendMode(_ sender: Any?) { currentSlot.blendMode = currentSlot.blendMode.next }
    @objc func toggleEditClip(_ sender: Any?) { toggleSlot(layer: editLayer, slot: editSlot) }
    @objc func tapTempo(_ sender: Any?) { clock.tap() }
    @objc func setDownbeat(_ sender: Any?) { clock.downbeat() }
    @objc func cycleQuantize(_ sender: Any?) { clock.quantize = clock.quantize.next }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectFit(_:)): item.state = item.tag == Int(renderer.fitMode.rawValue) ? .on : .off
        case #selector(selectResolution(_:)): item.state = item.tag == renderer.resolution.rawValue ? .on : .off
        case #selector(selectEditLayer(_:)): item.state = item.tag == editLayer ? .on : .off
        case #selector(selectEditDeck(_:)): item.state = item.tag == editDeck ? .on : .off
        case #selector(selectOutput(_:)): item.state = item.tag == outputDisplayID ? .on : .off
        default: break
        }
        return true
    }

    /// 出力ディスプレイのメニューを、開くたびに、いま接続されているディスプレイで作り直します。
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for choice in outputChoices {
            let item = menu.addItem(withTitle: choice.name, action: #selector(selectOutput(_:)), keyEquivalent: "")
            item.tag = choice.id
            item.target = self
        }
    }

    /// どちらのウィンドウを閉じてもアプリを終了します。
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
