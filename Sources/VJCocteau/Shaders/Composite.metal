#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// fitMode 0: 引き伸ばし / 1: 縦横比を保って黒帯 / 2: 縦横比を保って切り抜き
// blendMode 0: Normal / 1: Add / 2: Multiply / 3: Screen
struct Uniforms {
    float viewAspect;
    float clipAspect;
    int fitMode;
    float opacity;
    int blendMode;
    int layerTarget; // 1: Layer 用の中間テクスチャ(透明度つき)へ描く
};

// 画面全体を覆う1枚の三角形を描画します。
vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(pos[vid], 0, 1);
    out.uv = float2((pos[vid].x + 1) * 0.5, 1 - (pos[vid].y + 1) * 0.5);
    return out;
}

// 1枚の Layer を描画します。実際の合成は、Blend Mode ごとに設定した
// ブレンド係数(Renderer 側)で行います。ここでは各モードに合わせた値を出力します。
fragment float4 layer_fragment(VertexOut in [[stage_in]],
                               texture2d<float> clip [[texture(0)]],
                               constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 p = in.uv - 0.5;
    if (u.fitMode != 0) {
        // 黒帯は広い側を、切り抜きは狭い側を基準に合わせます。
        bool viewWider = u.viewAspect > u.clipAspect;
        bool scaleX = (u.fitMode == 1) ? viewWider : !viewWider;
        if (scaleX) { p.x *= u.viewAspect / u.clipAspect; }
        else        { p.y *= u.clipAspect / u.viewAspect; }
    }
    // 動画の外側(黒帯の部分)は透明として扱い、下の Layer を隠しません。
    float coverage = (abs(p.x) > 0.5 || abs(p.y) > 0.5) ? 0.0 : 1.0;
    float a = u.opacity * coverage;
    float3 src = clip.sample(s, p + 0.5).rgb;

    switch (u.blendMode) {
    case 2:  return float4(mix(float3(1.0), src, a), 1.0); // Multiply: dst * out
    case 3:  return float4(src * a, u.layerTarget != 0 ? a : 1.0); // Screen: out + dst*(1-out)
    default: return float4(src, a);                        // Normal / Add: 係数が alpha を使う
    }
}

// Bank A と Bank B の映像を Crossfader の重みで混ぜ、Master の明るさをかけます。
struct MixUniforms {
    float weightA;
    float weightB;
    float brightness;
};

fragment float4 mix_fragment(VertexOut in [[stage_in]],
                             texture2d<float> bankA [[texture(0)]],
                             texture2d<float> bankB [[texture(1)]],
                             constant MixUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 a = bankA.sample(s, in.uv).rgb;
    float3 b = bankB.sample(s, in.uv).rgb;
    return float4((a * u.weightA + b * u.weightB) * u.brightness, 1.0);
}


// Effect をかけた Layer の中間テクスチャ(透明度つき)を、Bank へ重ねます。
struct CompositeUniforms { float opacity; };

fragment float4 composite_fragment(VertexOut in [[stage_in]],
                                   texture2d<float> layer [[texture(0)]],
                                   constant CompositeUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = layer.sample(s, in.uv);
    return c * u.opacity; // 透明度を掛けた色なので、そのまま重ねられます
}

// 最終映像に Master の明るさをかけて、画面へ出します。
fragment float4 present_fragment(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant float &brightness [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return float4(tex.sample(s, in.uv).rgb * brightness, 1.0);
}
