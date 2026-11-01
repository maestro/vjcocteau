---
status: superseded by ADR-0003
---

[English](0002-two-banks-offscreen-composite.md) | [日本語](0002-two-banks-offscreen-composite.ja.md)

# Bank は固定2つで、各 Bank を画面外テクスチャに合成してから混ぜる

Layer を8本ずつ束ねた Bank A と Bank B の2つを持ち、Crossfader で A↔B を混ぜます。各 Bank は Layer を画面外のテクスチャに合成し、その結果を最後のパスで重み付けして画面へ出します。Bank 単位の Effect と、将来のトランジションを自然に差し込めることを優先しました。

## Considered Options

- **Layer 16本を1枚の画面に直接重ねる**: 描画パスが1つで軽く、メモリも少なくて済みます。しかし Bank 単位の Effect や、A と B を別々に混ぜる処理を後から入れにくくなります。
- **Bank を3つ以上にする**: 表現の幅は広がりますが、APC mini MK2 の操作面(フェーダー9本、ボタン各8個)に収まらず、見えない Bank の再生負荷も増えます。

## Consequences

- 画面外テクスチャを Bank 2枚分、描画解像度で持つため、4K ではメモリと帯域の負担が増えます。
- Crossfader が端にあるときは、見えない Bank の描画を省略します。動画の再生は止めず、切り替えた瞬間に頭出しからにならないようにします。
- Bank の数は固定で2つです。増やす場合は、この ADR を見直し、Controller Layout も合わせて作り直します。
