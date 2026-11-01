[English](controller-layout.md) | [日本語](controller-layout.ja.md)

# APC mini MK2 Controller Layout

Source: Akai Professional, "APC mini mk2 Communications Protocol v1.0". Not yet verified on real hardware.

## Input

| Control | Action |
|---|---|
| 8×8 pads | Column = Layer 1–8, row = slot (the top row is slot 1). Each press toggles that Clip ON/OFF. Acts on the Bank in the Edit Deck. |
| Bottom track buttons 1–8 | Layer ON/OFF for that column |
| Right scene buttons 1–8 | Load Bank 1–8 of the current page into the Edit Deck |
| Faders 1–8 | Layer opacity (a multiplier for every Clip in the Layer) |
| Fader 9 | Crossfader (A side = down) |
| `Shift` + track button 1 / 2 | Edit Deck A / B |
| `Shift` + track button 3 / 4 | Cut to Deck A / B |
| `Shift` + track buttons 5–8 | To be decided in stage 5 together with the Beat Clock (unassigned for now) |
| `Shift` + scene buttons 1–4 | Select the Bank page (01–08, 09–16, 17–24, 25–32) |
| `Shift` + fader 9 | Master brightness |

All faders use Pickup: the value does not change until the physical position reaches the current value.

## LEDs

| Place | Display |
|---|---|
| Pads | Off when nothing is assigned, dim (25%) when OFF, bright (100%) when ON. Columns whose Layer is OFF are dimmer still (10%). Color: blue for Deck A, magenta for Deck B. |
| Track buttons (red) | Lit when the Layer is ON. While `Shift` is held, the Edit Deck (1, 2) is lit and Cut (3, 4) is lit only while pressed. |
| Scene buttons (green) | Lit for a Bank loaded in a Deck, blinking while loading. While `Shift` is held, the current page (1–4) is lit. |

## MIDI map (from the specification)

- Pad notes: 0 at the bottom left, increasing left to right row by row, 63 at the top right
- Track buttons: notes 100–107. Scene buttons: notes 112–119. Shift: note 122
- Faders: CC 48–56
- Pad color: the note-on velocity is the palette index (blue 45, magenta 53). Brightness is set by the MIDI channel (ch 1 = 25%, ch 6 = 100%, ch 0 = 10%)
- Track and scene buttons: velocity 0 = off, 1 = on, 2 = blink
