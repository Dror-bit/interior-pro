# Project Rules for Claude

SketchUp interior design plugin, Ruby, module `InteriorPro`.
Live folder (edit in place, no RBZ):
`C:\Users\rordt\AppData\Roaming\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro`

## How we work (set by the user, 2026-08-10)

- Hebrew only. One or two sentences. Explain it the way you would to a
  five-year-old.
- Every command goes in its OWN copy box, labelled with where to paste it
  (Ruby Console / CMD).
- The user does NOT use Cursor. The assistant edits the files itself; the
  user tests inside SketchUp.
- The user has no Ruby installed, so the `rt*` suites give a FALSE FAIL on
  his machine. The assistant runs them in the cloud:
  `cd tests` then `"C:\Program Files\Git\bin\bash.exe" run_all.sh ..`
- The assistant NEVER runs git, not even read-only - it leaves `index.lock`
  stuck. Give the user CMD commands instead.
- Read the relevant file in full before changing it. Never trust another
  chat's summary - verify against the live code.
- One step at a time. Test in SketchUp, then commit, then next step.
- Do not break what already works.

## Current phase: curved walls, then 2D plans to PDF

(The old "doors only" restriction is retired - it was from the 2026-04 phase
and no longer applies. Doors, windows, walls, floors, roofs, moldings and the
2D editor are all live code now.)

Priority 1 - CURVED WALLS. Both entry points are wanted: dragging an existing
wall's middle to bow it, AND a 3-click arc tool. Both in the 2D editor and in
SketchUp itself.

Priority 2 - 2D PLANS TO PDF. Exterior plans first, no elevations yet. Needs a
page template, page size (Arch D / Arch E / A1...), a fixed scale, images and
dimensions. Check what the 2D editor and `plan_generator.rb` already do before
building anything twice.

## Kill switches (turn a feature off without deleting it)

- `InteriorPro::WallTool::USE_CURVED_WALLS = false` - every wall builds
  straight again, `arc_sag` ignored.
- `InteriorPro::WallTool::USE_NATIVE_OPENINGS = false` - the older opening
  path.

## Curved walls - how they are stored (2026-08-10)

A curved wall is a NORMAL wall with one extra attribute:

- `arc_sag` - how far the middle of the wall is pulled sideways off the
  straight line between its two ends, in inches, SIGNED. Positive = to the
  LEFT of start -> end. No attribute, or under `MIN_ARC_SAG` (1/16"), means
  the wall is straight and takes the original code path exactly.

Because the two ends stay ordinary `start_x/y` and `end_x/y`, every tool that
moves a wall (move, stretch, split, the 2D editor) keeps working untouched -
the bow just follows the ends.

- `arc_math.rb` - pure 2D arc maths, no SketchUp API at all. Tested by
  `tests/rt19.rb`.
- `WallTool.curved_footprint_xy` - pure, returns the floor outline. Tested by
  `tests/rt20.rb`.
- `WallTool.set_wall_sag!(wall, sag)` - THE one entry point. Both the drag and
  the arc tool must end here.
- Sign convention: "left" = turn 90 degrees counter-clockwise. Sag is measured
  against the straight line between the ends; wall side offsets are measured
  against the direction of travel along the arc (see the comments in
  `arc_math.rb` - on a half circle the straight-line test flips on floating
  point noise and would swap a wall's inside and outside).

### Curved walls - corners (fixed 2026-08-11)

A curved wall reports its TANGENT at each end, not the straight line between
its ends (`WallTool.corner_direction_xy`). `apply_miter` uses that, so the
neighbour gets cut at the right angle. Its own ends are cut radially
(`curved_end_corners_xy`), and `apply_corner_overrides` swaps the four stored
`corners_xy` into the built curve, so a miter reaches a curved wall the same
way it reaches a straight one. `set_wall_sag!` resets the corners and re-runs
`join_corners` afterwards.

STRAIGHT-TO-STRAIGHT CORNERS ARE UNTOUCHED. The tangent swap and the
centreline reference point both sit behind `curved_corner`, so a corner with
no curve in it runs the identical old code. `tests/rt22.rb` guards this.

### Curved walls - NOT wired up yet (deliberate, do not treat as bugs)

- Openings. A wall with doors or windows refuses to curve and says so.
- Butt joints (interior wall meeting an exterior one) still use the straight
  line, not the tangent.
- Board and Batten strips are left off a curved wall.
- `plan_generator.rb` draws it as a straight line in the 2D plan.
- `RoofManager.eave_polygon` treats it as a straight segment.
- The 2D editor cannot draw or bend a curved wall at all.

### Curved walls - the 3-click Arc tool (2026-08-11)

`wall_arc_tool.rb`, `WallArcTool < WallTool`. Click start, click end, click the
bow. It owns NO building logic: it fills in `@start_point`, `@end_point` and
`@arc_sag`, then calls the inherited `create_wall`, which bends the finished
wall via `set_wall_sag!` inside the same operation. That is why a curved wall
gets the same attributes, materials, level and corner joining as a straight
one. Do not give it its own builder - `tests/rt23.rb` fails if it grows one.

Reached from Extensions > Interior Pro > "Arc Wall (3 clicks)", which opens the
wall library first exactly like the Wall tool.

## UI rules (added 2026-08-07, set by the user)

### No duplicate ways to do the same thing

**Rotation covers flipping. Never build both.** Flip / mirror buttons
(left-right, up-down) and a rotation control are the same idea wearing a
different hat. Build the ROTATION only - a typed angle plus a quarter-turn
button - and leave flips out.

More generally: before adding a second control, ask whether an existing one
already does that job. If it does, do not add it. Fewer buttons, fewer
clicks. This is the user's standing preference for the whole plugin.

### Fewer clicks, always

- Clicking any tool button immediately runs that tool. No Escape first, no
  cancelling the previous mode by hand - the click itself cancels it.
- Panels stay open when the mode changes; the user must never reopen a panel
  to reach the tool they just used.
- Every action worth reaching for gets a single-letter keyboard shortcut.
  Current map: S select, D door, W window, L line, O guide line, M move,
  R rotate, U flip the guide angle to the other diagonal.
- Icons over words in dense panels: a dashed horizontal line beats the word
  "horizontal".

### Feedback

- A button that was pressed must LOOK pressed (Apply to Model shows a busy
  state until the model is built).
- The mouse cursor becomes the tool's own icon while move / rotate / offset
  are running, so the active mode is always visible.
