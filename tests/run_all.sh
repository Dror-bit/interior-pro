#!/usr/bin/env bash
# Interior Pro - full test run.
#   bash run_all.sh /path/to/interior_pro
# Copies the live plugin files in, rebuilds the extracted JS, and runs
# every suite. Exits non-zero if anything fails.
set -u
SRC="${1:-..}"
cd "$(dirname "$0")" || exit 1

for f in plan_editor.rb plan_generator.rb door_library.rb door_tool.rb room_manager.rb ceiling_manager.rb level_manager.rb molding_tool.rb wall_tool.rb foundation_manager.rb ui_dialogs.rb wall_stretch_tool.rb wall_curve_tool.rb wall_arc_tool.rb floor_manager.rb roof_manager.rb roof_dialog.rb arc_math.rb door_manager.rb window_tool.rb wall_curve_tool.rb; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" . || echo "  (missing $f - some suites will be skipped)"
done

echo "== ruby syntax =="
fail=0
for f in plan_editor.rb plan_generator.rb door_library.rb door_tool.rb arc_math.rb door_manager.rb wall_tool.rb; do
  [ -f "$f" ] || continue
  ruby -c "$f" >/dev/null 2>&1 && echo "  OK   $f" || { echo "  BAD  $f"; fail=1; }
done

echo "== extract the editor JS from the heredoc =="
ruby extract.rb || fail=1
node --check out.js && echo "  OK   out.js parses" || fail=1

echo "== javascript suites (the 2D editor canvas) =="
for t in t1 t2 t3 t4 t5 t6 t7 t8 t9 t12 t13 t14 t15 t16 t17 t18 t19 t20 t21 t22 t23 t24 t25 t26 t27 t28 t29 t30 t31 t32 t33 t34; do
  [ -f "$t.js" ] || continue
  if node "$t.js" >/dev/null 2>&1; then echo "  PASS $t"; else echo "  FAIL $t"; node "$t.js" 2>&1 | grep FAIL | head -3; fail=1; fi
done

echo "== ruby suites (callbacks, rooms, plans, doors) =="
for r in rt rt2 rt3 rt4 rt5 rt6 rt7 rt8 rt9 rt10 rt11 rt12 rt13 rt14 rt15 rt16 rt17 rt18 rt19 rt20 rt21 rt22 rt23 rt24 rt25 rt26 rt27 rt28 rt29 rt30 rt31 rt32 rt33 rt34 rt35 rt36; do
  [ -f "$r.rb" ] || continue
  if ruby "$r.rb" >/dev/null 2>&1; then echo "  PASS $r"; else echo "  FAIL $r"; ruby "$r.rb" 2>&1 | grep FAIL | head -3; fail=1; fi
done

[ "$fail" -eq 0 ] && echo "== ALL GREEN ==" || echo "== SOMETHING FAILED =="
exit $fail
