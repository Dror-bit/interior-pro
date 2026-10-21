# Brief for Codex — Kitchen elevations into the Sheets and the PDF
Version 2, 2026-10-15 14:30, by Claude. Read ALL of it before any change. If something you need is outside the
"MAY change" list, STOP and ask the user (he relays to Claude) — do not "just fix it".

## 0. Who owns what right now (so we never edit the same file)
| Area | Owner | Files |
|---|---|---|
| Kitchen elevation → sheet → PDF (cabinets, appliances, faucets, their dims, Kitchen page layout, plan from above for Kitchen) | **Codex** | see §2 |
| Outlets / switches standing behind the kitchen backsplash (in the 3D model) | **Claude** | `electrical_library.rb`, `debug_elec_front.rb` |
| Everything else | nobody this round | — |
Claude will NOT edit `elevation_tool.rb`, `plan_canvas.rb`, `plan_pdf.rb`, `plan_sheet_dialog.rb` or `kitchen/` while you work.
You do NOT edit `electrical_library.rb`.

## 1. What Claude changed today (all in the files you now own — read them, they are yours to keep working)
`elevation_tool.rb` (flags at the top of the module, each = kill switch):
- `USE_KITCHEN_PICK` + `make_kitchen!` / `kitchen_room` / `kitchen_sides` — "Kitchen" in the Elevations list.
- `USE_KITCHEN_FACING` + `kitchen_cab`, `kitchen_back`, `kitchen_on`, `side_frame` — a wall is a kitchen wall when a cabinet
  stands on it with its BACK (cabinet +y). Trace line "Kitchen walls [...]" in `OneDrive\InteriorPro\elevation_trace.txt`.
- `USE_KITCHEN_DIMS` + `kitchen_items`, `kitchen_dims!` — orange (`g 'kitchen'`) chains: bases under the floor (row 1),
  uppers over the ceiling (`'up' => true`), height columns. `UPPER_Z` 30, `TALL_Z` 80. Your `kitchen_body_heights` feeds it.
- `USE_ELEC_STACK` + `ELEC_STACK` in `elec_rows` — electric distance rows never on each other.
- `USE_WORKTOP_PIECES` in `off_wall` — far pieces of the continuous backsplash put aside per wall (the black shape; you saw it gone).
- `row_boxes(area, sizes, cols, up = 0)` + the `ups` line in `add_room_sheet!` — room over the pictures for the uppers' row.
- `kit_d` read once BEFORE the wall loop in `shoot!` (inside the loop it lost what the previous wall had hidden).
`plan_canvas.rb`: `ELEV_DIM_COLORS` now `remove_const` + `'kitchen' => '#c8731e'`; `'kitchen'` in the `gx` group list of
`draw_elev_dim`; the `'h'` branch understands `'up'` (`sg`). `plan_sheet_dialog.rb`: `['kitchen','KITCHEN']` in `GROUP_ROWS`.
Tests: `tests/rt317.rb` (rewritten for the facing rule), `tests/rt312.rb` (colour string), `tests/rt318.rb` (new, 16 checks).
Approved by the user on his model 12:59 ("וואו זה נראה בהרבה יותר טוב"). The worktop-pieces fix: not yet confirmed by him.

## 2. You MAY change
**`elevation_tool.rb` — only these functions, and only ADD new ones next to them:**
`make_kitchen!`, `kitchen_room`, `kitchen_sides`, `kitchen_cab`, `kitchen_back`, `kitchen_on`, `side_frame`, `kitchen_items`,
`kitchen_body_heights`, `kitchen_dims!`, `kitchen_tops`, `kitchen_wall_tag`; the worktop-pieces block inside `off_wall`;
the kitchen flags/constants. Layout of the Kitchen page: write a NEW function (e.g. `kitchen_boxes`) and call it from
`add_room_sheet!` ONLY when the sheet title is `KITCHEN_LABEL`, behind its own `USE_...` switch — every other room keeps
`row_boxes` exactly as it is. Plan from above for the Kitchen: same rule — a branch taken only when `label == KITCHEN_LABEL`
(there is already one: `keep_down` for the floors).
**`plan_canvas.rb`:** NEW branches in `draw_elev_dim` for NEW kinds (e.g. `'k' => 'dash'` for upper outlines); new keys in
`ELEV_DIM_COLORS`. Existing branches untouched.
**`plan_sheet_dialog.rb`:** only `GROUP_ROWS` (add rows). If the window must draw a new shape type, ask first.
**`kitchen/`**: your own code, as before.
**New files**: `kitchen_sheet_*.rb`, `debug_kitchen_*.rb`, `tests/rt3xx.rb` (take the next free number after rt318).
If you add a NEW plugin file, it must be added to `PLUGIN_FILES` in `main.rb` — ask the user first (it is a one-line edit).

