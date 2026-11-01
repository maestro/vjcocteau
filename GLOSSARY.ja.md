[English](GLOSSARY.md) | [日本語](GLOSSARY.ja.md)

# VJ Cocteau

ライブ会場で、MIDI コントローラーを使って映像を切り替え、重ね合わせ、エフェクトをかけ、音楽のテンポに同期させて外部ディスプレイへ出力する、Mac 向けの VJ ソフトウェアです。

## Language

### 映像の構成

**Clip**:
Layer のスロットに割り当てる、再生できる映像の単位です。動画ループまたは Generator のどちらかで、それぞれが Blend Mode と不透明度を持ちます。
_Avoid_: ソース、素材、ビデオ

**Generator**:
映像ファイルを持たず、パラメータから映像をその場で描画する Clip の種類です。
_Avoid_: プロシージャル clip、シェーダー clip

**Layer**:
Bank の中にある、最大8個の Clip を同時に再生できる列です。1つの Bank に8本あり、Layer 1 の Clip から順に、Layer の中ではスロット番号順に、すべての Clip を一列に重ねて Bank の映像をつくります。Layer はフェーダー1本(その Layer の全 Clip への不透明度の倍率)と ON/OFF を持ち、Blend Mode は持ちません。
_Avoid_: トラック、チャンネル

**Bank**:
8本の Layer をまとめた1組です。それぞれが独立した Layer、Clip Matrix、Effect Chain を持ち、Bank Library に32個あります。
_Avoid_: チャンネル、A/B チャンネル

**Bank Library**:
32個の Bank を並べた一覧です。使わない Bank は空のままです。
_Avoid_: バンクリスト、プリセット一覧

**Deck**:
Bank を1つロードして再生する枠です。Deck A と Deck B の2つがあります。同じ Bank を両方の Deck にロードすることはできません。
_Avoid_: チャンネル、スロット

**Edit Deck**:
コントローラーと画面の操作が向いている Deck です。いま映っている Deck とは別に選べます。
_Avoid_: Edit Bank、選択中の Deck、キュー

**Edit Layer**:
Edit Deck にロードされた Bank の中で、操作が向いている Layer です。
_Avoid_: 選択中の Layer、アクティブ Layer

**Edit Clip**:
Edit Layer の中で、不透明度、Blend Mode、読み込みなどの操作が向いているスロットの Clip です。
_Avoid_: 選択中の Clip

**Crossfader**:
Deck A と Deck B を、0〜1 の連続値でディゾルブして混ぜるフェーダーです。端に動かすと片方の Deck だけが映ります。
_Avoid_: ミックス、A/B フェーダー

**Cut**:
Crossfader の位置を、Deck A または Deck B の端へ一気に切り替える操作です。
_Avoid_: ジャンプ、スイッチ

**Clip Matrix**:
Layer(列)と Clip のスロット(行)でできた8×8の格子です。Bank ごとに1つあり、コントローラーのパッド格子に対応します。
_Avoid_: グリッド、デッキ

**Effect**:
Clip または Layer の映像に、リアルタイムで加工をかける差し替え可能な部品です。ユーザーが自分で追加できます。
_Avoid_: フィルター、プラグイン

**Blend Mode**:
Clip を、下に重なっている映像へ重ねるときの合成方法です。Normal、Add、Multiply、Screen から選びます。
_Avoid_: 合成モード、ミックスモード

**Effect Chain**:
Layer、Bank、Master のいずれかにかけられる、順番付きの Effect の列です。1か所あたり最大4個です。
_Avoid_: エフェクトスタック、FX リスト

**Set**:
ライブ1回分の、Bank Library 全体(32個の Bank)の Clip の割り当てを保存した単位です。ライブ中は Clip の追加や差し替えをしません。
_Avoid_: プロジェクト、プリセット、セットリスト

**Master**:
Crossfader で混ぜた後の最終映像と、その全体操作(明るさなど)を指します。
_Avoid_: ミックス、メイン

### 出力

**Output Window**:
最終映像だけを表示するウィンドウです。外部ディスプレイがあればそこへ全画面で出し、なければ通常のウィンドウで出します。
_Avoid_: プロジェクター出力、プレビュー

**Fit Mode**:
Clip を画面の縦横比に合わせるときの、はめ込み方です。「引き伸ばし」「黒帯」「切り抜き」から選びます。
_Avoid_: フィット方法、スケールモード

**Output Resolution**:
最終映像を描画する解像度(高さ)です。720p、1080p、4K、ウィンドウに合わせる、から選び、幅は Output Window の縦横比から決まります。
_Avoid_: 解像度設定、画質

### テンポ同期

**Beat Clock**:
現在の BPM と拍の位置を保持し、映像のタイミングを決める時計です。
_Avoid_: メトロノーム、テンポ

**Beat Detection**:
会場の音声入力から BPM と拍の位置を推定することです。
_Avoid_: BPM 解析

**Downbeat**:
小節の1拍目です。音声からは判別しないため、演者が手動で指定します。
_Avoid_: 小節頭、ワン

**Launch Quantize**:
パッドを押してから Clip が、Cut を押してから Deck が、Bank をロードしてから Deck の中身が、実際に切り替わるタイミングの設定です。Crossfader の連続操作には適用しません。「即時」または「次の拍の頭」から選びます。
_Avoid_: クオンタイズ、スナップ

**Tap Tempo**:
手動で拍を叩いて Beat Clock を合わせる操作です。Beat Detection が外れたときの手動補正にも使います。

### コントローラー

**Controller Layout**:
APC mini MK2 の各パッド、フェーダー、ボタンに割り当てる機能の固定された対応表です。具体的な割り当ては `docs/controller-layout.ja.md` にあります。
_Avoid_: マッピング、MIDI Learn

**Pickup**:
フェーダーの物理位置が、画面上の現在の値に追いつくまで、フェーダーの動きを無視する仕組みです。Deck の切り替えなどで値が急に飛ぶことを防ぎます。
_Avoid_: ソフトテイクオーバー、キャッチアップ
