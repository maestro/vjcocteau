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
    @Published var fitMode: FitMode = .contain
    @Published var resolution: OutputResolution = .p1080
    /// 0 で Deck A のみ、1 で Deck B のみが映ります。
    @Published var crossfader: Float = 0
    @Published var masterBrightness: Float = 1
}

private struct MixUniforms {
    var weightA: Float
    var weightB: Float
    var brightness: Float
}

private struct Uniforms {
    var viewAspect: Float
    var clipAspect: Float
    var fitMode: Int32
    var opacity: Float
    var blendMode: Int32
}

/// Output Window に最終映像を描画するレンダラーです。
final class Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelines: [BlendMode: MTLRenderPipelineState]
    private let mixPipeline: MTLRenderPipelineState
    private weak var view: MTKView?
    /// 32個の Bank です。動画を開くのは、Deck にロードされた Bank だけです。
    let bankLibrary = (0..<Bank.count).map { Bank(index: $0) }
    let decks: [Deck]
    /// 各 Deck の合成結果を一旦入れる画面外テクスチャです。
    private var bankTextures: [MTLTexture?] = [nil, nil]
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
        var pipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "layer_fragment")
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = view.colorPixelFormat
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .zero
            switch mode {
            case .normal:   color.sourceRGBBlendFactor = .sourceAlpha;      color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            case .add:      color.sourceRGBBlendFactor = .sourceAlpha;      color.destinationRGBBlendFactor = .one
            case .multiply: color.sourceRGBBlendFactor = .destinationColor; color.destinationRGBBlendFactor = .zero
            case .screen:   color.sourceRGBBlendFactor = .one;              color.destinationRGBBlendFactor = .oneMinusSourceColor
            }
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            pipelines[mode] = pipeline
        }
        self.pipelines = pipelines

        // Deck A と B を混ぜて画面へ出すパイプラインです(ブレンドなし)。
        let mixDescriptor = MTLRenderPipelineDescriptor()
        mixDescriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        mixDescriptor.fragmentFunction = library.makeFunction(name: "mix_fragment")
        mixDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        guard let mixPipeline = try? device.makeRenderPipelineState(descriptor: mixDescriptor) else { return nil }
        self.mixPipeline = mixPipeline

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

    /// 描画サイズに合わせて Deck 用の画面外テクスチャを用意します。
    private func ensureBankTextures(size: CGSize) {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0 else { return }
        for i in bankTextures.indices {
            if let t = bankTextures[i], t.width == width, t.height == height { continue }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: view?.colorPixelFormat ?? .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            bankTextures[i] = device.makeTexture(descriptor: descriptor)
        }
    }

    /// 1つの Bank の Clip を、Layer 1 から順に、Layer の中ではスロット番号順に重ねて描画します。
    private func drawLayers(of bank: Bank, with encoder: MTLRenderCommandEncoder, viewAspect: Float) {
        for layer in bank.layers where layer.isEnabled && layer.opacity > 0 {
            for slot in layer.slots where slot.isOn {
                guard let texture = slot.clip?.currentTexture(),
                      let pipeline = pipelines[slot.blendMode] else { continue }
                var uniforms = Uniforms(
                    viewAspect: viewAspect,
                    clipAspect: Float(texture.width) / Float(max(texture.height, 1)),
                    fitMode: fitMode.rawValue,
                    opacity: slot.opacity * layer.opacity,
                    blendMode: slot.blendMode.rawValue)
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }
    }

    func draw(in view: MTKView) {
        applyResolution(to: view)
        // ロード中の Bank が準備できていれば入れ替えます(拍への同期は段階5で入れます)。
        for deck in decks { deck.commitIfReady() }
        ensureBankTextures(size: view.drawableSize)
        guard let buffer = queue.makeCommandBuffer(),
              let textureA = bankTextures[0], let textureB = bankTextures[1] else { return }

        let mix = min(max(settings.crossfader, 0), 1)
        let weights = [1 - mix, mix]
        let viewAspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))

        // 見えている Bank だけ描画します。見えない Bank も動画の再生は止めません。
        for (index, deck) in decks.enumerated() where weights[index] > 0 {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = bankTextures[index]
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            drawLayers(of: deck.bank, with: encoder, viewAspect: viewAspect)
            encoder.endEncoding()
        }

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = MixUniforms(weightA: weights[0], weightB: weights[1],
                                   brightness: min(max(settings.masterBrightness, 0), 1))
        encoder.setRenderPipelineState(mixPipeline)
        encoder.setFragmentTexture(textureA, index: 0)
        encoder.setFragmentTexture(textureB, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MixUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
