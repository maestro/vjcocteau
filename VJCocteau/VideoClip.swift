import AVFoundation
import CoreVideo
import Metal

/// 動画ファイルをループ再生し、最新フレームを Metal テクスチャとして返す Clip です。
final class VideoClip {
    private let player: AVPlayer
    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private var textureCache: CVMetalTextureCache?
    private var heldTexture: CVMetalTexture?
    private var lastTexture: MTLTexture?
    private var endObserver: NSObjectProtocol?

    init?(url: URL, device: MTLDevice) {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item = AVPlayerItem(url: url)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true // 映像のみ出力します
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            return nil
        }
        // 終端に達したら先頭へ戻してループさせます。
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// 動画が壊れているなどで、再生できないことが確定した状態です。
    var hasFailed: Bool { item.status == .failed }

    /// 再生の準備ができた状態(または、再生できないと確定した状態)です。
    var isLoaded: Bool { hasFailed || item.status == .readyToPlay }

    func play() { player.play() }

    /// 頭から再生し直します。前回の最後のフレームが一瞬映らないよう、保持しているフレームを捨てます。
    func restart() {
        lastTexture = nil
        heldTexture = nil
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.player.play()
        }
    }
    func stop() { player.pause() }

    /// 現在時刻に対応するフレームを返します。新フレームがなければ直前のものを返します。
    func currentTexture() -> MTLTexture? {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
              let cache = textureCache else { return lastTexture }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return lastTexture }
        heldTexture = cvTexture // GPU が使い終わるまでテクスチャを保持します
        lastTexture = texture
        return texture
    }
}
