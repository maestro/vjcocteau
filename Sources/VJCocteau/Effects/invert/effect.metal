float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    float4 c = sample_src(tex, uv);
    return float4(mix(c.rgb, 1.0 - c.rgb, param_amount), c.a);
}
