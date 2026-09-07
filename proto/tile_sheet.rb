# encoding: utf-8
# Prototype of the tile LAYOUT DRAWING (the elevation he asked for).
# Reads the same tile_grid.rb the count reads - nothing invented here.
require_relative '../tile_grid'
require_relative '../tile_count'

TG = InteriorPro::TileGrid
TC = InteriorPro::TileCount

def rect(w, h) = [[0.0, 0.0], [w, 0.0], [w, h], [0.0, h]]

def ftin(v)
  neg = v < 0
  v = v.abs
  f = (v / 12.0).floor
  i = v - f * 12
  s = (i * 16).round
  whole = s / 16
  frac = s % 16
  g = frac.gcd(16)
  txt = f.positive? ? "#{f}'-" : ''
  txt += frac.zero? ? "#{whole}\"" : "#{whole} #{frac / g}/#{16 / g}\""
  (neg ? '-' : '') + txt
end

W = 48.0
L = 24.0
GROUT = 0.0
ROOM_W = 283.071
ROOM_H = 362.696
CENTERED = true
poly = rect(ROOM_W, ROOM_H)

cells = TG.cells(poly, u_size: W, v_size: L, grout: GROUT, centered: CENTERED)
res = TC.plan(poly, W, L, grout: GROUT, centered: CENTERED)
cell_area = W * L

# classify every cell the same way the count does
items = cells.map do |c|
  piece = TC.clip_convex(poly, c[:quad])
  a = TC.area(piece)
  next nil if a <= cell_area * 0.0005
  xs = piece.map { |p| p[0] }
  ys = piece.map { |p| p[1] }
  bw = TC.r16(xs.max - xs.min)
  bh = TC.r16(ys.max - ys.min)
  kind = if a >= cell_area - 1.0e-4 then :full
         elsif TC.small?([bw, bh], W, L) then :small
         else :cut
         end
  { x: xs.min, y: ys.min, w: xs.max - xs.min, h: ys.max - ys.min, kind: kind, bw: bw, bh: bh }
end.compact

schedule = Hash.new(0)
items.each { |i| schedule[[i[:bw], i[:bh], i[:kind]]] += 1 unless i[:kind] == :full }

# ---- sheet -----------------------------------------------------------
PAD_L = 108
PAD_T = 84
PAD_R = 292
PAD_B = 96
DRAW_W = 620.0
sc = DRAW_W / ROOM_W
dh = ROOM_H * sc
SW = (PAD_L + DRAW_W + PAD_R).round
SH = (PAD_T + dh + PAD_B).round

FILL = { full: '#ffffff', cut: '#cfe0ef', small: '#f2c9a8' }
S = []
S << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{SW}" height="#{SH}" viewBox="0 0 #{SW} #{SH}" font-family="Helvetica, Arial, sans-serif">)
S << %(<rect width="#{SW}" height="#{SH}" fill="#fbfaf8"/>)

px = ->(x) { PAD_L + x * sc }
py = ->(y) { PAD_T + dh - y * sc }

items.each do |i|
  x = px.call(i[:x])
  y = py.call(i[:y] + i[:h])
  S << %(<rect x="#{x.round(2)}" y="#{y.round(2)}" width="#{(i[:w] * sc).round(2)}" height="#{(i[:h] * sc).round(2)}" fill="#{FILL[i[:kind]]}" stroke="#5a5f66" stroke-width="0.7"/>)
end
S << %(<rect x="#{PAD_L}" y="#{PAD_T}" width="#{DRAW_W.round(2)}" height="#{dh.round(2)}" fill="none" stroke="#1d2733" stroke-width="2"/>)

# overall dimensions
dy = PAD_T + dh + 34
S << %(<line x1="#{PAD_L}" y1="#{dy}" x2="#{PAD_L + DRAW_W}" y2="#{dy}" stroke="#1d2733" stroke-width="1"/>)
[PAD_L, PAD_L + DRAW_W].each { |x| S << %(<line x1="#{x}" y1="#{dy - 6}" x2="#{x}" y2="#{dy + 6}" stroke="#1d2733" stroke-width="1"/>) }
S << %(<text x="#{(PAD_L + DRAW_W / 2).round}" y="#{dy + 22}" font-size="14" text-anchor="middle" fill="#1d2733">#{ftin(ROOM_W)}</text>)
dx = PAD_L - 40
S << %(<line x1="#{dx}" y1="#{PAD_T}" x2="#{dx}" y2="#{PAD_T + dh}" stroke="#1d2733" stroke-width="1"/>)
[PAD_T, PAD_T + dh].each { |y| S << %(<line x1="#{dx - 6}" y1="#{y}" x2="#{dx + 6}" y2="#{y}" stroke="#1d2733" stroke-width="1"/>) }
S << %(<text x="#{dx - 12}" y="#{(PAD_T + dh / 2).round}" font-size="14" text-anchor="middle" fill="#1d2733" transform="rotate(-90 #{dx - 12} #{(PAD_T + dh / 2).round})">#{ftin(ROOM_H)}</text>)

S << %(<text x="#{PAD_L}" y="38" font-size="19" fill="#1d2733">Bathroom 2</text>)
S << %(<text x="#{PAD_L}" y="60" font-size="13" fill="#6b7280">713.0 sq ft &#183; tile #{W.round} x #{L.round} &#183; joint #{GROUT} &#183; centred</text>)

# legend + schedule
lx = PAD_L + DRAW_W + 34
ly = PAD_T + 4
box = lambda do |y, fill, label, n|
  S << %(<rect x="#{lx}" y="#{y - 11}" width="15" height="15" fill="#{fill}" stroke="#5a5f66" stroke-width="0.8"/>)
  S << %(<text x="#{lx + 24}" y="#{y}" font-size="13" fill="#1d2733">#{label}</text>)
  S << %(<text x="#{lx + 232}" y="#{y}" font-size="13" text-anchor="end" fill="#1d2733">#{n}</text>)
end
box.call(ly + 14, FILL[:full],  'whole tiles', res[:full])
box.call(ly + 40, FILL[:cut],   'cut pieces', res[:cut_pieces])
box.call(ly + 66, FILL[:small], 'under 20% (waste)', res[:small_pieces])
S << %(<line x1="#{lx}" y1="#{ly + 84}" x2="#{lx + 232}" y2="#{ly + 84}" stroke="#c8ccd2" stroke-width="1"/>)
S << %(<text x="#{lx}" y="#{ly + 106}" font-size="14" font-weight="600" fill="#1d2733">TILES TO BUY</text>)
S << %(<text x="#{lx + 232}" y="#{ly + 106}" font-size="18" font-weight="700" text-anchor="end" fill="#1d2733">#{res[:tiles]}</text>)
S << %(<text x="#{lx}" y="#{ly + 128}" font-size="11" fill="#6b7280">#{res[:cut_pieces]} cuts came from #{res[:cut_tiles]} tiles &#183; #{res[:paired]} reused</text>)

S << '</svg>'
File.write('proto/tile_layout_bathroom2.svg', S.join("\n"))
puts "wrote proto/tile_layout_bathroom2.svg   #{items.length} pieces, buy #{res[:tiles]}"
puts schedule.inspect
