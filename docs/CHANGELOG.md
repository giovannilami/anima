# Changelog

## 0.5.6

- Batch Grid and screen updates during doodle load and snapshot recall; send one complete frame when the operation finishes.
- Retire callbacks owned by the previous script and release the Grid handler safely during cleanup.

## 0.5.5

- Import original Animator projects, including original playback behavior for supported clock divisions, intersections, note articulation and output handling.
- Preserve imported original projects and add the `/5` and `/7` divisions in EDIT.

## 0.5.4

- Evaluate probability independently for each hit in a ratchet or intersection-retrigger burst, including the first hit.
- Keep burst spacing when individual hits are skipped; share each decision across chord notes and layered outputs.

## 0.5.3

- Add live LFO values and source labels to Lines and Intersections displays.
- Isolate sample-and-hold display reads from musical random decisions.

## 0.5.2

- Coordinate local and global freezes by destination; show held values in the interface.
- Add a 2 Hz freeze indicator and live effective values on Intersections.

## 0.5.1

- Organize modulation controls in one EDIT > LFO group with selectors for global and per-track oscillators.
- Allow ratchet counts from 0 to 4, with zero representing a rest when ratchet or retrigger is active.

## 0.5.0

- Add two independent LFOs per track, each with up to two destinations.
- Add parameter freeze gestures and session undo/redo for manual Grid and encoder edits.
- Add format migration from Animator 2 and preserve the three-page Grid workflow.
