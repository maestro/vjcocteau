import Foundation

/// Set ファイル(JSON)の中身です。32個の Bank の割り当てと、Master の Effect Chain を持ちます。
/// 動画そのものは入れず、パスだけを記録します。ON/OFF や Crossfader など、ライブ中の状態は保存しません。
struct SetFile: Codable {
    static let currentVersion = 1
    var version = SetFile.currentVersion
    var banks: [BankData]
    var master: [EffectData]

    struct BankData: Codable {
        var layers: [LayerData]
        var effects: [EffectData]
    }

    struct LayerData: Codable {
        var opacity: Float
        var isEnabled: Bool
        var effects: [EffectData]
        var slots: [SlotData]
    }

    struct SlotData: Codable {
        /// 絶対パスです。
        var path: String?
        /// Set ファイルからの相対パスです。フォルダごと移動した場合は、こちらを先に探します。
        var relativePath: String?
        var opacity: Float
        var blend: Int32
    }

    struct EffectData: Codable {
        var id: String
        var isOn: Bool
        var values: [String: [Float]]
    }
}

// MARK: - 現在の状態から Set を作る

extension EffectChain {
    var data: [SetFile.EffectData] {
        items.map { SetFile.EffectData(id: $0.effectID, isOn: $0.isOn, values: $0.values) }
    }

    /// Chain の中身を、保存された Effect に置き換えます。
    func load(_ list: [SetFile.EffectData]) {
        replace(list.prefix(Self.maxCount).map {
            let instance = EffectInstance(effectID: $0.id)
            instance.isOn = $0.isOn
            instance.values = $0.values
            return instance
        })
    }
}

extension SetFile {
    /// `fileURL` は、相対パスの基準にする Set ファイルの場所です。
    static func make(banks: [Bank], master: EffectChain, fileURL: URL) -> SetFile {
        let base = fileURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        func relative(_ url: URL) -> String? {
            let target = url.standardizedFileURL.pathComponents
            var common = 0
            while common < min(base.count, target.count), base[common] == target[common] { common += 1 }
            // ルート以外に共通の階層がなければ、相対パスにしません。
            guard common > 1 else { return nil }
            let ups = Array(repeating: "..", count: base.count - common)
            return (ups + target[common...]).joined(separator: "/")
        }
        return SetFile(
            banks: banks.map { bank in
                BankData(
                    layers: bank.layers.map { layer in
                        LayerData(
                            opacity: layer.opacity, isEnabled: layer.isEnabled, effects: layer.effects.data,
                            slots: layer.slots.map {
                                SlotData(path: $0.clipURL?.path, relativePath: $0.clipURL.flatMap(relative),
                                         opacity: $0.opacity, blend: $0.blendMode.rawValue)
                            })
                    },
                    effects: bank.effects.data)
            },
            master: master.data)
    }

    /// 動画を探す場所です。相対パス、絶対パスの順に、実在するほうを返します。
    func resolve(_ slot: SlotData, fileURL: URL) -> URL? {
        let candidates = [
            slot.relativePath.map { URL(fileURLWithPath: $0, relativeTo: fileURL.deletingLastPathComponent()).standardizedFileURL },
            slot.path.map { URL(fileURLWithPath: $0) },
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
