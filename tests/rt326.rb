# encoding: utf-8
# rt326 - THE SIZE OF A ROOM'S DRAWINGS ON ITS PAGE (2026-10-15 17:05, his "הגדלה פר דף ... שלוש מידות שונות שכולם יכנסו
# בדף"): S = as before, M / L bigger in up to 2 / 4 rows; all at one scale, all on the page, none over another.
require './sketchup_stub'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switch is there and on', ET::USE_SHEET_SIZE == true && ET::SHEET_SIZES.keys == [1, 2, 3])
area = [0.5, 1.5, 34.0, 21.0]           # a 36 x 24 page under its title block
sizes = [[1700, 1460], [1129, 1440], [1333, 1440], [1129, 1440], [1333, 1440]]   # Room 2: the plan + four walls
cols = [[0, 0], [1, 2], [2, 1], [0, 2], [1, 1]]
s1 = ET.grid_boxes(area, sizes, cols, 0, 1)
ok('S = former Medium', s1 == ET.small_sheet_boxes(area, sizes, cols, 0, 2))
scale = ->(bx) { bx[1][2] / sizes[1][0] }
inside = lambda do |bx|
  bx.all? { |x, y, w, h| x >= area[0] - 1e-6 && y >= area[1] - 1e-6 && x + w <= area[0] + area[2] + 1e-6 && y + h <= area[1] + area[3] + 1e-6 }
end
apart = lambda do |bx|
  bx.combination(2).none? { |a, b| a[0] < b[0] + b[2] - 1e-6 && b[0] < a[0] + a[2] - 1e-6 && a[1] < b[1] + b[3] - 1e-6 && b[1] < a[1] + a[3] - 1e-6 }
end
s2 = ET.grid_boxes(area, sizes, cols, 0, 2)
s3 = ET.grid_boxes(area, sizes, cols, 0, 3)
ok('M bigger than S, L bigger than M', scale.(s2) > scale.(s1) && scale.(s3) > scale.(s2), [scale.(s1), scale.(s2), scale.(s3)])
ok('every size: all on the page, none over another', [s1, s2, s3].all? { |b| inside.(b) && apart.(b) })
ok('Medium leaves bottom photo space', s2.all? { |b| b[1] >= area[1]+area[3]*0.08 })
ok('one scale for all the pictures of a page', [s2, s3].all? { |b| b.each_with_index.map { |q, i| (q[2] / sizes[i][0]).round(9) }.uniq.size == 1 })
ok('a size not known = S', ET.grid_boxes(area, sizes, cols, 0, 7) == s1)
st = { 'elev_size' => { 'Room 2' => 3 } }
ok('his pick is kept per sheet title, 1 when none', ET.sheet_size(st, 'Room 2') == 3 && ET.sheet_size(st, 'Room 1') == 1 && ET.sheet_size({}, 'x') == 1)
src = File.read('./elevation_tool.rb')
ok('add_room_sheet! lays the boxes by his size', src.include?('grid_boxes(pc.pic_area(pg), sizes, cols, ups, sheet_size(st, sheet_title))'))
dsrc = File.read('./elevation_dialog.rb')
ok('the panel: S / M / L per room, sent with the room and kept', dsrc.include?('class=\"rsize\"') && dsrc.include?("size: sz ? sz.value : null") && dsrc.include?('remember_size!'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
