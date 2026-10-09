# encoding: utf-8
# rt292 - a dimension he draws on an elevation's picture (2026-10-08 19:46): kept in st['image_hand']
# by the picture's path, in shares of the picture, and drawn over it on its sheet like the automatic
# ones (PlanCanvas.pic_dim -> draw_elev_dim 'f'); the lines of a picture handed to the window; the switch.
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

ok('the switch is on', PC::USE_PIC_DIMS == true)
ok('one he drew becomes one the sheet draws, its number to the half inch',
   PC.pic_dim({ 'p' => [0.2, 0.2, 0.8, 0.2], 'o' => 'h', 'at' => 0.1, 'n' => 60.3 }) ==
   { 'k' => 'f', 'o' => 'h', 'p' => [0.2, 0.2, 0.8, 0.2], 'at' => 0.1, 't' => '60 1/2"' })
ok('a broken one is none', PC.pic_dim({ 'p' => [1, 2], 'o' => 'h' }).nil? && PC.pic_dim({ 'p' => [0, 0, 1, 1], 'o' => 'x' }).nil? && PC.pic_dim(nil).nil?)

st = psd.load_state
st['images'] = [P1]
st['image_dims'] = {}
st['image_hand'] = { P1 => [{ 'p' => [0.2, 0.2, 0.8, 0.2], 'o' => 'h', 'at' => 0.1, 'n' => 60.0 },
                            { 'p' => [0.8, 0.2, 0.8, 0.7], 'o' => 'v', 'at' => 0.9, 'n' => 60.0 }] }
psd.save_state(st)
ok('it survives save_state', psd.load_state['image_hand'] == st['image_hand'], psd.load_state['image_hand'])
psd.instance_variable_set(:@doc, nil)
doc = psd.document
pg = doc.pages.find { |p| p.kind == 'image' }
lay = pg && pg.layers.find { |l| l.name == PC::ELEV_DIM_LAYER }
ok('drawn on the picture\'s sheet even with no automatic ones', lay && lay.shapes.count { |s| s[:type] == :text } == 2, lay && lay.shapes.size)
main = pg.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
tx = lay.shapes.select { |s| s[:type] == :text }
h = tx.find { |s| (s[:rotation] || 0).zero? }
v = tx.find { |s| s[:rotation] == 90.0 }
ok('both read 60"', tx.all? { |s| s[:text] == '60"' }, tx.map { |s| s[:text] })
a = PC.elev_pt(main, 0.2, 0.1)
b = PC.elev_pt(main, 0.8, 0.1)
ok('the one across sits on its line, between its two points', h && h[:x] > a[0] && h[:x] < b[0] && (h[:y] - (a[1] + 0.035)).abs < 1e-6, [h, a, b])
ln = lay.shapes.select { |s| s[:type] == :line }
ok('its line runs from the first point to the second at the height he left it',
   ln.any? { |s| (s[:x1] - a[0]).abs < 1e-6 && (s[:x2] - b[0]).abs < 1e-6 && (s[:y1] - a[1]).abs < 1e-6 && (s[:y2] - a[1]).abs < 1e-6 }, ln.first(3))
up = PC.elev_pt(main, 0.8, 0.2)
ok('its witness lines start at the points he clicked and go past the line',
   ln.any? { |s| (s[:x1] - up[0]).abs < 1e-6 && (s[:y1] - (up[1] - PC::ELEV_GAP)).abs < 1e-6 && (s[:y2] - (a[1] - PC::ELEV_OVER)).abs < 1e-6 }, ln.first(6))
x9 = PC.elev_pt(main, 0.9, 0.2)[0]
ok('the one up stands upright, right of the corner where he left it', v && (v[:x] - (x9 - 0.035)).abs < 1e-6, v)
ok('each number has a name, so it can be picked and changed like any', tx.all? { |s| s[:key].to_s.start_with?('ELEV_DIMS|') })

# the window asks for a picture's lines; Ruby reads them from beside the picture
src = File.read('./plan_sheet_dialog.rb', encoding: 'utf-8')
ok('the lines are handed to the window from the file beside the picture',
   src.include?("dlg.add_action_callback('elev_snaps')") && src.include?('InteriorPro::ElevationTool.snaps_file(p)') &&
   src.include?('dlg.execute_script("picSnaps(#{JSON.generate(p)}, #{data})")'))
ok('every one drawn is a line in the trace', src.include?("dlg.add_action_callback('pic_dim_trace')") && src.include?('erase_trace("pic dims: drawn #{line}")'))
ok('the lines file carries the room inches the picture stands for',
   File.read('./elevation_tool.rb', encoding: 'utf-8').include?("'w_in' => side.len.to_f + 2 * MARGIN, 'h_in' => wall_h.to_f + 2 * MARGIN"))

PC.send(:remove_const, :USE_PIC_DIMS)
PC.const_set(:USE_PIC_DIMS, false)
psd.instance_variable_set(:@doc, nil)
pg = psd.document.pages.find { |p| p.kind == 'image' }
ok('switched off: kept but not drawn', pg.layers.none? { |l| l.name == PC::ELEV_DIM_LAYER && !l.shapes.empty? } && psd.load_state['image_hand'][P1].size == 2)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
