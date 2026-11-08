import Combine
import Foundation
import MetalKit

/// 動画の画面へのはめ込み方です。
enum FitMode: Int32, CaseIterable {
    case stretch = 0   // 引き伸ばし
    case contain = 1   // 縦横比を保って黒帯
    case cover = 2     // 縦横比を保って切り抜き

    var title: String {
        switch self {
        case .stretch: return "引き伸ばし"
        case .contain: return "黒帯(全体を表示)"
        case .cover: return "切り抜き(画面いっぱい)"
        }
    }
}

/// 内部の描画解像度(高さ)です。幅は表示領域の縦横比から決めます。
enum OutputResolution: Int, CaseIterable {
    case p720 = 720
    case p1080 = 1080
    case p2160 = 2160
    case auto = 0      // 表示領域の実ピクセルに合わせる

    var title: String {
        self == .auto ? "ウィンドウに合わせる" : (self == .p2160 ? "4K (2160p)" : "\(rawValue)p")
    }
}

/// 出力に関する設定です。画面の UI とメニューの両方から変更されます。
final class OutputSettings: ObservableObject {
    /// アプリの設定として、UserDefaults に保存します(Set とは別です)。
    @Published var fitMode: FitMode = (UserDefaults.standard.object(forKey: "fitMode") as? Int).flatMap { FitMode(rawValue: Int32($0)) } ?? .contain {
        didSet { UserDefaults.standard.set(Int(fitMode.rawValue), forKey: "fitMode") }
    }
    @Published var resolution: OutputResolution = {
        (UserDefaults.standard.object(forKey: "outputResolution") as? Int).flatMap { OutputResolution(rawValue: $0) } ?? .p1080
    }() {
        didSet { UserDefaults.standard.set(resolution.rawValue, forKey: "outputResolution") }
    }
    /// 0 で Deck A のみ、1 で Deck B のみが映ります。
    @Published var crossfader: Float = 0
    @Published var masterBrightness: Float = 1
}

private struct MixUniforms {
    var weightA: Float
    var weightB: Float
    var brightness: Float
}

private struct CompositeUniforms { var opacity: Float }

private struct Uniforms {
    var viewAspect: Float
    var clipAspect: Float
    var fitMode: Int32
    var opacity: Float
    var blendMode: Int32
    var layerTarget: Int32
}

