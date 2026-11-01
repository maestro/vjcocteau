[English](0004-clip-level-blend-flat-stack.md) | [日本語](0004-clip-level-blend-flat-stack.ja.md)

# Blend Mode と不透明度は Clip が持ち、Layer は列としてまとめるだけにする

各 Layer は最大8個の Clip を同時に再生できます。Blend Mode と不透明度は Clip ごとに持たせ、Layer は「列のまとまり」とフェーダー1本(Layer 内の全 Clip への不透明度の倍率)と ON/OFF だけを持ちます。重ねる順序は、Layer 1 の Clip から順に、Layer の中ではスロット番号順に、すべての Clip を一列にします。APC mini MK2 のパッド 8×8 を、そのまま Clip の ON/OFF の格子として使えるようにするためです。

## Considered Options

- **Layer も Blend Mode を持つ**: Layer 内の Clip を先に1枚へ合成してから、下の Layer へ重ねます。Layer 全体を1枚として薄くしたり、別の Blend Mode で重ねたりできますが、Layer ごとに画面外テクスチャが要り、描画パスと負荷が増えます。
- **Layer は1度に1つの Clip だけを再生する**: 実装は最も単純ですが、APC のパッド 8×8 を ON/OFF の格子として使う操作性を失います。

## Consequences

- 画面外テクスチャは Deck ごとの2枚で済みます。Layer ごとの合成は不要です。
- Layer のフェーダーを下げたときの見え方は、Layer 全体を薄くするのとは異なります。Normal で重ねた Clip は、それぞれが個別に薄くなり、下の Clip が透けて見えます。
- 1つの Bank で最大64本、2つの Deck で最大128本の動画を開いたままにします。ON でない Clip は、先頭で停止したままです。ON にした時点で頭から再生します。この負荷は、実機で測ってから制限を決めます。
