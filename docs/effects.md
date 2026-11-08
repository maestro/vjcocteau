[English](effects.md) | [日本語](effects.ja.md)

# Writing Effects

An Effect is a folder with two files:

```
Effects/invert/
  effect.json    name and parameter declarations
  effect.metal   the shader
```

Built-in Effects live in `Sources/VJCocteau/Effects/`. Your own go in `~/Library/Application Support/VJ Cocteau/Effects/` (the folder button in the Effect panel opens it). If a name exists in both, yours wins. Saving a file reloads it within a second. If it fails to compile, the last working version keeps running and the error is shown in the panel.

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

| type | extra fields | value in the shader |
|------|--------------|---------------------|
| `float` | `default`, `min`, `max` | `float` |
| `bool` | `default` | `bool` |
| `color` | `default` as `[r, g, b]` | `float3` |
| `choice` | `options`, `default` (index) | `int` |

Parameters are read in the shader as `param_<key>`. The total is limited to 16 floats (a color counts as 3).

## effect.metal

Define one function:

```metal
float4 effect_main(float2 uv, texture2d<float> tex, constant EffectParams &p) {
    float4 c = sample_src(tex, uv);
    return float4(1.0 - c.rgb, c.a);
}
```

- `sample_src(tex, uv)` reads the input as a straight (non-premultiplied) color.
- Return a straight color. The host premultiplies it.
- `p.beat` is the beat position (beats since the last Downbeat, fractional); `fract(p.beat)` is the progress within a beat. `p.bpm` is the tempo.
- `p.time` is seconds since launch, `p.aspect` is width / height, `p.resolution` is the size in pixels.
- Chain order is top to bottom. Only single-pass, stateless Effects are supported (see ADR-0001).

## Where Effects apply

- **Layer** chain: the Layer's Clips are blended inside the Layer first, then the Effects run, then the result is laid over the lower Layers with Normal blending. A Layer without Effects blends its Clips directly onto the lower Layers.
- **Bank** chain: runs on the Bank's composited picture.
- **Master** chain: runs after Deck A and B are mixed, before Master brightness.
