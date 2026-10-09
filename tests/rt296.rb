# encoding: utf-8
# rt296 - the plan's own marks on an elevation's sheet (2026-10-09, PlanCanvas::USE_PIC_MARKS): kept in
# st['page_marks'][the sheet's picture] in paper inches, drawn by the plan's draw_mark_dim / draw_mark_note
# on the sheet's PNOTES layer at the elevation's letter size; a dimension's number in ROOM inches by its
# picture's scale (per, and how much the picture grew since: pw); a line; a note's box fitted to its words
# when he changes them; named like every label; the switch.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
require 'tmpdir'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      []
    end
  end
end
require './door_library'
require './plan_generator'
require './plan_doc'
require './plan_tables'
require './plan_geometry'
require './plan_canvas'
require './plan_pdf'
require './plan_sheet_dialog'
require './tile_niche'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PC = InteriorPro::PlanCanvas
psd = InteriorPro::PlanSheetDialog
P1 = '/e/Room_2_North_lines.png'

st = psd.load_state
st['images'] = [P1]
st['image_dims'] = {}
st['image_hand'] = {}
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
pg = psd.document.pages.find { |p| p.kind == 'image' }
main = pg.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
x, y, w, h = PC.elev_rect(main)
full = w   # no crop
a = [x + 0.2 * w, y + 0.2 * h]
b = [x + 0.8 * w, y + 0.2 * h]
DIM = { 't' => 'dim', 'x1' => a[0], 'y1' => a[1], 'x2' => b[0], 'y2' => b[1], 'off' => -0.3,
        'pic' => P1, 'per' => 0.6 * w / 60.0, 'pw' => full }
NOTE = { 't' => 'note', 'x' => b[0] + 1.0, 'y' => b[1] + 1.0, 'kx' => b[0] + 0.5, 'ky' => b[1] + 1.0,
         'lx' => b[0], 'ly' => b[1], 'text' => 'Grab bar', 'arrow' => true }
LINE = { 't' => 'line', 'x1' => a[0], 'y1' => a[1], 'x2' => a[0], 'y2' => a[1] + 2.0 }
st['page_marks'] = { P1 => [DIM, NOTE, LINE] }
psd.save_state(st)
ok('they survive save_state', psd.load_state['page_marks'][P1].size == 3)
psd.instance_variable_set(:@doc, nil)
doc = psd.document
pg = doc.pages.find { |p| p.kind == 'image' }
lay = pg.layers.find { |l| l.name == PC::PAGE_MARK_LAYER }
ok('drawn on the sheet, on a layer of their own', lay && !lay.shapes.empty?, pg.layers.map(&:name))
tx = lay ? lay.shapes.select { |s| s[:type] == :text } : []
num = tx.find { |s| s[:text] == '60"' }
ok('the dimension reads 60" - room inches, by its picture', num, tx.map { |s| s[:text] })
eh = PC.elev_style(st)[0]
ok('its number is the elevation\'s size, centred', num && (num[:h] - eh).abs < 1e-9 && num[:align] == :center, num)
words = tx.find { |s| s[:text] == 'Grab bar' }
ok('the note\'s words, centred where the note says', words && (words[:x] - NOTE['x']).abs < 1e-9 && words[:align] == :center && (words[:h] - eh).abs < 1e-9, words)
ln = lay.shapes.select { |s| s[:type] == :line }
seg = ->(p, q) { ln.any? { |s| [[s[:x1], s[:y1], s[:x2], s[:y2]], [s[:x2], s[:y2], s[:x1], s[:y1]]].any? { |r| (r[0] - p[0]).abs < 1e-6 && (r[1] - p[1]).abs < 1e-6 && (r[2] - q[0]).abs < 1e-6 && (r[3] - q[1]).abs < 1e-6 } } }
ok('the dimension line stands off by its own distance', seg.call([a[0], a[1] - 0.3], [b[0], b[1] - 0.3]))
tk = PC::ELEV_TICK / 2.0
ok('ticked the elevation\'s size, not the plan\'s 4"', ln.any? { |s| (s[:x2] - s[:x1]).abs > 0.01 && (s[:x2] - s[:x1]).abs < 0.2 && ((s[:x1] + s[:x2]) / 2 - a[0]).abs < 1e-6 } &&
   ln.none? { |s| (s[:x2] - s[:x1]).abs > 3.0 && (s[:y2] - s[:y1]).abs > 3.0 })
