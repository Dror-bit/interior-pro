# encoding: utf-8
# rt293 - a note he writes on an elevation's picture (2026-10-09): kept in st['image_hand'] beside his
# dimensions, { 't' => 'note', 'p' => [tip, knee, end in shares], 'text', 'arrow' }, and drawn over the
# picture on its sheet the way a plan note is - words in a box past the end of the shoulder, the shoulder,
# the slant to what it points at, the head (PlanCanvas.draw_pic_note); the switch.
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
NOTE = { 't' => 'note', 'p' => [0.8, 0.2, 0.9, 0.4, 1.05, 0.4], 'text' => 'Grab bar here', 'arrow' => true }

st = psd.load_state
st['images'] = [P1]
st['image_dims'] = {}
st['image_hand'] = { P1 => [NOTE, { 'p' => [0.2, 0.2, 0.8, 0.2], 'o' => 'h', 'at' => 0.1, 'n' => 60.0 }] }
psd.save_state(st)
ok('it survives save_state', psd.load_state['image_hand'][P1][0] == NOTE)
psd.instance_variable_set(:@doc, nil)
doc = psd.document
pg = doc.pages.find { |p| p.kind == 'image' }
lay = pg && pg.layers.find { |l| l.name == PC::ELEV_DIM_LAYER }
main = pg.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
tx = lay ? lay.shapes.select { |s| s[:type] == :text } : []
w = tx.find { |s| s[:text] == 'Grab bar here' }
ok('its words are drawn on the picture\'s sheet', w, tx.map { |s| s[:text] })
ok('and the dimension beside it still is', tx.any? { |s| s[:text] == '60"' })
tip = PC.elev_pt(main, 0.8, 0.2)
knee = PC.elev_pt(main, 0.9, 0.4)
en = PC.elev_pt(main, 1.05, 0.4)
th = PC::ELEV_TEXT_H
ok('the letters are the elevation\'s size, level, from their left end (the window draws paper writing from its start)',
   w && (w[:h] - th).abs < 1e-9 && w[:align] == :left && (w[:rotation] || 0).zero?, w)
ok('the words stand on the shoulder\'s line, past its end: their middle on it', w && (w[:y] + th / 2.0 - en[1]).abs < 1e-9 && w[:x] > en[0], [w, en])
box = lay.shapes.find { |s| s[:type] == :polygon }
xs = box ? box[:points].map(&:first) : []
ys = box ? box[:points].map(&:last) : []
ok('a box round the words starts exactly at the end of the shoulder', box && (xs.min - en[0]).abs < 1e-6, [xs.min, en[0]])
tw = PC.text_width_in('Grab bar here', th / InteriorPro::PlanPDF::CAP_RATIO * 72.0)
ok('the words lie INSIDE the box, the same room left and right, top and bottom',
   w && (w[:x] - xs.min - (xs.max - (w[:x] + tw))).abs < 1e-6 && w[:x] > xs.min && w[:x] + tw < xs.max &&
   (w[:y] - ys.min - (ys.max - (w[:y] + th))).abs < 1e-6, [w, xs, ys, tw])
ln = lay.shapes.select { |s| s[:type] == :line }
seg = ->(a, b) { ln.any? { |s| [[s[:x1], s[:y1], s[:x2], s[:y2]], [s[:x2], s[:y2], s[:x1], s[:y1]]].any? { |q| (q[0] - a[0]).abs < 1e-6 && (q[1] - a[1]).abs < 1e-6 && (q[2] - b[0]).abs < 1e-6 && (q[3] - b[1]).abs < 1e-6 } } }
ok('the shoulder runs from the box to the knee', seg.call(en, knee))
ok('the slant runs from the knee to the corner it points at', seg.call(knee, tip))
heads = ln.count { |s| (s[:x1] - tip[0]).abs < 1e-6 && (s[:y1] - tip[1]).abs < 1e-6 }
ok('with a head on the end (two strokes from the tip)', heads == 2, heads)

# no head when he chose none; a broken one draws nothing and breaks nothing
st['image_hand'] = { P1 => [NOTE.merge('arrow' => false), { 't' => 'note', 'p' => [1, 2], 'text' => 'x' }, { 't' => 'note', 'p' => [0.1, 0.1, 0.2, 0.2, 0.3, 0.2], 'text' => '  ' }] }
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
lay = psd.document.pages.find { |p| p.kind == 'image' }.layers.find { |l| l.name == PC::ELEV_DIM_LAYER }
ln = lay.shapes.select { |s| s[:type] == :line }
ok('no head when he chose none', ln.count { |s| (s[:x1] - tip[0]).abs < 1e-6 && (s[:y1] - tip[1]).abs < 1e-6 } == 0)
ok('a broken note or one with no words draws nothing', lay.shapes.count { |s| s[:type] == :text } == 1 && lay.shapes.count { |s| s[:type] == :polygon } == 1)

src = File.read('./plan_canvas.rb', encoding: 'utf-8')
ok('a note that fails is written in the trace, not only the console',
   src.include?('def self.pic_note_safely(key, n)') && src.include?('InteriorPro::PlanSheetDialog.erase_trace(line)') &&
   src.include?('notes.each { |n| pic_note_safely(key, n) { draw_pic_note(lay, main, n) } }'))

PC.send(:remove_const, :USE_PIC_DIMS)
PC.const_set(:USE_PIC_DIMS, false)
psd.instance_variable_set(:@doc, nil)
pg = psd.document.pages.find { |p| p.kind == 'image' }
ok('switched off: kept but not drawn', pg.layers.none? { |l| l.name == PC::ELEV_DIM_LAYER && !l.shapes.empty? } && psd.load_state['image_hand'][P1].size == 3)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
