import SwiftUI

// MARK: - テーマ

/// 操作画面の配色です。暗い背景に、Bank ごとのネオン色を載せます。
enum Theme {
    static let background = Color(hex: 0x0A0B0F)
    static let panel = Color(hex: 0x14161D)
    static let border = Color(hex: 0x272B37)
    static let text = Color(hex: 0xE8EAF0)
    static let dim = Color(hex: 0x7B8296)
    static let bankA = Color(hex: 0x00E5FF)
    static let bankB = Color(hex: 0xFF2E93)

    static func bank(_ index: Int) -> Color { index == 0 ? bankA : bankB }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// パネルの見た目(角丸、細い枠線)です。
private struct Panel: ViewModifier {
    var highlight: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(highlight.map { $0.opacity(0.07) } ?? Theme.panel))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(highlight?.opacity(0.8) ?? Theme.border, lineWidth: 1))
            .shadow(color: (highlight ?? .clear).opacity(0.25), radius: 8)
    }
}

private extension View {
    func panel(highlight: Color? = nil) -> some View { modifier(Panel(highlight: highlight)) }
}

/// 小さな見出しです。
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Theme.dim)
    }
}

// MARK: - 部品

/// ドラッグで値を変えられる、光るスライダーです。
private struct NeonSlider: View {
    @Binding var value: Double
    var fill: AnyShapeStyle
    var glow: Color
    /// true なら左から値の位置まで塗ります。false なら全体を塗り、つまみだけ動かします。
    var filled = true
    /// Pickup 待ちのフェーダーの物理位置(0〜1)です。あれば、輪の印で示します。
    var hint: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = max(0, min(1, value)) * width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07)).frame(height: 8)
                if filled {
                    Capsule().fill(fill).frame(width: max(8, x), height: 8)
                        .shadow(color: glow.opacity(0.7), radius: 5)
                } else {
                    Capsule().fill(fill).frame(height: 8).opacity(0.85)
                }
                Circle().fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: glow.opacity(0.9), radius: 6)
                    .offset(x: min(max(x - 8, 0), width - 16))
                if let hint {
                    Circle().stroke(Color.yellow, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .offset(x: min(max(hint * width - 10, -2), width - 18))
                }
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = max(0, min(1, drag.location.x / max(width, 1)))
            })
        }
        .frame(height: 20)
    }
}

/// 角丸の小さなボタンです。
private struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.dim
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(active ? Color.black : tint)
            .background(Capsule().fill(active ? tint : tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(active ? 0 : 0.5), lineWidth: 1))
            .shadow(color: active ? tint.opacity(0.6) : .clear, radius: 6)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 縦のスライダーです。下が 0、上が 1 です。
private struct VerticalFader: View {
    @Binding var value: Double
    var tint: Color
    var hint: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let y = (1 - max(0, min(1, value))) * height
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.07)).frame(width: 8)
                Capsule().fill(tint).frame(width: 8, height: max(8, height - y))
                    .shadow(color: tint.opacity(0.7), radius: 5)
                Circle().fill(Color.white).frame(width: 14, height: 14)
                    .shadow(color: tint.opacity(0.9), radius: 5)
                    .offset(y: -(height - y) + 7 > 0 ? 0 : 0)
                    .position(x: geo.size.width / 2, y: min(max(y, 7), height - 7))
                if let hint {
                    Circle().stroke(Color.yellow, lineWidth: 2).frame(width: 18, height: 18)
                        .position(x: geo.size.width / 2, y: min(max((1 - hint) * height, 9), height - 9))
                }
            }
            .frame(width: geo.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = max(0, min(1, 1 - drag.location.y / max(height, 1)))
            })
        }
    }
}

// MARK: - 画面

