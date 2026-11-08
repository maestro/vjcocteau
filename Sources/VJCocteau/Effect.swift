import AppKit
import Combine
import Foundation
import Metal

/// Effect のパラメータの種類です。
enum EffectParamKind {
    case float
    case bool
    case color
    case choice([String])
}

/// 宣言ファイル(effect.json)に書かれた、1つのパラメータです。
struct EffectParam {
    let key: String
    let label: String
    let kind: EffectParamKind
    let defaultValue: [Float]
    let min: Float
    let max: Float
    /// シェーダーへ渡す Float の数です(色だけ 3、ほかは 1)。
    var width: Int { if case .color = kind { return 3 }; return 1 }
}

/// 読み込み済みの Effect です。宣言と、コンパイル済みのパイプラインを持ちます。
final class EffectDefinition {
    static let maxFloats = 16
    let id: String
    let name: String
    let params: [EffectParam]
    let pipeline: MTLRenderPipelineState
    init(id: String, name: String, params: [EffectParam], pipeline: MTLRenderPipelineState) {
        self.id = id; self.name = name; self.params = params; self.pipeline = pipeline
    }
}

/// Chain に載せた Effect 1つ分の状態です。パラメータの値は、キーごとに持ちます(再読み込みで宣言が変わっても残ります)。
final class EffectInstance: ObservableObject, Identifiable {
    let id = UUID()
    let effectID: String
    @Published var isOn = true
    @Published var values: [String: [Float]] = [:]

    init(effectID: String) { self.effectID = effectID }

    func value(of param: EffectParam) -> [Float] {
        if let v = values[param.key], v.count == param.width { return v }
        return param.defaultValue
    }

    /// シェーダーへ渡す values[16] に並べます。宣言順に詰めます。
    func packed(for definition: EffectDefinition) -> [Float] {
        var out: [Float] = []
        for param in definition.params { out += value(of: param) }
        out += Array(repeating: 0, count: max(0, EffectDefinition.maxFloats - out.count))
        return Array(out.prefix(EffectDefinition.maxFloats))
    }
}

/// Layer、Bank、Master のいずれかにかかる、順番付きの Effect の列です。
final class EffectChain: ObservableObject {
    static let maxCount = 4
    @Published private(set) var items: [EffectInstance] = []

    @discardableResult
    func add(_ effectID: String) -> Bool {
        guard items.count < Self.maxCount else { return false }
        items.append(EffectInstance(effectID: effectID))
        return true
    }
    func remove(_ instance: EffectInstance) { items.removeAll { $0 === instance } }
    func move(_ instance: EffectInstance, by offset: Int) {
        guard let i = items.firstIndex(where: { $0 === instance }) else { return }
        let j = i + offset
        guard items.indices.contains(j) else { return }
        items.swapAt(i, j)
    }
}

/// Effect のフォルダを読み込み、変更を監視して再コンパイルします。
/// 標準の Effect はアプリに同梱し、自作の Effect はユーザーフォルダに置きます。同じ名前なら自作が優先です。
final class EffectLibrary: ObservableObject {
    @Published private(set) var definitions: [EffectDefinition] = []
    /// Effect ごとの最新のエラーです。直したら消えます。エラー中も、直前に動いた版を使い続けます。
    @Published private(set) var errors: [String: String] = [:]

