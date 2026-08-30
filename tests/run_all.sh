#!/usr/bin/env bash
# Interior Pro - full test run.
#   bash run_all.sh /path/to/interior_pro
# Copies the live plugin files in, rebuilds the extracted JS, and runs
# every suite. Exits non-zero if anything fails.
set -u
SRC="${1:-..}"
cd "$(dirname "$0")" || exit 1

for f in plan_doc.rb plan_tables.rb plan_geometry.rb plan_canvas.rb plan_pdf.rb plan_sheet_dialog.rb plan_editor.rb plan_generator.rb state_backup.rb auto_backup.rb door_library.rb door_tool.rb room_manager.rb ceiling_manager.rb level_manager.rb molding_tool.rb wall_tool.rb foundation_manager.rb ui_dialogs.rb wall_stretch_tool.rb wall_delete_tool.rb wall_split_tool.rb wall_curve_tool.rb wall_arc_tool.rb floor_manager.rb roof_manager.rb dormer_manager.rb dormer_dialog.rb dormer_edit_tools.rb roof_dialog.rb roof_edit_tool.rb arc_math.rb roof_tile_math.rb roof_tile_parts.rb roof_tile_place.rb door_manager.rb window_tool.rb window_manager.rb window_library_dialog.rb wall_library_dialog.rb door_move_tool.rb door_delete_tool.rb door_library_dialog.rb toolbar.rb main.rb; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" . || echo "  (missing $f - some suites will be skipped)"
done

# Landscape Pro lives in its own folder, so it is copied in separately.
# Flattened on purpose: every suite requires './name', like all the others.
for f in fence_math.rb fence_tool.rb fence_library.rb fence_library_dialog.rb fence_ref_tool.rb garden_wall_tool.rb; do
  [ -f "$SRC/landscape/$f" ] && cp "$SRC/landscape/$f" . || echo "  (missing landscape/$f - some suites will be skipped)"
done

echo "== ruby syntax =="
fail=0
for f in plan_doc.rb plan_tables.rb plan_canvas.rb plan_pdf.rb plan_editor.rb plan_generator.rb state_backup.rb auto_backup.rb door_library.rb door_tool.rb arc_math.rb door_manager.rb wall_tool.rb fence_math.rb fence_tool.rb fence_library.rb fence_library_dialog.rb fence_ref_tool.rb garden_wall_tool.rb; do
  [ -f "$f" ] || continue
  ruby -c "$f" >/dev/null 2>&1 && echo "  OK   $f" || { echo "  BAD  $f"; fail=1; }
done

echo "== extract the editor + sheet JS from the heredocs =="
ruby extract.rb || fail=1
ruby extract_sheet.rb || fail=1
node --check out.js && echo "  OK   out.js parses" || fail=1
node --check sheet.js && echo "  OK   sheet.js parses" || fail=1

echo "== javascript suites (the 2D editor canvas) =="
for t in t1 t2 t3 t4 t5 t6 t7 t8 t9 t12 t13 t14 t15 t16 t17 t18 t19 t20 t21 t22 t23 t24 t25 t26 t27 t28 t29 t30 t31 t32 t33 t34 t35 t36 t37 t38 t39 t40 t41 t42 t43 t44b t45 t46 t47 t48 t49 t50 t51 t52 t53; do
  [ -f "$t.js" ] || continue
  if node "$t.js" >/dev/null 2>&1; then echo "  PASS $t"; else echo "  FAIL $t"; node "$t.js" 2>&1 | grep FAIL | head -3; fail=1; fi
done

echo "== ruby suites (callbacks, rooms, plans, doors) =="
for r in rt rt2 rt3 rt4 rt5 rt6 rt7 rt8 rt9 rt10 rt11 rt12 rt13 rt14 rt15 rt16 rt17 rt18 rt19 rt20 rt21 rt22 rt23 rt24 rt25 rt26 rt27 rt28 rt29 rt30 rt31 rt32 rt33 rt34 rt35 rt36 rt37 rt38 rt39 rt40 rt41 rt42 rt43 rt44 rt45 rt46 rt47 rt48 rt49 rt50 rt51 rt52 rt53 rt54 rt55 rt56 rt57 rt58 rt59 rt60 rt61 rt62 rt63 rt64 rt65 rt66 rt67 rt68 rt69 rt70 rt71 rt72 rt73 rt74 rt75 rt77 rt78 rt79 rt80 rt81 rt82 rt83 rt84 rt85 rt86 rt87 rt88 rt89 rt90 rt91 rt92 rt93 rt94 rt95 rt96 rt97 rt98 rt99 rt100 rt101 rt102 rt103 rt104 rt105 rt106 rt107 rt108 rt109 rt110 rt111 rt112 rt113 rt115 rt116 rt117 rt118 rt119 rt120 rt121 rt122 rt123 rt124 rt125 rt126; do
  [ -f "$r.rb" ] || continue
  if ruby "$r.rb" >/dev/null 2>&1; then echo "  PASS $r"; else echo "  FAIL $r"; ruby "$r.rb" 2>&1 | grep FAIL | head -3; fail=1; fi
done

[ "$fail" -eq 0 ] && echo "== ALL GREEN ==" || echo "== SOMETHING FAILED =="
exit $fail
