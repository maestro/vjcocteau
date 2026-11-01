[English](0003-bank-library-two-decks.md) | [日本語](0003-bank-library-two-decks.ja.md)

# Banks live in a library of about 30 and are loaded into two Decks to be mixed

Banks are kept in a library of 32; two of them are loaded into Deck A and Deck B and mixed with the Crossfader. Only the two loaded Banks (up to 16 videos) are decoded; the rest of the library holds only video paths. This replaces ADR 0002's "two fixed Banks". It lets us prepare many Banks for a set while keeping the playback load to two Banks' worth. The offscreen-composite structure from ADR 0002 carries over to the Decks unchanged.

## Considered Options

- **Play all 32 Banks at the same time**: removes load waits, but means decoding 8 Layers × 32 = 256 videos at once, which is not realistic.
- **Keep the two Banks and do not add more**: simplest to implement, but the work of rearranging Clips per Bank concentrates in the preparation before a show.

## Consequences

- There is a wait between loading a Bank into a Deck and the first picture appearing. We accept up to about 500 ms for a Deck that is not on air. While loading, the original Bank stays on air, and the contents are swapped according to Launch Quantize once loading finishes. We do not time out: we chose a delayed swap over showing a half-loaded picture. Loading a different Bank cancels the load in progress. Videos that cannot be played (for example a corrupt file) count as done so we never wait forever.
- The same Bank cannot be loaded into both A and B, because Layer opacity and Clip state would be shared.
- A Set stores the contents of all 32 Banks.
- How Banks are chosen on the APC mini MK2 is decided in stage 3 together with the Controller Layout. Until then they are chosen from the on-screen UI.
