# Anima

**Anima** is an eight-track, two-dimensional sequencer for monome norns and a 16×8 Grid. Draw lines on the Grid; their active steps generate notes as their playheads advance and meet. Each track can use its own clock division, direction, articulation, modulation and output route.

**Discussion and support:** [Anima on Lines](https://llllllll.co/t/anima/75862).

Anima is an adaptation and extension of [Animator by Crim](https://github.com/crimclark/animator). It imports original Animator doodles, and can optionally run imported projects with Animator's original playback rules.

> **Release status:** version 0.5.6 is the prepared release build. Its interface and software behavior have been exercised in local simulations.

## Install

You need **norns**, a **16×8 Grid** and **Molly the Poly**. MIDI, Crow and n.b. are optional (but suggested) output destinations.

1. If Molly the Poly is not already installed, enter this in the [Maiden](https://monome.org/docs/norns/maiden/) REPL:

   ```text
   ;install https://github.com/markwheeler/molly_the_poly
   ```

2. Restart norns to load the engine, then install Anima:

   ```text
   ;install https://github.com/giovannilami/anima
   ```

3. Connect Grid and select **anima** in the norns **SELECT** menu. Draw a line using the two-endpoint gesture described below. Set the scale and sound in **PARAMETERS → EDIT**; configure each track's output under **TRACK**.

Anima requires both the `MollyThePoly` engine and its Lua library. For a manual installation, copy `anima.lua` and the complete `lib/` folder into `dust/code/anima/`. The documentation and local tests are not required on norns. Installed n.b. libraries and voice mods determine which n.b. voices are available; Anima does not bundle them.

## Three performance pages

**Canvas** is for drawing and arranging the sequences. **Lines** controls how each track plays. **Intersections** chooses what happens when playheads meet. The Grid layout and the norns readout change together when you switch page.

The screen illustrations use the script's **128×64 layout**, displayed at 3× scale (384×192). Steps are drawn at their actual **3×3 px size on a 5 px pitch**. Text uses the original **norns.ttf** typeface at **8 px**, matching the default norns font and Anima's font size. Glyphs are embedded as vector outlines so the font and spacing remain consistent in every browser. These are illustrative states, not photographs of the device; values vary during use.

**Reading the Grid maps:** coordinates are **(column, row)**, counted from the top-left. The drawings contain all 128 square pads, with equal spacing on both axes. Colors distinguish functional groups in this guide; the real Grid uses monochrome brightness. Labels are a reference overlay, not text displayed on the hardware. Blank pads remain visible so you can locate the controls. On Lines and Intersections, each row is its numbered track; only existing tracks have lit controls. The bottom-right **(16,8)** always opens page selection.

### Canvas: draw the sequences

![Canvas screen: horizontal, vertical and 45-degree diagonal sequences crossing at three distinct cells](docs/images/canvas.svg)

**Grid: drawing area and performance row**

![Canvas Grid: seven drawing rows, eight snapshots, two pattern recorders, undo, ALT and navigation](docs/images/grid-canvas.svg)

Rows **1–7** are the drawing surface. The three lines in this map use the same coordinates as the screen illustration above. For example, hold **(5,1)** and press **(11,7)** for the diagonal: both axes span six steps. The eight snapshots are the first eight pads of **row 8**, separate from the drawing area. Hold **ALT (15,8)** first, then tap a snapshot to store the current scene; release ALT when finished. A plain snapshot tap recalls it. Save the doodle to keep snapshots on disk.

**P1 (10,8)** and **P2 (11,8)** record the order and timing of snapshot recalls. Tap an empty pattern to start recording, tap snapshot pads, then tap the pattern again to finish recording and start its loop. Further taps stop or restart playback. Starting an empty or stopped pattern stops the other pattern. With ALT held, tapping a stored pattern clears it and starts a fresh recording; if it is currently recording, ALT + its pad stops and clears that recording. With pattern quantization enabled, these events wait for the configured quantization boundary.

**U (13,8)** undoes the last manual edit; **ALT + U** redoes it. Undo/redo does not restore overwritten snapshots. **(9,8), (12,8) and (14,8)** are unassigned during normal Canvas use. Holding NAV temporarily turns (13,8), (14,8) and (15,8) into page selectors instead.

Each line is a track, with its own playhead travelling through its steps. Up to **eight tracks** share a **16-column × 7-row** drawing area. The bottom Grid row contains performance controls. A cell's pitch comes from the composition's scale and global transpose settings. Changing a line's position changes the cells it visits and the pitches it plays.

To draw, hold one Grid pad, press a second pad for the other endpoint, then release. Endpoints must share a row, a column, or form a **45-degree diagonal**: the horizontal and vertical distances must be equal. A diagonal advances by exactly one column and one row at each step. Other slopes do not create a sequence.

The illustration contains three tracks: a horizontal line, a vertical line and a diagonal crossing both. These are three distinct crossing cells. A drawn crossing is a possible meeting point; the intersection actions occur when sounding playheads meet there on the same pulse, depending on their timing and settings.

Tap a cell on an existing line to enable or disable that step. A cell shared by several lines has a shared step-on state. Bright points show current enabled steps; other enabled cells are dimmer, and disabled cells remain faint. Hold a line's two endpoints to delete that line.

| norns control | On Canvas |
| --- | --- |
| E2 | Move all lines vertically |
| E3 | Move all lines horizontally |
| K2 | Reset playback positions |
| K3 | Clear the Canvas |

| Bottom Grid row | Action |
| --- | --- |
| 1–8 | Recall snapshots |
| Hold 15 + press 1–8 | Overwrite a snapshot |
| 10–11 | Snapshot sequence record/play controls |
| 13 | Undo a manual edit |
| Hold 15 + press 13 | Redo |
| 15 | ALT modifier |
| Hold 16 | Open page selection |
| 9, 12, 14 | Unassigned |

The footer normally reads `K2 reset   K3 clear`. Save feedback temporarily replaces it. Undo/redo covers manual drawing, deletion, step toggles, clear and encoder moves during the current session.

### Lines: control each track

![Lines screen: selected track, direction, rate, output, probability, ratchet and mapped values](docs/images/lines.svg)

**Grid: the same controls on each track row**

![Lines Grid: mute and solo, four directions, ratchet, probability and seven playback rates repeated over eight track rows](docs/images/grid-lines.svg)

Read **across a row** to control one track. For example, **(3,2)** selects reverse for track 2; **(11,2)** selects ÷2 for that same track. **(1,2)** mutes it with a tap, or toggles solo with a hold of about **450 ms**. Hold again to release solo. A long hold does not also toggle mute.

The direction symbols are **>** forward, **<** reverse, **<>** pendulum and **?** random. **R** and **P** switch ratchet and probability on/off with a tap. A roughly 450 ms hold toggles the corresponding value's freeze without also switching the control on/off. For instance, hold **(7,2)** to freeze track 2's probability value while its other LFO targets keep moving. Freeze does not assign a new LFO target or enable probability by itself.

Column **8** is a gap between articulation and rate. Column **16** has no track control; only its bottom pad is NAV. On row 8, columns 1–15 still control **track 8**: they are not snapshots on this page. Hold NAV first to use the page shortcuts without changing track 8.

Each Grid row represents one track. Select a track with **E1**, or use that track's controls on Grid. The norns screen reports the selected track; **E2** moves that track vertically and **E3** moves it horizontally.

| Grid column | Action on that row's track |
| --- | --- |
| 1 | Tap to mute; hold for solo |
| 2–5 | Forward, reverse, pendulum, random |
| 6 | Tap to enable ratchet; hold to freeze/release its modulated value |
| 7 | Tap to enable probability; hold to freeze/release its modulated value |
| 8 | Unassigned separator |
| 9–15 | Rate: ×2, ×1, ÷2, ÷3, ÷4, ÷6, ÷8 |

Set probability percentage, ratchet count, output and other track values in **PARAMETERS → EDIT → TRACK**. A long press on ratchet or probability performs the hold gesture without also toggling the control. Frozen controls blink on Grid.

Read the example screen from top to bottom:

| Screen row | Meaning in the example |
| --- | --- |
| `LINES  1` | Track 1 is selected. `ORIG` is appended when original Animator playback is active. |
| `forward x1` | Forward playback at the base rate. `MUTE` and `SOLO` appear here when active. |
| `n.b.: fluid 1` | Output route and, for n.b., the assigned voice. Long names are shortened to fit. |
| `prob 75% LFO` | Probability is enabled and its current value comes from an LFO. |
| `ratchet 2 HOLD` | Ratchet is enabled with two strikes; its modulated value is frozen. |
| `O+1 T-12 L120 V96` | Other assigned modulation targets: octave, semitone transpose, note length in milliseconds and velocity. |

`BASE` means the manual value, `LFO` a moving modulated value, and `HOLD` a frozen value. The bottom row only lists assigned destinations; `*` marks a frozen one. An `off` suffix means probability or ratchet is disabled. `INT` on the ratchet row indicates that the count is used for intersection retrigger instead of continuous ratchet.

### Intersections: change what a meeting does

![Intersections screen: minor triad, retrigger, held LFO targets and effective performance values](docs/images/intersections.svg)

**Grid: harmonic, rhythmic and modulation groups**

![Intersections Grid: five harmonic actions, six rhythmic actions, LFO master and track preview on each row](docs/images/grid-intersections.svg)

Read each row as **harmonic choice → rhythmic choice → LFO → preview**. **+8 / −8** mean one octave up/down, not eight semitones. **5th** adds a fifth; **tri** and **7th** select a triad or seventh chord using the type configured in TRACK.

The rhythmic labels are **M** mute, **RT** retrigger, **REV** reverse, **RS** reset self, **RO** reset others and **RA** reset all. These choices apply when an intersection occurs. For example, tap **(4,3)** for a triad on track 3, then **(8,3)** for retrigger on the same track. Tap either selected pad again to turn off that action group while keeping the other choice.

**LFO (14,row)** controls that row's per-track modulation master. A tap switches it on/off; a roughly 450 ms hold freezes all currently assigned destinations, or releases the group freeze. It does not create mappings: assign them in EDIT → LFO. **V (15,row)** shows a track preview only for as long as the pad is held. For example, hold **(15,3)** to inspect track 3 on norns; release to return to its Intersections readout.

Columns **6** and **13** separate the groups and perform no action. Column **16** is also unassigned except for NAV at the bottom. Row 8 controls track 8 until NAV is held.

Choose one harmonic action and one rhythmic action for each track. These act when multiple eligible playheads reach the same enabled cell on the same pulse. Different rates, directions, rests and probability settings change when those meetings occur. A visible crossing alone does not continuously apply an action.

Each Grid row still represents a track. Press its desired action to select it; press that same pad again to return that action group to `none`. Harmonic and rhythmic actions can be combined.

| Grid column | Action |
| --- | --- |
| 1–5 | Octave up, octave down, fifth, triad, seventh |
| 6 | Unassigned separator |
| 7–12 | Mute, retrigger, reverse, reset self, reset others, reset all |
| 13 | Unassigned |
| 14 | Tap to switch the track's LFO master on/off; hold to freeze/release all assigned destinations |
| 15 | Hold to preview that row's track on the norns screen |

Choose the triad or seventh type in **PARAMETERS → EDIT → TRACK**. **E1** selects the track; **E2/E3** move it. Available actions on existing tracks are dim, selected actions bright, and frozen controls blink. Empty rows remain dark.

In the example, track 1 produces a **minor triad** and **retriggers** when it participates in a meeting. `LFO HOLD 2/3` means two of its three active mapped destinations are frozen; the remaining destination can continue moving. The footer reports the effective rate, probability and ratchet count: `x1  P75%  R2 int`.

The LFO line can also show `off`, `ON`, or `ON no targets`. The footer uses `Poff` or `Roff` when the corresponding control is disabled. `R2 int` means two strikes for intersection retrigger while continuous ratchet is off. Screen values refresh about ten times per second when modulation is moving; musical values are sampled at step boundaries.

### Switch page

![Page selection screen with the three bottom-row page shortcuts](docs/images/page-select.svg)

**The Grid while NAV is held**

![Grid navigation overlay: hold the bottom-right pad and choose Canvas on 13, Lines on 14 or Intersections on 15](docs/images/grid-navigation.svg)

Press and hold **NAV (16,8) before** touching a page pad. The other bottom-row functions are suspended: **(13,8)** selects Canvas, **(14,8)** Lines and **(15,8)** Intersections. Release both pads to resume normal controls. This combination works from every page; holding NAV alone does not switch pages. The other pads are inactive for editing during this overlay.

Hold the bottom-right Grid pad **(16,8)**, press one of these pads, then release:

| Pad | Page |
| --- | --- |
| (13,8) | Canvas |
| (14,8) | Lines |
| (15,8) | Intersections |

The temporary `SELECT PAGE` screen reminds you of these shortcuts. Holding the corner alone leaves the current page selected. While it is held, navigation takes priority over other bottom-row controls, including undo and track 8's controls.

### Preview one track

![Track preview screen showing the diagonal sequence of track 3](docs/images/track-preview.svg)

On Intersections, hold **column 15 on a track's row**. The norns screen temporarily shows only that track's drawing and moving playhead, while Grid stays on Intersections. `TRACK 3` identifies the track in this example. Release the pad to return to its parameter readout, as the footer `release 15: parameters` indicates.

This lets you inspect a line while keeping the intersection controls available. It is a temporary view, not a fourth performance page.

## Save, load and import

Anima stores its projects in `dust/data/anima/`. Use **PARAMETERS → EDIT → SAVE/LOAD → save doodle / load doodle** for Anima projects. Keep the `.doodle` and its matching `.pset` together: the preset contains sound settings as well as other parameters.

To import an original Animator project, choose **load Animator original** in the same menu. It opens `dust/data/animator/`. The `.pset` must sit alongside the `.doodle` with the same name. Saving from Anima writes a new copy into `dust/data/anima/`; the original files remain in their source folder.

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

## Development

Developed by Giovanni Lami with AI assistance (ChatGPT / OpenAI Codex) for implementation, debugging, tests and documentation. Musical direction, feature decisions and evaluation on the instrument are by Giovanni Lami. The original Animator concept and inherited code remain credited to Crim and the contributors identified below.

## Credits and licensing

Anima is based on [Animator by Crim](https://github.com/crimclark/animator); the original position-LFO implementation credits @justmat in `lib/hnds.lua`. This derivative was developed by Giovanni Lami.

On 16 November 2026, Crim (Tim Clark) kindly confirmed by email that he was happy for me to fork Animator, make updates and share Anima on Lines. Regarding sharing and licensing, he wrote:

> Feel free to share it on Lines and don't worry about the license.

He also welcomed the new features introduced in Anima. Many thanks to Crim for his encouragement and for creating Animator, which remains the foundation of this project. The original code and contributions remain credited to their respective authors. No specific license was designated in that exchange.
