---
status: superseded by ADR-0003
---

[English](0002-two-banks-offscreen-composite.md) | [日本語](0002-two-banks-offscreen-composite.ja.md)

# Two fixed Banks, each composited to an offscreen texture before mixing

There are two Banks, A and B, each bundling 8 Layers, mixed by a Crossfader. Each Bank composites its Layers into an offscreen texture, and a final pass weights and writes the result to the screen. We prioritized being able to add per-Bank Effects and future transitions naturally.

## Considered Options

- **Draw all 16 Layers directly onto one screen**: a single render pass, lighter and using less memory. But per-Bank Effects and mixing A and B separately would be hard to add later.
- **Three or more Banks**: more expressive, but it does not fit the APC mini MK2 control surface (9 faders, 8 buttons per side) and raises the playback load of Banks that are not visible.

## Consequences

- Two offscreen textures at the render resolution are kept, which increases memory and bandwidth use at 4K.
- When the Crossfader is at an end, the invisible Bank is not drawn. Its videos keep playing so a cut does not restart from the beginning.
- The number of Banks is fixed at two. Increasing it means revisiting this ADR and rebuilding the Controller Layout.
