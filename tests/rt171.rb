# encoding: utf-8
# rt171 - THE TILE NUMBERS ARE A WINDOW, NOT A FILE (2026-09-07).
#
# He stopped the file-writing button himself: "אם זה לי זה צריך להיות
# בקובץ זמין שאני יכול לפתוח וכרגע זה כמו שולח לי אתזה כPDF או פותח
# קובץ בראוזר חדש כל הזמן." The quantities are for HIM, while he designs,
# so they are a screen he opens - read from the model as it is, saving
# nothing.
#
# What is pinned: the table never invents a number for a floor it cannot
# count, and two rooms laid in the SAME tile are one order while two
# different tiles are never added together.
require './sketchup_stub'
require './tile_grid'
require './tile_count'
require './tile_takeoff'
require './tile_count_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

D = InteriorPro::TileCountDialog
def rect(w, h)
  [[0.0, 0.0], [w, 0.0], [w, h], [0.0, h]]
end

BATH = { name: 'Bathroom 2', area: 713.0, poly: rect(283.071, 362.696),
         tw: 48.0, tl: 24.0, grout: 0.0, ox: 0.0, oy: 0.0,
         angle: 0.0, centered: true, pattern: 'Tile' }
SMALL = { name: 'Powder', area: 48.0, poly: rect(96.0, 72.0),
          tw: 48.0, tl: 24.0, grout: 0.0, ox: 0.0, oy: 0.0,
          angle: 0.0, centered: false, pattern: 'Tile' }
WOOD = { name: 'Den', area: 200.0, poly: rect(120.0, 240.0),
         tw: 6.0, tl: 48.0, grout: 0.0, ox: 0.0, oy: 0.0,
         angle: 0.0, centered: false, pattern: 'Straight' }
SLAB = { name: 'Garage', area: 400.0, poly: rect(240.0, 240.0),
         tw: 0.0, tl: 0.0, grout: 0.0, ox: 0.0, oy: 0.0,
         angle: 0.0, centered: false, pattern: 'None' }
HERR = { name: 'Entry', area: 60.0, poly: rect(96.0, 96.0),
         tw: 6.0, tl: 24.0, grout: 0.0, ox: 0.0, oy: 0.0,
         angle: 0.0, centered: false, pattern: 'Herringbone' }

# ---- 1. a line per floor, and the real number ------------------------
rs = D.rows([BATH, SMALL, WOOD, SLAB, HERR])
ok('every floor gets a line', rs.length == 5, rs.length)
bath = rs.find { |r| r[:name] == 'Bathroom 2' }
ok('his bathroom still says 104', bath[:res][:tiles] == 104, bath[:res])
ok('...and the coverage carries the joint', bath[:cov] == [48.0, 24.0], bath[:cov])

# ---- 2. no number is invented ----------------------------------------
slab = rs.find { |r| r[:name] == 'Garage' }
ok('a floor with no tile size gets no count', slab[:res].nil?)
ok('...and says why, in words', slab[:why].to_s.include?('unit size'), slab[:why])
herr = rs.find { |r| r[:name] == 'Entry' }
ok('herringbone is refused, not guessed', herr[:res].nil? && herr[:why].to_s.include?('diagonal'), herr[:why])

# ---- 3. the order: same tile adds up, different tiles never do -------
t = D.totals(rs)
ok('three tile sizes in the model, two of them countable', t.length == 2, t.map { |x| [x[:tw], x[:tl]] })
big = t.find { |x| x[:tw] == 48.0 }
ok('the two 48x24 rooms are ONE order',
   big[:rooms] == 2 && big[:tiles] == bath[:res][:tiles] + rs.find { |r| r[:name] == 'Powder' }[:res][:tiles],
   big)
ok('...and their small pieces are added too',
   big[:small] == bath[:res][:small_pieces] + rs.find { |r| r[:name] == 'Powder' }[:res][:small_pieces], big)
ok('the plank floor is a separate order', t.any? { |x| x[:tw] == 6.0 && x[:rooms] == 1 })
ok('the uncounted floors are in no order at all',
   t.sum { |x| x[:rooms] } == 3, t.map { |x| x[:rooms] })
ok('a joint of its own makes a separate order line',
   D.totals(D.rows([BATH, BATH.merge(name: 'B3', grout: 0.25)])).length == 2)

# ---- 4. the window ---------------------------------------------------
doc = D.html(rs, t)
ok('it is a page', doc.include?('<html') && doc.include?('</html>'))
ok('every room is named on it', ['Bathroom 2', 'Powder', 'Den', 'Garage', 'Entry'].all? { |n| doc.include?(n) })
ok('the number he orders is on it', doc.include?('>104<') || doc =~ />\s*104\s*</)
ok('it says the model is read live, so he knows it is not a saved file',
   doc.include?('right now'))
ok('there is a Refresh, because the model keeps changing',
   doc.include?("sketchup.refresh('')"))
ok('IT WRITES NO FILE AND OPENS NO BROWSER',
   !doc.include?('file:///') && !doc.downcase.include?('.svg') && !doc.downcase.include?('.pdf'))
ok('an empty model says so instead of showing an empty table',
   D.html([], []).include?('No floors in this model.'))

# ---- 5. the page is safe with odd names ------------------------------
weird = D.rows([BATH.merge(name: 'Bath <script>x</script> "2"')])
page = D.html(weird, D.totals(weird))
ok('a room name cannot inject markup into the window',
   !page.include?('<script>x</script>'), page[/Bath.{0,40}/])

puts($fails.zero? ? 'rt171 OK' : "rt171 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
