float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    // size 0 でそのまま、1 で 8 ブロックまで粗くします。
    float blocks = mix(p.resolution.x, 8.0, pow(param_size, 0.5));
    float2 grid = float2(blocks, blocks / p.aspect);
    return sample_src(tex, (floor(uv * grid) + 0.5) / grid);
}