## 3. You must NOT touch
- In `elevation_tool.rb`: `shoot!` (camera, section planes, what is hidden, the abort_operation), `shot`, `top_shot`, `sides`,
  `compass`, `collect`, `room_poly`, `outside_room`, `outside_kitchen`, `foreign_frame?`, `side_items` (except its last line
  that calls `kitchen_items`), `elec_point`, `elec_rows`, `typed_parts`, `part_boxes`, `dims_for`, `dims_clean` (except the one
  `rown = ... kitchen_dims!` line), `fmt_in`, `row_boxes`, `add_room_sheet!` (except the one Kitchen-only call you add),
  `add_to_sheet!`, `make!`, the layers code (`shoot_variants!`, `write_layers_index!`, `ensure_variants!`, `CAT_TYPES`), the
  snaps code (`side_segs`, `seen_segs`), `trace`.
- In `plan_canvas.rb`: `elev_pt`, `elev_rect`, `elev_paper`, `elev_style`, `place_elev_dims!`, the existing branches of
  `draw_elev_dim` (`f`, `h`, `hi`, `v` L/R), `draw_pic_note`, `shape_group`, `text_key`, `name_texts!`, `pic_shown`.
- `plan_pdf.rb` (the exporter) — the existing pages, `pdf_skip`, `page_order` must keep working; if the PDF needs something,
  ask first.
- `plan_sheet_dialog.rb` except `GROUP_ROWS`: `shapeGroup`, `buildLayers`, the text-in-place editing (his law 2026-10-08:
  every label is edited ON itself, one "Text settings" panel, sizes in pt — no new bars or boxes), `load_state`/`save_state`.
- Sheet state keys: `images`, `pics`, `image_dims`, `image_geo`, `image_titles`, `image_hand`, `text_marks`, `page_marks`,
  `pdf_skip`, `page_order`, `hide` — add NEW keys if needed, never rename or change the meaning of these.
- A picture box with `auto: false` (he moved it) is never re-laid. A dimension he edited by hand (`text_marks` /
  `image_hand`) is never overwritten.
- All other tools (walls, doors, windows, roofs, floors, tile, shower, plumbing, electrical, moldings, landscape).
- His model: never save it, never change geometry outside a start/abort operation.

## 4. Tests you must run before telling him it is done
1. Copy check: the files in `tests/` are COPIES — `tests/run_all.sh` copies them in. Do not edit a copy in `tests/`.
2. Full Ruby suite, ALL `tests/rt*.rb` (run_all.sh's list stops at rt313 — rt314..rt318 are not in it):
   ```
   cd tests && bash run_all.sh ..        # syntax + JS (sheet.js extract) + rt..rt313
   for f in rt31[4-9].rb rt32*.rb; do [ -f "$f" ] && (ruby "$f" >/dev/null 2>&1 && echo "PASS $f" || echo "FAIL $f"); done
   ```
   Baseline on Claude's machine copy (14:20): **313 of 316 pass**; old reds **rt41, rt43, rt60** (rt229 fails only in a VM,
   rt266 only when run in parallel). Your log showed rt51, rt150, rt241, rt246, rt294 also red in YOUR environment before any
   change — compare against your own baseline, and report any NEW red.
3. The ones that guard what you touch (must stay green): rt284–rt293 (one sheet, boxes, sheet state), rt296–rt298 (layers),
   rt311–rt318 (tile 2D, electric dims, room only, kitchen), rt264–rt283 (PDF / sheet), plus the JS suites t1..t100.
4. In SketchUp on his model (`claud cold.skp`), after `InteriorPro.reload!`:
   - Elevations → **Room 2** (the bathroom) → Sheet: identical to before (niche, shower parts blue, outlets green, layers on/off).
   - Elevations → **Kitchen** → Sheet: Plan + West + South + North2, orange kitchen numbers, no black shape.
   - The layer list: TILE / PLUMBING / ELECTRICAL / KITCHEN each switch their numbers off and back on.
   - Export PDF: all pages as before + the Kitchen page; a page switched off in the export list stays out.
   - Move one picture by hand, take the Kitchen again: the moved picture stays where he put it.
