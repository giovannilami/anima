# Anima

**Anima** is an eight-track, two-dimensional sequencer for monome norns and a 16×8 Grid. Draw lines on the Grid; their active steps generate notes as they move and intersect. Each track can use its own clock division, direction, articulation, modulation and output route.

Anima is an adaptation and extension of [Animator by Crim](https://github.com/crimclark/animator). It imports Animator and Animator 2 doodles, and can optionally run imported projects with Animator's original playback rules.

> **Release status:** version 0.5.6 is the prepared release build. Its interface and software behavior have been exercised in local simulations; hardware checks for audio, MIDI, Crow, n.b. voices and the Grid remain necessary. See [verification notes](docs/VERIFICA_IT.md).

## Screen guide

These diagrams are approximate interface schematics based on `lib/ui.lua`, not pixel-accurate screenshots. The line drawing, selected track and live values change during use.

![Anima's Canvas, Lines, Intersections, and page-selection screens as rendered on the norns OLED](docs/images/norns-screen.svg)

## Install

Copy the `anima` folder into `dust/code/` using [Maiden](https://monome.org/docs/norns/maiden/), then select `anima` from the norns **SELECT** menu. To install from the Maiden REPL after this repository is public:

```text
;install https://github.com/giovannilami/anima
```

Anima requires the `MollyThePoly` engine and its supporting library. If Molly the Poly is not already installed, enter the following in the Maiden REPL and restart norns before running Anima:

```text
;install https://github.com/markwheeler/molly_the_poly
```

A Grid is required for drawing and performance controls. MIDI, Crow, Just Friends, ER-301 and n.b. destinations are optional. n.b. voice choices come from the n.b. libraries and voice mods installed on the device; Anima does not bundle those third-party voices.

Anima stores its projects in `dust/data/anima/`. In **PARAMETERS → EDIT → SAVE/LOAD**, use `load Animator 2 doodle` or `load Animator original` to import a project and its adjacent `.pset`. The source project is left in its original data folder; saving from Anima writes a new copy.

## Grid pages

Hold the bottom-right pad **(16,8)**, press a page selector, then release:

| Pad | Page |
| --- | --- |
| (13,8) | Canvas |
| (14,8) | Lines |
| (15,8) | Intersections |

The corner pad alone does not change page. While it is held, page selection takes precedence over other bottom-row actions, including controls for track 8.

### Canvas

Hold two pads to draw a straight horizontal, vertical or diagonal line. Press pads on a line to toggle its steps. On the bottom row, pads 1–8 recall snapshots, 10–11 record or play snapshot sequences, 13 undo (hold ALT on 15 and press 13 to redo), and 15 is ALT. Pads 9, 12 and 14 are blank. Hold pads 15 and 1–8 together to overwrite a snapshot.

On Canvas, E2 moves all lines vertically and E3 moves all lines horizontally. K2 resets the page; K3 clears it. Undo covers manual drawing, deletion, step toggles, clear and encoder moves during the current session.

### Lines

Each Grid row controls one track. Tap column 1 to mute; hold for solo. Columns 2–5 set direction (forward, reverse, pendulum, random); 6 toggles ratchet; 7 toggles probability; 8 is a separator; 9–15 select rates ×2, ×1, ÷2, ÷3, ÷4, ÷6 and ÷8. Hold 6 or 7 to freeze or release that modulated value. A long press does not also perform the tap.

E1 selects a track; E2/E3 move it. Probability amount, repeat count and other track values are set in **PARAMETERS → EDIT → TRACK**.

### Intersections

Columns 1–5 select harmonic actions, 6 separates the groups, and 7–12 select rhythmic actions. Press the active action again to turn it off. Column 13 is blank. Column 14 toggles the track's LFO master; hold it to freeze or release all mapped destinations. Hold column 15 on a track row to show that track's moving line on the norns screen while Grid remains on Intersections. E1 selects a track; E2/E3 move it.

Existing tracks have dim available pads; selected actions are bright. Empty rows, separators and unassigned columns stay dark. Frozen controls blink at 2 Hz, including while transport is stopped.

## What the norns screen shows

| View | Display |
| --- | --- |
| Canvas | `anima / CANVAS`, the 16×7 drawing area, then save feedback or `K2 reset   K3 clear` |
| Lines | Track number and optional `ORIG`; direction/rate and active MUTE/SOLO flags; output (including selected n.b. voice); probability and source; ratchet and source; then mapped octave, transpose, duration and velocity values |
| Intersections | Selected harmonic and rhythmic actions; LFO state; effective rate, probability and ratchet |
| Page selection | `SELECT PAGE`, the three page names, and the hold instruction |
| Track preview | `TRACK n`, that track's active steps, and `release 15: parameters` |

The Lines screen uses `BASE`, `LFO` or `HOLD` to identify probability/ratchet values. Its dim final row uses `O`, `T`, `L` and `V` for other mapped destinations; `*` marks a frozen value. Intersections reports `Poff`/`Roff` when those controls are disabled and `R2 int` for intersection-only retrigger. Live screen readings update about ten times per second; musical values are still sampled at step boundaries.

## Per-track modulation

Each track has two independent LFOs, with up to two destinations each: probability, velocity, note length, rate, octave, semitone transposition or ratchet count. Choose shape, clock-synced beats or free seconds, and a range for each mapping. In **EDIT → LFO**, `section` selects general LFO or track 1–8, and `oscillator` selects LFO 1/2; only that selection's controls are shown. The two legacy global position LFOs remain under general LFO.

An LFO replaces the corresponding manual value while enabled; it does not overwrite the saved base. Track step values are sampled at the start of each step. A freeze holds the last sampled value while other destinations keep moving. Freeze state is temporary and is cleared on project or snapshot recall.

Ratchet count ranges from 0–4: zero is a rest when ratchet or retrigger is active. With probability enabled, each strike in a ratchet/retrigger burst gets its own probability decision, including the first; skipped strikes keep their timing slots.

## Outputs and compatibility

Each track independently routes to internal synth, n.b., MIDI, fixed Crow pairs, original Animator-style Crow CV, Just Friends, ER-301, or supported combinations with MIDI. Set route-specific ports, channels and n.b. voices in **EDIT → TRACK**. The global maximum-note limit applies. Crow pitch/gate pairs are monophonic; use a polyphonic destination for chords.

Imported Animator projects can select **COMPOSITION → playback = Animator original**. The screen then shows `ORIG`. This mode preserves the original project's supported division, intersection and articulation behavior. Choose `anima` playback to use Anima's expanded per-track controls. New Anima projects use Anima playback.

## Verification

The source includes a local test suite (`tests/run.sh`). The 0.5.6 development record reports 134 passing local scenarios, including parameter, persistence, migration, playback, modulation, Grid, routing and cleanup simulations. Devices and n.b. voices in these tests are simulated; they do not replace testing on a norns and the user's connected hardware. See [detailed Italian verification notes](docs/VERIFICA_IT.md) and the [Italian guide](docs/GUIDA_IT.md).

See the [changelog](docs/CHANGELOG.md) for the 0.5.x development history.

## Credits and licensing

Anima is based on [Animator by Crim](https://github.com/crimclark/animator); the original position-LFO implementation credits @justmat in `lib/hnds.lua`. This derivative was developed by Giovanni Lami.

I contacted Crim on Lines to ask about sharing this adaptation and its licensing, but have not yet received a reply. I could not find a license in the original Animator repository when preparing this release.

If the original authors would like to discuss attribution, licensing or the availability of this adaptation, please open an issue or contact me. No repository-wide open-source license has been assigned to the inherited code.