/// Output Window に最終映像を描画するレンダラーです。
final class Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelines: [BlendMode: MTLRenderPipelineState]
    /// Effect をかける Layer の中間テクスチャ(透明度つき)へ描くためのパイプラインです。
    private let layerPipelines: [BlendMode: MTLRenderPipelineState]
    private let compositePipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private let mixPipeline: MTLRenderPipelineState
    let effectLibrary: EffectLibrary
    let clock = BeatClock()
    /// 毎フレームの最初に呼ばれます(Launch Quantize で待たせた操作の実行に使います)。
    var onFrame: (() -> Void)?
    /// 最終映像(Deck A/B を混ぜたあと)にかかる Effect Chain です。
    let masterEffects = EffectChain()
    private let startTime = CACurrentMediaTime()
    private weak var view: MTKView?
    /// 32個の Bank です。動画を開くのは、Deck にロードされた Bank だけです。
    let bankLibrary = (0..<Bank.count).map { Bank(index: $0) }
    let decks: [Deck]
    /// 画面外テクスチャです(Deck ごとの合成結果、Effect の入れ替え用、Layer 用、Master 用)。
    private var textures: [String: MTLTexture] = [:]
    let settings = OutputSettings()
    var fitMode: FitMode { get { settings.fitMode } set { settings.fitMode = newValue } }
    var resolution: OutputResolution { get { settings.resolution } set { settings.resolution = newValue } }

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let url = Bundle.module.url(forResource: "Composite", withExtension: "metal", subdirectory: "Shaders"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let library = try? device.makeLibrary(source: source, options: nil)
        else { return nil }
        self.device = device
        self.queue = queue
        self.view = view

        // Blend Mode ごとにブレンド係数の違うパイプラインを作ります。
        // Bank へ描くものは、透明度を保ちます。Layer の中間テクスチャへ描くものは、透明度も合成します。
        func makePipelines(layerTarget: Bool) -> [BlendMode: MTLRenderPipelineState]? {
            var result: [BlendMode: MTLRenderPipelineState] = [:]
            for mode in BlendMode.allCases {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
                descriptor.fragmentFunction = library.makeFunction(name: "layer_fragment")
                let color = descriptor.colorAttachments[0]!
                color.pixelFormat = view.colorPixelFormat
                color.isBlendingEnabled = true
                color.rgbBlendOperation = .add
                color.alphaBlendOperation = .add
                switch mode {
                case .normal:   color.sourceRGBBlendFactor = .sourceAlpha;      color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                case .add:      color.sourceRGBBlendFactor = .sourceAlpha;      color.destinationRGBBlendFactor = .one
                case .multiply: color.sourceRGBBlendFactor = .destinationColor; color.destinationRGBBlendFactor = .zero
                case .screen:   color.sourceRGBBlendFactor = .one;              color.destinationRGBBlendFactor = .oneMinusSourceColor
                }
                if !layerTarget {
                    color.sourceAlphaBlendFactor = .zero; color.destinationAlphaBlendFactor = .one
                } else if mode == .multiply {
                    color.sourceAlphaBlendFactor = .zero; color.destinationAlphaBlendFactor = .one
                } else {
                    color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
                guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
                result[mode] = pipeline
            }
            return result
        }
        guard let bankPipelines = makePipelines(layerTarget: false),
              let layerPipelines = makePipelines(layerTarget: true) else { return nil }
        self.pipelines = bankPipelines
        self.layerPipelines = layerPipelines

        func makeSimple(_ fragment: String, blend: Bool = false) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = view.colorPixelFormat
            if blend {
                // 透明度を掛けた色を、Bank の上にそのまま重ねます(Bank の透明度は保ちます)。
                color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.sourceAlphaBlendFactor = .zero; color.destinationAlphaBlendFactor = .one
            }
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let mixPipeline = makeSimple("mix_fragment"),
              let compositePipeline = makeSimple("composite_fragment", blend: true),
              let presentPipeline = makeSimple("present_fragment") else { return nil }
        self.mixPipeline = mixPipeline
        self.compositePipeline = compositePipeline
        self.presentPipeline = presentPipeline
        effectLibrary = EffectLibrary(device: device, pixelFormat: view.colorPixelFormat)

        // 起動時は Deck A に Bank 01、Deck B に Bank 02 をロードしておきます。
        decks = [Deck(name: "A", bank: bankLibrary[0]), Deck(name: "B", bank: bankLibrary[1])]
        for deck in decks { deck.bank.activate(device: device) }

        super.init()
        view.device = device
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = false // 描画解像度は applyResolution で決めます
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = self
    }

    var metalDevice: MTLDevice { device }

    /// 描画解像度を、表示領域の縦横比を保ったまま設定します。
    private func applyResolution(to view: MTKView) {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        var size: CGSize
        if resolution == .auto {
            size = view.convertToBacking(bounds).size
        } else {
            let height = CGFloat(resolution.rawValue)
            size = CGSize(width: (height * bounds.width / bounds.height).rounded(), height: height)
        }
        if view.drawableSize != size { view.drawableSize = size }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Bank を Deck にロードします。同じ Bank をもう一方の Deck が持っている場合は失敗します。
    @discardableResult
    func loadBank(_ bank: Bank, into deckIndex: Int) -> Bool {
        let deck = decks[deckIndex], other = decks[1 - deckIndex]
        guard deck.bank !== bank, deck.pendingBank !== bank,
              other.bank !== bank, other.pendingBank !== bank else { return false }
        bank.activate(device: device)
        deck.beginLoading(bank)
        return true
    }

    /// 描画サイズに合わせて、画面外テクスチャを用意します。
    private func ensureTextures(size: CGSize) {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0 else { return }
        let keys = ["bank0", "bank1", "bankS0", "bankS1", "layer", "layerS", "mix", "mixS"]
        for key in keys {
            if let t = textures[key], t.width == width, t.height == height { continue }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: view?.colorPixelFormat ?? .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            textures[key] = device.makeTexture(descriptor: descriptor)
        }
    }

    /// 1つの Layer の ON の Clip を、スロット番号順に重ねて描画します。
    private func drawSlots(of layer: Layer, opacity: Float, pipelines: [BlendMode: MTLRenderPipelineState],
                           layerTarget: Bool, with encoder: MTLRenderCommandEncoder, viewAspect: Float) {
        for slot in layer.slots where slot.isOn {
            guard let texture = slot.clip?.currentTexture(),
                  let pipeline = pipelines[slot.blendMode] else { continue }
            var uniforms = Uniforms(
                viewAspect: viewAspect,
                clipAspect: Float(texture.width) / Float(max(texture.height, 1)),
                fitMode: fitMode.rawValue,
                opacity: slot.opacity * opacity,
                blendMode: slot.blendMode.rawValue,
                layerTarget: layerTarget ? 1 : 0)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    /// Chain のうち、ON で、読み込みに成功している Effect だけを返します。
    private func activeEffects(_ chain: EffectChain) -> [(EffectInstance, EffectDefinition)] {
        chain.items.compactMap { item in
            guard item.isOn, let def = effectLibrary.definition(for: item.effectID) else { return nil }
            return (item, def)
        }
    }

    /// Effect を順にかけます。2枚のテクスチャを行き来し、結果が入ったほうを返します。
    private func applyChain(_ effects: [(EffectInstance, EffectDefinition)], source: MTLTexture, scratch: MTLTexture,
                            buffer: MTLCommandBuffer) -> MTLTexture {
        var from = source, to = scratch
        let time = Float(CACurrentMediaTime() - startTime)
        let beat = Float(clock.position()), bpm = Float(clock.bpm)
        for (instance, definition) in effects {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = to
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            let width = Float(to.width), height = Float(to.height)
            var values: [Float] = [time, width / max(height, 1), width, height, beat, bpm, 0, 0] + instance.packed(for: definition)
            encoder.setRenderPipelineState(definition.pipeline)
            encoder.setFragmentTexture(from, index: 0)
            encoder.setFragmentBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            swap(&from, &to)
        }
        return from
    }

    /// 1つの Bank を、Layer 1 から順に合成し、Layer と Bank の Effect をかけて、結果のテクスチャを返します。
    private func render(bank: Bank, deckIndex: Int, buffer: MTLCommandBuffer, viewAspect: Float) -> MTLTexture? {
        guard let target = textures["bank\(deckIndex)"], let bankScratch = textures["bankS\(deckIndex)"],
              let layerTexture = textures["layer"], let layerScratch = textures["layerS"] else { return nil }
        var encoder: MTLRenderCommandEncoder?
        var cleared = false
        /// Bank への描画を始めます(途中で Layer の中間描画を挟むと、閉じて、続きから開き直します)。
        func bankEncoder() -> MTLRenderCommandEncoder? {
            if let encoder { return encoder }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = cleared ? .load : .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            cleared = true
            encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
            return encoder
        }
        for layer in bank.layers where layer.isEnabled && layer.opacity > 0 {
            let effects = activeEffects(layer.effects)
            if effects.isEmpty {
                guard let e = bankEncoder() else { continue }
                drawSlots(of: layer, opacity: layer.opacity, pipelines: pipelines, layerTarget: false, with: e, viewAspect: viewAspect)
                continue
            }
            guard layer.slots.contains(where: { $0.isOn }) else { continue }
            // Effect あり: Layer の中で合成 → Effect → Bank へ Normal で重ねる
            encoder?.endEncoding(); encoder = nil
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = layerTexture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let layerEncoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            drawSlots(of: layer, opacity: 1, pipelines: layerPipelines, layerTarget: true, with: layerEncoder, viewAspect: viewAspect)
            layerEncoder.endEncoding()
            let result = applyChain(effects, source: layerTexture, scratch: layerScratch, buffer: buffer)
            guard let e = bankEncoder() else { continue }
            var uniforms = CompositeUniforms(opacity: layer.opacity)
            e.setRenderPipelineState(compositePipeline)
            e.setFragmentTexture(result, index: 0)
            e.setFragmentBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        _ = bankEncoder() // 何も描かなくても、背景の黒で塗りつぶします
        encoder?.endEncoding()
        return applyChain(activeEffects(bank.effects), source: target, scratch: bankScratch, buffer: buffer)
    }

    func draw(in view: MTKView) {
        applyResolution(to: view)
        // ロード中の Bank が準備できていれば入れ替えます(拍への同期は段階5で入れます)。
        onFrame?()
        for deck in decks { deck.commitIfReady { [clock] in clock.launchTime() } }
        ensureTextures(size: view.drawableSize)
        guard let buffer = queue.makeCommandBuffer(),
              let fallbackA = textures["bank0"], let fallbackB = textures["bank1"],
              let mixTexture = textures["mix"], let mixScratch = textures["mixS"] else { return }

        let mix = min(max(settings.crossfader, 0), 1)
        let weights = [1 - mix, mix]
        let viewAspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))

        // 見えている Bank だけ描画します。見えない Bank も動画の再生は止めません。
        var results = [fallbackA, fallbackB]
        for (index, deck) in decks.enumerated() where weights[index] > 0 {
            if let result = render(bank: deck.bank, deckIndex: index, buffer: buffer, viewAspect: viewAspect) {
                results[index] = result
            }
        }

        // Deck A と B を混ぜます。
        let mixPass = MTLRenderPassDescriptor()
        mixPass.colorAttachments[0].texture = mixTexture
        mixPass.colorAttachments[0].loadAction = .dontCare
        mixPass.colorAttachments[0].storeAction = .store
        if let encoder = buffer.makeRenderCommandEncoder(descriptor: mixPass) {
            var uniforms = MixUniforms(weightA: weights[0], weightB: weights[1], brightness: 1)
            encoder.setRenderPipelineState(mixPipeline)
            encoder.setFragmentTexture(results[0], index: 0)
            encoder.setFragmentTexture(results[1], index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MixUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        // Master の Effect → Master の明るさ → 画面
        let final = applyChain(activeEffects(masterEffects), source: mixTexture, scratch: mixScratch, buffer: buffer)
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var brightness = min(max(settings.masterBrightness, 0), 1)
        encoder.setRenderPipelineState(presentPipeline)
        encoder.setFragmentTexture(final, index: 0)
        encoder.setFragmentBytes(&brightness, length: MemoryLayout<Float>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
