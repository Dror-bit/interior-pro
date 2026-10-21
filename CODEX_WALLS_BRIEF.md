# Brief for Codex — walls, doors and windows (Interior Pro)
Version 1, 2026-10-20 13:45 PT, by Claude. **A handoff and an explanation only. No code was changed to write it.**
Read ALL of it before you touch any wall / door / window / room / level file. If what you need is outside what the user
has given you, STOP and ask him (he relays to Claude). Do not "just fix it".

---------------------------------------------------------------------------------------------------------------------
## 0. Right now: who is working on what (read this first)

| Area | Owner right now | State |
|---|---|---|
| Wall corners when a room is added; wall delete -> corner + room sync; exterior <-> interior auto | **Claude (another chat, "113")** | IN PROGRESS, uncommitted |
| 2D window delete that "freezes" | **Claude (chat 113)** | measuring |
| kitchen/, vanity/, fixture_*, molding stops at cabinets | **Codex** (as before) | your uncommitted changes in git status |
| Everything else in walls/doors/windows | nobody yet | wait for the user's "go" |

What chat 113 has open **today** (2026-10-20), not in git yet:
- `wall_tool.rb` — new `tee_at_existing_corner!`, `in_line_flush?`, `butt_to_face!`, flag `USE_TEE_AT_CORNER` (around l.1660-1815),
  called at the top of the `[:start, :end].each` loop in `join_corners`. Backup before the change:
  `OneDrive\InteriorPro\work\wall_tool_before_tee_2026-10-20.rb`. Test `tests/rt336.rb`.
- **SketchUp crashed at 13:30** right after the T was built (the T itself was made, the 3 walls committed; it died in a later
  step: rooms / floors / electrical / molding). Chat 113 is measuring it with `debug_tee_crash_probe.rb` ->
  `OneDrive\InteriorPro\tee_crash_probe.txt`.
- Measuring files running on his model: `debug_room_add_watch.rb` (-> `room_add_watch.txt`),
  `debug_window_delete_trace.rb` + `debug_window_delete_js.rb` (-> `window_delete_trace.txt`).
- `plan_editor.rb` also shows as modified in git status — find out from the user who has it open before you touch it.

**So: do not edit `wall_tool.rb`, `plan_editor.rb`, `wall_delete_tool.rb`, `room_manager.rb` until the user says chat 113's
work is committed and the crash is closed.** Then agree with him on a file table like §0 of `CODEX_KITCHEN_BRIEF.md`, so two
agents never have the same file open. The Claude chat that wrote THIS brief is editing no files.

---------------------------------------------------------------------------------------------------------------------
## 1. Read before anything (in this order)

The LIVE folder is `C:\Users\rordt\AppData\Roaming\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro` (git, branch
door-stabilize; SketchUp 2026 on Windows loads this same folder through `interior_pro_link.rb`).
**`C:\InteriorPro_Agent\source_readonly` is a stale copy from July** — its CLAUDE.md ("doors only, never touch walls") and
STATUS_handoff.md are retired. Do not read rules or code from there.

Documents (live folder):
1. `CLAUDE.md` — the user's rules in his words (top ~540 lines), the iron law (l.127), "Curved walls" (l.1206-1308),
   "Kill switches" (l.972+), the current step (l.540).
2. `HOW_WE_WORK.md` (short version of the same).
3. `CONTRACT_2D.md` — attributes are the single source of truth; every body must regen from attributes; ids never change.
4. `HANDOFF_2026-10-12_ELECTRICAL.md` from "2026-10-16 15:20" to the end — the corner bug of 10-16, room 3 / the broken
   corner of 10-19, and the 3-part add-room plan (20:30).
5. `CODEX_KITCHEN_BRIEF.md` §10 — Claude's corner findings for you (10-16), incl. `wall_trace.txt`.
6. `RETRO_and_plan.md` — WHY openings are "build the hole", never boolean (the July collapse).