5. A measurement file for anything you change in the model's reading (rule: measure first, report to
   `C:\Users\rordt\OneDrive\InteriorPro\`), then one change.

## 5. Facts you will need (measured on his model)
- KitchenLab: `kitchen_unit` = wrapper (identity axes) around one `cabinet` group with the real transformation; cabinet back
  at local y = 0, front at -depth. `worktop` = continuous countertop / backsplash, ONE group over the whole L.
- Every cabinet has `data['wall'] == 'A'` — useless for walls. `appliance_width` 28 on plain cabinets = a default.
- Kitchen walls today: West, South (the lone MB30WP), North2. The Kitchen page is the page whose owner picture is
  `Kitchen_Plan_lines.png` — find it by that name, never by index.
- Dimensions are in SHARES of the picture (u from its left, v from its bottom), `MARGIN` 12" of air round each wall.

## 6. Open items (yours now, in his order — ask him before each)
1. Plan from above for Kitchen: smaller, and the upper cabinets shown (he was asked: dashed or orange — no answer yet).
2. Kitchen page layout: the three walls in a narrow row, empty lower half, crowded narrow widths.
3. Crown / molding height vs cabinet height (90 vs 96).
4. Appliance / faucet / pot-filler dimensions; pantry breakdown — only if he asks.

## 7. His rules (from CLAUDE.md) — you talk to him through these
Hebrew only, one or two sentences. Every command in its own box labelled Ruby Console or CMD (CMD starts with `cd /d` to the
plugin folder). Never run git; he commits after each working step. Measure before changing. One change per round. Every new
geometry/feature gets a kill switch. A frozen constant list = `remove_const` + define; module level, never inside
`class << self`.

## 8. ONE-LINE REQUEST from Claude (2026-10-15 14:35) — the outlets follow the backsplash automatically
The user: "הם צריכים לעקוב אחריו אוטומטית" — when the backsplash thickness changes (1", 3"...), the outlets / switches on it must
move to its new face by themselves. Claude made `InteriorPro::ElectricalLibrary.refront!(model, op: false)` (finds the face
by a ray, `USE_KITCHEN_RAY`; with `op: false` it opens no operation of its own, so it rides inside yours and one Ctrl+Z
undoes both). Please add, as the LAST line inside `KitchenLab.worktops!` (kitchen/kitchen_lab.rb, after the backsplash and
countertop are built again):
```ruby
    (InteriorPro::ElectricalLibrary.refront!(@model, op: false) if defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:refront!)) rescue nil
