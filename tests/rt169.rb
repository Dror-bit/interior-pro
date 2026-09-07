# encoding: utf-8
# rt169 - THE LAYOUT SHEET DRAWS WHAT THE COUNT COUNTED (2026-09-06).
#
# The picture and the order have to come from the same layout, or the
# sheet is a lie. This pins that, and it pins what he asked to leave OFF
# the sheet: "אני רק מזמין את החומר אני לא אומר לו איך לחתוך... אז ניתן
# לקבלן להסתדר עם זה בעצמו" - so no cut schedule.
require './tile_grid'
require './tile_count'
require './tile_sheet'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

TS = InteriorPro::TileSheet
TC = InteriorPro::TileCount
def rect(w, h, x = 0.0, y = 0.0)
  [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
end

# His Bathroom 2, to the inch.
ROOM = rect(283.071, 362.696)
W = 48.0
L = 24.0

# ---- 1. every piece drawn is a piece counted -------------------------
parts = TS.pieces(ROOM, W, L, centered: true)
res = TC.plan(ROOM, W, L, centered: true)
ok('the sheet draws a shape for every whole tile',
   parts.count { |p| p[:kind] == :full } == res[:full],
   [parts.count { |p| p[:kind] == :full }, res[:full]])
ok('...for every cut piece',
   parts.count { |p| p[:kind] == :cut } == res[:cut_pieces],
   [parts.count { |p| p[:kind] == :cut }, res[:cut_pieces]])
ok('...and for every piece under 20%',
   parts.count { |p| p[:kind] == :small } == res[:small_pieces],
   [parts.count { |p| p[:kind] == :small }, res[:small_pieces]])
ok('his room is 119 pieces on the floor and 104 tiles to buy',
   parts.length == 119 && res[:tiles] == 104, [parts.length, res[:tiles]])

# ---- 2. the pieces are the real shapes, not boxes --------------------
L_ROOM = [[0, 0], [96, 0], [96, 48], [48, 48], [48, 96], [0, 96]]
lp = TS.pieces(L_ROOM, 24, 48)
ok('an L-shaped room draws no tile outside itself',
   lp.all? { |p| p[:shape].all? { |q| q[0] >= -0.01 && q[1] >= -0.01 && (q[0] <= 48.01 || q[1] <= 48.01) } })
turned = TS.pieces(ROOM, W, L, angle: 30.0)
ok('a turned layout keeps its corners turned - not squared off',
   turned.any? { |p| p[:kind] == :full && p[:shape].length == 4 &&
                     (p[:shape][0][1] - p[:shape][1][1]).abs > 1.0 })

# ---- 3. the sheet itself ---------------------------------------------
doc = TS.svg('Bathroom 2', ROOM, W, L, centered: true, area_sqft: 713.0)
ok('it is an svg', doc.start_with?('<svg') && doc.end_with?('</svg>'))
ok('the room is named on it', doc.include?('Bathroom 2'))
ok('the number he orders is on it', doc =~ />104</, doc[/TILES TO BUY.{0,120}/m])
ok('so are the three lines behind it',
   doc.include?('whole tiles') && doc.include?('cut pieces') && doc.include?('under 20% (waste)'))
ok('the room is dimensioned in feet and inches',
   doc.include?(TS.ftin(283.071)) && doc.include?(TS.ftin(362.696)),
   [TS.ftin(283.071), TS.ftin(362.696)])
ok('THERE IS NO CUT SCHEDULE - he orders material, the tiler cuts',
   !doc.downcase.include?('cut schedule'))
ok('one shape is drawn for every piece',
   doc.scan('<polygon').length == parts.length + 1, doc.scan('<polygon').length)
ok('the three colours are all used',
   TS::FILL.values.all? { |c| doc.include?(c) })

# ---- 4. feet and inches ----------------------------------------------
ok('283.071" is 23\'-7 1/16"', TS.ftin(283.071) == %(23'-7 1/16"), TS.ftin(283.071))
ok('24" is 2\'-0"', TS.ftin(24) == %(2'-0"), TS.ftin(24))
ok('11.9999" rounds up to 1\'-0", it does not become 0\'-12"',
   TS.ftin(11.9999) == %(1'-0"), TS.ftin(11.9999))
ok('half an inch is 0 1/2"', TS.ftin(0.5) == %(0 1/2"), TS.ftin(0.5))

# ---- 5. names that survive a file system -----------------------------
ok('a plain name becomes a plain file', TS.file_name('Bathroom 2') == 'tile_layout_Bathroom_2.svg')
ok('a name with a slash cannot escape the folder',
   !TS.file_name('a/b:c*d').include?('/') && !TS.file_name('a/b:c*d').include?(':'),
   TS.file_name('a/b:c*d'))
ok('an empty name still makes a file', TS.file_name('') == 'tile_layout_room.svg')

# ---- 6. nothing to draw is said, not guessed -------------------------
ok('a room with no outline draws nothing', TS.svg('x', [[0, 0]], 24, 48).nil?)
ok('a tile too small for the room draws nothing',
   TS.pieces(rect(1000, 1000), 1, 1) == [])

puts($fails.zero? ? 'rt169 OK' : "rt169 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