Code — read IN FULL before changing (his rule: never trust a summary, this one included):
- `wall_tool.rb` (4236 lines): `join_corners`, `find_neighbor_at`, `weld_drifted_end!`/`AUTO_WELD_ENDS`, `apply_miter`,
  `weld_corner!`, `read_door_openings`/`persist_door_openings!`/`append_door_opening!`, `rebuild_wall_native!`,
  `rebuild_wall_native_geometry!`, `build_wall_with_openings_oriented`, `punch_curved_openings!`, `set_wall_sag!`,
  `curved_wall?`, `set_wall_base!`, `ensure_unique_ids!`, `wall_trace`.
- `door_manager.rb`: `find_wall_by_id`, `move_hosted_doors!`, `wall_geometry`, `remove_native_opening!`,
  `update_native_opening_t!`, `delete_door`, `move_door`, `update_door`.
- `window_manager.rb` (377): `delete_window`, `move_window`, `update_window`, WindowMove/Edit/Delete tools.
- `window_tool.rb`: `cut_window_opening` (l.284-620) — placement, the transparent sub-operations.
- `wall_delete_tool.rb` (192): `neighbor_walls`, `delete_wall!`.
- `room_manager.rb`: `detect_rooms!`, `sync_rooms!`. `level_manager.rb` (381).
- `plan_editor.rb` Ruby side only: callbacks `delete_wall`, `delete_many`, `delete_opening`, `move_opening`,
  `edit_opening_size`, `set_opening_t`, `apply_walls`, `UndoRefreshObserver`/`ElecRefreshObserver`.
  (12k lines; the JS lives in a Ruby heredoc — see §6.)
- The wall tools: `wall_stretch_tool.rb`, `wall_split_tool.rb`, `wall_merge_tool.rb`, `wall_move_tool.rb`,
  `wall_edit_tool.rb`, `wall_arc_tool.rb`, `wall_curve_tool.rb`, `ui_dialogs.rb` (`wall_move`), `arc_math.rb`.

---------------------------------------------------------------------------------------------------------------------
## 2. How we work (his rules — not optional)

- You edit files yourself; he does not write code. He pastes commands and tests in SketchUp.
- **Never run git, not even read-only** (it left `index.lock` stuck once). Give him a CMD box; every CMD starts with
  `cd /d "C:\Users\rordt\AppData\Roaming\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro"` in the same box.
- Hebrew only, one or two sentences, one question at a time (two numbered options when unclear). Every command in its own box
  labelled **Ruby Console** or **CMD**. After every change: numbered steps — reload / restart / what to click / what he should see.
