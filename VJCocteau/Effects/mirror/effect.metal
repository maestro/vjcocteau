float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    float2 q = uv;
    int mode = param_mode;
    if (mode == 0 || mode == 2) { q.x = q.x < 0.5 ? q.x : 1.0 - q.x; }
    if (mode == 1 || mode == 2) { q.y = q.y < 0.5 ? q.y : 1.0 - q.y; }
    return sample_src(tex, q);
}
