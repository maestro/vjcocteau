import AVFoundation
import Combine
import CoreAudio
import Foundation

/// 音声の波形から、拍の目安になる「低域の立ち上がり」を取り出し、BPM と拍の位置を推定します。
/// スレッドの管理はしません(呼ぶ側で守ります)。
final class BeatAnalyzer {
    static let hop = 512
    static let seconds = 8.0

    let sampleRate: Double
    var fps: Double { sampleRate / Double(Self.hop) }
    private let alpha: Float
    private var lowpass: Float = 0
    private var energySum: Float = 0
    private var rawSum: Float = 0
    private var pending = 0
    private var previousEnergy: Float = 0
    private let maxFrames: Int
    /// 直近の、低域エネルギーの増え方(1ホップごと)です。
    private(set) var flux: [Float] = []
    /// これまでに作ったホップの数です。
    private(set) var frameCount = 0
    /// まだホップに満たない、手前のサンプル数です。
    var pendingSamples: Int { pending }
    /// 入力の大きさ(メーター用)です。
    private(set) var level: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        alpha = Float(1 - exp(-2 * Double.pi * 200 / sampleRate)) // 200Hz 以下を見る
        maxFrames = Int(Self.seconds * sampleRate / Double(Self.hop)) + 8
    }

    func feed(_ samples: UnsafePointer<Float>, count: Int) {
        for i in 0..<count {
            let x = samples[i]
            lowpass += alpha * (x - lowpass)
            energySum += lowpass * lowpass
            rawSum += x * x
            pending += 1
            if pending == Self.hop { finishHop() }
        }
    }

    private func finishHop() {
        let n = Float(Self.hop)
        let energy = (energySum / n).squareRoot()
        let raw = (rawSum / n).squareRoot()
        level = max(raw, level * 0.97)
        flux.append(max(0, energy - previousEnergy))
        previousEnergy = energy
        frameCount += 1
        if flux.count > maxFrames { flux.removeFirst(flux.count - maxFrames) }
        energySum = 0; rawSum = 0; pending = 0
    }

    struct Result {
        let bpm: Double
        /// 0〜1。正規化した自己相関の山の高さです。
        let confidence: Double
        /// 最後の拍があったホップの番号(通し番号)です。
        let lastBeatFrame: Int
    }

    /// 約8秒分の立ち上がりから、BPM(70〜180)と、最後の拍の位置を推定します。
    static func analyze(flux: [Float], fps: Double, endFrame: Int) -> Result? {
        let n = flux.count
        guard Double(n) >= fps * 4 else { return nil }
        let mean = flux.reduce(0, +) / Float(n)
        let x = flux.map { Double($0 - mean) }
        let variance = x.reduce(0) { $0 + $1 * $1 } / Double(n)
        guard variance > 1e-14 else { return nil }

        let lagMin = max(2, Int(60 * fps / 180)), lagMax = Int(60 * fps / 70) + 1
        guard lagMax * 2 + 1 < n else { return nil }
        var ac = [Double](repeating: 0, count: lagMax * 2 + 2)
        for lag in (lagMin - 1)...(lagMax * 2 + 1) {
            var sum = 0.0
            for i in 0..<(n - lag) { sum += x[i] * x[i + lag] }
            ac[lag] = sum / Double(n - lag) / variance
        }
        // 倍のテンポではなく拍の周期を選ぶよう、2拍ぶんの山も加点し、120BPM付近をわずかに優先します。
        var bestLag = lagMin, bestScore = -Double.infinity
        for lag in lagMin...lagMax {
            let bpm = 60 * fps / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 120) / 0.8, 2))
            let score = (ac[lag] + 0.5 * ac[lag * 2]) * prior
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        let a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1]
        let denominator = a - 2 * b + c
        let period = Double(bestLag) + (abs(denominator) > 1e-9 ? 0.5 * (a - c) / denominator : 0)

        // 周期ごとに立ち上がりを足して、いちばん合う位置を拍の位置にします。
        var bestOffset = 0, bestSum = -Double.infinity, bestLast = 0
        for offset in 0..<Int(period.rounded(.up)) {
            var sum = 0.0, count = 0, last = offset, k = 0
            while true {
                let index = Int((Double(offset) + Double(k) * period).rounded())
                if index >= n - 1 { break }
                for j in max(0, index - 1)...min(n - 1, index + 1) { sum += Double(flux[j]) }
                last = index; count += 1; k += 1
            }
            guard count > 0 else { continue }
            let average = sum / Double(count)
            if average > bestSum { bestSum = average; bestOffset = offset; bestLast = last }
        }
        _ = bestOffset
        return Result(bpm: 60 * fps / period, confidence: max(0, min(1, b)),
                      lastBeatFrame: endFrame - n + bestLast)
    }
}

/// 音声入力デバイスです。
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    /// 入力チャンネルを持つデバイスの一覧です。
    static func all() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// 音声入力から拍を検出して、Beat Clock に合わせます。