- **Measure before you change.** A debug_*.rb file that writes a report to `C:\Users\rordt\OneDrive\InteriorPro\`, you read it
  yourself, then ONE change. Never "it works" from a picture or from tests alone. Best: the tool writes its own trace.
- One small change per reload; test in SketchUp; he commits; next step. Exactly what he asked, nothing extra.
- Every feature that builds geometry gets a kill switch on day one. Every silent `next unless` that writes to the model gets a `puts`.
- Back up a file to `OneDrive\InteriorPro\work\<file>_before_<what>_<date>.rb` before a risky edit (the other chats do this).
- The iron law (CLAUDE.md l.127): Escape exits, Ctrl+Z undoes one action, zoom to mouse, the view does not jump, it responds
  at once, snapping shows where it locked, the plugin finds its own things inside groups.
- No instruction text in any window (law 2026-10-13). New window = copy of an existing one, field by field.
- Save files as LF, not CRLF.

---------------------------------------------------------------------------------------------------------------------
## 3. The six areas you asked about — how it works, what is deliberate, what is open

### 3.1 Openings <-> walls (doors AND windows)
- **One list on the wall:** `door_openings` = rows `[t, width, height, floor_offset, arch_rise]`. **It holds windows too** —
  the name is misleading; do not rename it (CONTRACT_2D §7).
- `t` = `position_along_wall_in` on the body = distance from the wall's drawn START, along the centre line, to the
  opening's MIDDLE (`x1 = t - width/2` in `build_wall_with_openings_test`; `update_window` places at `clx + ux*t`).
- Rows have **no id**. An opening is found by `t` within 1" (`remove_native_opening!`, `update_native_opening_t!`).
  `remove_native_opening!` drops EVERY row within 1" — that is the "self-healing" against orphans, on purpose.
- The body (door/window group or component) carries `host_wall_id` -> wall `id`. Ids must stay unique and stable:
  `WallTool.ensure_unique_ids!` (run inside every `sync_rooms!`) renames Copy/Paste twins, but **leaves alone** a duplicate id
  that an opening points at (no honest way to tell whose it is). Deliberate. `tests/rt71.rb`.
- **"Build the hole, do not cut it"** (`USE_NATIVE_OPENINGS = true`): every change = edit the list -> `rebuild_wall_native!`
  (rebuilds the body from attributes, then `join_corners`). The old boolean/fill path (`door_boolean.rb`, `fill_opening!`,
  `DoorBoolean`) is what broke everything in July (orphan holes, non-solid walls, cascading failures). Do NOT route anything
  new through it. It is still loaded as a fallback only.
- `DoorManager.move_hosted_doors!` moves door + window bodies when a wall moves. It was deleted by accident once (07-02) while
  `ui_dialogs.rb` still called it — keep it.
- Exterior doors: `exterior_effective_n` in door_tool.rb flips the normal when the wall body is on the negative side of the
  clicked face. Interior and exterior doors use different depth conventions on purpose. Do not "unify".
- Dormer (gablet) windows belong to `DormerManager`; WindowManager refuses to move/delete/edit them — deliberate.
- Checked in code, **not found**: any test that a moved/resized opening does not overlap another opening on the same wall
  (`move_window` / `move_door` only check the wall's two ends). Measure before assuming it is a bug.
- `move_hosted_doors!` walks `model.entities` (top level only) while `find_wall_by_id` searches nested — a wall inside a
  group would move without its windows. Not measured on his model.

### 3.2 Editing and moving windows
- Move = `WindowManager.move_window(window, delta_t)`: one operation 'Move Window' — `update_native_opening_t!`, rebuild wall,
  translate body, update `position_along_wall_in`, `face_x/face_y`. From the 2D editor: `move_opening` / `set_opening_t`,
  then `MoldingManager.refresh!`.
- Edit = `update_window(window, settings)`: **two separate steps** — operation 'Edit Window — Remove' (erase body + opening,
  COMMITTED), then `WindowTool#cut_window_opening` places a new one in its own operation. Consequences to keep in mind:
  Ctrl+Z after an edit takes back only the second half; if the second half fails the window is gone. Not reported by him —
  measure before touching.
- `cut_window_opening` uses transparent sub-operations (`start_operation(..., true, false, true)`) for Data / Casing /
  To Component so one placement = one undo. Copy that pattern.
- Window casing: `build_window_casing!` (4 sides, Follow Me, same catalogue as doors; `WINDOW_CASING_REVEAL` 0.25,
  `WINDOW_JAMB_WIDTH` 1.0). Profile orientation fixed in `door_casing_profiles.rb` `skp_spec` (wide side faces out) — shared
  with doors, do not flip it for windows only.
- **OPEN (today, chat 113):** in the 2D editor, Delete and the X did nothing for a window (no request reached Ruby —
  measuring inside the JS now), a press registered as a drag and moved window 985885f1 ~8", and the molding refresh after it
  took 27 s (looked like a freeze). Delete of one window measured 14 s: ~5 s electrical (outlets moving on the wall
  opposite), ~8 s molding.

