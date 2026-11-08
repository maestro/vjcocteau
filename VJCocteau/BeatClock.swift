import Combine
import Foundation
import QuartzCore

/// 操作を待たせる単位です。
enum LaunchQuantize: Int, CaseIterable {
    case none = 0
    case beat = 1
    case bar = 2

    var title: String {
        switch self {
        case .none: return "なし"
        case .beat: return "1拍"
        case .bar: return "1小節"
        }
    }

    /// 待つ拍数です。なしは 0 です。
    var beats: Int {
        switch self {
        case .none: return 0
        case .beat: return 1
        case .bar: return BeatClock.beatsPerBar
        }
    }

    var next: LaunchQuantize { LaunchQuantize(rawValue: (rawValue + 1) % Self.allCases.count) ?? .none }
}

/// BPM と拍の位置を持つ時計です。タップテンポと手入力で合わせます。
/// 拍の位置は、Downbeat(小節の頭)を起点にした拍数で表します。
final class BeatClock: ObservableObject {
    static let beatsPerBar = 4
    static let bpmRange = 40.0...240.0
    private static let bpmKey = "bpm"
    private static let quantizeKey = "launchQuantize"

    @Published private(set) var bpm: Double
    @Published var quantize: LaunchQuantize {
        didSet { UserDefaults.standard.set(quantize.rawValue, forKey: Self.quantizeKey) }
    }
    /// 拍の位置が 0 になる時刻です(CACurrentMediaTime の秒)。
    private var anchor = CACurrentMediaTime()
    private var taps: [Double] = []
    /// 手で BPM や拍を合わせたときに呼ばれます(Beat Detection を止めるために使います)。
    var onManualChange: (() -> Void)?

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.bpmKey)
        bpm = Self.bpmRange.contains(saved) ? saved : 120
        quantize = LaunchQuantize(rawValue: UserDefaults.standard.object(forKey: Self.quantizeKey) as? Int ?? 1) ?? .beat
    }

    var beatDuration: Double { 60 / bpm }

    /// Downbeat からの拍数です(小数つき)。
    func position(at now: Double = CACurrentMediaTime()) -> Double { (now - anchor) / beatDuration }

    /// 小節の中の拍番号(0〜3)と、拍の中の進み具合(0〜1)です。
    func beatInBar(at now: Double = CACurrentMediaTime()) -> (index: Int, phase: Double) {
        let p = position(at: now)
        let whole = p.rounded(.down)
        let n = Self.beatsPerBar
        return ((((Int(whole) % n) + n) % n), p - whole)
    }

    private func store(_ value: Double) {
        bpm = min(max(value, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        UserDefaults.standard.set(bpm, forKey: Self.bpmKey)
    }

    /// BPM を変えます。いまの拍の位置は変わりません。
    func setBPM(_ value: Double) {
        onManualChange?()
        let now = CACurrentMediaTime()
        let p = position(at: now)
        store(value)
        anchor = now - p * beatDuration
    }

    /// 押した瞬間を、小節の頭にします。
    func downbeat() { anchor = CACurrentMediaTime() }

    /// 叩いた間隔から BPM を決め、拍の位置を叩いたタイミングに合わせます。小節の中の位置は保ちます。
    /// 2秒以上あいたら、叩き直しとして扱います。
    func tap() {
        onManualChange?()
        let now = CACurrentMediaTime()
        if let last = taps.last, now - last > 2 { taps.removeAll() }
        taps.append(now)
        taps = Array(taps.suffix(8))
        if taps.count >= 2, let first = taps.first, let last = taps.last {
            store(60 / ((last - first) / Double(taps.count - 1)))
        }
        let p = position(at: now)
        anchor += (p - p.rounded()) * beatDuration
    }

    /// Beat Detection の結果に合わせます。gain は、検出値へどれだけ近づけるかです(1 で一気に合わせます)。
    func follow(bpm target: Double, beatTime: Double, bpmGain: Double, phaseGain: Double) {
        let now = CACurrentMediaTime()
        if abs(target - bpm) > 0.05 {
            let p = position(at: now)
            store(bpm + (target - bpm) * bpmGain)
            anchor = now - p * beatDuration
        }
        let p = position(at: beatTime)
        anchor += (p - p.rounded()) * beatDuration * phaseGain
    }

    /// 次の Launch Quantize の境目の時刻です。なしなら、いまです。
    func launchTime(now: Double = CACurrentMediaTime()) -> Double {
        let unit = Double(quantize.beats)
        guard unit > 0 else { return now }
        let next = (position(at: now) / unit).rounded(.up) * unit
        return anchor + next * beatDuration
    }
}