/// 操作用ウィンドウの中身です。Deck の混合、Bank の選択、Clip Matrix、出力設定を操作します。
struct ControlView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: OutputSettings
    @ObservedObject var apc: APCMini

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            crossfaderPanel
            BeatPanel(clock: controller.clock, detector: controller.detector)
            outputPanel
            bankLibraryPanel
            clipMatrixPanel
            editClipPanel
            EffectsPanel(controller: controller, library: controller.renderer.effectLibrary)
        }
        .padding(18)
        .frame(width: 700)
        .background(
            LinearGradient(colors: [Theme.background, Color(hex: 0x10121A)], startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        HStack {
            Text("VJ COCTEAU")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .tracking(5)
                .foregroundStyle(LinearGradient(colors: [Theme.bankA, Theme.bankB], startPoint: .leading, endPoint: .trailing))
            Spacer()
            // APC mini MK2 の接続状態
            HStack(spacing: 6) {
                Circle().fill(apc.isConnected ? Color.green : Theme.dim).frame(width: 8, height: 8)
                Caption(apc.isConnected ? "APC mini MK2" : "APC 未接続")
            }
            .padding(.trailing, 10)
            Caption("Edit Deck")
            ForEach(controller.renderer.decks.indices, id: \.self) { index in
                let deck = controller.renderer.decks[index]
                let loading = deck.pendingBank.map { " → \($0.name) \(Int((deck.progress * 100).rounded()))%" } ?? ""
                Button("DECK \(deck.name) · BANK \(deck.bank.name)\(loading)") { controller.setEditDeck(index) }
                    .buttonStyle(PillButtonStyle(tint: Theme.bank(index), active: controller.editDeck == index))
            }
        }
    }

    private var crossfaderPanel: some View {
        let mix = Double(settings.crossfader)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caption("Crossfader")
                Spacer()
                Text("A \(Int(((1 - mix) * 100).rounded()))%")
                    .foregroundStyle(Theme.bankA)
                Text("·").foregroundStyle(Theme.dim)
                Text("B \(Int((mix * 100).rounded()))%")
                    .foregroundStyle(Theme.bankB)
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            HStack(spacing: 12) {
                Button("CUT A") { controller.cut(to: 0) }
                    .buttonStyle(PillButtonStyle(tint: Theme.bankA, active: settings.crossfader == 0))
                NeonSlider(
                    value: Binding(get: { mix }, set: { settings.crossfader = Float($0) }),
                    fill: AnyShapeStyle(LinearGradient(colors: [Theme.bankA, Theme.bankB], startPoint: .leading, endPoint: .trailing)),
                    glow: mix < 0.5 ? Theme.bankA : Theme.bankB,
                    filled: false,
                    hint: apc.pendingFaders[APCMini.crossfaderID])
                Button("CUT B") { controller.cut(to: 1) }
                    .buttonStyle(PillButtonStyle(tint: Theme.bankB, active: settings.crossfader == 1))
            }
            HStack(spacing: 12) {
                Caption("Master").frame(width: 56, alignment: .leading)
                NeonSlider(
                    value: Binding(get: { Double(settings.masterBrightness) }, set: { settings.masterBrightness = Float($0) }),
                    fill: AnyShapeStyle(Color.white), glow: .white,
                    hint: apc.pendingFaders[APCMini.masterID])
                Text("\(Int((settings.masterBrightness * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .panel()
    }

    private var outputPanel: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Caption("Display")
                Picker("", selection: Binding(get: { controller.outputDisplayID }, set: { controller.setOutput(displayID: $0) })) {
                    ForEach(controller.outputChoices, id: \.id) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 230)
            }
            HStack(spacing: 8) {
                Caption("Fit Mode")
                Picker("", selection: $settings.fitMode) {
                    ForEach(FitMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            HStack(spacing: 8) {
                Caption("Resolution")
                Picker("", selection: $settings.resolution) {
                    ForEach(OutputResolution.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
            Spacer()
        }
        .panel()
    }

    /// Bank Library の一覧です。押すと Edit Deck にロードします。
    private var bankLibraryPanel: some View {
        let decks = controller.renderer.decks
        let tint = Theme.bank(controller.editDeck)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caption("Bank Library")
                Spacer()
                Caption("APC ページ \(controller.page + 1)/4 · 押すと Deck \(decks[controller.editDeck].name) にロード")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(controller.renderer.bankLibrary, id: \.index) { bank in
                    let deckIndex = decks.firstIndex { $0.bank === bank }
                    let loadingDeck = decks.first { $0.pendingBank === bank }
                    let color = deckIndex.map(Theme.bank) ?? (loadingDeck != nil ? tint : Theme.dim)
                    let blocked = decks.indices.contains { $0 != controller.editDeck && decks[$0].bank === bank }
                    let onPage = bank.index / 8 == controller.page
                    Button {
                        controller.loadBank(bank.index)
                    } label: {
                        VStack(spacing: 2) {
                            Text(bank.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            if let loadingDeck {
                                // ロード中は、進み具合を細いバーで示します。
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.black.opacity(0.25))
                                        Capsule().fill(Color.black.opacity(0.8))
                                            .frame(width: geo.size.width * max(0.08, loadingDeck.progress))
                                    }
                                }
                                .frame(height: 4)
                            } else {
                                Circle().fill(bank.hasContent ? color : Color.clear).frame(width: 4, height: 4)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .foregroundStyle(deckIndex != nil || loadingDeck != nil ? Color.black : color)
                        .background(RoundedRectangle(cornerRadius: 6).fill(deckIndex != nil ? color : (loadingDeck != nil ? color.opacity(0.6) : color.opacity(0.08))))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(onPage ? Color.white.opacity(0.6) : color.opacity(0.5), lineWidth: onPage ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .opacity(blocked ? 0.35 : 1)
                    .disabled(blocked)
                    .help(blocked ? "もう一方の Deck にロード済みです" : "Bank \(bank.name)")
                }
            }
        }
        .panel()
    }

    /// Edit Deck の Bank の Clip Matrix です。列 = Layer、行 = スロット(上がスロット1)。
    private var clipMatrixPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caption("Deck \(controller.currentDeck.name) · Bank \(controller.currentBank.name) — Clip Matrix")
                Spacer()
                Caption("押すと ON/OFF · 右クリックで読込")
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(0..<Layer.count, id: \.self) { index in
                    LayerColumn(index: index, layer: controller.currentBank.layers[index], controller: controller, apc: apc)
                }
            }
            .id(controller.currentBank.index)
        }
        .panel()
    }

    /// Edit Clip の設定です。
    private var editClipPanel: some View {
        EditClipPanel(controller: controller, slot: controller.currentSlot)
            .id("\(controller.currentBank.index)-\(controller.editLayer)-\(controller.editSlot)")
    }
}

/// Clip Matrix の1列(1つの Layer)です。
private struct LayerColumn: View {
    let index: Int
    @ObservedObject var layer: Layer
    @ObservedObject var controller: AppController
    @ObservedObject var apc: APCMini

    var body: some View {
        let tint = Theme.bank(controller.editDeck)
        let isEditLayer = controller.editLayer == index
        VStack(spacing: 6) {
            Button { controller.toggleLayer(index) } label: {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .foregroundStyle(layer.isEnabled ? Color.black : Theme.dim)
                    .background(RoundedRectangle(cornerRadius: 6).fill(layer.isEnabled ? tint : Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isEditLayer ? Color.white : Color.clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain).help("Layer の ON/OFF")
            VerticalFader(
                value: Binding(get: { Double(layer.opacity) }, set: { layer.opacity = Float($0) }),
                tint: tint, hint: apc.pendingFaders[index])
                .frame(height: 90)
            Text("\(Int((layer.opacity * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.dim)
            ForEach(0..<Layer.slotCount, id: \.self) { slotIndex in
                SlotCell(
                    slot: layer.slots[slotIndex], tint: tint, layerOn: layer.isEnabled,
                    selected: isEditLayer && controller.editSlot == slotIndex,
                    onTap: {
                        controller.setEditClip(layer: index, slot: slotIndex)
                        controller.toggleSlot(layer: index, slot: slotIndex)
                    },
                    onSelect: { controller.setEditClip(layer: index, slot: slotIndex) },
                    onLoad: { controller.chooseClip(layer: index, slot: slotIndex) },
                    onClear: { controller.clearClip(layer: index, slot: slotIndex) })
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Clip Matrix の1マス(1つのスロット)です。APC のパッドに対応します。
private struct SlotCell: View {
    @ObservedObject var slot: ClipSlot
    let tint: Color
    let layerOn: Bool
    let selected: Bool
    let onTap: () -> Void
    let onSelect: () -> Void
    let onLoad: () -> Void
    let onClear: () -> Void

    var body: some View {
        let assigned: Bool = slot.clipName != nil
        let isOn: Bool = slot.isOn
        let label: String = slot.clipName.map { String($0.prefix(9)) } ?? ""
        let fillColor: Color = isOn ? tint : (assigned ? tint.opacity(0.14) : Color.white.opacity(0.03))
        let strokeColor: Color = selected ? Color.white : tint.opacity(assigned ? 0.4 : 0.12)
        let strokeWidth: CGFloat = selected ? 1.5 : 1
        let textColor: Color = isOn ? Color.black : tint
        let glow: Color = isOn ? tint.opacity(0.5) : Color.clear
        let shape = RoundedRectangle(cornerRadius: 6)
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(textColor)
                .background(shape.fill(fillColor))
                .overlay(shape.stroke(strokeColor, lineWidth: strokeWidth))
                .shadow(color: glow, radius: 5)
        }
        .buttonStyle(.plain)
        .opacity(layerOn ? 1 : 0.4)
        .contextMenu {
            Button("Edit Clip にする", action: onSelect)
            Button("動画を読み込む…", action: onLoad)
            Button("Clip を外す", action: onClear).disabled(!assigned)
        }
    }
}

/// Edit Clip の不透明度、Blend Mode、読み込みの操作です。
private struct EditClipPanel: View {
    @ObservedObject var controller: AppController
    @ObservedObject var slot: ClipSlot

    var body: some View {
        let tint = Theme.bank(controller.editDeck)
        let empty = slot.clipName == nil
        HStack(spacing: 10) {
            Caption("Edit Clip")
            Text("L\(controller.editLayer + 1)·S\(controller.editSlot + 1)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(tint)
            Text(slot.clipName ?? "— 空 —")
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(empty ? Theme.dim : Theme.text)
                .frame(width: 120, alignment: .leading)
            NeonSlider(
                value: Binding(get: { Double(slot.opacity) }, set: { slot.opacity = Float($0) }),
                fill: AnyShapeStyle(tint), glow: tint)
            Text("\(Int((slot.opacity * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 42, alignment: .trailing)
            Menu {
                ForEach(BlendMode.allCases, id: \.self) { mode in
                    Button(mode.title) { slot.blendMode = mode }
                }
            } label: {
                Text(slot.blendMode.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 62)
            }
            .menuStyle(.button).buttonStyle(PillButtonStyle(tint: Theme.dim))
            .menuIndicator(.hidden)
            Button { controller.chooseClip(layer: controller.editLayer, slot: controller.editSlot) } label: { Image(systemName: "folder") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("動画を読み込む")
            Button { controller.clearClip(layer: controller.editLayer, slot: controller.editSlot) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).disabled(empty).help("Clip を外す")
        }
        .panel()
    }
}

// MARK: - Effect

/// Effect Chain の編集パネルです。Edit Layer、Edit Deck の Bank、Master のどれかを選んで編集します。
private struct EffectsPanel: View {
    enum Target: String, CaseIterable { case layer = "Layer", bank = "Bank", master = "Master" }

    @ObservedObject var controller: AppController
    @ObservedObject var library: EffectLibrary
    @State private var target: Target = .layer

    private var chain: EffectChain {
        switch target {
        case .layer: return controller.currentLayer.effects
        case .bank: return controller.currentBank.effects
        case .master: return controller.renderer.masterEffects
        }
    }

    private var targetTitle: String {
        switch target {
        case .layer: return "Deck \(controller.currentDeck.name) · Layer \(controller.editLayer + 1)"
        case .bank: return "Deck \(controller.currentDeck.name) · Bank \(controller.currentBank.name)"
        case .master: return "Master"
        }
    }

    var body: some View {
        let tint = Theme.bank(controller.editDeck)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Caption("Effect — \(targetTitle)")
                Spacer()
                ForEach(Target.allCases, id: \.self) { item in
                    Button(item.rawValue) { target = item }
                        .buttonStyle(PillButtonStyle(tint: tint, active: target == item))
                }
                Button { NSWorkspace.shared.open(EffectLibrary.userFolder) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim).help("自作 Effect のフォルダを開く")
            }
            // Layer・Bank の切り替えで、別の Chain の表示に切り替わるよう、識別子を付けます。
            EffectChainView(chain: chain, library: library, tint: tint)
                .id("\(target.rawValue)-\(controller.editDeck)-\(controller.currentBank.index)-\(controller.editLayer)")
            ForEach(library.errors.keys.sorted(), id: \.self) { key in
                Text("⚠︎ \(key): \(library.errors[key] ?? "")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.orange)
                    .lineLimit(2)
            }
        }
        .panel()
    }
}

private struct EffectChainView: View {
    @ObservedObject var chain: EffectChain
    @ObservedObject var library: EffectLibrary
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chain.items) { item in
                EffectRow(item: item, chain: chain, definition: library.definition(for: item.effectID), tint: tint)
            }
            Menu {
                ForEach(library.definitions, id: \.id) { def in
                    Button(def.name) { chain.add(def.id) }
                }
            } label: {
                Text(chain.items.count >= EffectChain.maxCount ? "満杯(最大 \(EffectChain.maxCount) 個)" : "+ Effect を追加")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .menuStyle(.button).buttonStyle(PillButtonStyle(tint: Theme.dim))
            .menuIndicator(.hidden)
            .disabled(chain.items.count >= EffectChain.maxCount)
        }
    }
}

/// Chain の1行(1つの Effect)です。ON/OFF、順番の入れ替え、削除、パラメータの調整ができます。
private struct EffectRow: View {
    @ObservedObject var item: EffectInstance
    let chain: EffectChain
    let definition: EffectDefinition?
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { item.isOn.toggle() } label: {
                Text(definition?.name ?? item.effectID)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 96)
            }
            .buttonStyle(PillButtonStyle(tint: definition == nil ? Color.orange : tint, active: item.isOn && definition != nil))
            if let definition {
                ForEach(definition.params, id: \.key) { param in
                    ParamControl(item: item, param: param, tint: tint)
                }
            } else {
                Text("見つかりません").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.orange)
            }
            Spacer(minLength: 0)
            Button { chain.move(item, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("前へ")
            Button { chain.move(item, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("後ろへ")
            Button { chain.remove(item) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).help("外す")
        }
    }
}

/// パラメータ1つ分の操作部品です。種類ごとに、スライダー・スイッチ・色・選択肢になります。
private struct ParamControl: View {
    @ObservedObject var item: EffectInstance
    let param: EffectParam
    let tint: Color

    var body: some View {
        let current = item.value(of: param)
        HStack(spacing: 5) {
            Text(param.label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.dim)
            switch param.kind {
            case .float:
                NeonSlider(
                    value: Binding(
                        get: { Double((current[0] - param.min) / max(param.max - param.min, 0.0001)) },
                        set: { item.values[param.key] = [param.min + Float($0) * (param.max - param.min)] }),
                    fill: AnyShapeStyle(tint), glow: tint)
                    .frame(width: 70)
            case .bool:
                Toggle("", isOn: Binding(
                    get: { current[0] > 0.5 }, set: { item.values[param.key] = [$0 ? 1 : 0] }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            case .color:
                ColorPicker("", selection: Binding(
                    get: { Color(red: Double(current[0]), green: Double(current[1]), blue: Double(current[2])) },
                    set: { color in
                        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
                        item.values[param.key] = [Float(ns.redComponent), Float(ns.greenComponent), Float(ns.blueComponent)]
                    }))
                    .labelsHidden()
            case .choice(let options):
                Picker("", selection: Binding(
                    get: { Int(current[0]) }, set: { item.values[param.key] = [Float($0)] })) {
                    ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                }
                .labelsHidden().frame(width: 100)
            }
        }
    }
}

// MARK: - Beat

/// Beat Clock の操作パネルです。BPM、Tap Tempo、Downbeat、Launch Quantize を操作します。
private struct BeatPanel: View {
    @ObservedObject var clock: BeatClock
    @ObservedObject var detector: BeatDetector

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Caption("Beat")
                TextField("", value: Binding(get: { clock.bpm }, set: { clock.setBPM($0) }),
                          format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("BPM").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.dim)
                ForEach([-1.0, -0.1, 0.1, 1.0], id: \.self) { step in
                    Button(step > 0 ? "+\(step.formatted())" : step.formatted()) { clock.setBPM(clock.bpm + step) }
                        .buttonStyle(PillButtonStyle())
                }
                Spacer()
                BeatDots(clock: clock)
            }
            HStack(spacing: 8) {
                Button("TAP") { clock.tap() }.buttonStyle(PillButtonStyle(tint: Theme.bankA))
                    .help("叩いた間隔で BPM を決めます(キー: t)")
                Button("DOWNBEAT") { clock.downbeat() }.buttonStyle(PillButtonStyle(tint: Theme.bankB))
                    .help("いまを小節の頭にします(キー: d)")
                Button("AUTO") { detector.toggle() }
                    .buttonStyle(PillButtonStyle(tint: detector.isEnabled && !detector.isLocked ? Color.orange : Theme.bankA,
                                                 active: detector.isEnabled))
                    .help("音声から BPM を自動で検出します(キー: g)。手で BPM を合わせると止まります")
                Spacer()
                Caption("Launch Quantize")
                ForEach(LaunchQuantize.allCases, id: \.self) { mode in
                    Button(mode.title) { clock.quantize = mode }
                        .buttonStyle(PillButtonStyle(tint: Theme.bankA, active: clock.quantize == mode))
                }
            }
            HStack(spacing: 8) {
                Caption("Audio In")
                Picker("", selection: Binding(get: { detector.selectedUID ?? "" }, set: { detector.select(uid: $0.isEmpty ? nil : $0) })) {
                    Text("システムの既定").tag("")
                    ForEach(detector.devices) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden().frame(width: 220)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule().fill(Theme.bankA).frame(width: max(0, CGFloat(detector.level)) * geo.size.width)
                    }
                }
                .frame(height: 6)
                Text(statusText).font(.system(size: 10, design: .monospaced)).foregroundStyle(statusColor)
                    .frame(width: 150, alignment: .trailing).lineLimit(1)
            }
        }
        .panel()
    }
}

extension BeatPanel {
    fileprivate var statusText: String {
        switch detector.status {
        case .off: return "自動検出 OFF"
        case .starting: return "起動中…"
        case .running: return detector.isLocked ? "拍を検出中" : "拍を探しています…"
        case .denied: return "マイクの許可が必要です"
        case .failed(let message): return message
        }
    }
    fileprivate var statusColor: Color {
        switch detector.status {
        case .denied, .failed: return Color.orange
        case .running: return detector.isLocked ? Theme.bankA : Theme.dim
        default: return Theme.dim
        }
    }
}

/// 小節の4拍を、いまの拍だけ光る点で示します。
private struct BeatDots: View {
    let clock: BeatClock

    var body: some View {
        TimelineView(.animation) { _ in
            let beat = clock.beatInBar()
            HStack(spacing: 6) {
                ForEach(0..<BeatClock.beatsPerBar, id: \.self) { i in
                    let lit = i == beat.index ? max(0.15, 1 - beat.phase) : 0.15
                    Circle()
                        .fill(i == 0 ? Theme.bankB : Theme.bankA)
                        .opacity(lit)
                        .frame(width: 12, height: 12)
                        .shadow(color: (i == 0 ? Theme.bankB : Theme.bankA).opacity(lit * 0.8), radius: 5)
                }
            }
        }
    }
}