### 3.3 Curved walls (CLOSED as a feature by him — "a bug in one is a bug, not a phase")
- Stored as a normal wall + `arc_sag` (inches, signed, + = left of start->end; under `MIN_ARC_SAG` 1/16" = straight).
  Ends stay plain `start/end`, so move/stretch/split/2D keep working. `set_wall_sag!` is THE one entry point;
  `WallArcTool < WallTool` has no builder of its own (`rt23` fails if it grows one).
- **Corners with a curve are WELDED, never mitered** (`weld_corner!` — straight wall keeps its full length and square cut,
  the curve is fitted to it). The tangent-miter was removed after spikes/steps/tilted walls (08-12). Do not bring it back.
  Straight-to-straight corners run the identical old code (`rt22`). 2D mirror: `weldPendingEnds` (`t34`).
- Openings on a curve: flat panels with `POCKET_PAD` 1.5" each side (`rt24`), `RESEAT_OPENINGS_ON_CURVE` carries bodies
  onto the new shape (`rt34`, `rt37`).
- Known and accepted: the printed plan (`plan_generator.rb`) draws curved walls straight; butt joints use the straight line;
  an inward arc at a shallow angle leaves a tooth-sized overlap. The new T fix skips curved walls.
- If you change any of this, update the "Curved walls - what is wired up" list in CLAUDE.md in the same step.
- `fix_corners_once.rb` = reloads, verifies the new code is loaded, re-joins every corner. Use it after a corner change.

### 3.4 Levels (floors) and heights
- A wall's floor is the `level` attribute (1, 2...). **Every neighbour search filters by `level`, not by z** (`find_neighbor_at`,
  `neighbor_walls` in delete, `tee_at_existing_corner!`, rooms, molding). Reason: he builds level 2 by copying level 1, so
  upstairs ends sit exactly over downstairs ends; and a dropped garage must keep its neighbours. `rt10`, `rt12`, `rt13`, `rt75`.
- `LevelManager.level_base(n) = (n-1) * (wall_height + joist + subfloor)` = 106" by default (96 + 9.25 + 0.75), numbers on
  the model. Exterior walls of the lower level GROW to the level-2 floor and remember `ceiling_h` (crown and ceilings stop
  there). `USE_LEVEL2_SUBFLOOR = false` — he asked for the deck to be gone. `rt9`.
- `base_z` on a wall (`set_wall_base!`) also moves its opening bodies. Door/window heights are LOCAL to the wall (wall floor = 0).
- Rule from CLAUDE.md: `group.bounds` is in the parent's coordinates, geometry inside is local — identical on level 1, wrong
  upstairs. Test anything that mixes them on a wall with `base_z != 0`.
- The 2D editor shows only the active level, the level below as a snapping ghost (`rt11`, `t29`).

### 3.5 Undo / redo
- Law: one user action = one `start_operation`/`commit_operation`; failure -> `abort_operation` rolls back everything.
  Escape is enforced by `tests/rt268.rb` (fails if any tool has no answer to Escape).
- Constants written `X = v unless const_defined?(:X, false)` are NOT re-read by `InteriorPro.reload!` — use `remove_const` +
  `const_set` (or restart). `DOOR_SETTING_KEYS` change = full SketchUp restart. A new file in `main.rb` = restart.
- 2D editor: `UndoRefreshObserver` re-sends walls to the canvas after ANY undo/redo (`onTransactionUndo/Redo`), so Ctrl+Z in
  SketchUp and the editor's own Undo stay in sync (`t40`). `ElecRefreshObserver` re-reads outlets after every commit.
- The Sheet window has its own undo, no redo (`USE_SHEET_UNDO`).
- Kitchen / laundry / vanity have their own ModelObservers for undo (your code).
- **Things to measure, not yet reported by him:**
  - `delete_wall!` commits 'Delete Wall', THEN runs `sync_rooms!` (its own operation) and `MoldingManager.refresh!` outside it
    -> deleting one wall is probably several Ctrl+Z steps.
  - 2D `delete_many` opens '2D Delete Selection' and calls `delete_window` / `delete_wall!`, which each open their own
    operation inside it. SketchUp does not nest operations — check what one Ctrl+Z really takes back.
  - `update_window` = two operations (3.2).

