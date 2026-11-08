float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    // 拍の頭で明るくなり、次の拍へ向けて減衰します。decay が大きいほど、すぐ暗くなります。
    float phase = fract(p.beat);
    float flash = pow(1.0 - phase, mix(0.5, 8.0, param_decay));
    float4 c = sample_src(tex, uv);
    return float4(c.rgb * (1.0 + param_amount * flash), c.a);
}