final class BeatDetector: ObservableObject {
    enum Status: Equatable {
        case off, starting, running, denied
        case failed(String)
    }
    private static let deviceKey = "audioInputUID"

    @Published private(set) var status: Status = .off
    /// 拍を取れている(音があり、周期がはっきりしている)かどうかです。
    @Published private(set) var isLocked = false
    @Published private(set) var level: Float = 0
    @Published private(set) var devices: [AudioInputDevice] = AudioInputDevice.all()
    /// 選んだデバイスの UID です。nil はシステムの既定の入力です。
    @Published private(set) var selectedUID: String? = UserDefaults.standard.string(forKey: BeatDetector.deviceKey)

    var isEnabled: Bool { status != .off }

    private let clock: BeatClock
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var analyzer: BeatAnalyzer?
    private var hopEndTime = 0.0
    private var timer: Timer?
    private var candidate: Double?
    private var candidateCount = 0

    init(clock: BeatClock) {
        self.clock = clock
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        // メーターは速く動かします。
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateLevel() }
    }

    // MARK: - 操作

    func setEnabled(_ on: Bool) {
        if on { start() } else { stop() }
    }

    func toggle() { setEnabled(!isEnabled) }

    func select(uid: String?) {
        selectedUID = uid
        UserDefaults.standard.set(uid, forKey: Self.deviceKey)
        if isEnabled { stop(); start() }
    }

    private func start() {
        guard status == .off || status == .denied || { if case .failed = status { return true }; return false }() else { return }
        status = .starting
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { granted ? self.startEngine() : (self.status = .denied) }
            }
        default: status = .denied
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        lock.lock(); analyzer = nil; lock.unlock()
        status = .off
        isLocked = false
        level = 0
        candidate = nil; candidateCount = 0
    }

    private func startEngine() {
        guard status == .starting else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let uid = selectedUID, let device = AudioInputDevice.all().first(where: { $0.uid == uid }), let unit = input.audioUnit {
            var id = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .failed("入力デバイスを開けませんでした")
            return
        }
        lock.lock(); analyzer = BeatAnalyzer(sampleRate: format.sampleRate); lock.unlock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            self?.handle(buffer, when)
        }
        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            status = .running
        } catch {
            input.removeTap(onBus: 0)
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - 音声の取り込み(音声スレッド)

    private func handle(_ buffer: AVAudioPCMBuffer, _ when: AVAudioTime) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        for c in 0..<channelCount {
            let data = channels[c]
            for i in 0..<count { mono[i] += data[i] / Float(channelCount) }
        }
        let end = AVAudioTime.seconds(forHostTime: when.hostTime) + Double(count) / buffer.format.sampleRate
        lock.lock()
        if let analyzer {
            mono.withUnsafeBufferPointer { analyzer.feed($0.baseAddress!, count: count) }
            hopEndTime = end - Double(analyzer.pendingSamples) / analyzer.sampleRate
        }
        lock.unlock()
    }

    // MARK: - 解析(0.5秒ごと)

    private func updateLevel() {
        lock.lock(); let value = analyzer?.level ?? 0; lock.unlock()
        let shown = min(1, value * 4)
        if abs(shown - level) > 0.01 || (shown == 0 && level != 0) { level = shown }
    }

    private func tick() {
        let now = AudioInputDevice.all()
        if now != devices { devices = now }
        guard status == .running else { return }
        lock.lock()
        let snapshot = analyzer.map { (flux: $0.flux, fps: $0.fps, frames: $0.frameCount, level: $0.level, rate: $0.sampleRate) }
        let endTime = hopEndTime
        lock.unlock()
        guard let s = snapshot else { return }
        guard s.level > 0.003,
              let result = BeatAnalyzer.analyze(flux: s.flux, fps: s.fps, endFrame: s.frames),
              result.confidence >= 0.2 else {
            isLocked = false
            candidate = nil; candidateCount = 0
            return
        }
        isLocked = true
        let hop = Double(BeatAnalyzer.hop) / s.rate
        let beatTime = endTime - Double(s.frames - 1 - result.lastBeatFrame) * hop - hop / 2
        // 現在値から大きく離れた推定は、3回続けて同じ値が出てから採用します。
        if abs(result.bpm - clock.bpm) > 3 {
            if let c = candidate, abs(c - result.bpm) < 1.5 { candidateCount += 1 } else { candidate = result.bpm; candidateCount = 1 }
            if candidateCount >= 3 {
                clock.follow(bpm: result.bpm, beatTime: beatTime, bpmGain: 1, phaseGain: 1)
                candidate = nil; candidateCount = 0
            }
        } else {
            candidate = nil; candidateCount = 0
            clock.follow(bpm: result.bpm, beatTime: beatTime, bpmGain: 0.3, phaseGain: 0.3)
        }
    }
}