### 3.6 Deleting a wall -> corners and rooms
- `WallDeleteTool.delete_wall!` (also used by the 2D editor): finds neighbours BEFORE erasing (same level, ends within
  (t1+t2)/2 + 1"), erases the wall + its doors/windows/baseboard/crown, resets each neighbour to a square end, re-joins it
  (`join_corners(..., allow_centerline_fallback: true)`), then `sync_rooms!` (-> floors, ceilings) and molding.
  Neighbour logic is tested on its own in `rt75`.
- Measured 10-20 13:17: from the 2D editor it WORKS (corner closed, room 3 gone) but 3 walls took ~1.5 min — the whole
  house refresh (rooms, floors + tile, outlets, molding 8-25 s) runs once PER wall and once more at the end.
- **Deleting with SketchUp's own Delete key bypasses all of it**: there is no observer that notices a wall leaving
  (the only EntitiesObserver is electrical `HoleWatch`). That is how 10-19 ended with a broken corner and a room left over.
- `sync_rooms!` matches rooms by centroid within `MATCH_TOL` 36", per level, erases rooms it no longer finds, renumbers
  default names ("Room n") but keeps names he typed.
- The 3-part plan (handoff 10-19 20:30), owned by chat 113, one step at a time:
  1. delete in any way -> neighbours re-joined + rooms synced (2D/tool: works, slow; SketchUp Delete: open);
  2. a new exterior wall that ends on an existing wall/corner joins as T or L without flipping the neighbour (fix written
     today, uncommitted, crash after it under investigation);
  3. an exterior wall that ends up between two rooms becomes interior by itself, and back (not started; ask him first about
     thickness, materials, siding on it, tile / molding / electrical hanging on it).

---------------------------------------------------------------------------------------------------------------------
## 4. Open bugs (walls / doors / windows), newest first
1. Crash after the T at an existing corner — 2026-10-20 13:30 (chat 113, measuring).
2. 2D window delete: Delete / X not reaching Ruby; a press moves the window; molding refresh 27 s (chat 113).
3. SketchUp's Delete on a wall: corner of the neighbour and the room are not updated (part 1 of the plan).
4. Deleting walls from 2D is slow: the full refresh per wall (rooms, floors, tile, electrical, molding).
5. Exterior <-> interior by itself (part 3) — not built.
6. Older, verify before working on them: Merge Wall miter bug; 24 px icons blurry; Garden Wall has no icon
   (`garden_wall_tool` missing in icons/). Mac SketchUp 2026 still loads an August folder (install problem, not code).
7. Not bugs — his decisions: editing wall thickness does not change the width (he decided); "90° corners" button is off
   (`USE_SQUARE_UP = false`) — do not reopen.

---------------------------------------------------------------------------------------------------------------------
## 5. Deliberate solutions — do not change without understanding why (and asking him)
- Native openings, one list, self-healing remove (3.1). No boolean/fill for anything new.
- `door_openings` holds windows; `interior_material` holds a colour (interior walls paint by `side_a_color`/`side_b_color`).
  Misleading names, documented — do not rename.
- `corners_xy` is a CACHE of the mitered footprint (CONTRACT_2D §1), recomputed from start/end + thickness + anchor +
  neighbours. Never treat it as the source of a new feature.
- **A wall only gets longer or shorter — never bent.** A point sets the LENGTH, the axis sets the DIRECTION
  (`ORTHO_SNAP_DEG` 12, `DIAG_SNAP_DEG` 5 in the 2D editor; `DRAW_SNAP_ORTHO_DEG` 8 in the 3D tool); never round
  coordinates after the angle locked (the 89.8/90.2 bug); stretching a wall slides the neighbour's end along ITS OWN line
  (`slideEndAlong`, `stretch_wall!`). Rule of thumb in CLAUDE.md: if you write `sx = np.x` on a wall he did not touch, stop.
- `AUTO_WELD_ENDS`: a corner that missed by less than one thickness closes itself (`rt70`).
- `REJOIN_FLIPPED_CORNERS` (JS, plan_editor.rb, 10-16): when `autoOrientExterior` flips walls drawn the "wrong" way, the
  ends move to the new outer corner — otherwise every corner opens 7.07" (`t100`, `t61`).
- Curved corners welded, never mitered (3.3). Level filter by attribute, not z (3.4).
- All siding in ONE subgroup `InteriorPro_Siding` inside the wall; `MAX_SIDING_PIECES` 260 — this is what stopped SketchUp
  crashing. "Every board in a group of its own" — touching solids in one group + pushpull = crash.
- `ensure_unique_ids!` leaves hosted duplicate ids alone (3.1). `move_hosted_doors!` must exist (3.1).
- `USE_WALL_TRACE` is on: wall joins write to `OneDrive\InteriorPro\wall_trace.txt`. Use it, do not remove it.
- Real SketchUp has `erase_entities`, not `erase_entity` (the stub hid it, rt250).
- JS inside `plan_editor.rb` sits in a Ruby heredoc: no `\d` — write `[0-9]`, `\\s`, `\\.` (rt/t tests on the pure function
  passed while the tool did nothing). Keyboard tests go through `__listeners.__win.keydown[0]` (end of `t56.js`).
- Kill switches you will meet (all `InteriorPro::WallTool` unless said): `USE_NATIVE_OPENINGS`, `USE_CURVED_WALLS`,
  `RESEAT_OPENINGS_ON_CURVE`, `USE_3D_SIDING`, `AUTO_WELD_ENDS`, `DRAW_SNAP_ORTHO_ONLY`, `USE_WALL_TRACE`,
  `USE_TEE_AT_CORNER` (new, uncommitted); `LevelManager::USE_LEVEL2_SUBFLOOR`; plan_editor `USE_SQUARE_UP` (off).

---------------------------------------------------------------------------------------------------------------------
## 6. Tests
- `tests/` holds COPIES; `run_all.sh` copies the live files in. Never edit a copy in tests/. A single test without run_all
  first runs on old code.
- `cd tests && LANG=C.UTF-8 timeout 170 bash run_all.sh ..` (in the foreground). **Its list stops at rt313** — run
  rt314..rt336 by hand after it (rt336 = the T). `run_all.sh` does NOT copy `wall_merge_tool.rb`, `window_library.rb`,
  `room_link_dialog.rb` — copy them yourself if a test needs them.
- Old reds to expect: rt41, rt43, rt60 (rt229 only in a VM; rt266 only in parallel). Compare with YOUR baseline before a change.
- A new test must also FAIL on the old code. A feature that touches the model needs an rt (Ruby) test on the real path, not
  only a JS test on the pure function (law 2026-09-23).
- The ones that guard this area:
  - Corners / drawing: rt14, rt16, rt33, rt38, rt54, rt55, rt70, rt71, rt336; JS t37, t39, t40, t41, t42, t44b, t54, t55,
    t58, t59, t61, t100.
  - Openings: rt24, rt25, rt34, rt37, rt58, rt74 (a window is never cut into a wall you did not click), rt122.
  - Curves: rt19, rt20, rt21, rt22, rt23, rt29, rt30, rt31, rt32, rt35, rt36; JS t33, t34.
  - Levels / rooms / delete: rt9, rt10, rt11, rt12, rt13, rt68, rt69, rt75; JS t29, t30, t31.
  - Things that hang on walls and must survive a wall change: molding rt9 rt12 rt328 rt329; tile rt175-rt190, rt194-rt197;
    plans rt41, rt42, rt264, rt265; Escape rt268.
- In SketchUp, after any wall change (his checklist from §10 of the kitchen brief): L / T / X corners, exterior and interior;
  a door and a window in a corner wall; siding; wall tile at the corner; molding miters; one Ctrl+Z. On a clean model first
  (File > New), then on his model. Ask him which model.

---------------------------------------------------------------------------------------------------------------------
## 7. Before your first step, ask him (one question at a time)
1. Is chat 113's work committed and the crash closed? Which files may you take?
2. Which bug first (§4)?
Then: a measuring file, his run, you read the report, one change, his test, his commit.
