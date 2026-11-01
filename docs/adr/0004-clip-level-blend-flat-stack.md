[English](0004-clip-level-blend-flat-stack.md) | [日本語](0004-clip-level-blend-flat-stack.ja.md)

# Blend Mode and opacity belong to the Clip; a Layer only groups a column

Each Layer can play up to 8 Clips at the same time. Blend Mode and opacity belong to each Clip. A Layer only has one fader (an opacity multiplier for all Clips in the Layer) and an ON/OFF switch. Clips are stacked in one line: Layer 1's Clips first, and within a Layer in slot order. This lets the APC mini MK2's 8×8 pad grid act directly as a grid of Clip ON/OFF switches.

## Considered Options

- **Layers also have a Blend Mode**: composite the Clips of a Layer into one picture first, then blend it onto the Layers below. This allows fading a whole Layer as one picture or blending it with a different mode, but needs an offscreen texture per Layer, which adds render passes and load.
- **A Layer plays only one Clip at a time**: simplest to implement, but loses the usability of treating the 8×8 pad grid as ON/OFF switches.

## Consequences

- Only two offscreen textures (one per Deck) are needed. No per-Layer compositing.
- Lowering a Layer fader looks different from fading the Layer as a whole. Clips blended with Normal each fade individually, so Clips beneath show through.
- One Bank keeps up to 64 videos open, and two Decks up to 128. Clips that are not ON stay paused at the first frame; turning one ON plays it from the beginning. The load of this will be measured on real hardware before deciding on limits.