    static var userFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VJ Cocteau/Effects", isDirectory: true)
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private var stamps: [String: String] = [:]
    private var timer: Timer?
    private let folders: [URL]

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        self.device = device
        self.pixelFormat = pixelFormat
        var folders: [URL] = []
        if let bundled = Bundle.module.url(forResource: "Effects", withExtension: nil) { folders.append(bundled) }
        try? FileManager.default.createDirectory(at: Self.userFolder, withIntermediateDirectories: true)
        folders.append(Self.userFolder)
        self.folders = folders
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.scan() }
    }

    func definition(for id: String) -> EffectDefinition? { definitions.first { $0.id == id } }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// フォルダを走査し、変わった Effect だけコンパイルし直します。
    private func scan() {
        // id → (フォルダ)。後ろのフォルダ(ユーザー)が前を上書きします。
        var found: [String: URL] = [:]
        for folder in folders {
            let subs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for dir in subs where FileManager.default.fileExists(atPath: dir.appendingPathComponent("effect.json").path) {
                found[dir.lastPathComponent] = dir
            }
        }
        var result = definitions
        var newErrors = errors
        var changed = false
        for (id, dir) in found {
            let json = dir.appendingPathComponent("effect.json"), metal = dir.appendingPathComponent("effect.metal")
            let stamp = "\(dir.path)|\(modified(json).timeIntervalSince1970)|\(modified(metal).timeIntervalSince1970)"
            if stamps[id] == stamp { continue }
            stamps[id] = stamp
            changed = true
            do {
                let def = try Self.compile(id: id, json: json, metal: metal, device: device, pixelFormat: pixelFormat)
                result.removeAll { $0.id == id }
                result.append(def)
                newErrors[id] = nil
                FileHandle.standardError.write(Data("Effect を読み込みました: \(id)\n".utf8))
            } catch {
                newErrors[id] = "\(error.localizedDescription)"
                FileHandle.standardError.write(Data("Effect のエラー(\(id)): \(error.localizedDescription)\n".utf8))
            }
        }
        // フォルダごと消えた Effect は外します。
        let before = result.count
        result.removeAll { found[$0.id] == nil }
        if result.count != before { changed = true }
        for key in newErrors.keys where found[key] == nil { newErrors[key] = nil; changed = true }
        if changed {
            definitions = result.sorted { $0.name < $1.name }
            errors = newErrors
        }
    }

    private struct LoadError: LocalizedError { let message: String; var errorDescription: String? { message } }

    private static func compile(id: String, json: URL, metal: URL, device: MTLDevice, pixelFormat: MTLPixelFormat) throws -> EffectDefinition {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any] else {
            throw LoadError(message: "effect.json の形式が正しくありません")
        }
        let name = object["name"] as? String ?? id
        var params: [EffectParam] = []
        var floats = 0
        for raw in object["params"] as? [[String: Any]] ?? [] {
            guard let key = raw["key"] as? String, key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw LoadError(message: "パラメータの key が正しくありません")
            }
            let label = raw["label"] as? String ?? key
            let min = (raw["min"] as? NSNumber)?.floatValue ?? 0
            let max = (raw["max"] as? NSNumber)?.floatValue ?? 1
            let param: EffectParam
            switch raw["type"] as? String ?? "float" {
            case "float":
                param = EffectParam(key: key, label: label, kind: .float,
                                    defaultValue: [(raw["default"] as? NSNumber)?.floatValue ?? min], min: min, max: max)
            case "bool":
                param = EffectParam(key: key, label: label, kind: .bool,
                                    defaultValue: [(raw["default"] as? NSNumber)?.boolValue == true ? 1 : 0], min: 0, max: 1)
            case "color":
                let c = (raw["default"] as? [NSNumber])?.map { $0.floatValue } ?? [1, 1, 1]
                param = EffectParam(key: key, label: label, kind: .color,
                                    defaultValue: c.count == 3 ? c : [1, 1, 1], min: 0, max: 1)
            case "choice":
                let options = raw["options"] as? [String] ?? []
                guard !options.isEmpty else { throw LoadError(message: "choice の options が空です(\(key))") }
                param = EffectParam(key: key, label: label, kind: .choice(options),
                                    defaultValue: [(raw["default"] as? NSNumber)?.floatValue ?? 0], min: 0, max: Float(options.count - 1))
            default:
                throw LoadError(message: "未知の type です(\(key))")
            }
            floats += param.width
            params.append(param)
        }
        guard floats <= EffectDefinition.maxFloats else { throw LoadError(message: "パラメータが多すぎます(最大 \(EffectDefinition.maxFloats) 個分)") }

        // パラメータへのアクセス用に、param_<key> のマクロを作ります。
        var macros = ""
        var offset = 0
        for param in params {
            switch param.kind {
            case .float: macros += "#define param_\(param.key) (p.values[\(offset)])\n"
            case .bool: macros += "#define param_\(param.key) (p.values[\(offset)] > 0.5)\n"
            case .choice: macros += "#define param_\(param.key) ((int)(p.values[\(offset)] + 0.5))\n"
            case .color: macros += "#define param_\(param.key) float3(p.values[\(offset)], p.values[\(offset + 1)], p.values[\(offset + 2)])\n"
            }
            offset += param.width
        }
        let user = try String(contentsOf: metal, encoding: .utf8)
        let source = prelude + macros + user + "\n" + wrapper
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: source, options: nil) }
        catch { throw LoadError(message: Self.firstError(error)) }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "effect_fragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        return EffectDefinition(id: id, name: name, params: params, pipeline: pipeline)
    }

    /// コンパイルエラーの長い文章から、最初の error の行だけを取り出します。
    private static func firstError(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.split(separator: "\n").first { $0.contains("error:") }.map(String.init) ?? String(text.prefix(200))
    }

    private static let prelude = """
    #include <metal_stdlib>
    using namespace metal;
    struct EffectVertexOut { float4 position [[position]]; float2 uv; };
    struct EffectParams { float time; float aspect; float2 resolution; float values[16]; };
    vertex EffectVertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
        float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        EffectVertexOut out;
        out.position = float4(pos[vid], 0, 1);
        out.uv = float2((pos[vid].x + 1) * 0.5, 1 - (pos[vid].y + 1) * 0.5);
        return out;
    }
    // 入力を、透明度を分けた(straight)色で読みます。
    inline float4 sample_src(texture2d<float> tex, float2 uv) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 c = tex.sample(s, uv);
        return c.a > 0.0001 ? float4(c.rgb / c.a, c.a) : float4(0.0);
    }

    """

    private static let wrapper = """
    fragment float4 effect_fragment(EffectVertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant EffectParams &p [[buffer(0)]]) {
        float4 c = effect_main(in.uv, tex, p);
        return float4(c.rgb * c.a, c.a);
    }
    """
}
