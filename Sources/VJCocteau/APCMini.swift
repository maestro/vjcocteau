import Combine
import CoreMIDI
import Foundation

/// Akai APC mini MK2 の入出力です。割り当ては `docs/controller-layout.md` にあります。
final class APCMini: ObservableObject {
    /// フェーダーの種類です。0〜7 は Layer、8 は Crossfader、9 は Master の明るさです。
    static let crossfaderID = 8
    static let masterID = 9

    @Published private(set) var isConnected = false
    /// Pickup 待ちのフェーダーの物理位置(0〜1)です。追いついたフェーダーは含みません。
    @Published private(set) var pendingFaders: [Int: Double] = [:]

    private unowned let controller: AppController
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSources: Set<MIDIEndpointRef> = []
    private var destinations: [MIDIEndpointRef] = []

    private var shiftHeld = false
    private var pressedButtons: Set<UInt8> = []
    /// 物理フェーダー9本の最後の位置です(0〜7 は Layer、8 は9本目)。
    private var physical: [Double?] = Array(repeating: nil, count: 9)
    private var engaged: [Bool] = Array(repeating: false, count: 10)
    private var lastApplied: [Double?] = Array(repeating: nil, count: 10)
    private var contextKey = ""
    /// LED の送信済みの状態です(重複送信を避けます)。
    private var sentLEDs: [UInt8: UInt16] = [:]
    private var timer: Timer?

    init(controller: AppController) { self.controller = controller }

    // MARK: - 接続

