# VJ Cocteau

[English](README.md) | [日本語](README.ja.md)

A native macOS VJ application. Switch, layer and (soon) process live video from a MIDI controller, and output it to an external display or projector.

Built with Swift, Metal, AVFoundation and CoreMIDI. Designed around the Akai Professional **APC mini MK2**.

> **Status: early development.** Stages 1–6 are implemented (see [Roadmap](#roadmap)). The APC mini MK2 integration has been tested only against a simulated MIDI device, **not yet on real hardware**.

## Features

- **Native and fast** — Metal rendering at 60 fps, hardware-decoded video through AVFoundation.
- **Layered compositing** — 8 Layers × 8 Clip slots per Bank. Every Clip has its own opacity and Blend Mode (Normal, Add, Multiply, Screen).
- **32 Banks, two Decks** — keep up to 32 Banks in a library, load any two into Deck A and Deck B, and mix them with a Crossfader. Only the two loaded Banks are decoded.
- **APC mini MK2 as the main instrument** — the 8×8 pad grid is the Clip Matrix; faders, buttons and LEDs are wired up with soft-takeover (Pickup) so values never jump.
- **External display output** — pick the output display from the UI; the choice is remembered. Output resolution (720p / 1080p / 4K / follow window) and Fit Mode (stretch / letterbox / crop) are adjustable.
- **Dark control window** — a separate control window with the Crossfader, Bank Library, Clip Matrix and per-Clip settings.

- **Modular Effects** — drop a folder with a Metal shader and a JSON parameter declaration to add an Effect, with hot-reload. Up to 4 Effects each on a Layer, a Bank, and the Master output. See [docs/effects.md](docs/effects.md).

- **Beat Clock** — set the BPM by tap tempo or by hand. Clip ON, Cut and Bank swaps wait for the next beat (Launch Quantize: none / 1 beat / 1 bar). Effects can read the beat position as `p.beat` (see the Beat Pulse Effect).

- **Beat Detection** — pick an audio input (for example an interface fed from the venue mixer) and the app follows its tempo and beat position from the low-frequency onsets. Downbeats stay manual, and tapping or typing a BPM switches detection off. macOS asks for microphone access the first time (when started from a terminal, the permission may be asked of the terminal app instead).

- **Sets** — save and load all 32 Banks (Clip paths, opacity, Blend Modes, Layer/Bank/Master Effect Chains) as one JSON file from the **File** menu (`⌘O` / `⌘S` / `⇧⌘S`). Video files are referenced by path, not copied, and the Set remembers a path relative to itself too, so a Set and its footage can move together. Clips start OFF after loading. App settings (display, Fit Mode, resolution, audio input, BPM, Launch Quantize) are stored separately and are not part of a Set. The last Set is reopened at launch.

## Packaging

In Xcode, choose Product → Archive, then Distribute App → Copy App to get `VJ Cocteau.app`. The project is ad-hoc signed, which is enough for your own Mac; a copy downloaded onto another Mac is blocked by Gatekeeper (right-click → Open). For distribution, set your team and a Developer ID signing identity in the target's Signing & Capabilities, and notarize through the Archive organizer.

## Requirements

- macOS 14 or later (developed on Apple Silicon)
- Xcode with the Swift toolchain (Swift 5.9 or later)
- Your own video clips (H.264 / HEVC / ProRes in `.mov` or `.mp4`)
- Optional: Akai Professional APC mini MK2

## Build and run

```sh
open VJCocteau.xcodeproj   # then Run (⌘R) in Xcode
# After editing project.yml: brew install xcodegen && xcodegen generate
```

The optional arguments are assigned, in order, to slot 1 of Layers 1–8 of Bank 01 (loaded in Deck A) and switched ON. You can also load clips from the control window (click the folder icon, or right-click a cell of the Clip Matrix).

On first launch the Output Window goes to the first non-built-in display, or to a normal window if there is none. Change it from the control window or the **View** menu.

## Controls

### Keyboard

| Key | Action |
|---|---|
| `1` `2` `3` | Fit Mode: stretch / letterbox / crop |
| `4` `5` `6` `7` | Output Resolution: 720p / 1080p / 4K / follow window |
| `⌘O` `⌘S` `⇧⌘S` | Open Set / save Set / save Set as |
| `f` | Toggle full screen (Output Window) |
| `a` `s` | Edit Deck A / B |
| `z` `x` | Cut to Deck A / B |
| `←` `→` | Move the Crossfader by 5% |
| `Cmd+1`–`Cmd+8` | Edit Layer 1–8 |
| `↑` `↓` | Edit Clip opacity ±10% |
| `b` | Cycle the Edit Clip's Blend Mode |
| `m` | Toggle the Edit Clip ON/OFF |
| `Esc` / `Cmd+Q` | Quit |

### APC mini MK2

| Control | Action |
|---|---|
| 8×8 pads | Toggle a Clip ON/OFF (column = Layer, row = slot, top row = slot 1) |
| Bottom buttons 1–8 | Layer ON/OFF |
| Right buttons 1–8 | Load Bank 1–8 of the current page into the Edit Deck |
| Faders 1–8 | Layer opacity (multiplier for every Clip in the Layer) |
| Fader 9 | Crossfader |
| `Shift` + bottom 1 / 2 | Edit Deck A / B |
| `Shift` + bottom 3 / 4 | Cut to Deck A / B |
| `Shift` + right 1–4 | Select Bank page (01–08, 09–16, 17–24, 25–32) |
| `Shift` + bottom 5 / 6 / 7 / 8 | Tap Tempo / Downbeat / cycle Launch Quantize / Beat Detection on-off |
| `Shift` + fader 9 | Master brightness |

Faders use Pickup: a fader is ignored until it reaches the current on-screen value. The control window shows a yellow ring at the physical position while a fader is waiting. See [docs/controller-layout.md](docs/controller-layout.md) for LED behavior and the MIDI map.

## Concepts

| Term | Meaning |
|---|---|
| **Clip** | A video loop assigned to a slot. Has its own opacity and Blend Mode. |
| **Layer** | A column of up to 8 Clips that play at the same time, with one fader and an ON/OFF switch. |
| **Bank** | A set of 8 Layers. 32 Banks live in the Bank Library. |
| **Deck** | A slot that holds one loaded Bank. There are two: A and B. |
| **Crossfader** | Dissolves between Deck A and Deck B. |
| **Master** | The final mixed picture and its overall brightness. |

The full vocabulary is in [GLOSSARY.md](GLOSSARY.md).

## How it renders

```
Clip (AVFoundation) ─▶ Metal texture
   per Deck:  Layer 1 … Layer 8, slots in order, each blended onto an offscreen texture
   Deck A ─┐
           ├─ mix (Crossfader × Master brightness) ─▶ Output Window
   Deck B ─┘
```

A Deck that is fully faded out is not drawn, but its videos keep playing so that a cut lands in sync. A Bank that is being loaded keeps the old picture on air until every video is ready.

## Project layout

```
VJCocteau/
  main.swift            app setup, windows, menus
  AppController.swift   actions from the menu, UI and controller; output display
  APCMini.swift         APC mini MK2 input, LEDs, Pickup (CoreMIDI)
  Renderer.swift        Metal rendering, Deck compositing and mixing
  Layer.swift           ClipSlot, Layer, Bank, Deck, Blend Mode
  VideoClip.swift       video playback to Metal textures
  ControlView.swift     SwiftUI control window
  Shaders/              Metal shader source, compiled at launch
docs/                   controller layout and architecture decision records
GLOSSARY.md             project vocabulary
```

## Documentation

All documents are available in English and Japanese (`*.ja.md`).

- [GLOSSARY.md](GLOSSARY.md) — vocabulary
- [docs/effects.md](docs/effects.md) — writing your own Effects
- [docs/controller-layout.md](docs/controller-layout.md) — APC mini MK2 layout and MIDI map
- [docs/adr/](docs/adr/) — architecture decision records

## Roadmap

- [x] 1. Play a video clip in the Output Window
- [x] 2. Layer compositing and Blend Modes, control UI
- [x] 3. APC mini MK2 input/output, Clip Matrix, Bank Library and Decks
- [x] 4. Effects as Metal shader files with parameter declarations, hot-reload
- [x] 5. Beat Clock: tap tempo, beat detection from audio input, quantized launches
- [x] 6. Save and load a Set (all 32 Banks)

## License

Released under the [MIT License](LICENSE).

This repository does not include any video clips. Bring your own, and respect the license of any footage you use.