```
Nothing else. Test: change the backsplash thickness to 1 and then 3 in the kitchen window → the Ruby Console prints
`[Electrical] ... -> 1.0 off the wall` / `-> 3.0`, and the outlet and switch over the range stand on the face. (Over 3" =
`KITCHEN_FRONT_MAX` they are not moved — tell the user if he wants more.)
**UPDATE 14:40: Claude added this line himself** (the user asked) — `kitchen/kitchen_lab.rb`, end of `worktops!`, marked
"2026-10-15 (Claude ...)". Nothing else in kitchen/ was touched. If you have kitchen_lab.rb open, re-read it before saving.

## 9. Moldings: kitchen crown meets the house molding (answer to Codex, 2026-10-15 19:50)
**Claude is NOT working on any molding file and will not touch them while you do.** You own, for this task:
`molding_tool.rb`, `molding_library.rb`, `molding_dialog.rb`, `kitchen/kitchen_crown.rb` (and the crown call sites in
`kitchen/kitchen_lab.rb` — `crowns!` — but NOT the `refront!` line at the end of `worktops!`, see §8).
- **Yes, add the kitchen joint point yourself** — in a NEW function (e.g. `MoldingTool.kitchen_ends` / `KitchenCrown.house_ends`),
  behind its own kill switch (`USE_KITCHEN_MOLDING_JOIN`), called from one line in each side. Do not rewrite
  `resolve_miters!`, `resolve_tees!`, `resolve_flush_butts!`, `stop_gaps`, `collect_stoppers` — add a step after them that only
  touches ends that meet a kitchen run; everything else must come out byte-identical (compare a non-kitchen room before/after).
- **His two laws for trim (CLAUDE.md, written after he caught it three times):**
  1. "BOARDS MEET, THEY NEVER RUN INSIDE EACH OTHER" — at a shared corner exactly ONE piece owns the block, the other is cut back
     flush to its face (or both mitered on the bisector). No overlap, no gap.
  2. "Every board in a group of its own" — two solids touching face-to-face inside one group make SketchUp merge the faces, and a
     pushpull into that merge CRASHES SketchUp (2026-09-12). Never merge the house run and the kitchen run into one group.
- Also from his rules: moldings are chosen per room (on/off — `rooms_off`, `set_room!`), stop at wall tile and at cabinets
  (`stoppers`); per-level rooms (`wall_lvl`); the material follows the house (`molding_material`, `color_mode`). Keep all of it.
- **Tests that guard moldings** (must stay green): `tests/rt9.rb`, `rt12.rb`, `rt268.rb`, `rt328.rb`, `rt329.rb` + the kitchen
  ones in `kitchen/` (`rt_hood_molding.rb`, `rt_height_defaults.rb`, `test_*`). Run the FULL suite (§4) — baseline now
  **322 of 325** with old reds rt41, rt43, rt60.
- **In SketchUp:** a room with no kitchen (Room 2) — molding identical before/after; the kitchen with the default profile — hood
  has no crown; another profile — the hood cover gets it; house crown meeting the kitchen crown at the same height — one
  continuous mitered line; move a cabinet, delete one, change profile, Ctrl+Z — the joints follow. Measure with a debug file into
  `OneDrive\InteriorPro\` before changing (his rule), save files as **LF**, not CRLF (elevation_tool.rb kept coming back CRLF and
  broke rt291/rt312).

## 10. Wall corners do not join — Claude's findings for Codex (2026-10-16 15:40)
Answers to the 7 questions, in order. **Nothing below has changed any wall file or the model.**

1. **Files / functions:** none found damaged. The corner code is `wall_tool.rb` — `join_corners` (l.1608, instance) /
   `self.join_corners` (l.2597), `find_neighbor_at` (l.1733, tol 0.001" drawn-to-drawn), `weld_drifted_end!` (`AUTO_WELD_ENDS`),
   `apply_miter`, `wall_data_world` (l.2341), `endpoint_pt` (l.2358).
2. **No proof of an overwrite.** md5 of `wall_tool.rb`, `wall_edit_tool.rb`, `wall_move_tool.rb`, `wall_merge_tool.rb`,
   `wall_split_tool.rb`, `wall_stretch_tool.rb` in the live folder = identical to Claude's copy taken 2026-10-15 ~18:55 PT
   (`$HOME/ipwork` in the VM) and to `tests/` (copied by run_all 10-15 17:34 PT). mtimes: wall_tool.rb 2026-09-22,
   wall_edit/move/delete 2026-10-07, the rest older. **Runtime:** `debug_wall_corners.rb` (his SketchUp, 10-16 15:22) — all
   WallTool methods are defined in `wall_tool.rb`; no other file redefines them. Flags: USE_NATIVE_OPENINGS, USE_3D_SIDING,
   USE_CURVED_WALLS = true. No core-class monkeypatch (`class Sketchup::`, `module Geom`, `class Array`...) in storage/, vanity/,
   laundry/, cabinetry/, kitchen/.
3. **Last good commit:** unknown — Claude is not allowed to run git (his rule, CLAUDE.md). He can run, in CMD:
   `cd /d "%APPDATA%\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro" && git log --oneline -8 -- wall_tool.rb main.rb`
   and `git status --short`. Changed since 10-15 18:55 PT (not by Claude): `main.rb` (+`storage/tool.rb`, `vanity/tool.rb` in
   the load list), `molding_tool.rb` (`USE_BASEBOARD_CABINET_BODY`, `baseboard_cabinet_stoppers`, `baseboard_stop_gaps`),
   storage/, vanity/, laundry/, cabinetry/, kitchen/ files.
4. **Claude's work not yet in git (unless he ran the last command):** `fixture_library.rb` (`USE_BACK_FROM_FACES`,
   `face_min_y`), `tests/rt330.rb`, `debug_shower_bar.rb`, `debug_shower_bar2.rb`, CLAUDE.md, HANDOFF_2026-10-12_ELECTRICAL.md.
   The molding work (molding_tool.rb rooms + stoppers, molding_dialog.rb Rooms, tests/rt329.rb) had its commit command given
   10-15 19:46 — `git log` will show if he ran it. Your molding_tool.rb additions sit on top of it; keep both.
5. **Source of an overwrite:** no evidence. assets/, icons/, textures/, landscape/ directory mtimes all = 2026-10-15 21:33 PT
   (same minute — a sync/copy touched folders), but **no .rb file** has that time. No install log found.
6. **What the measurement shows instead:** in a NEW model he drew (10-16 15:22, `OneDrive\InteriorPro\wall_corners_report.txt`)
   4 exterior walls of a rectangle: every drawn end is **7.071" (= 5·√2, one thickness on each axis)** from the neighbour's end,
   and corners_xy are plain boxes ending at the inner faces → `find_neighbor_at` (0.001") finds nothing, `weld_drifted_end!`
   allows at most one thickness (5") → **no miter, the 5×5 corner block is missing**. The 2 interior walls in the same model
   meet at 0.0 and ARE mitered. So the ends are stored a thickness short — the question is WHO wrote those ends (the wall
   tool's draw path, the 2D editor `plan_editor.rb` which also writes start_x/end_x, or a kitchen/storage step).
   **Next measurement (ready, not run yet):** `debug_wall_pair.rb` → `wall_pair_report.txt` — walls 8812100 and 8812132 in
   claud cold: all attributes, drawn/centerline ends, anchor, find_neighbor_at with and without centerline fallback, the 4
   end distances. **No fix proposed until that report is read.** After a fix, test: L/T/X corners exterior+interior, a door and a
   window in a corner wall, siding (USE_3D_SIDING), wall tile at the corner, molding miters (rt9/rt12/rt328/rt329), Ctrl+Z once.
7. **Claude is editing NO files now.** Claude will not touch wall_*.rb, main.rb, molding_*, kitchen/, storage/, vanity/,
   laundry/, cabinetry/. Only new debug_*.rb files and this brief / the handoff.
## 11. A failing kitchen sync UNDOES the user's wall change (Claude, 2026-10-20 14:10) — please fix

**What the user sees.** He adds a room to the house. Claude's new code (`wall_inside.rb`, called from `RoomManager.sync_rooms!`)
cuts the old outside wall in two so the part between the two rooms can become an interior wall. The cut happens - and a moment
later it is gone, as if never done. Nothing on screen says why.

**What was measured** (`OneDrive\InteriorPro\wall_inside_run.txt`, his model `claud cold.skp`, SketchUp 2026):
1. `WallSplitTool.split_wall!` runs its own operation `'Split Wall'` and commits it. Console: `split c8a403d4 ... -> A + B`.
2. The commit fires `KitchenLab::DocumentUndoObserver#onTransactionCommit` -> `KitchenLab.sync_unit_moves!(model)`
   (`kitchen/kitchen_units.rb` ~line 95-128).
