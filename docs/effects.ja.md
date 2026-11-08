[English](effects.md) | [日本語](effects.ja.md)

# Effect の書き方

Effect は、2つのファイルを入れたフォルダです。

```
Effects/invert/
  effect.json    名前とパラメータの宣言
  effect.metal   シェーダー
```

標準の Effect は `VJCocteau/Effects/` にあります。自作の Effect は `~/Library/Application Support/VJ Cocteau/Effects/` に置きます(Effect パネルのフォルダボタンで開けます)。同じ名前が両方にあれば、自作が優先です。ファイルを保存すると、1秒以内に読み込み直します。コンパイルに失敗しても、直前に動いた版が動き続けます。エラーはパネルに表示されます。

## effect.json

```json
{
  "name": "Grayscale",
  "params": [
    { "key": "amount", "label": "Amount", "type": "float", "default": 1, "min": 0, "max": 1 },
    { "key": "tint", "label": "Tint", "type": "color", "default": [1, 1, 1] }
  ]
}
```

| type | 追加の項目 | シェーダーでの値 |
|------|-----------|-----------------|
| `float` | `default`、`min`、`max` | `float` |
| `bool` | `default` | `bool` |
| `color` | `default`(`[r, g, b]`) | `float3` |
| `choice` | `options`、`default`(番号) | `int` |

パラメータは、シェーダーの中で `param_<key>` として読めます。合計は Float 16個分までです(色は3個分)。

## effect.metal

関数を1つ定義します。

```metal
float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    float4 c = sample_src(tex, uv);
    return float4(1.0 - c.rgb, c.a);
}
```

- `sample_src(tex, uv)` は、入力を、透明度を分けた(premultiplied でない)色で読みます。
- 返す色も、透明度を分けた色にします。本体が premultiplied にします。
- `p.beat` は拍の位置(最後の Downbeat からの拍数、小数つき)です。`fract(p.beat)` が、拍の中の進み具合になります。`p.bpm` はテンポです。
- `p.time` は起動からの秒数、`p.aspect` は 幅 / 高さ、`p.resolution` はピクセル単位の大きさです。
- Chain は上から順にかかります。対応するのは、1パスでステートを持たない Effect だけです(ADR-0001 を参照)。

## Effect がかかる範囲

- **Layer** の Chain: 先に Layer の中で Clip を合成し、Effect をかけ、Normal で下の Layer の上に重ねます。Effect のない Layer は、今まで通り Clip を直接、下の Layer に重ねます。
- **Bank** の Chain: Bank の合成結果にかかります。
- **Master** の Chain: Deck A と B を混ぜたあと、Master の明るさの前にかかります。
