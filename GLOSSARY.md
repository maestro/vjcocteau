[English](GLOSSARY.md) | [日本語](GLOSSARY.ja.md)

# VJ Cocteau

A native macOS VJ application. A performer uses a MIDI controller to switch and layer video, apply effects and sync to the tempo of the music, and sends the result to an external display.

## Language

### Picture structure

**Clip**:
A playable unit of video assigned to a slot of a Layer. Either a video loop or a Generator; each Clip has its own Blend Mode and opacity.
_Avoid_: source, footage, video

**Generator**:
A kind of Clip that has no video file and draws its picture on the fly from parameters.
_Avoid_: procedural clip, shader clip

**Layer**:
A column inside a Bank that can play up to 8 Clips at the same time. A Bank has 8 Layers; all Clips are stacked in one line — Layer 1 first, and within a Layer in slot order — to make the Bank's picture. A Layer has one fader (an opacity multiplier for all of its Clips) and an ON/OFF switch, but no Blend Mode.
_Avoid_: track, channel

**Bank**:
A set of 8 Layers. Each Bank has its own Layers, Clip Matrix and Effect Chain; there are 32 in the Bank Library.
_Avoid_: channel, A/B channel

**Bank Library**:
The list of all 32 Banks. Unused Banks stay empty.
_Avoid_: bank list, preset list

**Deck**:
A slot that holds one loaded Bank and plays it. There are two: Deck A and Deck B. The same Bank cannot be loaded into both Decks.
_Avoid_: channel, slot

**Edit Deck**:
The Deck that the controller and the screen currently operate on. It can differ from the Deck that is on air.
_Avoid_: Edit Bank, selected Deck, cue

**Edit Layer**:
The Layer being operated on, within the Bank loaded in the Edit Deck.
_Avoid_: selected Layer, active Layer

**Edit Clip**:
The Clip in the slot being operated on within the Edit Layer — for opacity, Blend Mode, loading and so on.
_Avoid_: selected Clip

**Crossfader**:
The fader that dissolves between Deck A and Deck B with a continuous value from 0 to 1. At either end, only one Deck is visible.
_Avoid_: mix, A/B fader

**Cut**:
Jumping the Crossfader straight to the Deck A end or the Deck B end.
_Avoid_: jump, switch

**Clip Matrix**:
An 8×8 grid of Layers (columns) and Clip slots (rows). There is one per Bank, and it maps to the controller's pad grid.
_Avoid_: grid, deck

**Effect**:
A swappable part that processes the picture of a Clip or Layer in real time. Users can add their own.
_Avoid_: filter, plugin

**Blend Mode**:
How a Clip is composited onto the picture beneath it. One of Normal, Add, Multiply, Screen.
_Avoid_: composite mode, mix mode

**Effect Chain**:
An ordered list of Effects applied at a Layer, a Bank or the Master. Up to 4 per place.
_Avoid_: effect stack, FX list

**Set**:
A saved unit for one live show: the Clip assignments of the whole Bank Library (all 32 Banks). Clips are not added or swapped during the show.
_Avoid_: project, preset, setlist

**Master**:
The final picture after the Crossfader mix, and its overall controls such as brightness.
_Avoid_: mix, main

### Output

**Output Window**:
The window that shows only the final picture. It goes full screen on an external display when one is chosen, and is a normal window otherwise.
_Avoid_: projector output, preview

**Fit Mode**:
How a Clip is fitted to the aspect ratio of the screen: stretch, letterbox, or crop.
_Avoid_: fit method, scale mode

**Output Resolution**:
The resolution (height) at which the final picture is rendered: 720p, 1080p, 4K, or follow the window. The width follows the aspect ratio of the Output Window.
_Avoid_: resolution setting, quality

### Tempo sync

**Beat Clock**:
The clock that holds the current BPM and beat position and decides the timing of the picture.
_Avoid_: metronome, tempo

**Beat Detection**:
Estimating BPM and beat position from the venue's audio input.
_Avoid_: BPM analysis

**Downbeat**:
The first beat of a bar. It is not detected from audio; the performer sets it by hand.
_Avoid_: bar start, one

**Launch Quantize**:
A setting for when a change takes effect after the performer asks for it: a Clip after a pad press, a Deck after a Cut, or a Deck's contents after a Bank load. It does not apply to continuous Crossfader movement. Either "immediate" or "next beat".
_Avoid_: quantize, snap

**Tap Tempo**:
Tapping the beat by hand to set the Beat Clock. Also used to correct it when Beat Detection goes wrong.

### Controller

**Controller Layout**:
The fixed table that assigns functions to each pad, fader and button of the APC mini MK2. The concrete assignments are in `docs/controller-layout.md`.
_Avoid_: mapping, MIDI Learn

**Pickup**:
A mechanism that ignores a fader's movement until its physical position catches up with the current on-screen value. It prevents values from jumping, for example after switching Decks.
_Avoid_: soft takeover, catch-up
