float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    float2 d = float2(cos(param_angle), sin(param_angle)) * param_amount * 0.03;
    float4 c = sample_src(tex, uv);
    return float4(sample_src(tex, uv + d).r, c.g, sample_src(tex, uv - d).b, c.a);
}
