import Combine
import Foundation
import Metal
import QuartzCore

/// Layer を下の Layer に重ねるときの合成方法です。
enum BlendMode: Int32, CaseIterable {
    case normal = 0
    case add = 1
    case multiply = 2
    case screen = 3

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .add: return "Add"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        }
    }

    /// 次の Blend Mode です。最後まで進んだら先頭に戻ります。
    var next: BlendMode {
        BlendMode(rawValue: (rawValue + 1) % Int32(BlendMode.allCases.count)) ?? .normal
    }
}

/// Layer のスロットに割り当てる Clip の状態です。Blend Mode と不透明度は Clip ごとに持ちます。
final class ClipSlot: ObservableObject {
    /// 割り当てた動画のパスです。Bank が Deck にロードされるまで、動画は開きません。
    var clipURL: URL?
    /// 開いている動画です。Bank が Deck にロードされている間だけ存在します。ON でない間は先頭で止まっています。
    var clip: VideoClip?
    @Published var clipName: String?
    @Published var opacity: Float = 1
    @Published var blendMode: BlendMode = .normal
    /// ON のとき、再生して重ねて映します。
    @Published private(set) var isOn = false

    /// 動画を割り当てます。`open` が true なら、動画をすぐ開きます(再生はしません)。
    @discardableResult
    func assign(_ url: URL, device: MTLDevice?, open: Bool) -> Bool {
        var newClip: VideoClip?
        if open, let device {
            guard let opened = VideoClip(url: url, device: device) else { return false }
            newClip = opened
        }
        clip?.stop()
        clipURL = url
        clip = newClip
        clipName = url.lastPathComponent
        isOn = false
        return true
    }

    func clear() {
        clip?.stop()
        clip = nil
        clipURL = nil
        clipName = nil
        isOn = false
    }

    /// ON にすると頭から再生を始めます。OFF にすると止めます(再生位置は保ちません)。
    func setOn(_ on: Bool) {
        guard clipURL != nil, on != isOn else { return }
        isOn = on
        if on { clip?.restart() } else { clip?.stop() }
    }
}

/// Bank の中にある、最大8個の Clip を同時に再生できる列です。
final class Layer: ObservableObject {
    static let count = 8
    static let slotCount = 8

    let slots = (0..<Layer.slotCount).map { _ in ClipSlot() }
    /// この Layer の全 Clip への不透明度の倍率です。
    @Published var opacity: Float = 1
    @Published var isEnabled = true
}

/// 8本の Layer をまとめた1組です。Bank Library に32個あります。
final class Bank {
    static let count = 32

    let index: Int
    let layers = (0..<Layer.count).map { _ in Layer() }
    /// Deck にロードされていて、動画を開いているかどうかです。
    private(set) var isActive = false

    init(index: Int) { self.index = index }

    var name: String { String(format: "%02d", index + 1) }
    var slots: [ClipSlot] { layers.flatMap { $0.slots } }
    var hasContent: Bool { slots.contains { $0.clipURL != nil } }

    /// 割り当て済みの動画をすべて開きます。ON だった Clip は、頭から再生します。
    func activate(device: MTLDevice) {
        for slot in slots {
            guard let url = slot.clipURL, slot.clip == nil else { continue }
            slot.clip = VideoClip(url: url, device: device)
            if slot.isOn { slot.clip?.restart() }
        }
        isActive = true
    }

    /// 動画を閉じます。割り当て(パス)と ON/OFF の状態は残ります。
    func deactivate() {
        for slot in slots {
            slot.clip?.stop()
            slot.clip = nil
        }
        isActive = false
    }

    /// 開いた動画のうち、再生の準備ができた本数と、全体の本数です。
    /// 再生できないと確定した動画は、待ち続けないよう「済み」として数えます。
    var loadState: (ready: Int, total: Int) {
        let clips = slots.compactMap { $0.clip }
        return (clips.filter { $0.isLoaded }.count, clips.count)
    }
}

/// Bank を1つロードして再生する枠です。Deck A と Deck B があります。
final class Deck: ObservableObject {
    let name: String
    /// 映っている Bank です。
    @Published private(set) var bank: Bank
    /// ロード中の Bank です。読み込みが終わるまで、映像は元の Bank のままです。
    @Published private(set) var pendingBank: Bank?
    /// ロード中の Bank の進み具合です(0〜1)。ロード中でなければ 0 です。
    @Published private(set) var progress: Double = 0

    init(name: String, bank: Bank) {
        self.name = name
        self.bank = bank
    }

    func beginLoading(_ next: Bank) {
        if let pendingBank, pendingBank !== bank { pendingBank.deactivate() }
        pendingBank = next
        progress = 0
    }

    /// ロード中の Bank が準備できたら入れ替えます。入れ替えたら true を返します。
    /// 時間で打ち切ることはしません。終わるまで元の Bank を出し続けます。
    /// 別の Bank をロードし直せば、ロード中の Bank を取り消せます。
    @discardableResult
    func commitIfReady() -> Bool {
        guard let next = pendingBank else { return false }
        let state = next.loadState
        let done = state.ready == state.total
        let value = state.total == 0 ? 1 : Double(state.ready) / Double(state.total)
        if value != progress { progress = value }
        guard done else { return false }
        let old = bank
        bank = next
        pendingBank = nil
        progress = 0
        old.deactivate()
        return true
    }
}
