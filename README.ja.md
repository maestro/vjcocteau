# VJ Cocteau

[English](README.md) | [日本語](README.ja.md)

Mac ネイティブの VJ ソフトウェアです。MIDI コントローラーで映像を切り替え、重ね合わせ、(これから)リアルタイムに加工して、外部ディスプレイやプロジェクターへ出力します。

Swift、Metal、AVFoundation、CoreMIDI で作っています。Akai Professional の **APC mini MK2** を前提に設計しています。

> **ステータス: 開発の初期段階です。** 段階1〜3を実装済みです([ロードマップ](#ロードマップ)を参照)。APC mini MK2 との連携は、疑似の MIDI 機器でだけ検証していて、**実機ではまだ試していません**。

## 特長

- **ネイティブで高速** — Metal で 60fps 描画し、AVFoundation でハードウェアデコードします。
- **レイヤー合成** — 1つの Bank に Layer 8本 × Clip スロット8個です。Clip ごとに不透明度と Blend Mode(Normal、Add、Multiply、Screen)を持ちます。
- **32個の Bank と2つの Deck** — ライブラリに最大32個の Bank を用意し、任意の2つを Deck A と Deck B にロードして、Crossfader で混ぜます。デコードするのはロード済みの2つの Bank だけです。
- **APC mini MK2 を主役に** — パッドの 8×8 の格子が Clip Matrix です。フェーダー、ボタン、LED もつなぎ、Pickup(ソフトテイクオーバー)で値が飛ばないようにしています。
- **外部ディスプレイへの出力** — 出力先は UI から選べて、選択は保存されます。出力解像度(720p / 1080p / 4K / ウィンドウに合わせる)と Fit Mode(引き伸ばし / 黒帯 / 切り抜き)も変えられます。
- **ダークテーマの操作画面** — Crossfader、Bank Library、Clip Matrix、Clip ごとの設定を、別ウィンドウで操作できます。

予定: Metal シェーダーのファイルだけで追加できるモジュール式の Effect(ホットリロード対応)、ライブ音声からの BPM 同期、Set の保存・読込。[ロードマップ](#ロードマップ)を参照してください。

## 動作環境

- macOS 14 以降(開発は Apple Silicon)
- Swift ツールチェーンを含む Xcode(Swift 5.9 以降)
- 自分で用意した動画(`.mov` または `.mp4` の H.264 / HEVC / ProRes)
- 任意: Akai Professional APC mini MK2

## ビルドと実行

```sh
swift build -c release
swift run -c release VJCocteau [動画1 動画2 ... 動画8]
```

引数の動画は、Deck A にロードされた Bank 01 の Layer 1〜8 のスロット1に、順に割り当てて ON にします。操作画面からも読み込めます(フォルダのアイコン、または Clip Matrix のマスを右クリック)。

初回起動では、Output Window を内蔵以外で最初のディスプレイに出します。なければ通常のウィンドウです。出力先は、操作画面か「表示」メニューで変えられます。

## 操作

### キーボード

| キー | 動作 |
|---|---|
| `1` `2` `3` | Fit Mode: 引き伸ばし / 黒帯 / 切り抜き |
| `4` `5` `6` `7` | Output Resolution: 720p / 1080p / 4K / ウィンドウに合わせる |
| `f` | フルスクリーン切り替え(Output Window) |
| `a` `s` | Edit Deck を A / B にする |
| `z` `x` | Deck A / B へ Cut |
| `←` `→` | Crossfader を 5% ずつ動かす |
| `Cmd+1`〜`Cmd+8` | Edit Layer を 1〜8 にする |
| `↑` `↓` | Edit Clip の不透明度を ±10% |
| `b` | Edit Clip の Blend Mode を切り替える |
| `m` | Edit Clip の ON/OFF |
| `Esc` / `Cmd+Q` | 終了 |

### APC mini MK2

| 操作子 | 動作 |
|---|---|
| パッド 8×8 | Clip の ON/OFF を切り替える(列 = Layer、行 = スロット、最上段がスロット1) |
| 下段のボタン 1〜8 | Layer の ON/OFF |
| 右列のボタン 1〜8 | いまのページの Bank 1〜8 を Edit Deck にロード |
| フェーダー 1〜8 | Layer の不透明度(Layer 内の全 Clip への倍率) |
| フェーダー 9 | Crossfader |
| `Shift` + 下段 1 / 2 | Edit Deck を A / B にする |
| `Shift` + 下段 3 / 4 | Deck A / B へ Cut |
| `Shift` + 右列 1〜4 | Bank のページを選ぶ(01〜08、09〜16、17〜24、25〜32) |
| `Shift` + フェーダー 9 | Master の明るさ |

フェーダーは Pickup 方式です。物理位置が画面上の現在の値に追いつくまで、動きを無視します。待っている間、操作画面には物理位置を黄色い輪で表示します。LED の動作と MIDI の割り当ては、[docs/controller-layout.ja.md](docs/controller-layout.ja.md) を参照してください。

## 用語

| 用語 | 意味 |
|---|---|
| **Clip** | スロットに割り当てる動画のループです。不透明度と Blend Mode を持ちます。 |
| **Layer** | 最大8個の Clip を同時に再生できる列です。フェーダー1本と ON/OFF を持ちます。 |
| **Bank** | 8本の Layer の組です。Bank Library に32個あります。 |
| **Deck** | Bank を1つロードする枠です。A と B の2つがあります。 |
| **Crossfader** | Deck A と Deck B をディゾルブで混ぜます。 |
| **Master** | 混ぜた後の最終映像と、その全体の明るさです。 |

用語の全体は [GLOSSARY.ja.md](GLOSSARY.ja.md) にあります。

## 描画のしくみ

```
Clip(AVFoundation) ─▶ Metal テクスチャ
   Deck ごと:  Layer 1 … Layer 8、スロット順に、画面外テクスチャへ Blend Mode で重ねる
   Deck A ─┐
           ├─ 混合(Crossfader × Master の明るさ) ─▶ Output Window
   Deck B ─┘
```

完全にフェードアウトした Deck は描画しませんが、動画の再生は続けます。Cut したときに拍がずれないようにするためです。ロード中の Bank がある間は、すべての動画の準備ができるまで、元の映像を出し続けます。

## プロジェクトの構成

```
Sources/VJCocteau/
  main.swift            アプリの起動、ウィンドウ、メニュー
  AppController.swift   メニュー、UI、コントローラーからの操作。出力ディスプレイ
  APCMini.swift         APC mini MK2 の入力、LED、Pickup(CoreMIDI)
  Renderer.swift        Metal 描画、Deck の合成と混合
  Layer.swift           ClipSlot、Layer、Bank、Deck、Blend Mode
  VideoClip.swift       動画を Metal テクスチャへ再生
  ControlView.swift     SwiftUI の操作画面
  Shaders/              Metal シェーダーのソース(起動時にコンパイル)
docs/                   コントローラーの割り当てと、設計判断の記録(ADR)
GLOSSARY.ja.md          プロジェクトの用語集
```

## ドキュメント

すべての文書を、英語と日本語(`*.ja.md`)で用意しています。

- [GLOSSARY.ja.md](GLOSSARY.ja.md) — 用語集
- [docs/controller-layout.ja.md](docs/controller-layout.ja.md) — APC mini MK2 の割り当てと MIDI の対応表
- [docs/adr/](docs/adr/) — 設計判断の記録(ADR)

## ロードマップ

- [x] 1. 動画 Clip を Output Window に出す
- [x] 2. Layer の合成と Blend Mode、操作画面
- [x] 3. APC mini MK2 の入出力、Clip Matrix、Bank Library と Deck
- [ ] 4. Effect を Metal シェーダーのファイル + パラメータ宣言で追加できるようにする(ホットリロード)
- [ ] 5. Beat Clock: タップテンポ、続いて音声入力からの Beat Detection、拍に揃えた切り替え
- [ ] 6. Set(32個の Bank 全体)の保存と読込

## ライセンス

[MIT License](LICENSE) で公開しています。

このリポジトリには動画を含めていません。各自で用意し、使う映像のライセンスを守ってください。
