# CODEX BRIEF — 1/32" bevel on wall tiles + grout at the bottom of the bevel (2026-10-19)

From Claude, after your review "TILE GEOMETRY FOR BETTER V-RAY RENDERS" (2026-10-19). The user picked your P1, first
deliverable only: micro-bevel on the existing SOLID WALL tiles. Floors, niche lining, texture variants, detail levels,
V-Ray materials — NOT in this step.

## The user's decisions (his words, 2026-10-19 11:31)
> "נתחיל ב-1/32 אינץ', רק בקצה העליון של כל אריח, בלי לשנות מידות או פריסה. תעשה קודם דוגמה על כמה אריחים ונבדוק ברנדר
> לפני שמתחילים על כולם."

and after seeing the sample (11:34): **"תעביר את הגראוט לסוף השיפוע"** — the grout goes back to the bottom of the bevel.
At 11:40 he said to hand it to you to build.

So:
1. Bevel = **1/32" (0.03125")**, a single 45° chamfer, **only on the outer (front) edge loop** of each tile.
2. **Same outline, same depth (0.625"), same finished-face position, same layout, same count.** The chamfer is cut INTO
   the existing box (front face inset by 1/32" on every side, sides stop 1/32" short of the front).
3. **Grout face = 1/32" under the tile face** (at `dp - BEVEL`) instead of `dp - GROUT_BACK` (0.005") — only when the
   bevel is on.
4. The photo stays anchored to the tile's own corner (`p[:u0], p[:v0]`) exactly as today.

## Measured on his model (`debug_tile_bevel.rb` → `OneDrive\InteriorPro\tile_bevel_report.txt`, 11:29)
- Model `claud cold.skp`. 4 tile_wall areas, **556 solid tiles, all plain boxes, no bevel anywhere**.
- TW028 48x48 (4 boxes), TW032 48x48 (4 boxes), TW005 2x2 mosaic (378 boxes, smallest piece 0.625"),
  TW034 48x48 with a niche (170 groups, 1..12 faces each — the niche lining/mitre pieces).
- grout 0.125", depth 0.625", mode tiles, angle 0. `MAX_SOLID` 900 not reached anywhere.

## The sample that was approved (reference implementation — read it)
- `debug_tile_bevel_sample.rb` — rebuilt the 4 boxes of TW032 as chamfered boxes (10 faces each: back, 4 sides,
  4 chamfers, top). Front ring inset by `B` along both edge directions; middle ring = front ring moved `B` toward the wall;
  faces re-oriented outward from the box centre; material on both sides; UV re-anchored on the new top with
  `position_material` using the ORIGINAL front corners and their UVs (from `get_UVHelper`), so the picture does not shift.
- `debug_tile_bevel_grout.rb` — moved the area's grout face `B - GROUT_BACK` (0.02625") toward the wall.
- Reports: `tile_bevel_sample_report.txt` (4 × "bevelled, depth 0.625, faces 10, top 20.3685x47.875"),
  `tile_bevel_grout_report.txt` (grout 0.3075 → 0.2813 from tile middle = exactly the bevel bottom).
- These were done on the model only, not in code. A rebuild of TW032 brings back the sharp tiles — that is expected.

## What to build (tile_wall.rb only)
1. Constants next to `USE_SOLID_TILES` / `MAX_SOLID`, with the `unless const_defined?` pattern and a comment quoting him:
   - `USE_TILE_BEVEL = true` (kill switch; false = exactly today's geometry and today's grout depth)
   - `TILE_BEVEL = 1.0 / 32`
2. `emit_tile_solids!` (≈ line 1859): when `USE_TILE_BEVEL`, build each piece as a chamfered box instead of
   face + `pushpull`. Keep: one group per tile (the law that crashed SketchUp — never two solids in one group),
   material + back_material on every face, the UV anchor on the outer face, the fail counters and the one-line puts.
   - Which pieces get the bevel: a piece with **no holes**, a **simple** outer polygon, and every edge ≥ `3 * TILE_BEVEL`.
     Inset the front polygon by offsetting every edge inward by `TILE_BEVEL` (mitre at the corners — not the
     "move along both neighbours" trick from the sample, which is only right for 90° corners). Reject the inset
     (build the old sharp box for that piece) if it self-intersects, flips orientation, or loses area < 0.
   - Every other piece: today's face + pushpull, unchanged. Count them and add to the existing puts
     (e.g. `"[TileWall] bevel: N tiles, M kept sharp"`).
   - Cut pieces at the area's outer edge get the bevel on all sides too — he said "each tile"; don't try to tell factory
     edge from cut edge in this step.
3. The grout line (≈ line 1314): `back = solid ? [dp - GROUT_BACK, GROUT_OFF].max : GROUT_OFF` →
   when `solid && USE_TILE_BEVEL`: `[dp - TILE_BEVEL, GROUT_OFF].max`. Nothing else in that branch changes.
4. **Do NOT touch**: `bevel_niche_tiles!`, `lining_solid!`, `emit_niche_lining!` (the 45° niche mitre — rt194),
   `emit_slab_solids!` / image mode, `TileGrid`, counts/takeoff, `MAX_SOLID`, floor_pattern.rb, shower_floor.rb,
   tile_niche*.rb, any wall_*.rb, window_*.rb. If the niche needs work later, that is a separate step he will ask for.
5. No new attributes in this step (the flag is global). Old models get the bevel the next time an area is rebuilt —
   that is fine; he will rebuild by Edit Tile → Apply.

## Tests
- New `tests/rt336.rb` (check the next free number first) — behaviour, not source strings:
  a square piece → 10 faces, outer face area = (w - 2B)(h - 2B), back face area = w·h, depth unchanged (0.625),
  every face material set on both sides; an L-shaped (concave) piece → bevelled, no self-intersection;
  a piece with a hole → kept sharp (6+ faces, old path); a 0.05" sliver → kept sharp; `USE_TILE_BEVEL = false` →
  identical to today (6 faces, grout at `dp - GROUT_BACK`); grout face at `dp - TILE_BEVEL` with the flag on.
- Run the old tests that touch this file: rt175 (wall geometry), rt194 (niche mitres), and the whole suite:
  `cd tests && LANG=C.UTF-8 timeout 170 bash run_all.sh ..` (known old reds: rt41, rt43, rt60; rt229 only in the VM).
  rt314+ run alone — run the tile ones by hand too.
- **Line endings: LF.** elevation_tool.rb and plan_sheet_dialog.rb were found in CRLF twice after your edits and broke
  rt291/rt312. Save tile_wall.rb as LF.

## Rules of this project (from CLAUDE.md — please follow)
- One change only. Don't improve anything he didn't ask for.
- **Never run git** (not even `git status` / `git log`). He commits from his own CMD.
- Before changing: read `tile_wall.rb` whole. Make a backup copy first:
  `OneDrive\InteriorPro\work\tile_wall_before_bevel_2026-10-19.rb`.
- Every new geometry gets a kill switch (that's `USE_TILE_BEVEL`).
- When done, write a short report at the bottom of this file: what changed (functions + line numbers), test results,
  and the exact steps for him (reload → Edit Tile on TW032 / TW005 → Apply → what he should see). Claude will give him
  the steps in Hebrew and measure on his model before he renders.

## What he should see when it works
Every wall tile has a thin 1/32" bevel on its front edge that catches a line of light in V-Ray, the grout sits at the
bottom of that bevel, and nothing moved: same tiles, same joints, same picture on each tile, same niche.
