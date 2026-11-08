float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    float4 c = sample_src(tex, uv);
    float y = dot(c.rgb, float3(0.299, 0.587, 0.114));
    return float4(mix(c.rgb, float3(y) * param_tint, param_amount), c.a);
}