ok('the line drawn on the sheet', seg.call([a[0], a[1]], [a[0], a[1] + 2.0]))
ok('the note\'s slant to what it points at, with a head', seg.call([NOTE['kx'], NOTE['ky']], [b[0], b[1]]) &&
   ln.count { |s| (s[:x1] - b[0]).abs < 1e-6 && (s[:y1] - b[1]).abs < 1e-6 } >= 2)
box = lay.shapes.find { |s| s[:type] == :polygon }
ok('and a box round its words', box && box[:points].map(&:first).min < words[:x] && box[:points].map(&:first).max > words[:x])
ok('every one has a name, like every label', tx.all? { |s| s[:key].to_s.start_with?('PNOTES|') }, tx.map { |s| s[:key] })
ok('the plan\'s marks are not there', doc.canvas('MODEL').layer?(PC::MARK_LAYER) == false || doc.canvas('MODEL').layer(PC::MARK_LAYER).shapes.empty?)

# the picture made half as wide: the dimension stays on the paper, so the same paper length is
# now twice as many room inches - the scale is the picture's as it is NOW
st['image_geo'] = { '0' => { 'box' => [x, y, w * 0.5, h * 0.5], 'crop' => [0, 0, 0, 0], 'rot' => 0 } }
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
pg2 = psd.document.pages.find { |p| p.kind == 'image' }
main2 = pg2.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
grew = PC.elev_rect(main2)[2] / w
t2 = pg2.layers.find { |l| l.name == PC::PAGE_MARK_LAYER }.shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('the scale follows the picture\'s size: half as wide, 120"', (grew - 0.5).abs < 1e-6 && t2.include?('120"'), [grew, t2])
st.delete('image_geo')

# his own size on the note's words: the box is drawn again around them
psd.instance_variable_set(:@doc, nil)
key = tx.find { |s| s[:text] == 'Grab bar' }[:key]
st['text_marks'] = { key => { 'pct' => 200 } }
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
lay3 = psd.document.pages.find { |p| p.kind == 'image' }.layers.find { |l| l.name == PC::PAGE_MARK_LAYER }
w3 = lay3.shapes.find { |s| s[:type] == :text && s[:text] == 'Grab bar' }
b3 = lay3.shapes.find { |s| s[:type] == :polygon }
bw0 = box[:points].map(&:first).max - box[:points].map(&:first).min
bw3 = b3[:points].map(&:first).max - b3[:points].map(&:first).min
ok('twice the size: the words twice as tall and the box grown round them', (w3[:h] - 2 * eh).abs < 1e-9 && bw3 > bw0 * 1.6, [w3[:h], bw0, bw3])
st['text_marks'] = {}

# one with no scale is not drawn, and says so in the trace
st['page_marks'] = { P1 => [DIM.merge('per' => 0)] }
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
said = []
psd.define_singleton_method(:erase_trace) { |t| said << t }
lay4 = psd.document.pages.find { |p| p.kind == 'image' }.layers.find { |l| l.name == PC::PAGE_MARK_LAYER }
ok('a dimension with no scale is not drawn, and the trace says why', (lay4.nil? || lay4.shapes.empty?) && said.any? { |t| t.include?('page marks: NOT drawn') }, said)

src = File.read('./plan_canvas.rb', encoding: 'utf-8')
ok('drawn before the sizing passes, so each gets a name', src.index('place_page_marks!(doc, st)') < src.index('apply_text_scale!(doc, st)', src.index('def self.layout_pages!')))

PC.send(:remove_const, :USE_PIC_MARKS)
PC.const_set(:USE_PIC_MARKS, false)
st['page_marks'] = { P1 => [DIM, NOTE, LINE] }
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
pg = psd.document.pages.find { |p| p.kind == 'image' }
ok('switched off: kept but not drawn', pg.layers.none? { |l| l.name == PC::PAGE_MARK_LAYER && !l.shapes.empty? } && psd.load_state['page_marks'][P1].size == 3)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
