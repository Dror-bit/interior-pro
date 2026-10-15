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