    func start() {
        MIDIClientCreateWithBlock("VJ Cocteau" as CFString, &client) { [weak self] notification in
            let id = notification.pointee.messageID
            if id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved {
                DispatchQueue.main.async { self?.rescan() }
            }
        }
        MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &inputPort) { [weak self] list, _ in
            self?.receive(list)
        }
        MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        rescan()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func name(of endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value)
        return value?.takeRetainedValue() as String? ?? ""
    }

    private func isAPC(_ endpoint: MIDIEndpointRef) -> Bool {
        name(of: endpoint).range(of: "APC mini", options: .caseInsensitive) != nil
    }

    /// 接続されている APC mini の入出力を探し直します。
    private func rescan() {
        let sources = (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter(isAPC)
        for source in sources where !connectedSources.contains(source) {
            MIDIPortConnectSource(inputPort, source, nil)
        }
        connectedSources = Set(sources)
        destinations = (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }.filter(isAPC)
        let connected = !sources.isEmpty
        if connected != isConnected {
            isConnected = connected
            sentLEDs.removeAll() // つなぎ直したら、LED をすべて送り直します
            shiftHeld = false
            pressedButtons.removeAll()
            FileHandle.standardError.write(Data((connected ? "APC mini MK2 に接続しました\n" : "APC mini MK2 が切断されました\n").utf8))
        }
    }

    // MARK: - 受信

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        var messages: [(UInt8, UInt8, UInt8)] = []
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafePointer(to: packet.pointee.words) { tuple in
                tuple.withMemoryRebound(to: UInt32.self, capacity: 64) { words in
                    for i in 0..<min(count, 64) {
                        let word = words[i]
                        // MIDI 1.0 のチャンネルボイスメッセージ(UMP のタイプ 2)だけを読みます。
                        guard (word >> 28) == 0x2 else { continue }
                        messages.append((UInt8((word >> 16) & 0xF0), UInt8((word >> 8) & 0x7F), UInt8(word & 0x7F)))
                    }
                }
            }
        }
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for (type, data1, data2) in messages { self?.handle(type: type, data1: data1, data2: data2) }
        }
    }

    private func handle(type: UInt8, data1: UInt8, data2: UInt8) {
        switch type {
        case 0x90 where data2 > 0: noteDown(data1)
        case 0x90, 0x80: noteUp(data1)
        case 0xB0: controlChange(data1, data2)
        default: break
        }
    }

    private func noteDown(_ note: UInt8) {
        pressedButtons.insert(note)
        switch note {
        case 0..<64:
            // 行は下から数えるので、最上段がスロット1になるよう反転します。
            controller.toggleSlot(layer: Int(note) % 8, slot: 7 - Int(note) / 8)
        case 100...107:
            let index = Int(note) - 100
            if shiftHeld {
                switch index {
                case 0: controller.setEditDeck(0)
                case 1: controller.setEditDeck(1)
                case 2: controller.cut(to: 0)
                case 3: controller.cut(to: 1)
                case 4: controller.clock.tap()
                case 5: controller.clock.downbeat()
                case 6: controller.clock.quantize = controller.clock.quantize.next
                default: break // 8 は Beat Detection の ON/OFF 用に予約
                }
            } else {
                controller.toggleLayer(index)
            }
        case 112...119:
            let index = Int(note) - 112
            if shiftHeld {
                if index < 4 { controller.setPage(index) }
            } else {
                controller.loadBank(controller.page * 8 + index)
            }
        case 122: shiftHeld = true
        default: break
        }
    }

    private func noteUp(_ note: UInt8) {
        pressedButtons.remove(note)
        if note == 122 { shiftHeld = false }
    }

    private func controlChange(_ number: UInt8, _ value: UInt8) {
        let position = Double(value) / 127
        switch number {
        case 48...55: moveFader(id: Int(number) - 48, physicalIndex: Int(number) - 48, position: position)
        case 56: moveFader(id: shiftHeld ? Self.masterID : Self.crossfaderID, physicalIndex: 8, position: position)
        default: break
        }
    }

    // MARK: - フェーダーと Pickup

    private func currentValue(of id: Int) -> Double {
        switch id {
        case 0..<8: return Double(controller.currentBank.layers[id].opacity)
        case Self.crossfaderID: return Double(controller.renderer.settings.crossfader)
        default: return Double(controller.renderer.settings.masterBrightness)
        }
    }

    private func apply(_ value: Double, to id: Int) {
        let v = Float(min(max(value, 0), 1))
        switch id {
        case 0..<8: controller.currentBank.layers[id].opacity = v
        case Self.crossfaderID: controller.renderer.settings.crossfader = v
        default: controller.renderer.settings.masterBrightness = v
        }
    }

    private func moveFader(id: Int, physicalIndex: Int, position: Double) {
        let current = currentValue(of: id)
        // 画面など、フェーダー以外で値が変えられていたら、Pickup をやり直します。
        if engaged[id], let applied = lastApplied[id], abs(current - applied) > 0.015 { engaged[id] = false }
        if !engaged[id] {
            let previous = physical[physicalIndex]
            let reached = abs(position - current) <= 0.02
            let crossed = previous.map { ($0 - current) * (position - current) <= 0 } ?? false
            if reached || crossed { engaged[id] = true }
        }
        physical[physicalIndex] = position
        if engaged[id] {
            apply(position, to: id)
            lastApplied[id] = position
        }
        updatePending()
    }

    /// 物理位置が現在の値とずれているフェーダーを、画面に伝えます。
    private func updatePending() {
        var result: [Int: Double] = [:]
        let activeIDs = Array(0..<8) + [shiftHeld ? Self.masterID : Self.crossfaderID]
        for id in activeIDs where !engaged[id] {
            let index = id < 8 ? id : 8
            if let position = physical[index], abs(position - currentValue(of: id)) > 0.02 { result[id] = position }
        }
        if result != pendingFaders { pendingFaders = result }
    }

    /// Deck の切り替えや Bank の入れ替え、Shift の出入りがあったら、Pickup をやり直します。
    private func checkContext() {
        let decks = controller.renderer.decks
        let key = "\(controller.editDeck)-\(decks[0].bank.index)-\(decks[1].bank.index)-\(shiftHeld)"
        if key != contextKey {
            contextKey = key
            engaged = Array(repeating: false, count: 10)
        }
    }

    // MARK: - LED

    private func refresh() {
        guard isConnected else { return }
        checkContext()
        updatePending()
        let decks = controller.renderer.decks
        let bank = controller.currentBank
        let deckColor: UInt8 = controller.editDeck == 0 ? 45 : 53 // 青 / マゼンタ

        // パッド: 列 = Layer、行 = スロット(最上段がスロット1)
        for column in 0..<Layer.count {
            let layer = bank.layers[column]
            for slotIndex in 0..<Layer.slotCount {
                let slot = layer.slots[slotIndex]
                var channel: UInt8 = 0, velocity: UInt8 = 0
                if slot.clipURL != nil {
                    velocity = deckColor
                    channel = !layer.isEnabled ? 0 : (slot.isOn ? 6 : 1) // 10% / 100% / 25%
                    if slot.isPending { channel = 12 } // 拍待ちは点滅
                }
                led(note: UInt8((7 - slotIndex) * 8 + column), status: 0x90 | channel, velocity: velocity)
            }
        }
        // 下段のトラックボタン(赤)
        for index in 0..<8 {
            var velocity: UInt8 = 0 // 0 = 消灯、1 = 点灯、2 = 点滅
            if shiftHeld {
                let beat = controller.clock.beatInBar()
                switch index {
                case 0: velocity = controller.editDeck == 0 ? 1 : 0
                case 1: velocity = controller.editDeck == 1 ? 1 : 0
                case 2, 3:
                    velocity = controller.pendingCut == index - 2 ? 2 : (pressedButtons.contains(UInt8(100 + index)) ? 1 : 0)
                case 4: velocity = beat.phase < 0.2 ? 1 : 0
                case 5: velocity = beat.index == 0 && beat.phase < 0.2 ? 1 : 0
                case 6: velocity = UInt8(controller.clock.quantize.rawValue) // なし 0 / 1拍 1 / 1小節 2
                default: velocity = 0
                }
            } else {
                velocity = bank.layers[index].isEnabled ? 1 : 0
            }
            led(note: UInt8(100 + index), status: 0x90, velocity: velocity)
        }
        // 右列のシーンボタン(緑): 1 = 点灯、2 = 点滅
        for index in 0..<8 {
            var velocity: UInt8 = 0
            if shiftHeld {
                velocity = index == controller.page ? 1 : 0
            } else {
                let target = controller.renderer.bankLibrary[controller.page * 8 + index]
                if decks.contains(where: { $0.pendingBank === target }) { velocity = 2 }
                else if decks.contains(where: { $0.bank === target }) { velocity = 1 }
            }
            led(note: UInt8(112 + index), status: 0x90, velocity: velocity)
        }
    }

    /// 前回から変わった LED だけを送ります。
    private func led(note: UInt8, status: UInt8, velocity: UInt8) {
        let value = UInt16(status) << 8 | UInt16(velocity)
        guard sentLEDs[note] != value else { return }
        sentLEDs[note] = value
        send([status, note, velocity])
    }

    private func send(_ bytes: [UInt8]) {
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)
        for destination in destinations { MIDISend(outputPort, destination, &list) }
    }
}