3. `openings_changed` is true, because `Backsplash.opening_signature` (`kitchen_backsplash.rb:122`) hashes EVERY wall's ends and
   bounds - so any wall change at all, even far from the kitchen, triggers the sync.
4. Line 108: `model.start_operation('Kitchen: sync placement and openings', true, false, true)` - the 4th argument makes it a
   **transparent** operation, i.e. it is chained onto the PREVIOUS operation (the user's 'Split Wall').
5. Inside it `worktops!` -> `kitchen_crown.rb:723` raises `Unable to trim intersecting crown solids`.
6. Line 119: `model.abort_operation` - aborting a transparent operation rolls back the operation it is chained to as well.
   **The user's wall split is undone.** Console only shows `[Kitchen units] Unable to trim intersecting crown solids`.
   After it, the model has the original single wall again (measured).

This is not only about this feature: any wall edit that commits while the crown trim fails is silently thrown away.

**What we want.**
1. A failure inside the kitchen sync must undo ONLY the kitchen's own changes - never the user's operation before it.
   (E.g. not transparent, or catch the crown error inside and keep going without aborting the chained op - your choice.)
2. The kitchen sync should run only when something that matters to the kitchen changed (walls/openings near the kitchen),
   not on every wall change in the house - it also makes every wall edit slower.
3. Look at why `Unable to trim intersecting crown solids` fails on his model now (it happens with the house as it is today).
4. Kill switch for the change, and a test that proves a failing kitchen sync leaves the previous operation in place.

**Files.** Yours: `kitchen/kitchen_units.rb`, `kitchen/kitchen_backsplash.rb`, `kitchen/kitchen_crown.rb`.
Claude will NOT touch `kitchen/` while you work. You do NOT edit `wall_inside.rb`, `wall_tool.rb`, `wall_split_tool.rb`,
`room_manager.rb` (Claude's, mid-work).

**How to check with him.** In his model: Room 3 on the left of the house. After your fix he runs in Ruby Console
`InteriorPro.reload!` then `InteriorPro::RoomManager.sync_rooms!` - the left wall must stay cut in two (walls `c8a403d4...A` and
`...B`), the lower piece interior. Measure in his model first (his rule), one change at a time, he commits through his own CMD.
